using System;
using System.Collections;

namespace Tessera;

/// A rope (docs/soft-bodies.md "Ropes"): from the object in Start Attached To (this object if none) to the one in
/// End Attached To, or hanging free. Tow or lift with it from code: `Rope.Attach(truck, trailer)`.
/// It sags, swings, drapes over things and is pushed about by what moves through it, simulated as a chain of short
/// stiff lengths that resist bending and twisting (Jolt's Cosserat rods).
///
/// Each end is held where it is on its object, and moves with it. An end on a dynamic Rigidbody also pulls on it:
/// the two ends can get no further apart than the rope is long (it goes slack when they come closer), so a rope
/// holds up a crate, swings it, and is pulled tight by it. The pull acts along the straight line between the ends;
/// a rope over a beam still shows on the beam, but holds as though it went straight.
///
/// The rope draws itself as a tube with the Mesh Renderer on this object (added if there is none).
[Component]
class Rope : Component
{
	/// How long it is, in metres.
	public float length = 3;
	/// How thick it is, in metres.
	public float thickness = 0.04f;
	/// The whole rope's weight in kilograms.
	public float mass = 1;
	/// How many lengths it is made of: more bends more smoothly and costs more. 0 picks about one per 10 cm.
	[Range(0, 256)]
	public int32 segments = 0;
	/// How hard it resists bending: 0 a limp rope, 1 a stiff cable.
	[Range(0, 1)]
	public float bendStiffness = 0.1f;
	/// How fast it loses speed, like moving through thick air.
	[Range(0, 5)]
	public float damping = 0.2f;
	public float friction = 0.6f;
	/// What its first end is tied to. None: this object holds it (or nothing, with Hold Start off).
	public Transform startAttachedTo;
	/// With nothing in Start Attached To: whether this object holds the first end. Off: that end hangs free too.
	public bool holdStart = true;
	/// Where it is tied on that object, relative to it.
	public Vector3 startOffset = .Zero;
	/// What its other end is tied to. None: it hangs free.
	public Transform endAttachedTo;
	/// Where it is tied on that object, relative to it.
	public Vector3 endOffset = .Zero;
	/// Solver passes each step: more is firmer and costs more.
	[Range(1, 32)]
	public int32 iterations = 8;

	/// Sides of the tube drawn.
	const int Sides = 8;

	[CLink] static extern uint32 tn_rope_create(void* world, NativeConfig* config, float* positions, uint32 count, float* pinned, float* center);
	[CLink] static extern void* tn_rope_tie(void* world, uint32 bodyA, float* pointA, uint32 bodyB, float* pointB, float length);
	[CLink] static extern void tn_rope_untie(void* world, void* tie);
	[CLink] static extern float tn_rope_pull(void* tie, float step);
	[CLink] static extern uint32 tn_soft_read(void* world, uint32 bodyId, float* positions, float* velocities, uint32 capacity);
	[CLink] static extern void tn_soft_move_pinned(void* world, uint32 bodyId, uint32* indices, float* targets, uint32 count, float step);
	[CLink] static extern void tn_soft_ignore(void* world, uint32 bodyId, uint32 ignoredBody);
	[CLink] static extern void tn_soft_forget(void* world, uint32 bodyId);

	/// native/tessera_softbody.cpp's RopeConfig, in the same order.
	[CRepr]
	struct NativeConfig
	{
		public float mass, stretch, bend, damping, friction, restitution, gravityFactor, radius;
		public int32 iterations;
		public uint32 layer;
		public uint64 userData;
	}

	uint32 mBody = uint32.MaxValue;
	bool mReady;
	PhysicsWorld mWorld;
	// The tie that carries the pull between the ends' bodies, and where its ends were fixed in the world (a tie to
	// an object without a Rigidbody is to a point in the world, made again when the object moves).
	void* mTie;
	Vector3 mTiedStart, mTiedEnd;
	float mPull;
	float mStep;
	bool mLetGo;
	// Whether each end was tied to an object when the rope was made.
	bool mStartTied, mEndTied;
	uint32[2] mHeld;
	int mHeldCount;
	List<Vector3> mPositions = new .() ~ delete _;
	List<float> mTargets = new .() ~ delete _;
	Mesh mMesh ~ delete _;

	/// The rope's body id in the physics world, or uint32.MaxValue before it is made.
	public uint32 BodyId => mBody;
	public bool HasBody => mBody != uint32.MaxValue;
	/// Where each point along it is now, in the world, from this end to the other.
	public List<Vector3> Points => mPositions;
	/// How hard it pulled on what it is tied to in the last step, in newtons (0 while slack or not tied to a body).
	public float Pull => mPull;
	/// Whether the ends are as far apart as the rope is long.
	public bool IsTaut => HasBody && endAttachedTo != null && StartHeld && (EndPoint - StartPoint).Length >= length * 0.99f;

	/// Where it starts, in the world.
	public Vector3 StartPoint => (StartHeld || mPositions.IsEmpty) ? StartObject.TransformPoint(startOffset) : mPositions[0];
	/// What its first end is on.
	Transform StartObject => startAttachedTo ?? Transform;
	/// Where its other end is tied, in the world (where it hangs, if it is free).
	public Vector3 EndPoint => endAttachedTo != null ? endAttachedTo.TransformPoint(endOffset) : (mPositions.IsEmpty ? StartPoint - Vector3(0, length, 0) : mPositions.Back);

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

	/// Ties a new rope between two objects: towing (a truck and a trailer) or lifting (a helicopter and a crate). The
	/// offsets are where on each it is tied, relative to it. Length below zero: as far apart as they are now, plus a
	/// little slack. The rope is an object of its own; destroy it (or call Release) to let go.
	public static Rope Attach(GameObject from, GameObject to, Vector3 fromOffset = .Zero, Vector3 toOffset = .Zero, float length = -1, float thickness = 0.04f)
	{
		let holder = from.Scene.CreateGameObject("Rope");
		let rope = holder.AddComponent<Rope>();
		rope.startAttachedTo = from.Transform;
		rope.startOffset = fromOffset;
		rope.endAttachedTo = to.Transform;
		rope.endOffset = toOffset;
		rope.thickness = thickness;
		let apart = (to.Transform.TransformPoint(toOffset) - from.Transform.TransformPoint(fromOffset)).Length;
		rope.length = length >= 0 ? length : Math.Max(apart * 1.05f, 0.1f);
		if (from.Scene.IsPlaying)
			rope.Start();
		return rope;
	}

	/// Ties its first end to an object (any object: a player, a vehicle, a crate), or to nothing: it lets go and
	/// that end hangs free. Keeps its length.
	public void AttachStart(Transform to, Vector3 offset = .Zero)
	{
		startAttachedTo = to;
		startOffset = offset;
		holdStart = to != null;
		if (HasBody)
			Rebuild();
	}

	/// Ties its other end to an object, or to nothing (it lets go and that end hangs free). Keeps its length.
	public void AttachEnd(Transform to, Vector3 offset = .Zero)
	{
		endAttachedTo = to;
		endOffset = offset;
		if (HasBody)
			Rebuild();
	}

	/// Lets go of what its other end holds.
	public void Release() => AttachEnd(null);

	/// Whether its first end is held by something.
	bool StartHeld => startAttachedTo != null || holdStart;

	/// Makes the rope again from its fields (after changing them while it runs), hanging between its ends.
	public void Rebuild()
	{
		DestroyBody();
		CreateBody();
	}

	/// A dynamic Rigidbody on an object or above it: what a rope's end pulls on.
	static Rigidbody PulledBody(Transform at)
	{
		for (var up = at; up != null; up = up.Parent)
		{
			if (let body = up.GameObject.GetComponent<Rigidbody>())
			{
				body.EnsureBody();
				return body.HasBody ? body : null;
			}
		}
		return null;
	}

	void CreateBody()
	{
		if (mBody != uint32.MaxValue)
			return;
		let world = Scene.Physics;
		world.[Friend]EnsureCreated();
		let system = world.[Friend]mSystem;
		if (system == null)
			return;
		let count = Math.Clamp(segments > 0 ? (int)segments : (int)Math.Round(length / 0.1f), 2, 256) + 1;
		let tied = endAttachedTo != null;
		if (StartHeld || !tied)
		{
			let start = StartObject.TransformPoint(startOffset);
			LayOut(start, tied ? EndPoint : start - Vector3(0, length, 0), length, count, mPositions);
		}
		else
		{
			// Held only at its far end: hanging down from there.
			let end = EndPoint;
			LayOut(end, end - Vector3(0, length, 0), length, count, mPositions);
			for (int i < mPositions.Count / 2)
				Swap!(mPositions[i], mPositions[mPositions.Count - 1 - i]);
		}

		var center = Vector3.Zero;
		for (let p in mPositions)
			center = center + p;
		center = center / mPositions.Count;
		let positions = scope List<float>(count * 3);
		for (let p in mPositions)
		{
			positions.Add(p.x - center.x);
			positions.Add(p.y - center.y);
			positions.Add(p.z - center.z);
		}
		let pinned = scope List<float>();
		pinned.Resize(count);
		mHeldCount = 0;
		if (StartHeld)
		{
			pinned[0] = 1;
			mHeld[mHeldCount++] = 0;
		}
		if (tied)
		{
			pinned[count - 1] = 1;
			mHeld[mHeldCount++] = (uint32)(count - 1);
		}

		NativeConfig config = default;
		config.mass = Math.Max(mass, 0.001f);
		config.stretch = 1.0e-7f;
		// Compliance (how far a bend gives under force) from 1 (limp) to 1e-4 (a stiff cable).
		config.bend = Math.Pow(10.0f, -4.0f * Mathf.Clamp01(bendStiffness));
		config.damping = damping;
		config.friction = friction;
		config.restitution = 0;
		config.gravityFactor = 1;
		config.radius = Math.Max(thickness * 0.5f, 0.001f);
		config.iterations = Math.Clamp(iterations, 1, 32);
		config.layer = PhysicsWorld.[Friend]ObjectLayer(PhysicsWorld.[Friend]LayerMoving, Transform);
		config.userData = (uint64)GameObject.Id;
		mBody = tn_rope_create(system, &config, positions.Ptr, (uint32)count, pinned.Ptr, (float*)&center);
		if (mBody == uint32.MaxValue)
			return;
		mWorld = world;
		world.[Friend]AddRope(this);
		mStartTied = startAttachedTo != null;
		mEndTied = tied;

		// It does not catch on what its ends are tied to.
		let startBody = PulledBody(StartObject);
		let endBody = tied ? PulledBody(endAttachedTo) : null;
		if (startBody != null)
			tn_soft_ignore(system, mBody, startBody.BodyId);
		if (endBody != null && endBody != startBody)
			tn_soft_ignore(system, mBody, endBody.BodyId);

		var renderer = GetComponent<MeshRenderer>();
		if (renderer == null)
			renderer = GameObject.AddComponent<MeshRenderer>();
		delete mMesh;
		mMesh = new Mesh();
		mMesh.Name.Set("Rope");
		BuildTube();
		mMesh.UploadDynamic();
		renderer.RuntimeMesh = mMesh;
	}

	void DestroyBody()
	{
		if (mWorld != null)
		{
			let system = mWorld.[Friend]mSystem;
			if (mTie != null)
				tn_rope_untie(system, mTie);
			if (mBody != uint32.MaxValue)
			{
				tn_soft_forget(system, mBody);
				mWorld.[Friend]RemoveRope(this);
			}
		}
		mTie = null;
		mBody = uint32.MaxValue;
		mWorld = null;
		mPull = 0;
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null && renderer.RuntimeMesh == mMesh)
			renderer.RuntimeMesh = null;
	}

	/// Points from start towards end along a rope `length` long: hanging between them in a curve as long as the
	/// rope, or, when they are further apart than that, a straight line from start as far towards end as it reaches.
	public static void LayOut(Vector3 start, Vector3 end, float length, int count, List<Vector3> output)
	{
		output.Clear();
		let span = (end - start).Length;
		if (span >= length)
		{
			let toward = span > 1.0e-6f ? (end - start) / span : Vector3(0, -1, 0);
			for (int i < count)
				output.Add(start + toward * (length * i / (float)(count - 1)));
			return;
		}
		// The sag that makes a parabola through both ends as long as the rope.
		float sag = 0;
		if (span < length * 0.999f)
		{
			float low = 0, high = length;
			for (int i < 40)
			{
				sag = (low + high) * 0.5f;
				if (CurveLength(start, end, sag, 64) < length)
					low = sag;
				else
					high = sag;
			}
		}
		for (int i < count)
			output.Add(CurvePoint(start, end, sag, i / (float)(count - 1)));
	}

	static Vector3 CurvePoint(Vector3 start, Vector3 end, float sag, float t)
	{
		return Vector3.Lerp(start, end, t) - Vector3(0, sag * 4 * t * (1 - t), 0);
	}

	static float CurveLength(Vector3 start, Vector3 end, float sag, int steps)
	{
		float total = 0;
		var previous = start;
		for (int i = 1; i <= steps; i++)
		{
			let p = CurvePoint(start, end, sag, i / (float)steps);
			total += (p - previous).Length;
			previous = p;
		}
		return total;
	}

	/// Before each physics step: the ends go where their objects hold them, and the pull is tied between their
	/// bodies.
	void BeforeStep(float step)
	{
		if (mBody == uint32.MaxValue || mWorld == null)
			return;
		let system = mWorld.[Friend]mSystem;
		mStep = step;
		if (LetsGo())
			return;
		let start = StartPoint;
		let end = EndPoint;
		mTargets.Clear();
		for (int i < mHeldCount)
		{
			let p = mHeld[i] == 0 ? start : end;
			mTargets.Add(p.x);
			mTargets.Add(p.y);
			mTargets.Add(p.z);
		}
		if (mHeldCount > 0)
			tn_soft_move_pinned(system, mBody, &mHeld, mTargets.Ptr, (uint32)mHeldCount, step);
		mPull = mTie != null ? tn_rope_pull(mTie, step) : 0;

		// The pull: needed when both ends are held and either is on a dynamic Rigidbody.
		if (endAttachedTo == null || !StartHeld)
		{
			if (mTie != null)
			{
				tn_rope_untie(system, mTie);
				mTie = null;
			}
			return;
		}
		let startBody = PulledBody(StartObject);
		let endBody = PulledBody(endAttachedTo);
		let startPulls = startBody != null && !startBody.isKinematic;
		let endPulls = endBody != null && !endBody.isKinematic;
		if (!startPulls && !endPulls)
		{
			if (mTie != null)
			{
				tn_rope_untie(system, mTie);
				mTie = null;
			}
			return;
		}
		// A tie to the world (or to a kinematic body) is made again when that end has moved.
		let moved = (startBody == null && (start - mTiedStart).LengthSquared > 1.0e-4f) || (endBody == null && (end - mTiedEnd).LengthSquared > 1.0e-4f);
		if (mTie != null && !moved)
			return;
		if (mTie != null)
			tn_rope_untie(system, mTie);
		var from = start;
		var to = end;
		mTie = tn_rope_tie(system, startBody?.BodyId ?? uint32.MaxValue, (float*)&from, endBody?.BodyId ?? uint32.MaxValue, (float*)&to, length);
		mTiedStart = start;
		mTiedEnd = end;
	}

	/// Whether what an end was tied to is being destroyed or gone (the scene empties reference fields to deleted
	/// objects): that end lets go, and the rope is made again after the step, not while the world steps.
	bool LetsGo()
	{
		if (mEndTied && (endAttachedTo == null || endAttachedTo.GameObject.IsDestroyed))
		{
			endAttachedTo = null;
			mLetGo = true;
		}
		if (mStartTied && (startAttachedTo == null || startAttachedTo.GameObject.IsDestroyed))
		{
			startAttachedTo = null;
			holdStart = false;
			mLetGo = true;
		}
		return mLetGo;
	}

	public override void LateUpdate()
	{
		if (LetsGo())
		{
			mLetGo = false;
			Rebuild();
		}
		ReadBack();
	}

	/// The simulation's points into Points and the tube drawn.
	void ReadBack()
	{
		if (mBody == uint32.MaxValue || mWorld == null || mMesh == null)
			return;
		let count = mPositions.Count;
		let read = tn_soft_read(mWorld.[Friend]mSystem, mBody, (float*)mPositions.Ptr, null, (uint32)count);
		if (read != (uint32)count)
			return;
		BuildTube();
		mMesh.UpdateDynamic();
	}

	/// A tube round the points, in this object's space: a ring of Sides vertices at each point, turned along the
	/// rope (each ring's frame carried from the last, so the tube does not twist).
	void BuildTube()
	{
		let toLocal = Transform.WorldToLocal;
		let count = mPositions.Count;
		let radius = thickness * 0.5f;
		mMesh.Vertices.Clear();
		mMesh.Indices.Clear();
		var side = Vector3(1, 0, 0);
		for (int i < count)
		{
			let along = (mPositions[Math.Min(i + 1, count - 1)] - mPositions[Math.Max(i - 1, 0)]).Normalized;
			// Keep the frame at right angles to the rope, as close as it can be to the last one.
			side = (side - along * Vector3.Dot(side, along));
			if (side.LengthSquared < 1.0e-8f)
				side = Vector3.Cross(along, Math.Abs(along.y) < 0.9f ? Vector3.Up : Vector3(1, 0, 0));
			side = side.Normalized;
			let up = Vector3.Cross(along, side);
			for (int k < Sides)
			{
				let angle = k * Math.PI_f * 2 / Sides;
				let normal = side * Math.Cos(angle) + up * Math.Sin(angle);
				let world = mPositions[i] + normal * radius;
				mMesh.AddVertex(toLocal.TransformPoint(world), toLocal.TransformDirection(normal).Normalized, .White, .(k / (float)Sides, i / (float)(count - 1)));
			}
		}
		for (int i < count - 1)
		{
			for (int k < Sides)
			{
				let a = (uint32)(i * Sides + k), b = (uint32)(i * Sides + (k + 1) % Sides);
				let c = a + (uint32)Sides, d = b + (uint32)Sides;
				mMesh.AddTriangle(a, c, b);
				mMesh.AddTriangle(b, c, d);
			}
		}
		mMesh.RecalculateBounds();
	}

	public override void OnDrawGizmos(bool selected)
	{
		if (!selected || HasBody)
			return;
		// Before it runs: where it will hang.
		let points = scope List<Vector3>();
		let start = StartPoint;
		LayOut(start, endAttachedTo != null ? EndPoint : start - Vector3(0, length, 0), length, 24, points);
		for (int i = 1; i < points.Count; i++)
			DebugDraw.Line(points[i - 1], points[i], .(0.9f, 0.75f, 0.4f, 1));
	}
}
