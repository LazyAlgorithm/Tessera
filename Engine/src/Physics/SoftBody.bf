using System;
using System.Collections;

namespace Tessera;

[Reflect(.All)]
enum SoftBodyKind : int32
{
	/// A sheet that hangs, folds and blows: flags, capes, curtains, sails. Pin some of it to hold it up.
	Cloth,
	/// A closed shape that keeps its volume by pushing out: jelly, rubber balls, soft tyres, cushions.
	Jelly
}

/// Makes this object's Mesh Renderer soft: its mesh is simulated as cloth or as a squashy body, which falls, folds,
/// collides with colliders, rigidbodies and characters, pushes them and is pushed back. Jolt steps it on the job
/// threads with the rest of the physics.
///
/// Pinned vertices (painted in the editor: select the object and press Paint Pins in its Inspector) are held where
/// they are on the object, and follow the object as it moves, so a cape on a character's back or a flag on a moving
/// ship goes with it. Wind Zones blow on cloth. A stiffness map, painted the same way, makes parts of it softer.
///
/// The simulation runs on every machine by itself. Pinned cloth follows its object, so it looks the same everywhere
/// when the object is shared; a free soft body on a networked object is drawn towards where the server has it
/// (see docs/soft-bodies.md).
[Component]
class SoftBody : Component
{
	public SoftBodyKind kind = .Cloth;
	/// The whole body's weight in kilograms, shared by the vertices that are not pinned.
	public float mass = 1;
	/// How hard it resists stretching: 1 barely stretches, 0 like elastic.
	[Range(0, 1)]
	public float stiffness = 0.9f;
	/// How hard it resists bending: 0 folds freely (silk), 1 holds its shape (leather, rubber).
	[Range(0, 1)]
	public float bendStiffness = 0.2f;
	/// Jelly: how hard the air inside pushes out (pascals above the air outside), whatever its size. 0 collapses,
	/// 200 a soft cushion, 600 jelly, 2000 a firm ball.
	public float pressure = 600;
	/// How fast it loses speed, like moving through thick air.
	[Range(0, 5)]
	public float damping = 0.1f;
	public float friction = 0.4f;
	[Range(0, 1)]
	public float bounciness = 0;
	public float gravityScale = 1;
	/// How far from its surface it keeps other things (its thickness), in metres.
	public float thickness = 0.02f;
	/// How much wind pushes it: 0 not at all.
	public float windDrag = 1;
	/// Solver passes each step: more is stiffer and costs more.
	[Range(1, 32)]
	public int32 iterations = 5;
	/// The vertices held in place, by number ("0-12 40 41"): Paint Pins in the editor writes these.
	public String pins = new .() ~ delete _;
	/// Where it is softer than Stiffness says, by vertex ("12=0.5 13=0.25"): painted in the editor.
	public String stiffnessMap = new .() ~ delete _;

	/// Wind Zones' strength is a feel (1 a breeze, 6 a gale); this is how many metres a second each is.
	const float WindSpeed = 4;

	[CLink] static extern uint32 tn_soft_create(void* world, NativeConfig* config, float* positions, uint32 vertexCount, uint32* triangles, uint32 triangleCount, float* pinned, float* stiffness, float* center);
	[CLink] static extern uint32 tn_soft_read(void* world, uint32 bodyId, float* positions, float* velocities, uint32 capacity);
	[CLink] static extern void tn_soft_move_pinned(void* world, uint32 bodyId, uint32* indices, float* targets, uint32 count, float step);
	[CLink] static extern void tn_soft_set_positions(void* world, uint32 bodyId, float* positions, float* velocities, uint32 count);
	[CLink] static extern void tn_soft_wind(void* world, uint32 bodyId, float* wind, float drag, float step);
	[CLink] static extern uint32 tn_soft_touching(void* world, uint32 bodyId, uint32* output, uint32 capacity);
	[CLink] static extern void tn_soft_world_destroyed(void* world);
	[CLink] static extern void tn_soft_shift(void* world, uint32 bodyId, float* offset);

	/// native/tessera_softbody.cpp's Config, in the same order.
	[CRepr]
	struct NativeConfig
	{
		public float mass, stretch, shear, bend, pressure, damping, friction, restitution, gravityFactor, vertexRadius;
		public int32 iterations, doubleSided, longRange, dihedral;
		public uint32 layer;
		public uint64 userData;
	}

	uint32 mBody = uint32.MaxValue;
	bool mReady;
	PhysicsWorld mWorld;
	// The mesh drawn (the renderer's own, copied so its vertices can move), and for each of its vertices the welded
	// vertex of the simulation it follows: a mesh splits a vertex where its texture or shading has a seam, the
	// simulation must not.
	Mesh mMesh ~ delete _;
	List<int32> mRenderToSim = new .() ~ delete _;
	// The simulation's vertices where they rest on the object, its triangles, and which are pinned.
	List<Vector3> mRest = new .() ~ delete _;
	List<uint32> mTriangles = new .() ~ delete _;
	List<uint32> mPinned = new .() ~ delete _;
	List<float> mTargets = new .() ~ delete _;
	List<Vector3> mPositions = new .() ~ delete _;
	List<Vector3> mNormals = new .() ~ delete _;
	// A free body's middle, from its object's position (where the middle was when it was made).
	Vector3 mCarried;

	/// The body's id in the physics world, or uint32.MaxValue before it is made.
	public uint32 BodyId => mBody;
	public bool HasBody => mBody != uint32.MaxValue;
	/// How many vertices the simulation has (the mesh's, with its seams joined).
	public int SimulatedVertexCount => mRest.Count;
	/// Where each simulated vertex is now, in the world (updated every frame while it runs).
	public List<Vector3> Positions => mPositions;

	public override void Start()
	{
		mReady = true;
		CreateBody();
	}

	public override void OnEnable()
	{
		if (mReady)
			CreateBody();
	}

	public override void OnDisable()
	{
		DestroyBody();
	}

	/// Makes the body again from the mesh and settings (after changing them while it runs). It starts at rest.
	public void Rebuild()
	{
		DestroyBody();
		CreateBody();
	}

	void DestroyBody()
	{
		if (mBody != uint32.MaxValue && mWorld != null)
			mWorld.[Friend]RemoveSoftBody(mBody);
		mBody = uint32.MaxValue;
		mWorld = null;
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null && renderer.RuntimeMesh == mMesh)
			renderer.RuntimeMesh = null;
	}

	void CreateBody()
	{
		if (mBody != uint32.MaxValue)
			return;
		let renderer = GetComponent<MeshRenderer>();
		let source = renderer?.ActiveMesh;
		if (source == null || source.Vertices.Count < 3 || source.Indices.Count < 3)
		{
			Log.Warning(scope $"Soft Body on '{GameObject.Name}' needs a Mesh Renderer with a mesh.");
			return;
		}
		let world = Scene.Physics;
		world.[Friend]EnsureCreated();
		let system = world.[Friend]mSystem;
		if (system == null)
			return;
		Weld(source, mRest, mTriangles, mRenderToSim);

		// The simulation works in the world; the mesh drawn stays in the object's own space.
		let toWorld = Transform.LocalToWorld;
		var center = Vector3.Zero;
		for (let rest in mRest)
			center = center + toWorld.TransformPoint(rest);
		center = center / mRest.Count;
		let positions = scope List<float>(mRest.Count * 3);
		for (let rest in mRest)
		{
			let p = toWorld.TransformPoint(rest) - center;
			positions.Add(p.x);
			positions.Add(p.y);
			positions.Add(p.z);
		}
		let pinned = scope List<float>();
		pinned.Resize(mRest.Count);
		mPinned.Clear();
		ParsePins(pins, mRest.Count, mPinned);
		for (let index in mPinned)
			pinned[index] = 1;
		let stiffnesses = scope List<float>();
		stiffnesses.Resize(mRest.Count);
		for (int i < mRest.Count)
			stiffnesses[i] = 1;
		ParseStiffness(stiffnessMap, stiffnesses);

		NativeConfig config = default;
		let cloth = kind == .Cloth;
		config.mass = Math.Max(mass, 0.001f);
		// Compliance (how far a constraint gives under force) from 1e-2 (stiffness 0) to 1e-6 (stiffness 1).
		config.stretch = Compliance(stiffness);
		config.shear = Compliance(stiffness * 0.9f);
		config.bend = bendStiffness <= 0 ? -1 : Compliance(bendStiffness) * 100;
		// Jolt's pressure is the amount of gas (pressure times volume), so the same setting holds any size alike.
		config.pressure = cloth ? 0 : Math.Max(pressure, 0) * Volume(positions, mTriangles);
		config.damping = damping;
		config.friction = friction;
		config.restitution = bounciness;
		config.gravityFactor = gravityScale;
		config.vertexRadius = Math.Max(thickness, 0);
		config.iterations = Math.Clamp(iterations, 1, 32);
		config.doubleSided = cloth ? 1 : 0;
		config.longRange = cloth ? 1 : 0;
		config.dihedral = cloth ? 1 : 0;
		config.layer = PhysicsWorld.[Friend]ObjectLayer(PhysicsWorld.[Friend]LayerMoving, Transform);
		config.userData = (uint64)GameObject.Id;
		mBody = tn_soft_create(system, &config, positions.Ptr, (uint32)mRest.Count, mTriangles.Ptr, (uint32)(mTriangles.Count / 3), pinned.Ptr, stiffnesses.Ptr, (float*)&center);
		if (mBody == uint32.MaxValue)
		{
			Log.Warning(scope $"Soft Body on '{GameObject.Name}': its mesh has no faces the simulation can use.");
			return;
		}
		mWorld = world;
		world.[Friend]AddSoftBody(mBody, this);
		mCarried = center - Transform.Position;

		// The renderer draws a copy whose vertices follow the simulation.
		delete mMesh;
		mMesh = new Mesh();
		mMesh.Name.Set(source.Name);
		mMesh.Vertices.AddRange(source.Vertices);
		mMesh.Indices.AddRange(source.Indices);
		mMesh.UploadDynamic();
		renderer.RuntimeMesh = mMesh;
		ReadBack();
	}

	/// The volume a closed mesh holds (from its faces, packed x, y, z), in cubic metres.
	static float Volume(List<float> positions, List<uint32> triangles)
	{
		float sixVolume = 0;
		for (int t = 0; t + 2 < triangles.Count; t += 3)
		{
			let a = Vector3(positions[triangles[t] * 3], positions[triangles[t] * 3 + 1], positions[triangles[t] * 3 + 2]);
			let b = Vector3(positions[triangles[t + 1] * 3], positions[triangles[t + 1] * 3 + 1], positions[triangles[t + 1] * 3 + 2]);
			let c = Vector3(positions[triangles[t + 2] * 3], positions[triangles[t + 2] * 3 + 1], positions[triangles[t + 2] * 3 + 2]);
			sixVolume += Vector3.Dot(a, Vector3.Cross(b, c));
		}
		return Math.Abs(sixVolume) / 6;
	}

	static float Compliance(float stiffness) => Math.Pow(10.0f, -6.0f + 4.0f * (1.0f - Mathf.Clamp01(stiffness)));

	/// Joins the mesh's vertices that share a place (split at texture or shading seams) into the simulation's
	/// vertices: where each rests, the triangles between them, and which one each of the mesh's vertices is.
	public static void Weld(Mesh source, List<Vector3> rest, List<uint32> triangles, List<int32> renderToSim)
	{
		rest.Clear();
		triangles.Clear();
		renderToSim.Clear();
		let byPlace = scope Dictionary<int64, int32>();
		for (let vertex in source.Vertices)
		{
			let p = vertex.position;
			// A millimetre grid: vertices closer than that are one.
			let key = ((int64)Math.Round(p.x * 1000) & 0x1FFFFF) | (((int64)Math.Round(p.y * 1000) & 0x1FFFFF) << 21) | (((int64)Math.Round(p.z * 1000) & 0x1FFFFF) << 42);
			if (!byPlace.TryGetValue(key, var index))
			{
				index = (int32)rest.Count;
				byPlace[key] = index;
				rest.Add(p);
			}
			renderToSim.Add(index);
		}
		for (int i = 0; i + 2 < source.Indices.Count; i += 3)
		{
			let a = (uint32)renderToSim[(int)source.Indices[i]], b = (uint32)renderToSim[(int)source.Indices[i + 1]], c = (uint32)renderToSim[(int)source.Indices[i + 2]];
			if (a == b || b == c || a == c)
				continue;
			triangles.Add(a);
			triangles.Add(b);
			triangles.Add(c);
		}
	}

	/// Whether the server says where this body is: a free soft body on a networked object, on a client.
	bool FollowsServer => mPinned.IsEmpty && Scene.Network != null && !Scene.Network.IsServer && GetComponent<NetworkIdentity>() != null;

	/// The middle of the simulated vertices, as last read.
	Vector3 Middle()
	{
		var sum = Vector3.Zero;
		for (let p in mPositions)
			sum = sum + p;
		return sum / Math.Max(mPositions.Count, 1);
	}

	/// A free body carries its object (ReadBack puts the object where the body is). When something else moved the
	/// object since (a script, or the server's position arriving on a client), the body goes with it: at once, or
	/// on a client eased towards it unless far off.
	void FollowMovedObject()
	{
		if (!mPinned.IsEmpty || mPositions.Count != mRest.Count || mBody == uint32.MaxValue || mWorld == null)
			return;
		let gap = Transform.Position - (Middle() - mCarried);
		if (gap.LengthSquared < 1.0e-8f)
			return;
		var shift = (FollowsServer && gap.LengthSquared < 4) ? gap * 0.2f : gap;
		tn_soft_shift(mWorld.[Friend]mSystem, mBody, (float*)&shift);
		for (var p in ref mPositions)
			p = p + shift;
	}

	/// Before each physics step: pinned vertices go where the object holds them, and the wind blows.
	void BeforeStep(float step)
	{
		if (mBody == uint32.MaxValue || mWorld == null)
			return;
		let system = mWorld.[Friend]mSystem;
		FollowMovedObject();
		if (!mPinned.IsEmpty)
		{
			let toWorld = Transform.LocalToWorld;
			mTargets.Clear();
			for (let index in mPinned)
			{
				let p = toWorld.TransformPoint(mRest[index]);
				mTargets.Add(p.x);
				mTargets.Add(p.y);
				mTargets.Add(p.z);
			}
			tn_soft_move_pinned(system, mBody, mPinned.Ptr, mTargets.Ptr, (uint32)mPinned.Count, step);
		}
		if (windDrag > 0 && kind == .Cloth)
		{
			var wind = Wind.At(Scene, Transform.Position) * WindSpeed;
			if (wind.LengthSquared > 0.0001f)
			{
				// Gusts come and go, a little differently for each object.
				let phase = (float)(GameObject.Id % 97);
				wind = wind * (1.0f + 0.35f * Math.Sin(Time.Time * 1.7f + phase) + 0.15f * Math.Sin(Time.Time * 4.3f + phase * 0.5f));
				tn_soft_wind(system, mBody, (float*)&wind, windDrag, step);
			}
		}
	}

	public override void LateUpdate()
	{
		ReadBack();
	}

	/// The simulation's vertices into Positions and the mesh drawn.
	void ReadBack()
	{
		if (mBody == uint32.MaxValue || mWorld == null || mMesh == null)
			return;
		FollowMovedObject();
		mPositions.Resize(mRest.Count);
		let read = tn_soft_read(mWorld.[Friend]mSystem, mBody, (float*)mPositions.Ptr, null, (uint32)mRest.Count);
		if (read != (uint32)mRest.Count)
			return;
		// Normals from the faces round each vertex, in the world.
		mNormals.Resize(mRest.Count);
		for (int i < mNormals.Count)
			mNormals[i] = .Zero;
		for (int t = 0; t + 2 < mTriangles.Count; t += 3)
		{
			let a = mTriangles[t], b = mTriangles[t + 1], c = mTriangles[t + 2];
			let normal = Vector3.Cross(mPositions[b] - mPositions[a], mPositions[c] - mPositions[a]);
			mNormals[a] = mNormals[a] + normal;
			mNormals[b] = mNormals[b] + normal;
			mNormals[c] = mNormals[c] + normal;
		}
		// A free body carries its object (where the server says it is, on a client).
		if (mPinned.IsEmpty && !FollowsServer)
			Transform.Position = Middle() - mCarried;
		let toLocal = Transform.WorldToLocal;
		for (int v < mMesh.Vertices.Count)
		{
			let sim = mRenderToSim[v];
			var vertex = ref mMesh.Vertices[v];
			vertex.position = toLocal.TransformPoint(mPositions[sim]);
			let normal = toLocal.TransformDirection(mNormals[sim]);
			if (normal.LengthSquared > 1.0e-12f)
				vertex.normal = normal.Normalized;
		}
		mMesh.RecalculateBounds();
		mMesh.UpdateDynamic();
	}

	/// The bodies (by physics body id) its vertices have touched since this was last called.
	public void TouchingBodies(List<uint32> output)
	{
		output.Clear();
		if (mBody == uint32.MaxValue || mWorld == null)
			return;
		uint32[64] found = ?;
		let count = tn_soft_touching(mWorld.[Friend]mSystem, mBody, &found, 64);
		for (int i < count)
			output.Add(found[i]);
	}

	/// Puts the simulated vertices at places in the world, still (a network correction, or a reset).
	public void SetPositions(Span<Vector3> positions)
	{
		if (mBody == uint32.MaxValue || mWorld == null || positions.Length != mRest.Count)
			return;
		tn_soft_set_positions(mWorld.[Friend]mSystem, mBody, (float*)positions.Ptr, null, (uint32)positions.Length);
		ReadBack();
	}

	/// Reads "0-12 40 41" into vertex numbers below count.
	public static void ParsePins(StringView text, int count, List<uint32> output)
	{
		for (let word in text.Split(' ', .RemoveEmptyEntries))
		{
			let dash = word.IndexOf('-');
			let first = int.Parse(dash < 0 ? word : word.Substring(0, dash)) case .Ok(let value) ? value : -1;
			let last = dash < 0 ? first : (int.Parse(word.Substring(dash + 1)) case .Ok(let value) ? value : -1);
			for (int i = Math.Max(first, 0); i <= last && i < count; i++)
			{
				if (!output.Contains((uint32)i))
					output.Add((uint32)i);
			}
		}
	}

	/// Writes vertex numbers as "0-12 40 41".
	public static void FormatPins(List<uint32> pinned, String output)
	{
		let sorted = scope List<uint32>(pinned);
		sorted.Sort();
		int i = 0;
		while (i < sorted.Count)
		{
			int j = i;
			while (j + 1 < sorted.Count && sorted[j + 1] <= sorted[j] + 1)
				j++;
			if (!output.IsEmpty)
				output.Append(' ');
			if (j > i)
				output.AppendF("{}-{}", sorted[i], sorted[j]);
			else
				output.AppendF("{}", sorted[i]);
			i = j + 1;
		}
	}

	/// Reads "12=0.5 13=0.25" into a stiffness for each vertex (the rest stay as they are).
	public static void ParseStiffness(StringView text, List<float> stiffnesses)
	{
		for (let word in text.Split(' ', .RemoveEmptyEntries))
		{
			let equals = word.IndexOf('=');
			if (equals < 0)
				continue;
			let index = int.Parse(word.Substring(0, equals)) case .Ok(let value) ? value : -1;
			if (index >= 0 && index < stiffnesses.Count)
				stiffnesses[index] = Mathf.Clamp01(SceneSerializer.ParseFloat(word.Substring(equals + 1)));
		}
	}

	/// Writes the stiffnesses below 1 as "12=0.5 13=0.25".
	public static void FormatStiffness(List<float> stiffnesses, String output)
	{
		for (int i < stiffnesses.Count)
		{
			if (stiffnesses[i] >= 0.999f)
				continue;
			if (!output.IsEmpty)
				output.Append(' ');
			output.AppendF("{}={}", i, Math.Round(stiffnesses[i] * 100) / 100);
		}
	}

	public override void OnDrawGizmos(bool selected)
	{
		if (!selected || mPinned.IsEmpty || mPositions.Count != mRest.Count)
			return;
		for (let index in mPinned)
			DebugDraw.Sphere(mPositions[index], 0.03f, .(1, 0.55f, 0.1f, 1));
	}
}
