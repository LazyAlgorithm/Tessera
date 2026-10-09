---
title: A character that walks, climbs steps and jumps
summary: Set up a Character Controller, write a short movement script, and try the capsule and rounded-box shapes on a flight of steps.
difficulty: Beginner
minutes: 20
order: 2
---
A Character Controller moves an object by sweeping a shape through the level. Unlike a rigid body it walks up steps, stays put on slopes and never tips over. This tutorial builds a character you steer with the keyboard.

## 1. A level with steps

1. Make a floor: a cube scaled to about `30, 1, 30` at height `-0.5`, with a **Box Collider**.
2. Make three steps: cubes with Box Colliders, each `3` wide and `1` deep, with tops at `0.25`, `0.5` and `0.75`. For example scale `3, 0.25, 1` at position `0, 0.125, 4`, then `3, 0.5, 1` at `0, 0.25, 5`, then `3, 0.75, 3` at `0, 0.375, 7` as a landing.
3. Point the **Main Camera** at the scene, for example position `0, 6, -9` rotated 25 degrees about X.

## 2. The character

1. Create an empty object (GameObject > Create Empty), name it `Player` and place it at `0, 0, 0`.
2. Click **Add Component** and pick **Character Controller** from the Physics group. Do not add a Rigidbody or a collider; the controller replaces both.
3. Set **Radius** `0.35`, **Height** `1.8` and **Center** `0, 0.9, 0`. The centre is half the height, which puts the object's origin at the character's feet.
4. Give it a body to look at: add a child object with a capsule mesh at local position `0, 0.9, 0`, scaled `0.7, 0.9, 0.7`.

With the Player selected, the Scene view outlines the controller's shape in green.

| Setting | What to try |
|---|---|
| Step Height | `0.4` climbs the 0.25 m steps above. Lower it to `0.2` and the same steps become a wall. |
| Max Slope | Steepest slope in degrees it can stand on. |
| Jump Grace | Seconds after leaving the ground during which a jump still works. |

## 3. The movement script

Create a script named `WalkingCharacter` and replace its contents, using your project's namespace:

```beef
using System;
using Tessera;

namespace MyGame;

/// WASD or arrows to move relative to the camera, Shift to run, Space to jump.
[Component]
class WalkingCharacter : Component
{
    public float walkSpeed = 4;
    public float runSpeed = 7;
    public float acceleration = 30;
    public float jumpSpeed = 6.5f;
    public Camera camera;

    CharacterController mController;
    Vector3 mWish;
    bool mRun;
    float mJumpBuffer;

    public override void Start()
    {
        mController = GetComponent<CharacterController>();
        if (camera == null) camera = Scene.FindComponent<Camera>();
    }

    // Input is read every rendered frame...
    public override void Update()
    {
        var forward = camera != null ? camera.Transform.Forward : Vector3.Forward;
        forward.y = 0;
        forward = forward.LengthSquared > 0.0001f ? forward.Normalized : Vector3.Forward;
        let right = Vector3(forward.z, 0, -forward.x);
        mWish = right * Input.GetAxis("Horizontal") + forward * Input.GetAxis("Vertical");
        if (mWish.LengthSquared > 1) mWish = mWish.Normalized;
        mRun = Input.GetKey(.LeftShift);
        // Remember a jump press for a moment, so it is not lost between fixed ticks.
        mJumpBuffer = Input.GetKeyDown(.Space) ? 0.15f : Math.Max(0, mJumpBuffer - Time.DeltaTime);
    }

    // ...and the character moves once per fixed tick.
    public override void FixedUpdate()
    {
        if (mController == null) return;
        let target = mWish * (mRun ? runSpeed : walkSpeed);
        let current = Vector3(mController.Velocity.x, 0, mController.Velocity.z);
        let horizontal = Vector3.MoveTowards(current, target, acceleration * Time.FixedDeltaTime);

        float jump = 0;
        if (mJumpBuffer > 0 && mController.CanJump)
        {
            jump = jumpSpeed;
            mJumpBuffer = 0;
        }
        // The controller keeps the falling speed, applies gravity and climbs steps.
        mController.SimpleMove(horizontal, Time.FixedDeltaTime, jump);

        if (mWish.LengthSquared > 0.01f)
            Transform.Rotation = Quaternion.Euler(0, Math.Atan2(mWish.x, mWish.z) * Mathf.Rad2Deg, 0);
    }
}
```

What the script does and what it leaves to the controller:

- The script decides only the **horizontal velocity**: where the player wants to go, eased toward with `MoveTowards` so starts and stops are not instant.
- `SimpleMove` does the rest: gravity, falling, stepping up, following the floor down, and the jump when a jump speed is passed.
- `Velocity` is what the controller actually achieved, so after walking into a wall the next tick starts from zero instead of pushing harder.
- `CanJump` is true on the ground and for the Jump Grace time after leaving it.

Save the script and add **Walking Character** to the Player.

## 4. Play

Press **Play**, click the Game view so it receives input, and walk at the steps. The character climbs them without slowing, comes back down without leaving the ground, and jumps with Space.

## 5. Try the rounded box

1. Stop, select the Player and set **Shape** to **Box**, **Box Size** `0.8, 1, 0.8`, **Edge Radius** `0.1` and **Center** `0, 0.5, 0`.
2. Scale the child mesh to match, or swap it for a cube.
3. Play again. The box climbs the same steps.

The rounded edges are what keep a box from catching on small lips and on the seams between floor triangles. The box stays aligned to the world axes while the object turns, so a long box cannot swing a corner into a wall; tick **Turn Shape With Object** only for boxes that are close to square.

To switch shape while the game runs, for example when a player becomes a different object:

```beef
if (!mController.SetBox(.(1.2f, 0.8f, 1.2f), 0.1f, .(0, 0.4f, 0)))
    Log.Info("Not enough room to become that here.");
```

`SetBox` and `SetCapsule` refuse, and change nothing, when the new shape would not fit where the character stands.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| The character does not move | The Game view does not have focus, or the script is on a different object from the controller. |
| It falls through the floor | The floor has no collider. |
| It hovers above or sinks into the floor | Center does not match the shape: use half the height for an origin at the feet. |
| It stops at a step | The step is taller than Step Height. |

## Where to go next

- [Character controller](docs.php?page=character-controller) lists every setting, `Move` for flying or swimming, and how characters push each other.
- [Click-to-move agents with navigation](tutorials.php?t=click-to-move): put a Navigation Agent on the same object and it walks its path through the controller, steps included.
