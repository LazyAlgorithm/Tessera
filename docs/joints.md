# Joints and debris

## Joints

A **Joint** (Add Component > Physics) holds two rigid bodies together at a point. They can turn about the point but cannot come apart: a link in a chain, a lamp on a cable, a limb on a body.

| Field | Meaning |
|---|---|
| Connected To | The other body. It needs a Rigidbody too. Make that one kinematic to hang things from a point that does not move. |
| Anchor | Where the two are joined, relative to this object. |
| Axis | The direction the swing limit is measured from, relative to this object. |
| Swing Limit | How far, in degrees, the bodies may swing away from the axis: a shoulder or a hip. 0 is a free ball joint. |

From code:

```beef
// Hang a weight from a post, joined at the post.
Joint.Connect(weight.GetComponent<Rigidbody>(), post.GetComponent<Rigidbody>(), post.Transform.Position, .Down);

// A forearm on an upper arm that bends no more than 70 degrees.
Joint.Connect(forearm, upperArm, elbowPosition, upperArm.Transform.Up * -1, 70);
```

`Joint.Connect` adds a Joint component to the first body and returns it. Destroying either object removes the joint; `IsConnected` says whether it is in place. After changing a joint's fields while playing, call `Rebuild()`.

A ragdoll is a handful of small bodies joined this way: give each limb a box collider and a Rigidbody, join them at the shoulders, elbows, hips and knees with swing limits, and let go.

Joints are local to the machine they are on. In multiplayer the bodies are shared like any others, so create the same joints on every machine; joints saved in a scene or prefab already are.

## Debris

Turn **Debris** on in a Rigidbody for things that should lie about without getting in the way: corpses, dropped weapons, rubble. Debris rests on scenery and is drawn like anything else, but:

- characters and ordinary bodies pass straight through it, and so do other pieces of debris;
- rays, shape casts and overlaps ignore it, so it never blocks a shot or a line of sight.

`Scene.Physics.IsDebris(bodyId)` tells you whether a body is debris.

## Limits

- The only joints are ball joints, with or without a swing limit: no hinges, sliders, springs or motors.
- A swing limit is held by the solver, not exactly: a hard knock can carry a limb a little past it before it is pulled back.
- Because nothing can query debris, picking it up or shooting it has to be done by distance from its object, not by ray.

CPU tests (`Tests/Joints`) cover a weight swinging on a joint, a joint going when one of its bodies is destroyed, a swing limit under a shove, and debris resting on a floor while a body, a character, a ray, a shape cast and an overlap all pass through it.
