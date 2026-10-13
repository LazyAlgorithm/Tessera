using System;
using System.Collections;

namespace Tessera;

/// Full dynamic state of a body; what the network layer sends and rewinds to.
[CRepr]
struct BodyState
{
	public Vector3 position;
	public Quaternion rotation;
	public Vector3 linearVelocity;
	public Vector3 angularVelocity;
}

struct RaycastHit
{
	public GameObject gameObject;
	public Vector3 point;
	public float distance;
}

/// Closest swept-volume contact. Distance measures travel of the shape's center,
/// point is on the contacted surface, and normal points out of that surface.
struct ShapeCastHit
{
	public GameObject gameObject;
	public Vector3 point;
	public Vector3 normal;
	public float distance;
	public float penetrationDepth;
	public uint32 bodyId;
}

/// Description used to build a collision shape. Sizes are already scaled to world units.
struct ShapeDesc
{
	public enum Kind { Box, Sphere, Capsule, Mesh, ConvexHull, Compound }
	/// Compound: boxCount pairs of (center, half extents).
	public Vector3* boxes;
	public int32 boxCount;
	public Kind kind;
	public Vector3 halfExtents;
	/// Box only: how far the edges and corners are rounded. 0 uses a small default.
	public float convexRadius;
	public float radius;
	public float halfHeight;
	public Vector3 center;
	public Mesh mesh;
	public Vector3 meshScale;
}

/// One Jolt simulation per scene. Bodies are created by Rigidbody and Collider components while playing.
///
/// Jolt is built with cross-platform determinism, so replaying the same inputs from the same
/// state gives the same result, which is what client-side prediction relies on.
class PhysicsWorld
{
	class Entry
	{
		public uint32 bodyId;
		public Transform transform;
		public bool dynamic;
		public bool kinematic;
		public uint32 lastVersion;
		public void* shape;
		/// The body belongs to a character controller, which moves and destroys it; it is listed so queries can name its object.
		public bool external;
	}

	const uint32 LayerStatic = 0;
	const uint32 LayerMoving = 1;
	/// Debris rests on scenery but passes through everything that moves, characters included.
	const uint32 LayerDebris = 2;

	static bool sJoltInitialized;
	static void* sJobSystem;
	static int sWorldCount;

	void* mSystem;
	void* mBodyInterface;
	List<Entry> mEntries = new .() ~ DeleteContainerAndItems!(_);
	List<void*> mCharacters = new .() ~ delete _;
	/// Every live character controller in this world, for the soft push between characters.
	public List<CharacterController> Controllers = new .() ~ delete _;
	Dictionary<uint32, Entry> mByBody = new .() ~ delete _;
	bool mBroadPhaseDirty;
	void* mSphereQueryShape;
	void* mCapsuleQueryShape;
	void* mBoxQueryShape;
	float mSphereQueryRadius = -1;
	Vector2 mCapsuleQuerySize = .(-1, -1);
	Vector3 mBoxQuerySize = .(-1, -1, -1);
	List<Jolt.ShapeHit> mOverlapHits = new .() ~ delete _;


	public Vector3 Gravity = .(0, -9.81f, 0);
	public int32 BodyCount => (int32)mEntries.Count;

	public this()
	{
		sWorldCount++;
	}

	public ~this()
	{
		Clear();
		if (mSphereQueryShape != null) Jolt.JPH_Shape_Destroy(mSphereQueryShape);
		if (mCapsuleQueryShape != null) Jolt.JPH_Shape_Destroy(mCapsuleQueryShape);
		if (mBoxQueryShape != null) Jolt.JPH_Shape_Destroy(mBoxQueryShape);
		if (mSystem != null)
			Jolt.JPH_PhysicsSystem_Destroy(mSystem);
		sWorldCount--;
	}

	void EnsureCreated()
	{
		if (mSystem != null)
			return;
		if (!sJoltInitialized)
		{
			Jolt.JPH_Init();
			Jolt.JobConfig config;
			config.maxJobs = 2048;
			config.maxBarriers = 8;
#if BF_PLATFORM_WASM
			// A web page has one thread: jobs run on it while the physics step waits for them.
			config.numThreads = 0;
#else
			config.numThreads = 3;
#endif
			sJobSystem = Jolt.JPH_JobSystemThreadPool_Create(&config);
			sJoltInitialized = true;
		}
		let broadPhase = Jolt.JPH_BroadPhaseLayerInterfaceTable_Create(3, 2);
		Jolt.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhase, LayerStatic, 0);
		Jolt.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhase, LayerMoving, 1);
		Jolt.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhase, LayerDebris, 1);
		let pairFilter = Jolt.JPH_ObjectLayerPairFilterTable_Create(3);
		Jolt.JPH_ObjectLayerPairFilterTable_EnableCollision(pairFilter, LayerStatic, LayerMoving);
		Jolt.JPH_ObjectLayerPairFilterTable_EnableCollision(pairFilter, LayerMoving, LayerMoving);
		Jolt.JPH_ObjectLayerPairFilterTable_EnableCollision(pairFilter, LayerStatic, LayerDebris);
		let objectVsBroadPhase = Jolt.JPH_ObjectVsBroadPhaseLayerFilterTable_Create(broadPhase, 2, pairFilter, 3);

		Jolt.PhysicsSystemSettings settings = default;
		settings.maxBodies = 16384;
		settings.numBodyMutexes = 0;
		settings.maxBodyPairs = 65536;
		settings.maxContactConstraints = 16384;
		settings.broadPhaseLayerInterface = broadPhase;
		settings.objectLayerPairFilter = pairFilter;
		settings.objectVsBroadPhaseLayerFilter = objectVsBroadPhase;
		mSystem = Jolt.JPH_PhysicsSystem_Create(&settings);
		mBodyInterface = Jolt.JPH_PhysicsSystem_GetBodyInterface(mSystem);
	}

	public void Clear()
	{
		// Characters go first: each owns an inner body that is listed below as an external entry.
		for (let character in mCharacters)
			Jolt.tn_character_destroy(character, mSystem);
		mCharacters.Clear();
		Controllers.Clear();
		for (let entry in mEntries)
		{
			if (entry.external)
				continue;
			Jolt.JPH_BodyInterface_RemoveAndDestroyBody(mBodyInterface, entry.bodyId);
			Jolt.JPH_Shape_Destroy(entry.shape);
		}
		ClearAndDeleteItems!(mEntries);
		mByBody.Clear();
	}

	void* CreateShape(ShapeDesc desc)
	{
		void* shape = null;
		switch (desc.kind)
		{
		case .Box:
			var half = Vector3.Max(desc.halfExtents, .(0.01f));
			let smallest = Math.Min(half.x, Math.Min(half.y, half.z));
			let convex = desc.convexRadius > 0 ? Math.Min(desc.convexRadius, smallest) : Math.Min(0.05f, smallest * 0.5f);
			shape = Jolt.JPH_BoxShape_Create(&half, convex);
		case .Sphere:
			shape = Jolt.JPH_SphereShape_Create(Math.Max(desc.radius, 0.01f));
		case .Capsule:
			shape = Jolt.JPH_CapsuleShape_Create(Math.Max(desc.halfHeight, 0.01f), Math.Max(desc.radius, 0.01f));
		case .Compound:
			if (desc.boxCount <= 0)
				return null;
			let compound = Jolt.JPH_StaticCompoundShapeSettings_Create();
			var identity = Quaternion.Identity;
			for (int i < desc.boxCount)
			{
				var boxCenter = desc.boxes[i * 2];
				var boxHalf = Vector3.Max(desc.boxes[i * 2 + 1], .(0.01f));
				let boxShape = Jolt.JPH_BoxShape_Create(&boxHalf, 0.02f);
				Jolt.JPH_CompoundShapeSettings_AddShape2(compound, &boxCenter, &identity, boxShape, (uint32)i);
				// The compound keeps its own reference to each part.
				Jolt.JPH_Shape_Destroy(boxShape);
			}
			shape = Jolt.JPH_StaticCompoundShape_Create(compound);
			Jolt.JPH_ShapeSettings_Destroy(compound);
		case .ConvexHull:
			let hullMesh = desc.mesh;
			if (hullMesh == null || hullMesh.Vertices.Count < 4)
				return null;
			// A few hundred well-spread points describe the hull; more only slows Jolt's builder down.
			let step = Math.Max(1, hullMesh.Vertices.Count / 256);
			List<Vector3> points = scope .();
			for (int i = 0; i < hullMesh.Vertices.Count; i += step)
				points.Add(hullMesh.Vertices[i].position * desc.meshScale);
			let hullSettings = Jolt.JPH_ConvexHullShapeSettings_Create(points.Ptr, (uint32)points.Count, 0.02f);
			shape = Jolt.JPH_ConvexHullShapeSettings_CreateShape(hullSettings);
			Jolt.JPH_ShapeSettings_Destroy(hullSettings);
		case .Mesh:
			let mesh = desc.mesh;
			if (mesh == null || mesh.Indices.Count < 3)
				return null;
			Vector3[] vertices = scope .[mesh.Vertices.Count];
			for (int i < mesh.Vertices.Count)
				vertices[i] = mesh.Vertices[i].position * desc.meshScale;
			let triangleCount = mesh.Indices.Count / 3;
			Jolt.IndexedTriangle[] triangles = new .[triangleCount];
			defer delete triangles;
			for (int i < triangleCount)
			{
				// Keep the mesh's own index order: Jolt takes (v2 - v1) x (v3 - v1) as the front of a
				// triangle, which is the side Tessera's meshes face. Reversing it makes every
				// triangle a back face, and Jolt lets bodies pass through back faces.
				triangles[i].i1 = mesh.Indices[i * 3];
				triangles[i].i2 = mesh.Indices[i * 3 + 1];
				triangles[i].i3 = mesh.Indices[i * 3 + 2];
				triangles[i].materialIndex = 0;
				triangles[i].userData = 0;
			}
			let settings = Jolt.JPH_MeshShapeSettings_Create2(vertices.Ptr, (uint32)vertices.Count, triangles.Ptr, (uint32)triangleCount);
			shape = Jolt.JPH_MeshShapeSettings_CreateShape(settings);
			Jolt.JPH_ShapeSettings_Destroy(settings);
		}
		if (shape != null && desc.center.LengthSquared > 1.0e-10f)
		{
			var center = desc.center;
			var identity = Quaternion.Identity;
			let offset = Jolt.JPH_RotatedTranslatedShape_Create(&center, &identity, shape);
			Jolt.JPH_Shape_Destroy(shape);
			shape = offset;
		}
		return shape;
	}

	/// Creates a body that follows (static/kinematic) or drives (dynamic) the given transform.
	/// Returns the body id, or uint32.MaxValue on failure.
	public uint32 CreateBody(Transform transform, ShapeDesc desc, Rigidbody rigidbody)
	{
		EnsureCreated();
		let shape = CreateShape(desc);
		if (shape == null)
			return uint32.MaxValue;

		var position = transform.Position;
		var rotation = transform.Rotation;
		int32 motion = Jolt.MotionStatic;
		if (rigidbody != null)
			motion = rigidbody.isKinematic ? Jolt.MotionKinematic : Jolt.MotionDynamic;
		// Mesh shapes cannot be dynamic in Jolt.
		if (desc.kind == .Mesh)
			motion = Jolt.MotionStatic;
		let debris = rigidbody != null && rigidbody.debris && motion != Jolt.MotionStatic;

		let settings = Jolt.JPH_BodyCreationSettings_Create3(shape, &position, &rotation, motion, motion == Jolt.MotionStatic ? LayerStatic : (debris ? LayerDebris : LayerMoving));
		Jolt.JPH_BodyCreationSettings_SetUserData(settings, (uint64)transform.GameObject.Id);
		if (rigidbody != null)
		{
			Jolt.JPH_BodyCreationSettings_SetFriction(settings, rigidbody.friction);
			Jolt.JPH_BodyCreationSettings_SetRestitution(settings, rigidbody.bounciness);
			Jolt.JPH_BodyCreationSettings_SetLinearDamping(settings, rigidbody.linearDamping);
			Jolt.JPH_BodyCreationSettings_SetAngularDamping(settings, rigidbody.angularDamping);
			Jolt.JPH_BodyCreationSettings_SetGravityFactor(settings, rigidbody.useGravity ? 1.0f : 0.0f);
			Jolt.JPH_BodyCreationSettings_SetAllowSleeping(settings, rigidbody.allowSleeping);
			if (rigidbody.continuousCollision)
				Jolt.JPH_BodyCreationSettings_SetMotionQuality(settings, 1);
			if (rigidbody.freezeRotation)
				Jolt.JPH_BodyCreationSettings_SetAllowedDOFs(settings, 0b000111);
			if (motion == Jolt.MotionDynamic)
			{
				Jolt.MassProperties mass = default;
				mass.mass = Math.Max(rigidbody.mass, 0.001f);
				Jolt.JPH_BodyCreationSettings_SetOverrideMassProperties(settings, 1);
				Jolt.JPH_BodyCreationSettings_SetMassPropertiesOverride(settings, &mass);
			}
		}
		let bodyId = Jolt.JPH_BodyInterface_CreateAndAddBody(mBodyInterface, settings, Jolt.Activate);
		Jolt.JPH_BodyCreationSettings_Destroy(settings);

		let entry = new Entry();
		entry.bodyId = bodyId;
		entry.transform = transform;
		entry.dynamic = motion == Jolt.MotionDynamic;
		entry.kinematic = motion == Jolt.MotionKinematic;
		entry.lastVersion = transform.Version;
		entry.shape = shape;
		mEntries.Add(entry);
		mByBody[bodyId] = entry;
		mBroadPhaseDirty = true;
		if (debris)
		{
			mDebris.Add(bodyId);
			Jolt.tn_physics_set_debris(bodyId, true);
		}
		return bodyId;
	}

	HashSet<uint32> mDebris = new .() ~ delete _;
	List<(void* joint, uint32 a, uint32 b)> mJoints = new .() ~ delete _;

	/// True for a body made by a Rigidbody with Debris on.
	public bool IsDebris(uint32 bodyId) => mDebris.Contains(bodyId);

	/// Joins two bodies at a point in world space. With swingLimitDegrees above zero the second body can swing no
	/// further than that from the axis, like a shoulder; with zero it is a free ball joint. Returns null if either
	/// body does not exist. The Joint component does this for you.
	public void* CreateJoint(uint32 bodyA, uint32 bodyB, Vector3 anchor, Vector3 axis, float swingLimitDegrees)
	{
		if (mSystem == null || !mByBody.ContainsKey(bodyA) || !mByBody.ContainsKey(bodyB) || bodyA == bodyB)
			return null;
		var point = anchor;
		var direction = axis.LengthSquared > 1.0e-8f ? axis.Normalized : Vector3.Up;
		let joint = Jolt.tn_joint_create(mSystem, bodyA, bodyB, &point, &direction, Mathf.Clamp(swingLimitDegrees, 0, 179) * Mathf.Deg2Rad);
		if (joint != null)
			mJoints.Add((joint, bodyA, bodyB));
		return joint;
	}

	/// Safe to call with a joint that has already gone (because one of its bodies was destroyed).
	public void DestroyJoint(void* joint)
	{
		for (int i < mJoints.Count)
		{
			if (mJoints[i].joint == joint)
			{
				Jolt.tn_joint_destroy(mSystem, joint);
				mJoints.RemoveAt(i);
				return;
			}
		}
	}

	public bool HasJoint(void* joint)
	{
		for (let entry in mJoints)
		{
			if (entry.joint == joint)
				return true;
		}
		return false;
	}

	public void DestroyBody(uint32 bodyId)
	{
		if (!mByBody.TryGetValue(bodyId, let entry))
			return;
		// A joint cannot outlive either of the bodies it holds together.
		for (int i = mJoints.Count - 1; i >= 0; i--)
		{
			if (mJoints[i].a == bodyId || mJoints[i].b == bodyId)
			{
				Jolt.tn_joint_destroy(mSystem, mJoints[i].joint);
				mJoints.RemoveAt(i);
			}
		}
		if (mDebris.Remove(bodyId))
			Jolt.tn_physics_set_debris(bodyId, false);
		Jolt.JPH_BodyInterface_RemoveAndDestroyBody(mBodyInterface, bodyId);
		Jolt.JPH_Shape_Destroy(entry.shape);
		mByBody.Remove(bodyId);
		mEntries.Remove(entry);
		delete entry;
	}

	// ---- character controllers ----

	void TrackInnerBody(void* character, Transform transform)
	{
		let bodyId = Jolt.tn_character_inner_body(character);
		if (bodyId == uint32.MaxValue)
			return;
		let entry = new Entry();
		entry.bodyId = bodyId;
		entry.transform = transform;
		entry.lastVersion = transform.Version;
		entry.external = true;
		mEntries.Add(entry);
		mByBody[bodyId] = entry;
	}

	void UntrackInnerBody(void* character)
	{
		if (!mByBody.TryGetValue(Jolt.tn_character_inner_body(character), let entry))
			return;
		mByBody.Remove(entry.bodyId);
		mEntries.Remove(entry);
		delete entry;
	}

	/// Creates a character that is moved by sweeping its shape (see CharacterController). supportHeight is how far above
	/// the transform's position a contact still counts as the floor. Returns null if the shape cannot be built.
	public void* CreateCharacter(Transform transform, ShapeDesc desc, Quaternion rotationIn, float maxSlopeDegrees, float mass, float pushStrength, float supportHeight, bool soft)
	{
		EnsureCreated();
		let shape = CreateShape(desc);
		if (shape == null)
			return null;
		var position = transform.Position;
		var rotation = rotationIn;
		let character = Jolt.tn_character_create(mSystem, shape, &position, &rotation, Mathf.Clamp(maxSlopeDegrees, 1, 89) * Mathf.Deg2Rad, Math.Max(mass, 0.001f), Math.Max(pushStrength, 0), supportHeight, LayerMoving, (uint64)transform.GameObject.Id, true, soft);
		// The character and its inner body hold their own references.
		Jolt.JPH_Shape_Destroy(shape);
		if (character == null)
			return null;
		mCharacters.Add(character);
		TrackInnerBody(character, transform);
		mBroadPhaseDirty = true;
		// Find the floor now, so ground state is right before the first move.
		var velocity = Vector3.Zero;
		PrepareQuery();
		Jolt.tn_character_set_state(character, mSystem, LayerMoving, &position, &rotation, &velocity, soft);
		return character;
	}

	/// Safe to call with a character this world has already destroyed.
	public void DestroyCharacter(void* character)
	{
		if (!mCharacters.Remove(character))
			return;
		UntrackInnerBody(character);
		Jolt.tn_character_destroy(character, mSystem);
	}

	public bool HasCharacter(void* character) => character != null && mCharacters.Contains(character);

	public Jolt.CharacterState GetCharacterState(void* character)
	{
		Jolt.CharacterState state = default;
		if (HasCharacter(character))
			Jolt.tn_character_get_state(character, &state);
		return state;
	}

	/// Moves a character for one step at the given velocity, climbing steps up to stepHeight and following the floor
	/// down by the same amount. stepReach is how far past a step's edge its top is probed for a place to stand.
	public Jolt.CharacterState MoveCharacter(void* character, Vector3 velocityIn, float deltaTime, float stepHeight, float stepReach, bool soft)
	{
		Jolt.CharacterState state = default;
		if (!HasCharacter(character) || !Finite(velocityIn) || !deltaTime.IsFinite || deltaTime <= 0)
			return GetCharacterState(character);
		PrepareQuery();
		var gravity = Gravity;
		Jolt.JPH_PhysicsSystem_SetGravity(mSystem, &gravity);
		var velocity = velocityIn;
		let step = Math.Max(stepHeight, 0);
		Jolt.tn_character_move(character, mSystem, LayerMoving, &velocity, deltaTime, step, step, Math.Max(stepReach, 0.15f), soft, &state);
		return state;
	}

	/// Teleports a character and gives it a velocity; its contacts are rebuilt at the new place.
	public void SetCharacterState(void* character, Vector3 positionIn, Quaternion rotationIn, Vector3 velocityIn, bool soft)
	{
		if (!HasCharacter(character) || !Finite(positionIn) || !Finite(velocityIn) || !ValidRotation(rotationIn))
			return;
		var position = positionIn; var rotation = rotationIn; var velocity = velocityIn;
		PrepareQuery();
		Jolt.tn_character_set_state(character, mSystem, LayerMoving, &position, &rotation, &velocity, soft);
	}

	/// True if the shape fits where the character stands, allowing that much overlap with the surroundings.
	/// The character switches to the shape when it fits.
	public bool TrySetCharacterShape(void* character, ShapeDesc desc, float maxPenetration, bool soft)
	{
		if (!HasCharacter(character))
			return false;
		let shape = CreateShape(desc);
		if (shape == null)
			return false;
		PrepareQuery();
		let fits = Jolt.tn_character_set_shape(character, mSystem, LayerMoving, shape, maxPenetration, soft);
		Jolt.JPH_Shape_Destroy(shape);
		return fits;
	}

	/// Advances the simulation by one fixed tick and writes the results to the transforms.
	public void Step(float deltaTime)
	{
		if (mSystem == null || mEntries.Count == 0)
			return;
		PrepareQuery();
		var gravity = Gravity;
		Jolt.JPH_PhysicsSystem_SetGravity(mSystem, &gravity);

		// Transforms moved by gameplay or the network since the last step win over the simulation.
		for (let entry in mEntries)
		{
			if (entry.external || entry.transform.Version == entry.lastVersion)
				continue;
			var position = entry.transform.Position;
			var rotation = entry.transform.Rotation;
			if (entry.kinematic)
				Jolt.JPH_BodyInterface_MoveKinematic(mBodyInterface, entry.bodyId, &position, &rotation, deltaTime);
			else
				Jolt.JPH_BodyInterface_SetPositionAndRotation(mBodyInterface, entry.bodyId, &position, &rotation, Jolt.Activate);
		}

		Jolt.JPH_PhysicsSystem_Update(mSystem, deltaTime, 1, sJobSystem);

		for (let entry in mEntries)
		{
			if (entry.dynamic || entry.kinematic)
			{
				Vector3 position = default;
				Quaternion rotation = default;
				Jolt.JPH_BodyInterface_GetPosition(mBodyInterface, entry.bodyId, &position);
				Jolt.JPH_BodyInterface_GetRotation(mBodyInterface, entry.bodyId, &rotation);
				entry.transform.SetPositionAndRotation(position, rotation);
			}
			entry.lastVersion = entry.transform.Version;
		}
	}

	/// Pushes a transform that gameplay moved since the last step into Jolt right away, so
	/// reads and writes of body state in the same tick see the new pose.
	void Flush(uint32 bodyId)
	{
		if (!mByBody.TryGetValue(bodyId, let entry) || entry.transform.Version == entry.lastVersion)
			return;
		var position = entry.transform.Position;
		var rotation = entry.transform.Rotation;
		Jolt.JPH_BodyInterface_SetPositionAndRotation(mBodyInterface, bodyId, &position, &rotation, Jolt.Activate);
		entry.lastVersion = entry.transform.Version;
	}

	public BodyState GetState(uint32 bodyId)
	{
		BodyState state = default;
		state.rotation = .Identity;
		if (mBodyInterface == null || bodyId == uint32.MaxValue)
			return state;
		Flush(bodyId);
		Jolt.JPH_BodyInterface_GetPosition(mBodyInterface, bodyId, &state.position);
		Jolt.JPH_BodyInterface_GetRotation(mBodyInterface, bodyId, &state.rotation);
		Jolt.JPH_BodyInterface_GetLinearVelocity(mBodyInterface, bodyId, &state.linearVelocity);
		Jolt.JPH_BodyInterface_GetAngularVelocity(mBodyInterface, bodyId, &state.angularVelocity);
		return state;
	}

	/// Teleports a body to a full state (used by network corrections and rollback).
	public void SetState(uint32 bodyId, BodyState stateIn)
	{
		if (!mByBody.TryGetValue(bodyId, let entry))
			return;
		var state = stateIn;
		if (entry.dynamic)
			Jolt.JPH_BodyInterface_SetPositionRotationAndVelocity(mBodyInterface, bodyId, &state.position, &state.rotation, &state.linearVelocity, &state.angularVelocity);
		else
			Jolt.JPH_BodyInterface_SetPositionAndRotation(mBodyInterface, bodyId, &state.position, &state.rotation, Jolt.Activate);
		Jolt.JPH_BodyInterface_ActivateBody(mBodyInterface, bodyId);
		entry.transform.SetPositionAndRotation(state.position, state.rotation);
		entry.lastVersion = entry.transform.Version;
	}

	public Vector3 GetLinearVelocity(uint32 bodyId)
	{
		Vector3 v = default;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_GetLinearVelocity(mBodyInterface, bodyId, &v);
		return v;
	}

	public void SetLinearVelocity(uint32 bodyId, Vector3 velocity)
	{
		var v = velocity;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
		{
			Jolt.JPH_BodyInterface_SetLinearVelocity(mBodyInterface, bodyId, &v);
			Jolt.JPH_BodyInterface_ActivateBody(mBodyInterface, bodyId);
		}
	}

	public Vector3 GetAngularVelocity(uint32 bodyId)
	{
		Vector3 v = default;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_GetAngularVelocity(mBodyInterface, bodyId, &v);
		return v;
	}

	public void SetAngularVelocity(uint32 bodyId, Vector3 velocity)
	{
		var v = velocity;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_SetAngularVelocity(mBodyInterface, bodyId, &v);
	}

	public void AddForce(uint32 bodyId, Vector3 force)
	{
		var f = force;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_AddForce(mBodyInterface, bodyId, &f);
	}

	public void AddForceAtPosition(uint32 bodyId, Vector3 force, Vector3 point)
	{
		var f = force;
		var p = point;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
		{
			Jolt.JPH_BodyInterface_AddForce2(mBodyInterface, bodyId, &f, &p);
			Jolt.JPH_BodyInterface_ActivateBody(mBodyInterface, bodyId);
		}
	}

	/// Velocity of the point on a body at a world position (linear plus rotational).
	public Vector3 GetPointVelocity(uint32 bodyId, Vector3 point)
	{
		Vector3 v = default;
		var p = point;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_GetPointVelocity(mBodyInterface, bodyId, &p, &v);
		return v;
	}

	public void AddImpulse(uint32 bodyId, Vector3 impulse)
	{
		var i = impulse;
		if (mBodyInterface != null && bodyId != uint32.MaxValue)
			Jolt.JPH_BodyInterface_AddImpulse(mBodyInterface, bodyId, &i);
	}

	// Queries run on the scene thread, like simulation and body state changes.
	void* PrepareQuery()
	{
		if (mSystem == null) return null;
		if (mBroadPhaseDirty)
		{
			Jolt.JPH_PhysicsSystem_OptimizeBroadPhase(mSystem);
			mBroadPhaseDirty = false;
		}
		return Jolt.JPH_PhysicsSystem_GetNarrowPhaseQuery(mSystem);
	}

	static bool Finite(Vector3 v) => v.x.IsFinite && v.y.IsFinite && v.z.IsFinite;
	static bool ValidRotation(Quaternion q) => q.x.IsFinite && q.y.IsFinite && q.z.IsFinite && q.w.IsFinite && Quaternion.Dot(q, q) > 1.0e-12f;

	void* SphereQueryShape(float radius)
	{
		if (mSystem == null) return null;
		if (!radius.IsFinite || radius <= 0) return null;
		if (mSphereQueryShape == null || radius != mSphereQueryRadius)
		{
			if (mSphereQueryShape != null) Jolt.JPH_Shape_Destroy(mSphereQueryShape);
			mSphereQueryShape = Jolt.JPH_SphereShape_Create(radius);
			mSphereQueryRadius = radius;
		}
		return mSphereQueryShape;
	}

	void* CapsuleQueryShape(float halfHeight, float radius)
	{
		if (mSystem == null) return null;
		if (!radius.IsFinite || radius <= 0 || !halfHeight.IsFinite) return null;
		// Coincident end centers describe a sphere.
		if (halfHeight <= 1.0e-6f) return SphereQueryShape(radius);
		if (mCapsuleQueryShape == null || mCapsuleQuerySize.x != halfHeight || mCapsuleQuerySize.y != radius)
		{
			if (mCapsuleQueryShape != null) Jolt.JPH_Shape_Destroy(mCapsuleQueryShape);
			mCapsuleQueryShape = Jolt.JPH_CapsuleShape_Create(halfHeight, radius);
			mCapsuleQuerySize = .(halfHeight, radius);
		}
		return mCapsuleQueryShape;
	}

	void* BoxQueryShape(Vector3 size)
	{
		if (mSystem == null) return null;
		if (!Finite(size) || size.x <= 0 || size.y <= 0 || size.z <= 0) return null;
		if (mBoxQueryShape == null || mBoxQuerySize.x != size.x || mBoxQuerySize.y != size.y || mBoxQuerySize.z != size.z)
		{
			if (mBoxQueryShape != null) Jolt.JPH_Shape_Destroy(mBoxQueryShape);
			var half = size * 0.5f;
			mBoxQueryShape = Jolt.JPH_BoxShape_Create(&half, Math.Min(0.02f, Math.Min(half.x, Math.Min(half.y, half.z))));
			mBoxQuerySize = size;
		}
		return mBoxQueryShape;
	}

	ShapeCastHit MakeShapeHit(Jolt.ShapeHit nativeHit, float maxDistance)
	{
		ShapeCastHit hit = default;
		hit.bodyId = nativeHit.bodyId;
		hit.point = nativeHit.point;
		hit.normal = nativeHit.normal;
		hit.distance = Math.Max(nativeHit.fraction, 0) * maxDistance;
		hit.penetrationDepth = nativeHit.penetrationDepth;
		if (mByBody.TryGetValue(nativeHit.bodyId, let entry)) hit.gameObject = entry.transform.GameObject;
		return hit;
	}

	bool CastQuery(void* shape, Vector3 origin, Quaternion orientation, Vector3 direction, float maxDistance, out ShapeCastHit hit, uint32 ignoreBody)
	{
		hit = default;
		if (shape == null || !Finite(origin) || !Finite(direction) || direction.LengthSquared < 1.0e-12f || !direction.LengthSquared.IsFinite || !maxDistance.IsFinite || maxDistance <= 0 || !ValidRotation(orientation)) return false;
		let query = PrepareQuery();
		if (query == null) return false;
		var from = origin;
		var rotation = orientation.Normalized;
		var displacement = direction.Normalized * maxDistance;
		Jolt.ShapeHit nativeHit = default;
		if (!Jolt.tn_physics_cast_shape(query, shape, &from, &rotation, &displacement, ignoreBody, &nativeHit)) return false;
		hit = MakeShapeHit(nativeHit, maxDistance);
		return true;
	}

	/// Sweeps a sphere and returns its closest contact. Direction need not be normalized.
	/// A starting overlap returns distance zero and its penetration depth.
	public bool SphereCast(Vector3 origin, float radius, Vector3 direction, float maxDistance, out ShapeCastHit hit, uint32 ignoreBody = uint32.MaxValue)
		=> CastQuery(SphereQueryShape(radius), origin, .Identity, direction, maxDistance, out hit, ignoreBody);

	/// The endpoints are the centers of the capsule's two hemispheres.
	public bool CapsuleCast(Vector3 point1, Vector3 point2, float radius, Vector3 direction, float maxDistance, out ShapeCastHit hit, uint32 ignoreBody = uint32.MaxValue)
	{
		hit = default;
		if (!Finite(point1) || !Finite(point2)) return false;
		let axis = point2 - point1;
		let length = axis.Length;
		if (!length.IsFinite) return false;
		// Local capsule Y is aligned with the endpoint axis.
		let rotation = length < 1.0e-6f ? Quaternion.Identity : Quaternion.LookRotation(Math.Abs(axis.Normalized.z) < 0.9f ? .Forward : .Right, axis.Normalized);
		return CastQuery(CapsuleQueryShape(length * 0.5f, radius), (point1 + point2) * 0.5f, rotation, direction, maxDistance, out hit, ignoreBody);
	}

	/// Size is the full width/height/depth, matching BoxCollider.size.
	public bool BoxCast(Vector3 origin, Vector3 size, Quaternion orientation, Vector3 direction, float maxDistance, out ShapeCastHit hit, uint32 ignoreBody = uint32.MaxValue)
		=> CastQuery(BoxQueryShape(size), origin, orientation, direction, maxDistance, out hit, ignoreBody);

	int OverlapQuery(void* shape, Vector3 origin, Quaternion orientation, List<ShapeCastHit> hits, uint32 ignoreBody)
	{
		hits.Clear();
		if (shape == null || !Finite(origin) || !ValidRotation(orientation)) return 0;
		let query = PrepareQuery();
		if (query == null) return 0;
		if (mOverlapHits.Count < 64) mOverlapHits.Resize(64);
		var from = origin; var rotation = orientation.Normalized;
		var count = Jolt.tn_physics_overlap_shape(query, shape, &from, &rotation, ignoreBody, mOverlapHits.Ptr, (int32)mOverlapHits.Count);
		if (count > mOverlapHits.Count)
		{
			mOverlapHits.Resize(count);
			count = Jolt.tn_physics_overlap_shape(query, shape, &from, &rotation, ignoreBody, mOverlapHits.Ptr, (int32)mOverlapHits.Count);
		}
		for (int i < count) hits.Add(MakeShapeHit(mOverlapHits[i], 0));
		return (int)hits.Count;
	}

	/// Returns contacts, including separate subshapes of compound/mesh bodies. Clears hits first.
	public int OverlapSphere(Vector3 origin, float radius, List<ShapeCastHit> hits, uint32 ignoreBody = uint32.MaxValue)
		=> OverlapQuery(SphereQueryShape(radius), origin, .Identity, hits, ignoreBody);
	public int OverlapBox(Vector3 origin, Vector3 size, Quaternion orientation, List<ShapeCastHit> hits, uint32 ignoreBody = uint32.MaxValue)
		=> OverlapQuery(BoxQueryShape(size), origin, orientation, hits, ignoreBody);
	public int OverlapCapsule(Vector3 point1, Vector3 point2, float radius, List<ShapeCastHit> hits, uint32 ignoreBody = uint32.MaxValue)
	{
		hits.Clear();
		if (!Finite(point1) || !Finite(point2)) return 0;
		let axis = point2 - point1; let length = axis.Length;
		if (!length.IsFinite) return 0;
		let rotation = length < 1.0e-6f ? Quaternion.Identity : Quaternion.LookRotation(Math.Abs(axis.Normalized.z) < 0.9f ? .Forward : .Right, axis.Normalized);
		return OverlapQuery(CapsuleQueryShape(length * 0.5f, radius), (point1 + point2) * 0.5f, rotation, hits, ignoreBody);
	}

	/// Casts a ray and reports the closest body hit within maxDistance. Debris is passed through.
	public bool Raycast(Vector3 origin, Vector3 direction, float maxDistance, out RaycastHit hit)
	{
		hit = default;
		if (mSystem == null || direction.LengthSquared < 1.0e-12f)
			return false;
		let unit = direction.Normalized;
		let query = PrepareQuery();
		float travelled = 0;
		// Debris in the way is stepped through a little at a time until the ray is out the other side.
		for (int attempt < 96)
		{
			var from = origin + unit * travelled;
			var delta = unit * (maxDistance - travelled);
			Jolt.RayCastResult result = default;
			if (!Jolt.JPH_NarrowPhaseQuery_CastRay(query, &from, &delta, &result, null, null, null))
				return false;
			let distance = travelled + result.fraction * (maxDistance - travelled);
			if (mDebris.Contains(result.bodyId))
			{
				travelled = distance + 0.2f;
				if (travelled >= maxDistance)
					return false;
				continue;
			}
			hit.distance = distance;
			hit.point = origin + unit * distance;
			if (mByBody.TryGetValue(result.bodyId, let entry))
				hit.gameObject = entry.transform.GameObject;
			return true;
		}
		return false;
	}
}
