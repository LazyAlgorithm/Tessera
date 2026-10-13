// Keeps JoltC's collector and transform ABI out of the Beef-facing API.
#include "joltc.h"
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_set>
#include <utility>
#include <vector>

// Bodies marked as debris (corpses, dropped items): shape casts and overlaps pass through them.
static std::unordered_set<uint32_t> gDebris;

extern "C" void tn_physics_set_debris(uint32_t bodyId, bool debris) {
    if (debris) gDebris.insert(bodyId); else gDebris.erase(bodyId);
}

// Ray and shape queries see only the physics layers in a mask. A Jolt object layer is the engine's motion class
// times 32 plus the project's layer (0-31), so the low five bits are the layer. Queries run on one thread at a time.
static uint32_t gQueryMask = 0xFFFFFFFFu;
static bool JPH_API_CALL queryLayerAllowed(void*, JPH_ObjectLayer layer) {
    return ((gQueryMask >> (layer & 31u)) & 1u) != 0;
}

// The filter for a query with that mask; null (no filtering) for every layer.
extern "C" const JPH_ObjectLayerFilter* tn_physics_layer_filter(uint32_t mask) {
    static JPH_ObjectLayerFilter* filter = nullptr;
    if (filter == nullptr) {
        static const JPH_ObjectLayerFilter_Procs procs{queryLayerAllowed};
        JPH_ObjectLayerFilter_SetProcs(&procs);
        filter = JPH_ObjectLayerFilter_Create(nullptr);
    }
    gQueryMask = mask;
    return mask == 0xFFFFFFFFu ? nullptr : filter;
}

struct TnShapeHit {
    uint32_t bodyId;
    float fraction;
    JPH_Vec3 point;
    JPH_Vec3 normal;
    float penetrationDepth;
};

static JPH_Vec3 outwardNormal(const JPH_Vec3& axis) {
    const float length = std::sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
    if (length < 1.0e-8f) return {0, 0, 0};
    return {-axis.x / length, -axis.y / length, -axis.z / length};
}

struct CastContext {
    uint32_t ignoreBody;
    TnShapeHit* hit;
};

static float collectCast(void* user, const JPH_ShapeCastResult* result) {
    auto& context = *static_cast<CastContext*>(user);
    if (result->bodyID2 == context.ignoreBody || gDebris.count(result->bodyID2)) return context.hit->fraction;
    auto& hit = *context.hit;
    if (hit.bodyId == UINT32_MAX || result->fraction < hit.fraction) {
        hit = {result->bodyID2, result->fraction, result->contactPointOn2,
               outwardNormal(result->penetrationAxis), result->penetrationDepth};
    }
    return hit.fraction;
}

extern "C" bool tn_physics_cast_shape(const JPH_NarrowPhaseQuery* query,
    const JPH_Shape* shape, const JPH_RVec3* origin, const JPH_Quat* rotation,
    const JPH_Vec3* displacement, uint32_t ignoreBody, TnShapeHit* hit, uint32_t layerMask) {
    *hit = {UINT32_MAX, 1, {0, 0, 0}, {0, 0, 0}, 0};
    JPH_RMat4 transform;
    #ifdef JPH_DOUBLE_PRECISION
    JPH_RMat4_RotationTranslation(&transform, rotation, origin);
#else
    JPH_Mat4_RotationTranslation(&transform, rotation, origin);
#endif
    JPH_ShapeCastSettings settings;
    JPH_ShapeCastSettings_Init(&settings);
    settings.returnDeepestPoint = true;
    settings.backFaceModeConvex = JPH_BackFaceMode_CollideWithBackFaces;
    JPH_RVec3 baseOffset{0, 0, 0};
    CastContext context{ignoreBody, hit};
    JPH_NarrowPhaseQuery_CastShape(query, shape, &transform, displacement, &settings,
        &baseOffset, collectCast, &context, nullptr, tn_physics_layer_filter(layerMask), nullptr, nullptr);
    return hit->bodyId != UINT32_MAX;
}

struct OverlapContext {
    uint32_t ignoreBody;
    TnShapeHit* hits;
    int capacity;
    int count;
};

static void collectOverlap(void* user, const JPH_CollideShapeResult* result) {
    auto& context = *static_cast<OverlapContext*>(user);
    if (result->bodyID2 == context.ignoreBody || gDebris.count(result->bodyID2)) return;
    if (context.count < context.capacity) {
        context.hits[context.count] = {result->bodyID2, 0, result->contactPointOn2,
            outwardNormal(result->penetrationAxis), result->penetrationDepth};
    }
    ++context.count;
}

extern "C" int tn_physics_overlap_shape(const JPH_NarrowPhaseQuery* query,
    const JPH_Shape* shape, const JPH_RVec3* origin, const JPH_Quat* rotation,
    uint32_t ignoreBody, TnShapeHit* hits, int capacity, uint32_t layerMask) {
    JPH_RMat4 transform;
    #ifdef JPH_DOUBLE_PRECISION
    JPH_RMat4_RotationTranslation(&transform, rotation, origin);
#else
    JPH_Mat4_RotationTranslation(&transform, rotation, origin);
#endif
    JPH_CollideShapeSettings settings;
    JPH_CollideShapeSettings_Init(&settings);
    JPH_Vec3 scale{1, 1, 1};
    JPH_RVec3 baseOffset{0, 0, 0};
    OverlapContext context{ignoreBody, hits, capacity, 0};
    JPH_NarrowPhaseQuery_CollideShape2(query, shape, &scale, &transform, &settings,
        &baseOffset, JPH_CollisionCollectorType_AllHit, collectOverlap, &context,
        nullptr, tn_physics_layer_filter(layerMask), nullptr, nullptr);
    return context.count;
}

// ---- virtual character ----
// A character that is moved by sweeping its shape through the world instead of being simulated as a body,
// which is what lets it climb steps and stay on slopes. Arguments are flat so Beef never mirrors JoltC's
// settings structs.

struct TnCharacterState {
    JPH_Vec3 position;
    JPH_Vec3 velocity;
    JPH_Vec3 groundNormal;
    JPH_Vec3 groundVelocity;
    int32_t groundState; // JPH_GroundState: 0 on ground, 1 on steep ground, 2 not supported, 3 in air
    uint32_t groundBody;
};

static JPH_RVec3 toR(const JPH_Vec3* v) { return JPH_RVec3{v->x, v->y, v->z}; }

// Inner bodies of characters that asked for soft contact with other characters. A soft character's sweep skips
// them, so two such characters overlap and are eased apart by the engine instead of stopping each other dead.
static std::vector<std::pair<const JPH_PhysicsSystem*, uint32_t>> softInnerBodies;
static const JPH_PhysicsSystem* filterSystem = nullptr;

static bool JPH_API_CALL softFilterCollide(void*, JPH_BodyID body) {
    for (const auto& entry : softInnerBodies)
        if (entry.second == body && entry.first == filterSystem) return false;
    return true;
}
static bool JPH_API_CALL softFilterCollideLocked(void*, const JPH_Body*) { return true; }

// The filter to sweep with: null (collide with everything) for a solid character.
static const JPH_BodyFilter* characterFilter(const JPH_PhysicsSystem* system, bool soft) {
    if (!soft) return nullptr;
    static JPH_BodyFilter* filter = nullptr;
    if (filter == nullptr) {
        static const JPH_BodyFilter_Procs procs{softFilterCollide, softFilterCollideLocked};
        JPH_BodyFilter_SetProcs(&procs);
        filter = JPH_BodyFilter_Create(nullptr);
    }
    filterSystem = system;
    return filter;
}

// supportHeight: contacts below this height above the character's position count as the floor.
// innerBody: also create a kinematic body of the same shape so rays and other bodies can hit the character.
extern "C" JPH_CharacterVirtual* tn_character_create(JPH_PhysicsSystem* system, const JPH_Shape* shape,
    const JPH_Vec3* position, const JPH_Quat* rotation, float maxSlopeRadians, float mass, float maxStrength,
    float supportHeight, uint32_t layer, uint64_t userData, bool innerBody, bool soft) {
    JPH_CharacterVirtualSettings settings;
    JPH_CharacterVirtualSettings_Init(&settings);
    settings.base.shape = shape;
    settings.base.up = {0, 1, 0};
    settings.base.supportingVolume = {{0, 1, 0}, -supportHeight};
    settings.base.maxSlopeAngle = maxSlopeRadians;
    // Stops flat-bottomed shapes catching on the seams between triangles of a mesh floor.
    settings.base.enhancedInternalEdgeRemoval = true;
    settings.mass = mass;
    settings.maxStrength = maxStrength;
    if (innerBody) {
        settings.innerBodyShape = shape;
        settings.innerBodyLayer = layer;
    }
    JPH_RVec3 at = toR(position);
    JPH_CharacterVirtual* character = JPH_CharacterVirtual_Create(&settings, &at, rotation, userData, system);
    if (character != nullptr && innerBody && soft)
        softInnerBodies.push_back({system, JPH_CharacterVirtual_GetInnerBodyID(character)});
    return character;
}

extern "C" void tn_character_destroy(JPH_CharacterVirtual* character, const JPH_PhysicsSystem* system) {
    const uint32_t inner = JPH_CharacterVirtual_GetInnerBodyID(character);
    for (size_t i = 0; i < softInnerBodies.size(); ++i) {
        if (softInnerBodies[i].second == inner && softInnerBodies[i].first == system) {
            softInnerBodies.erase(softInnerBodies.begin() + i);
            break;
        }
    }
    JPH_CharacterBase_Destroy((JPH_CharacterBase*)character);
}

extern "C" uint32_t tn_character_inner_body(const JPH_CharacterVirtual* character) {
    return JPH_CharacterVirtual_GetInnerBodyID(character);
}

extern "C" void tn_character_get_state(JPH_CharacterVirtual* character, TnCharacterState* state) {
    JPH_RVec3 position;
    JPH_CharacterVirtual_GetPosition(character, &position);
    state->position = {(float)position.x, (float)position.y, (float)position.z};
    JPH_CharacterVirtual_GetLinearVelocity(character, &state->velocity);
    auto base = (JPH_CharacterBase*)character;
    JPH_CharacterBase_GetGroundNormal(base, &state->groundNormal);
    JPH_CharacterBase_GetGroundVelocity(base, &state->groundVelocity);
    state->groundState = (int32_t)JPH_CharacterBase_GetGroundState(base);
    state->groundBody = JPH_CharacterBase_GetGroundBodyId(base);
}

// Moves with the given velocity for one step, climbing steps up to stepUp and following the floor down by stepDown.
// stepForwardTest is how far past a step's edge the landing is probed; a round-bottomed shape needs about its
// radius, or it only ever finds the edge itself and refuses the step.
extern "C" void tn_character_move(JPH_CharacterVirtual* character, JPH_PhysicsSystem* system, uint32_t layer,
    const JPH_Vec3* velocity, float deltaTime, float stepUp, float stepDown, float stepForwardTest, bool soft, TnCharacterState* state) {
    JPH_CharacterVirtual_SetLinearVelocity(character, velocity);
    JPH_ExtendedUpdateSettings settings;
    settings.stickToFloorStepDown = {0, -stepDown, 0};
    settings.walkStairsStepUp = {0, stepUp, 0};
    settings.walkStairsMinStepForward = 0.02f;
    settings.walkStairsStepForwardTest = stepForwardTest;
    settings.walkStairsCosAngleForwardContact = 0.9659258f; // cos 15 degrees
    settings.walkStairsStepDownExtra = {0, 0, 0};
    JPH_CharacterVirtual_ExtendedUpdate(character, deltaTime, &settings, layer, system, characterFilter(system, soft), nullptr);
    tn_character_get_state(character, state);
}

// Teleports the character and rebuilds its contacts so ground state is correct before the next move.
extern "C" void tn_character_set_state(JPH_CharacterVirtual* character, JPH_PhysicsSystem* system, uint32_t layer,
    const JPH_Vec3* position, const JPH_Quat* rotation, const JPH_Vec3* velocity, bool soft) {
    JPH_RVec3 at = toR(position);
    JPH_CharacterVirtual_SetPosition(character, &at);
    JPH_CharacterVirtual_SetRotation(character, rotation);
    JPH_CharacterVirtual_SetLinearVelocity(character, velocity);
    JPH_CharacterVirtual_RefreshContacts(character, layer, system, characterFilter(system, soft), nullptr);
}

// True if the shape fits where the character stands, allowing that much overlap. On true the shape is in use.
extern "C" bool tn_character_set_shape(JPH_CharacterVirtual* character, JPH_PhysicsSystem* system, uint32_t layer,
    const JPH_Shape* shape, float maxPenetration, bool soft) {
    return JPH_CharacterVirtual_SetShape(character, shape, maxPenetration, layer, system, characterFilter(system, soft), nullptr);
}

// Joins two bodies at a point given in world space. With halfConeAngle above zero the second body may only swing
// that far from the axis (a shoulder, a hip); with zero it is a free ball joint. Returns null if either body is gone.
extern "C" JPH_Constraint* tn_joint_create(JPH_PhysicsSystem* system, uint32_t bodyA, uint32_t bodyB,
    const JPH_Vec3* anchor, const JPH_Vec3* axis, float halfConeAngle) {
    const JPH_BodyLockInterface* locks = JPH_PhysicsSystem_GetBodyLockInterfaceNoLock(system);
    JPH_BodyLockWrite a, b;
    JPH_BodyLockInterface_LockWrite(locks, bodyA, &a);
    JPH_BodyLockInterface_LockWrite(locks, bodyB, &b);
    JPH_Constraint* constraint = nullptr;
    if (a.body != nullptr && b.body != nullptr && a.body != b.body) {
        JPH_RVec3 point = toR(anchor);
        if (halfConeAngle > 0) {
            JPH_ConeConstraintSettings settings;
            JPH_ConeConstraintSettings_Init(&settings);
            settings.space = JPH_ConstraintSpace_WorldSpace;
            settings.point1 = point;
            settings.point2 = point;
            settings.twistAxis1 = *axis;
            settings.twistAxis2 = *axis;
            settings.halfConeAngle = halfConeAngle;
            constraint = (JPH_Constraint*)JPH_ConeConstraint_Create(&settings, a.body, b.body);
        } else {
            JPH_PointConstraintSettings settings;
            JPH_PointConstraintSettings_Init(&settings);
            settings.space = JPH_ConstraintSpace_WorldSpace;
            settings.point1 = point;
            settings.point2 = point;
            constraint = (JPH_Constraint*)JPH_PointConstraint_Create(&settings, a.body, b.body);
        }
    }
    JPH_BodyLockInterface_UnlockWrite(locks, &b);
    JPH_BodyLockInterface_UnlockWrite(locks, &a);
    if (constraint != nullptr) JPH_PhysicsSystem_AddConstraint(system, constraint);
    return constraint;
}

extern "C" void tn_joint_destroy(JPH_PhysicsSystem* system, JPH_Constraint* constraint) {
    if (constraint == nullptr) return;
    JPH_PhysicsSystem_RemoveConstraint(system, constraint);
    JPH_Constraint_Destroy(constraint);
}
