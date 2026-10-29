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
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/SoftBody/SoftBodyContactListener.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyManifold.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
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
	int32_t iterations;   // solver passes per step
	int32_t doubleSided;  // faces collide from both sides (cloth)
	int32_t longRange;    // keep free vertices within reach of the pins (stops cloth stretching under its weight)
	int32_t dihedral;     // bend by the angle between faces (cloth) rather than by distance (volumes)
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

/// Remembers which bodies each soft body's vertices touched, until asked (soft bodies update on the job threads).
class Touches final : public JPH::SoftBodyContactListener
{
public:
	void OnSoftBodyContactAdded(const JPH::Body& soft, const JPH::SoftBodyManifold& manifold) override
	{
		std::lock_guard<std::mutex> guard(mutex);
		auto& touched = bodies[soft.GetID().GetIndexAndSequenceNumber()];
		for (const auto& vertex : manifold.GetVertices())
		{
			if (manifold.HasContact(vertex))
				touched.insert(manifold.GetContactBodyID(vertex).GetIndexAndSequenceNumber());
		}
	}

	std::mutex mutex;
	std::unordered_map<uint32_t, std::unordered_set<uint32_t>> bodies;
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
TN_API uint32_t tn_soft_create(JPH_PhysicsSystem* world, const Config* config, const float* positions, uint32_t vertexCount, const uint32_t* triangles,
	uint32_t triangleCount, const float* pinned, const float* stiffness, const float* center)
{
	if (!world || !config || !positions || vertexCount < 3 || !triangles || triangleCount == 0)
		return 0xFFFFFFFFu;
	uint32_t free = 0;
	for (uint32_t i = 0; i < vertexCount; i++)
		free += (pinned && pinned[i] >= 0.5f) ? 0 : 1;
	const float inverseMass = free > 0 ? float(free) / std::max(config->mass, 0.001f) : 1.0f;

	JPH::Ref<JPH::SoftBodySharedSettings> shared = new JPH::SoftBodySharedSettings();
	shared->mVertices.reserve(vertexCount);
	for (uint32_t i = 0; i < vertexCount; i++)
	{
		JPH::SoftBodySharedSettings::Vertex vertex;
		vertex.mPosition = JPH::Float3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
		vertex.mInvMass = (pinned && pinned[i] >= 0.5f) ? 0.0f : inverseMass;
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
	TouchesOf(world);
	const JPH::BodyID id = Bodies(world).CreateAndAddSoftBody(settings, JPH::EActivation::Activate);
	return id.IsInvalid() ? 0xFFFFFFFFu : id.GetIndexAndSequenceNumber();
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
