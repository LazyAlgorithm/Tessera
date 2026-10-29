// Soft bodies (cloth, jelly, rubber) on Jolt's soft body simulation, behind a small C ABI for Engine/src/Physics/SoftBody.bf.
// Jolt steps them on the job threads with the rest of the world and collides them with every other body. What Jolt
// leaves to the caller lives here: building the shared settings from a mesh, moving pinned vertices with an object,
// wind on the faces, and reading the vertices back for drawing and networking. The joltc handles are Jolt's own
// objects (joltc casts them), so this file reaches past joltc where it has no call for something.
#include <Jolt/Jolt.h>
#include <Jolt/Physics/Body/Body.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Body/BodyLockInterface.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLockMulti.h>
#include <Jolt/Physics/Collision/GroupFilter.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Constraints/DistanceConstraint.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/SoftBody/SoftBodyContactListener.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyManifold.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
#include <Jolt/Core/TempAllocator.h>
#include "joltc.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#if defined(_WIN32)
#define TN_API extern "C" __declspec(dllexport)
#else
#define TN_API extern "C" __attribute__((visibility("default")))
#endif

namespace
{

/// SoftBody.bf's settings, in the same order.
struct Config
{
	float mass;           // the whole body's mass (kg), shared by the vertices that are not pinned
	float stretch;        // compliance of the edges (0 does not stretch; higher stretches more)
	float shear;          // compliance of the edges across faces
	float bend;           // compliance of bending; below 0 bends freely
	float pressure;       // pushes a closed mesh outward (jelly, balls, tyres); 0 for cloth
	float damping;        // how fast the vertices lose speed
	float friction;
	float restitution;
	float gravityFactor;
	float vertexRadius;   // how far from the surface collisions keep other things
	float dentDepth;      // shell: how far a vertex can be pushed from its place on the object in one impact
	float dentYield;      // shell: how far it springs back from; pushed further, the rest stays dented
	int32_t iterations;   // solver passes per step
	int32_t doubleSided;  // faces collide from both sides (cloth)
	int32_t longRange;    // keep free vertices within reach of the pins (stops cloth stretching under its weight)
	int32_t dihedral;     // bend by the angle between faces (cloth) rather than by distance (volumes)
	int32_t shell;        // every vertex is held near its place on the object (skinned to it), which dents
	uint32_t layer;
	uint64_t userData;
};

const JPH::BodyLockInterface& Locks(JPH_PhysicsSystem* world)
{
	return *reinterpret_cast<const JPH::BodyLockInterface*>(JPH_PhysicsSystem_GetBodyLockInterface(world));
}

JPH::BodyInterface& Bodies(JPH_PhysicsSystem* world)
{
	return *reinterpret_cast<JPH::BodyInterface*>(JPH_PhysicsSystem_GetBodyInterface(world));
}

JPH::SoftBodyMotionProperties* Soft(JPH::Body& body)
{
	return body.IsSoftBody() ? static_cast<JPH::SoftBodyMotionProperties*>(body.GetMotionProperties()) : nullptr;
}

/// joltc's JPH_PhysicsSystem (third_party/joltc/src/joltc.cpp), to reach the Jolt system it wraps.
struct JoltcSystem
{
	void* broadPhaseLayerInterface;
	void* objectLayerPairFilter;
	void* objectVsBroadPhaseLayerFilter;
	JPH::PhysicsSystem* physicsSystem;
};

JPH::Mat44 Matrix(const float* m)
{
	return JPH::Mat44(JPH::Vec4(m[0], m[1], m[2], m[3]), JPH::Vec4(m[4], m[5], m[6], m[7]), JPH::Vec4(m[8], m[9], m[10], m[11]),
		JPH::Vec4(m[12], m[13], m[14], m[15]));
}

/// A shell's places on its object as made (bind positions), to repair it and to measure its dents by.
struct Shell
{
	std::vector<JPH::Float3> original;
	// Each vertex's outward direction as made (bind space): only a push inward dents.
	std::vector<JPH::Float3> outward;
	// The vertices that touched something since the last step: only they dent (the rest were only shaken).
	std::vector<uint8_t> touched;
	JPH::Mat44 bindToObject;
	float dentYield = 0;
	bool skinned = false;
	// Where the object was when last skinned to (the end of that step), to leave a shell asleep while it stays.
	JPH::Mat44 lastObject = JPH::Mat44::sZero();
};

/// Soft bodies only meet rigid bodies in the physics engine, so a closed soft body near another soft body gets a
/// proxy: a kinematic body shaped like its surface, rebuilt every step, which other soft bodies (and nothing else)
/// collide with. Group: the soft body's id; sub group 0 a closed soft body, 1 a proxy, 2 an open one (cloth).
class SoftGroups final : public JPH::GroupFilter
{
public:
	static constexpr JPH::CollisionGroup::SubGroupID Closed = 0, Proxy = 1, Open = 2;

	bool CanCollide(const JPH::CollisionGroup& a, const JPH::CollisionGroup& b) const override
	{
		const bool aOurs = a.GetGroupFilter() == this, bOurs = b.GetGroupFilter() == this;
		const bool aProxy = aOurs && a.GetSubGroupID() == Proxy, bProxy = bOurs && b.GetSubGroupID() == Proxy;
		if (!aProxy && !bProxy)
			return true;
		// A proxy meets soft bodies only, never its own, and not another proxy.
		if (!aOurs || !bOurs || (aProxy && bProxy) || a.GetGroupID() == b.GetGroupID())
			return false;
		// Cloth meets every proxy. Of two closed bodies, only one meets the other's proxy: both at once would
		// each push against a surface that cannot give, and fight.
		const JPH::CollisionGroup& soft = aProxy ? b : a;
		const JPH::CollisionGroup& proxy = aProxy ? a : b;
		return soft.GetSubGroupID() == Open || soft.GetGroupID() > proxy.GetGroupID();
	}
};

/// Made on first use: Jolt allocates through functions it is given at start-up, after static initialisation.
SoftGroups* Groups()
{
	static JPH::Ref<SoftGroups> groups = new SoftGroups();
	return groups.GetPtr();
}

/// Every proxy's body id, for rays, shape queries and characters to pass through (tn_soft_is_proxy).
std::mutex gProxyMutex;
std::unordered_set<uint32_t> gProxies;

/// Remembers which bodies each soft body's vertices touched, until asked (soft bodies update on the job threads),
/// and keeps each soft body off the bodies it should ignore (a shell's own rigidbody).
class Touches final : public JPH::SoftBodyContactListener
{
public:
	JPH::SoftBodyValidateResult OnSoftBodyContactValidate(const JPH::Body& soft, const JPH::Body& other, JPH::SoftBodyContactSettings&) override
	{
		std::lock_guard<std::mutex> guard(mutex);
		auto found = ignored.find(soft.GetID().GetIndexAndSequenceNumber());
		if (found != ignored.end() && std::find(found->second.begin(), found->second.end(), other.GetID().GetIndexAndSequenceNumber()) != found->second.end())
			return JPH::SoftBodyValidateResult::RejectContact;
		return JPH::SoftBodyValidateResult::AcceptContact;
	}

	void OnSoftBodyContactAdded(const JPH::Body& soft, const JPH::SoftBodyManifold& manifold) override
	{
		std::lock_guard<std::mutex> guard(mutex);
		const uint32_t id = soft.GetID().GetIndexAndSequenceNumber();
		auto& touched = bodies[id];
		auto shell = shells.find(id);
		const auto& vertices = manifold.GetVertices();
		if (shell != shells.end())
			shell->second.touched.resize(vertices.size());
		for (size_t i = 0; i < vertices.size(); i++)
		{
			if (!manifold.HasContact(vertices[i]))
				continue;
			touched.insert(manifold.GetContactBodyID(vertices[i]).GetIndexAndSequenceNumber());
			if (shell != shells.end())
				shell->second.touched[i] = 1;
		}
	}

	std::mutex mutex;
	std::unordered_map<uint32_t, std::unordered_set<uint32_t>> bodies;
	std::unordered_map<uint32_t, std::vector<uint32_t>> ignored;
	std::unordered_map<uint32_t, Shell> shells;
	// Each soft body's proxy, while it has one.
	std::unordered_map<uint32_t, uint32_t> proxies;
};

std::unordered_map<JPH::PhysicsSystem*, Touches*> gTouches;

Touches& TouchesOf(JPH_PhysicsSystem* world)
{
	auto* system = reinterpret_cast<JoltcSystem*>(world)->physicsSystem;
	auto& touches = gTouches[system];
	if (touches == nullptr)
	{
		touches = new Touches();
		system->SetSoftBodyContactListener(touches);
	}
	return *touches;
}

} // namespace

/// Makes a soft body from a welded mesh: positions (x, y, z per vertex, in the world, relative to `center`),
/// triangles (three vertex indices each), pinned (per vertex, 1 held in place by MovePinned, 0 free) and stiffness
/// (per vertex, multiplies how hard it resists stretching; null for 1). Returns the body's id, or 0xFFFFFFFF.
/// A shell (config->shell) also takes `objectMatrix`, its object's local-to-world matrix as it is made (16 floats,
/// column by column), and holds every vertex within dentDepth of where it sits on the object (tn_soft_skin).
TN_API uint32_t tn_soft_create(JPH_PhysicsSystem* world, const Config* config, const float* positions, uint32_t vertexCount, const uint32_t* triangles,
	uint32_t triangleCount, const float* pinned, const float* stiffness, const float* center, const float* objectMatrix)
{
	const bool shell = config && config->shell != 0 && objectMatrix;
	if (!world || !config || !positions || vertexCount < 3 || !triangles || triangleCount == 0)
		return 0xFFFFFFFFu;
	uint32_t free = 0;
	for (uint32_t i = 0; i < vertexCount; i++)
		free += (pinned && pinned[i] >= 0.5f) ? 0 : 1;

	// Each free vertex weighs its share of the surface (a third of each face round it), so many small faces round
	// one point (a sphere's poles) are not heavy against the large ones elsewhere.
	std::vector<float> area(vertexCount, 0.0f);
	float freeArea = 0;
	for (uint32_t t = 0; t < triangleCount; t++)
	{
		const uint32_t a = triangles[t * 3], b = triangles[t * 3 + 1], c = triangles[t * 3 + 2];
		if (a >= vertexCount || b >= vertexCount || c >= vertexCount)
			continue;
		const JPH::Vec3 pa(positions[a * 3], positions[a * 3 + 1], positions[a * 3 + 2]);
		const JPH::Vec3 pb(positions[b * 3], positions[b * 3 + 1], positions[b * 3 + 2]);
		const JPH::Vec3 pc(positions[c * 3], positions[c * 3 + 1], positions[c * 3 + 2]);
		const float third = (pb - pa).Cross(pc - pa).Length() / 6.0f;
		for (uint32_t corner : { a, b, c })
			area[corner] += third;
	}
	for (uint32_t i = 0; i < vertexCount; i++)
		freeArea += (pinned && pinned[i] >= 0.5f) ? 0.0f : area[i];

	JPH::Ref<JPH::SoftBodySharedSettings> shared = new JPH::SoftBodySharedSettings();
	shared->mVertices.reserve(vertexCount);
	for (uint32_t i = 0; i < vertexCount; i++)
	{
		JPH::SoftBodySharedSettings::Vertex vertex;
		vertex.mPosition = JPH::Float3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
		const float share = (freeArea > 1.0e-9f && area[i] > 1.0e-9f) ? area[i] / freeArea : 1.0f / float(std::max(free, 1u));
		vertex.mInvMass = (pinned && pinned[i] >= 0.5f) ? 0.0f : 1.0f / std::max(config->mass * share, 1.0e-6f);
		shared->mVertices.push_back(vertex);
	}
	for (uint32_t t = 0; t < triangleCount; t++)
	{
		const uint32_t a = triangles[t * 3], b = triangles[t * 3 + 1], c = triangles[t * 3 + 2];
		if (a >= vertexCount || b >= vertexCount || c >= vertexCount || a == b || b == c || a == c)
			continue;
		shared->AddFace(JPH::SoftBodySharedSettings::Face(a, b, c));
	}
	if (shared->mFaces.empty())
		return 0xFFFFFFFFu;

	// Per vertex: softer where the stiffness map is low. A pinned vertex's edges keep the default.
	std::vector<JPH::SoftBodySharedSettings::VertexAttributes> attributes(vertexCount);
	const auto longRange = (config->longRange != 0 && free < vertexCount) ? JPH::SoftBodySharedSettings::ELRAType::EuclideanDistance : JPH::SoftBodySharedSettings::ELRAType::None;
	for (uint32_t i = 0; i < vertexCount; i++)
	{
		const float scale = stiffness ? std::max(stiffness[i], 0.02f) : 1.0f;
		attributes[i] = JPH::SoftBodySharedSettings::VertexAttributes(std::max(config->stretch, 0.0f) / scale, std::max(config->shear, 0.0f) / scale,
			config->bend < 0 ? FLT_MAX : config->bend / scale, longRange);
	}
	if (shell)
	{
		// One joint, the object: bind positions (relative to center, in the world as made) to the object's space.
		const JPH::Mat44 bindToObject = Matrix(objectMatrix).Inversed() * JPH::Mat44::sTranslation(JPH::Vec3(center[0], center[1], center[2]));
		shared->mInvBindMatrices.push_back(JPH::SoftBodySharedSettings::InvBind(0, bindToObject));
		for (uint32_t i = 0; i < vertexCount; i++)
		{
			const bool held = pinned && pinned[i] >= 0.5f;
			JPH::SoftBodySharedSettings::Skinned skinned(i, held ? 0.0f : std::max(config->dentDepth, 0.001f), FLT_MAX, 0.0f);
			skinned.mWeights[0] = JPH::SoftBodySharedSettings::SkinWeight(0, 1.0f);
			shared->mSkinnedConstraints.push_back(skinned);
		}
	}
	const auto bendType = config->bend < 0 ? JPH::SoftBodySharedSettings::EBendType::None
		: (config->dihedral != 0 ? JPH::SoftBodySharedSettings::EBendType::Dihedral : JPH::SoftBodySharedSettings::EBendType::Distance);
	shared->CreateConstraints(attributes.data(), (JPH::uint)attributes.size(), bendType);
	shared->Optimize();

	JPH::SoftBodyCreationSettings settings(shared, JPH::RVec3(center[0], center[1], center[2]), JPH::Quat::sIdentity(), (JPH::ObjectLayer)config->layer);
	settings.mUserData = config->userData;
	settings.mNumIterations = (JPH::uint32)std::clamp(config->iterations, 1, 64);
	settings.mLinearDamping = std::max(config->damping, 0.0f);
	settings.mFriction = std::max(config->friction, 0.0f);
	settings.mRestitution = std::clamp(config->restitution, 0.0f, 1.0f);
	settings.mGravityFactor = config->gravityFactor;
	settings.mPressure = std::max(config->pressure, 0.0f);
	settings.mVertexRadius = std::max(config->vertexRadius, 0.0f);
	settings.mFacesDoubleSided = config->doubleSided != 0;
	settings.mUpdatePosition = true;
	settings.mMakeRotationIdentity = true;
	settings.mAllowSleeping = true;
	auto& touches = TouchesOf(world);
	const JPH::BodyID id = Bodies(world).CreateAndAddSoftBody(settings, JPH::EActivation::Activate);
	if (id.IsInvalid())
		return 0xFFFFFFFFu;
	{
		JPH::BodyLockWrite lock(Locks(world), id);
		if (lock.Succeeded())
			lock.GetBody().SetCollisionGroup(JPH::CollisionGroup(Groups(), id.GetIndexAndSequenceNumber(),
				(config->pressure > 0 || config->shell != 0 || config->doubleSided == 0) ? SoftGroups::Closed : SoftGroups::Open));
	}
	if (shell)
	{
		std::lock_guard<std::mutex> guard(touches.mutex);
		auto& kept = touches.shells[id.GetIndexAndSequenceNumber()];
		kept.bindToObject = shared->mInvBindMatrices[0].mInvBind;
		kept.dentYield = std::max(config->dentYield, 0.0f);
		for (const auto& vertex : shared->mVertices)
			kept.original.push_back(vertex.mPosition);
		std::vector<JPH::Vec3> outward(shared->mVertices.size(), JPH::Vec3::sZero());
		for (const auto& face : shared->mFaces)
		{
			const JPH::Vec3 a(shared->mVertices[face.mVertex[0]].mPosition), b(shared->mVertices[face.mVertex[1]].mPosition),
				c(shared->mVertices[face.mVertex[2]].mPosition);
			const JPH::Vec3 normal = (b - a).Cross(c - a);
			for (uint32_t corner : face.mVertex)
				outward[corner] += normal;
		}
		for (const auto& normal : outward)
		{
			kept.outward.emplace_back();
			normal.NormalizedOr(JPH::Vec3::sZero()).StoreFloat3(&kept.outward.back());
		}
	}
	return id.GetIndexAndSequenceNumber();
}

TN_API uint32_t tn_soft_vertex_count(JPH_PhysicsSystem* world, uint32_t bodyId)
{
	JPH::BodyLockRead lock(Locks(world), JPH::BodyID(bodyId));
	if (!lock.Succeeded())
		return 0;
	auto* soft = Soft(const_cast<JPH::Body&>(lock.GetBody()));
	return soft ? (uint32_t)soft->GetVertices().size() : 0;
}

/// The vertices where they are now, in the world (x, y, z each), and how fast they move if velocities is not null.
TN_API uint32_t tn_soft_read(JPH_PhysicsSystem* world, uint32_t bodyId, float* positions, float* velocities, uint32_t capacity)
{
	JPH::BodyLockRead lock(Locks(world), JPH::BodyID(bodyId));
	if (!lock.Succeeded())
		return 0;
	const JPH::Body& body = lock.GetBody();
	auto* soft = Soft(const_cast<JPH::Body&>(body));
	if (!soft)
		return 0;
	const JPH::RMat44 transform = body.GetCenterOfMassTransform();
	const auto& vertices = soft->GetVertices();
	const uint32_t count = std::min<uint32_t>((uint32_t)vertices.size(), capacity);
	for (uint32_t i = 0; i < count; i++)
	{
		const JPH::RVec3 p = transform * vertices[i].mPosition;
		positions[i * 3] = float(p.GetX());
		positions[i * 3 + 1] = float(p.GetY());
		positions[i * 3 + 2] = float(p.GetZ());
		if (velocities)
		{
			const JPH::Vec3 v = transform.Multiply3x3(vertices[i].mVelocity);
			velocities[i * 3] = v.GetX();
			velocities[i * 3 + 1] = v.GetY();
			velocities[i * 3 + 2] = v.GetZ();
		}
	}
	return count;
}

/// Moves pinned vertices (indices) to where they should be by the end of the next step (targets in the world): each
/// gets the speed that takes it there in `step` seconds, so what it touches on the way is pushed rather than jumped
/// through. Wakes the body when anything moves.
TN_API void tn_soft_move_pinned(JPH_PhysicsSystem* world, uint32_t bodyId, const uint32_t* indices, const float* targets, uint32_t count, float step)
{
	if (count == 0 || step <= 0)
		return;
	bool moved = false;
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		const JPH::RMat44 inverse = body.GetInverseCenterOfMassTransform();
		auto& vertices = soft->GetVertices();
		for (uint32_t i = 0; i < count; i++)
		{
			if (indices[i] >= vertices.size())
				continue;
			auto& vertex = vertices[indices[i]];
			const JPH::Vec3 target = JPH::Vec3(inverse * JPH::RVec3(targets[i * 3], targets[i * 3 + 1], targets[i * 3 + 2]));
			vertex.mVelocity = (target - vertex.mPosition) / step;
			moved |= vertex.mVelocity.LengthSq() > 1.0e-8f;
		}
	}
	if (moved)
		Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// Puts every vertex at a place in the world, still (after a teleport, or a correction from the server).
TN_API void tn_soft_set_positions(JPH_PhysicsSystem* world, uint32_t bodyId, const float* positions, const float* velocities, uint32_t count)
{
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		const JPH::RMat44 transform = body.GetCenterOfMassTransform();
		const JPH::RMat44 inverse = body.GetInverseCenterOfMassTransform();
		auto& vertices = soft->GetVertices();
		const uint32_t n = std::min<uint32_t>(count, (uint32_t)vertices.size());
		for (uint32_t i = 0; i < n; i++)
		{
			vertices[i].mPosition = JPH::Vec3(inverse * JPH::RVec3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]));
			vertices[i].mPreviousPosition = vertices[i].mPosition;
			vertices[i].mVelocity = velocities ? transform.Multiply3x3Transposed(JPH::Vec3(velocities[i * 3], velocities[i * 3 + 1], velocities[i * 3 + 2])) : JPH::Vec3::sZero();
		}
	}
	Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// Air moving at `wind` (m/s, in the world) pushes on each face by how squarely it meets it: half the air's density
/// times drag times area times the speed into the face squared, shared by the face's free vertices, over `step` seconds.
TN_API void tn_soft_wind(JPH_PhysicsSystem* world, uint32_t bodyId, const float* wind, float drag, float step)
{
	if (drag <= 0 || step <= 0)
		return;
	const JPH::Vec3 air(wind[0], wind[1], wind[2]);
	bool pushed = false;
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		const JPH::Vec3 localAir = body.GetInverseCenterOfMassTransform().Multiply3x3(air);
		auto& vertices = soft->GetVertices();
		const float density = 1.2f;
		for (const auto& face : soft->GetSettings()->mFaces)
		{
			auto& a = vertices[face.mVertex[0]];
			auto& b = vertices[face.mVertex[1]];
			auto& c = vertices[face.mVertex[2]];
			JPH::Vec3 normal = (b.mPosition - a.mPosition).Cross(c.mPosition - a.mPosition);
			const float twiceArea = normal.Length();
			if (twiceArea < 1.0e-9f)
				continue;
			normal /= twiceArea;
			const JPH::Vec3 relative = localAir - (a.mVelocity + b.mVelocity + c.mVelocity) / 3.0f;
			const float into = normal.Dot(relative);
			const JPH::Vec3 impulse = normal * (0.5f * density * drag * 0.5f * twiceArea * into * std::abs(into) * step / 3.0f);
			for (auto* vertex : { &a, &b, &c })
				vertex->mVelocity += impulse * vertex->mInvMass;
			pushed |= std::abs(into) > 0.01f;
		}
	}
	if (pushed)
		Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// The bodies a soft body's vertices have touched since this was last asked (up to capacity of them); returns how many.
TN_API uint32_t tn_soft_touching(JPH_PhysicsSystem* world, uint32_t bodyId, uint32_t* output, uint32_t capacity)
{
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	auto found = touches.bodies.find(bodyId);
	if (found == touches.bodies.end())
		return 0;
	uint32_t count = 0;
	for (uint32_t id : found->second)
	{
		if (count < capacity)
			output[count] = id;
		count++;
	}
	touches.bodies.erase(found);
	return std::min(count, capacity);
}

/// Forgets a world's contact listener (when the world is destroyed).
TN_API void tn_soft_world_destroyed(JPH_PhysicsSystem* world)
{
	auto* system = reinterpret_cast<JoltcSystem*>(world)->physicsSystem;
	auto found = gTouches.find(system);
	if (found == gTouches.end())
		return;
	system->SetSoftBodyContactListener(nullptr);
	{
		std::lock_guard<std::mutex> guard(gProxyMutex);
		for (const auto& [owner, proxy] : found->second->proxies)
			gProxies.erase(proxy);
	}
	delete found->second;
	gTouches.erase(found);
}

/// Moves every vertex by an offset (in the world), keeping how they move: a teleport, or easing towards where the
/// server says the body is.
TN_API void tn_soft_shift(JPH_PhysicsSystem* world, uint32_t bodyId, const float* offset)
{
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		const JPH::Vec3 local = body.GetInverseCenterOfMassTransform().Multiply3x3(JPH::Vec3(offset[0], offset[1], offset[2]));
		for (auto& vertex : soft->GetVertices())
		{
			vertex.mPosition += local;
			vertex.mPreviousPosition += local;
		}
	}
	Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// Keeps a soft body's vertices from colliding with a body (a shell's own rigidbody, what a rope is tied to);
/// 0xFFFFFFFF forgets them all.
TN_API void tn_soft_ignore(JPH_PhysicsSystem* world, uint32_t bodyId, uint32_t ignoredBody)
{
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	if (ignoredBody == 0xFFFFFFFFu)
		touches.ignored.erase(bodyId);
	else
		touches.ignored[bodyId].push_back(ignoredBody);
}

/// Forgets what was kept about a soft body (when it is removed).
void RemoveProxy(JPH_PhysicsSystem* world, uint32_t proxy);

TN_API void tn_soft_forget(JPH_PhysicsSystem* world, uint32_t bodyId)
{
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	auto proxy = touches.proxies.find(bodyId);
	if (proxy != touches.proxies.end())
	{
		RemoveProxy(world, proxy->second);
		touches.proxies.erase(proxy);
	}
	touches.ignored.erase(bodyId);
	touches.shells.erase(bodyId);
	touches.bodies.erase(bodyId);
}

namespace
{

/// Where a shell's vertex sits on its object now, in the body's space: object (bind to object, then to the world)
/// then into the body.
JPH::Mat44 BindToBody(const JPH::Body& body, const Shell& shell, const float* objectMatrix)
{
	const JPH::Mat44 worldToBody = body.GetInverseCenterOfMassTransform().ToMat44();
	return worldToBody * Matrix(objectMatrix) * shell.bindToObject;
}

/// Edges' rest lengths from the bind positions (after dents moved them), so the edges keep a dent rather than
/// pulling it back out.
void RestLengthsFromBind(JPH::SoftBodySharedSettings& settings)
{
	for (auto& edge : settings.mEdgeConstraints)
	{
		const JPH::Vec3 a(settings.mVertices[edge.mVertex[0]].mPosition), b(settings.mVertices[edge.mVertex[1]].mPosition);
		edge.mRestLength = (b - a).Length();
	}
}

} // namespace

/// Before a step, for a shell: dents (vertices pushed further than dentYield from their place keep the rest of the
/// way as their new place), springs the rest back towards their places, and holds every vertex within dentDepth of
/// where its object will put it by the end of the step. objectMatrix: the object's local-to-world matrix now;
/// objectNext: where it will be after the step (it moves with its rigidbody during the step).
TN_API void tn_soft_skin(JPH_PhysicsSystem* world, uint32_t bodyId, const float* objectMatrix, const float* objectNext, float step)
{
	static JPH::TempAllocatorMalloc temp;
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	auto found = touches.shells.find(bodyId);
	if (found == touches.shells.end())
		return;
	Shell& shell = found->second;
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		// Asleep, with its object where it was: nothing to do, and no reason to wake it.
		const JPH::Mat44 next = Matrix(objectNext);
		if (shell.skinned && !body.IsActive() && next == shell.lastObject)
			return;
		shell.lastObject = next;
		auto& settings = const_cast<JPH::SoftBodySharedSettings&>(*soft->GetSettings());
		const JPH::Mat44 bindToBody = BindToBody(body, shell, objectMatrix);
		const JPH::Mat44 bindToBodyNext = BindToBody(body, shell, objectNext);
		const JPH::Mat44 bodyToBind = bindToBody.Inversed();
		auto& vertices = soft->GetVertices();
		bool dented = false;
		if (shell.skinned)
		{
			for (uint32_t i = 0; i < vertices.size(); i++)
			{
				auto& vertex = vertices[i];
				if (vertex.mInvMass == 0)
					continue;
				auto& bind = settings.mVertices[i].mPosition;
				const JPH::Vec3 place = bindToBody * JPH::Vec3(bind);
				// Only a push into the surface by something it touched dents it; dragging along it (friction) and
				// shaking (the object stopping short) spring back.
				const JPH::Vec3 out = bindToBody.Multiply3x3(JPH::Vec3(shell.outward[i])).NormalizedOr(JPH::Vec3::sZero());
				const JPH::Vec3 away = vertex.mPosition - place;
				const float depth = -away.Dot(out);
				const bool hit = i < shell.touched.size() && shell.touched[i] != 0;
				if (hit && depth > shell.dentYield)
				{
					// Pushed in past what springs back: the rest of the way it was pushed is a dent.
					JPH::Vec3(bodyToBind * (place + away * (1.0f - shell.dentYield / depth))).StoreFloat3(&bind);
					dented = true;
				}
				// What is left springs back over a few steps, and wobbling on the object dies away; the object's
				// own motion carries the vertex.
				if (step > 0)
				{
					const JPH::Vec3 now = bindToBody * JPH::Vec3(bind);
					const JPH::Vec3 carried = (bindToBodyNext * JPH::Vec3(bind) - now) / step;
					const JPH::Vec3 back = now - vertex.mPosition;
					vertex.mVelocity = carried + (vertex.mVelocity - carried) * 0.75f + back * (0.25f / step);
				}
			}
		}
		std::fill(shell.touched.begin(), shell.touched.end(), 0);
		if (dented)
			RestLengthsFromBind(settings);
		const JPH::Mat44 joint = body.GetInverseCenterOfMassTransform().ToMat44() * Matrix(objectNext);
		soft->SkinVertices(body.GetCenterOfMassTransform(), &joint, 1, !shell.skinned, temp);
		shell.skinned = true;
		if (body.IsActive() && !dented)
			return;
	}
	Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// A shell's dents: per vertex, how far it has been moved on its object (in the object's space, x, y, z each).
TN_API uint32_t tn_soft_dents(JPH_PhysicsSystem* world, uint32_t bodyId, float* output, uint32_t capacity)
{
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	auto found = touches.shells.find(bodyId);
	if (found == touches.shells.end())
		return 0;
	JPH::BodyLockRead lock(Locks(world), JPH::BodyID(bodyId));
	if (!lock.Succeeded())
		return 0;
	auto* soft = Soft(const_cast<JPH::Body&>(lock.GetBody()));
	if (!soft)
		return 0;
	const auto& settings = *soft->GetSettings();
	const Shell& shell = found->second;
	const uint32_t count = std::min<uint32_t>((uint32_t)settings.mVertices.size(), capacity);
	for (uint32_t i = 0; i < count; i++)
	{
		const JPH::Vec3 moved = shell.bindToObject.Multiply3x3(JPH::Vec3(settings.mVertices[i].mPosition) - JPH::Vec3(shell.original[i]));
		moved.StoreFloat3(reinterpret_cast<JPH::Float3*>(output + i * 3));
	}
	return count;
}

/// Sets a shell's dents (as tn_soft_dents gives them; null repairs it), moving its vertices to match.
TN_API void tn_soft_set_dents(JPH_PhysicsSystem* world, uint32_t bodyId, const float* dents, uint32_t count, const float* objectMatrix)
{
	auto& touches = TouchesOf(world);
	std::lock_guard<std::mutex> guard(touches.mutex);
	auto found = touches.shells.find(bodyId);
	if (found == touches.shells.end())
		return;
	{
		JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
		if (!lock.Succeeded())
			return;
		JPH::Body& body = lock.GetBody();
		auto* soft = Soft(body);
		if (!soft)
			return;
		Shell& shell = found->second;
		auto& settings = const_cast<JPH::SoftBodySharedSettings&>(*soft->GetSettings());
		const JPH::Mat44 objectToBind = shell.bindToObject.Inversed();
		const JPH::Mat44 bindToBody = BindToBody(body, shell, objectMatrix);
		auto& vertices = soft->GetVertices();
		for (uint32_t i = 0; i < settings.mVertices.size(); i++)
		{
			JPH::Vec3 bind(shell.original[i]);
			if (dents && i < count)
				bind += objectToBind.Multiply3x3(JPH::Vec3(dents[i * 3], dents[i * 3 + 1], dents[i * 3 + 2]));
			bind.StoreFloat3(&settings.mVertices[i].mPosition);
			vertices[i].mPosition = bindToBody * bind;
			vertices[i].mPreviousPosition = vertices[i].mPosition;
			vertices[i].mVelocity = JPH::Vec3::sZero();
		}
		RestLengthsFromBind(settings);
		shell.skinned = false;
	}
	Bodies(world).ActivateBody(JPH::BodyID(bodyId));
}

/// Changes how hard a closed soft body's air pushes out (Jolt's n R T: pressure times rest volume).
TN_API void tn_soft_set_pressure(JPH_PhysicsSystem* world, uint32_t bodyId, float pressure)
{
	JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
	if (!lock.Succeeded())
		return;
	if (auto* soft = Soft(lock.GetBody()))
		soft->SetPressure(std::max(pressure, 0.0f));
}

/// Slows the vertices' movement against the body as a whole (its wobbling, and springing back from a squash) by
/// `rate` a second, leaving how the whole body moves alone.
TN_API void tn_soft_damp_wobble(JPH_PhysicsSystem* world, uint32_t bodyId, float rate, float step)
{
	if (rate <= 0 || step <= 0)
		return;
	JPH::BodyLockWrite lock(Locks(world), JPH::BodyID(bodyId));
	if (!lock.Succeeded() || !lock.GetBody().IsActive())
		return;
	auto* soft = Soft(lock.GetBody());
	if (!soft)
		return;
	auto& vertices = soft->GetVertices();
	JPH::Vec3 momentum = JPH::Vec3::sZero();
	float mass = 0;
	for (const auto& vertex : vertices)
	{
		if (vertex.mInvMass <= 0)
			continue;
		momentum += vertex.mVelocity / vertex.mInvMass;
		mass += 1.0f / vertex.mInvMass;
	}
	if (mass <= 0)
		return;
	const JPH::Vec3 whole = momentum / mass;
	const float keep = std::max(0.0f, 1.0f - rate * step);
	for (auto& vertex : vertices)
	{
		if (vertex.mInvMass > 0)
			vertex.mVelocity = whole + (vertex.mVelocity - whole) * keep;
	}
}


extern "C" void tn_physics_set_debris(uint32_t bodyId, bool debris);

void RemoveProxy(JPH_PhysicsSystem* world, uint32_t proxy)
{
	Bodies(world).RemoveBody(JPH::BodyID(proxy));
	Bodies(world).DestroyBody(JPH::BodyID(proxy));
	tn_physics_set_debris(proxy, false);
	std::lock_guard<std::mutex> guard(gProxyMutex);
	gProxies.erase(proxy);
}

/// Whether a body is a soft body's proxy (which only other soft bodies touch).
TN_API bool tn_soft_is_proxy(uint32_t bodyId)
{
	std::lock_guard<std::mutex> guard(gProxyMutex);
	return gProxies.count(bodyId) != 0;
}

/// Before a step: each closed soft body (closed[i] != 0) within reach of another soft body gets a proxy shaped like
/// its surface where it is now, moving as it moves; the others lose theirs.
TN_API void tn_soft_proxies(JPH_PhysicsSystem* world, const uint32_t* bodies, const int32_t* closed, const float* reach, uint32_t count)
{
	auto& touches = TouchesOf(world);
	std::vector<JPH::AABox> bounds(count);
	std::vector<bool> awake(count, false);
	for (uint32_t i = 0; i < count; i++)
	{
		JPH::BodyLockRead lock(Locks(world), JPH::BodyID(bodies[i]));
		if (!lock.Succeeded())
			continue;
		bounds[i] = lock.GetBody().GetWorldSpaceBounds();
		bounds[i].ExpandBy(JPH::Vec3::sReplicate(reach[i]));
		awake[i] = lock.GetBody().IsActive();
	}
	for (uint32_t i = 0; i < count; i++)
	{
		bool near = false;
		for (uint32_t j = 0; j < count && closed[i] != 0 && !near; j++)
			near = j != i && (awake[i] || awake[j]) && bounds[i].Overlaps(bounds[j]);
		std::lock_guard<std::mutex> guard(touches.mutex);
		auto found = touches.proxies.find(bodies[i]);
		if (!near)
		{
			if (found != touches.proxies.end())
			{
				RemoveProxy(world, found->second);
				touches.proxies.erase(found);
			}
			continue;
		}

		// The surface where it is now, about its middle, and how fast it moves as a whole.
		JPH::VertexList points;
		JPH::IndexedTriangleList triangles;
		JPH::RVec3 middle;
		JPH::Vec3 velocity = JPH::Vec3::sZero();
		JPH::ObjectLayer layer;
		{
			JPH::BodyLockRead lock(Locks(world), JPH::BodyID(bodies[i]));
			if (!lock.Succeeded())
				continue;
			const JPH::Body& body = lock.GetBody();
			auto* soft = Soft(const_cast<JPH::Body&>(body));
			const JPH::Mat44 turn = body.GetCenterOfMassTransform().GetRotation();
			middle = body.GetCenterOfMassPosition();
			layer = body.GetObjectLayer();
			for (const auto& vertex : soft->GetVertices())
			{
				points.push_back(JPH::Float3());
				(turn * vertex.mPosition).StoreFloat3(&points.back());
				velocity += vertex.mVelocity;
			}
			velocity = turn.Multiply3x3(velocity / float(std::max<size_t>(points.size(), 1)));
			for (const auto& face : soft->GetSettings()->mFaces)
				triangles.push_back(JPH::IndexedTriangle(face.mVertex[0], face.mVertex[1], face.mVertex[2]));
		}
		JPH::MeshShapeSettings mesh(std::move(points), std::move(triangles));
		auto made = mesh.Create();
		if (made.HasError())
			continue;
		if (found == touches.proxies.end())
		{
			JPH::BodyCreationSettings settings(made.Get(), middle, JPH::Quat::sIdentity(), JPH::EMotionType::Kinematic, layer);
			settings.mOverrideMassProperties = JPH::EOverrideMassProperties::MassAndInertiaProvided;
			settings.mMassPropertiesOverride.mMass = 1.0f;
			settings.mMassPropertiesOverride.mInertia = JPH::Mat44::sIdentity();
			settings.mCollisionGroup = JPH::CollisionGroup(Groups(), bodies[i], SoftGroups::Proxy);
			settings.mAllowSleeping = false;
			const JPH::BodyID proxy = Bodies(world).CreateAndAddBody(settings, JPH::EActivation::Activate);
			if (proxy.IsInvalid())
				continue;
			touches.proxies[bodies[i]] = proxy.GetIndexAndSequenceNumber();
			tn_physics_set_debris(proxy.GetIndexAndSequenceNumber(), true);
			std::lock_guard<std::mutex> proxyGuard(gProxyMutex);
			gProxies.insert(proxy.GetIndexAndSequenceNumber());
		}
		else
		{
			const JPH::BodyID proxy(found->second);
			Bodies(world).SetShape(proxy, made.Get(), false, JPH::EActivation::Activate);
			Bodies(world).SetPositionAndRotation(proxy, middle, JPH::Quat::sIdentity(), JPH::EActivation::Activate);
			Bodies(world).SetLinearVelocity(proxy, velocity);
		}
	}
}

namespace
{

/// Rope.bf's settings, in the same order.
struct RopeConfig
{
	float mass;          // the whole rope's mass (kg), shared by its free points
	float stretch;       // compliance of each length of rope (0 does not stretch)
	float bend;          // compliance of bending and twisting where lengths meet
	float damping;
	float friction;
	float restitution;
	float gravityFactor;
	float radius;        // half its thickness: how far from its line it keeps other things
	int32_t iterations;
	uint32_t layer;
	uint64_t userData;
};

} // namespace

/// Makes a rope: points along it (x, y, z each, in the world, relative to `center`), the first and last held where
/// pinned says (1 held, 0 free). Each length between points is a Cosserat rod: it keeps its length and resists
/// bending and twisting against the next. Returns the body's id, or 0xFFFFFFFF.
TN_API uint32_t tn_rope_create(JPH_PhysicsSystem* world, const RopeConfig* config, const float* positions, uint32_t count, const float* pinned, const float* center)
{
	if (!world || !config || !positions || count < 2)
		return 0xFFFFFFFFu;
	uint32_t free = 0;
	for (uint32_t i = 0; i < count; i++)
		free += (pinned && pinned[i] >= 0.5f) ? 0 : 1;
	const float inverseMass = free > 0 ? float(free) / std::max(config->mass, 0.001f) : 1.0f;
	JPH::Ref<JPH::SoftBodySharedSettings> shared = new JPH::SoftBodySharedSettings();
	for (uint32_t i = 0; i < count; i++)
	{
		JPH::SoftBodySharedSettings::Vertex vertex;
		vertex.mPosition = JPH::Float3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
		vertex.mInvMass = (pinned && pinned[i] >= 0.5f) ? 0.0f : inverseMass;
		shared->mVertices.push_back(vertex);
		if (i > 0)
			shared->mRodStretchShearConstraints.push_back(JPH::SoftBodySharedSettings::RodStretchShear(i - 1, i, std::max(config->stretch, 0.0f)));
		if (i > 1)
			shared->mRodBendTwistConstraints.push_back(JPH::SoftBodySharedSettings::RodBendTwist(i - 2, i - 1, std::max(config->bend, 0.0f)));
	}
	shared->CalculateRodProperties();
	// From each held end, no point gets further away than the rope between them is long: a long rope holding
	// weight does not stretch however few passes the solver makes.
	for (uint32_t end : { 0u, count - 1 })
	{
		if (!pinned || pinned[end] < 0.5f)
			continue;
		float along = 0;
		for (uint32_t step = 1; step < count; step++)
		{
			const uint32_t i = end == 0 ? step : count - 1 - step;
			const uint32_t before = end == 0 ? i - 1 : i + 1;
			along += (JPH::Vec3(shared->mVertices[i].mPosition) - JPH::Vec3(shared->mVertices[before].mPosition)).Length();
			if (pinned[i] >= 0.5f)
				continue;
			JPH::SoftBodySharedSettings::LRA reach(end, i, along);
			shared->mLRAConstraints.push_back(reach);
		}
	}
	shared->Optimize();

	JPH::SoftBodyCreationSettings settings(shared, JPH::RVec3(center[0], center[1], center[2]), JPH::Quat::sIdentity(), (JPH::ObjectLayer)config->layer);
	settings.mUserData = config->userData;
	settings.mNumIterations = (JPH::uint32)std::clamp(config->iterations, 1, 64);
	settings.mLinearDamping = std::max(config->damping, 0.0f);
	settings.mFriction = std::max(config->friction, 0.0f);
	settings.mRestitution = std::clamp(config->restitution, 0.0f, 1.0f);
	settings.mGravityFactor = config->gravityFactor;
	settings.mVertexRadius = std::max(config->radius, 0.0f);
	settings.mUpdatePosition = true;
	settings.mMakeRotationIdentity = true;
	settings.mAllowSleeping = true;
	TouchesOf(world);
	const JPH::BodyID id = Bodies(world).CreateAndAddSoftBody(settings, JPH::EActivation::Activate);
	if (id.IsInvalid())
		return 0xFFFFFFFFu;
	JPH::BodyLockWrite lock(Locks(world), id);
	if (lock.Succeeded())
		lock.GetBody().SetCollisionGroup(JPH::CollisionGroup(Groups(), id.GetIndexAndSequenceNumber(), SoftGroups::Open));
	return id.GetIndexAndSequenceNumber();
}

/// Ties two bodies (0xFFFFFFFF for a point fixed in the world) so that their points (in the world, as they are now)
/// get no further apart than `length`: the rope's pull. Returns the tie, for tn_rope_untie.
TN_API void* tn_rope_tie(JPH_PhysicsSystem* world, uint32_t bodyA, const float* pointA, uint32_t bodyB, const float* pointB, float length)
{
	auto* system = reinterpret_cast<JoltcSystem*>(world)->physicsSystem;
	JPH::DistanceConstraintSettings settings;
	settings.mSpace = JPH::EConstraintSpace::WorldSpace;
	settings.mPoint1 = JPH::RVec3(pointA[0], pointA[1], pointA[2]);
	settings.mPoint2 = JPH::RVec3(pointB[0], pointB[1], pointB[2]);
	settings.mMinDistance = 0;
	settings.mMaxDistance = std::max(length, 0.001f);
	JPH::BodyID ids[2] = { JPH::BodyID(bodyA), JPH::BodyID(bodyB) };
	JPH::BodyLockMultiWrite lock(system->GetBodyLockInterface(), ids, 2);
	JPH::Body* a = bodyA == 0xFFFFFFFFu ? &JPH::Body::sFixedToWorld : lock.GetBody(0);
	JPH::Body* b = bodyB == 0xFFFFFFFFu ? &JPH::Body::sFixedToWorld : lock.GetBody(1);
	if (a == nullptr || b == nullptr || a == b)
		return nullptr;
	JPH::TwoBodyConstraint* tie = settings.Create(*a, *b);
	tie->AddRef();
	system->AddConstraint(tie);
	return tie;
}

/// Lets go of a tie (tn_rope_tie).
TN_API void tn_rope_untie(JPH_PhysicsSystem* world, void* tie)
{
	if (!tie)
		return;
	auto* constraint = static_cast<JPH::TwoBodyConstraint*>(tie);
	reinterpret_cast<JoltcSystem*>(world)->physicsSystem->RemoveConstraint(constraint);
	constraint->Release();
}

/// How hard a tie pulled in its last step, in newtons.
TN_API float tn_rope_pull(void* tie, float step)
{
	if (!tie || step <= 0)
		return 0;
	return std::abs(static_cast<JPH::DistanceConstraint*>(tie)->GetTotalLambdaPosition()) / step;
}
