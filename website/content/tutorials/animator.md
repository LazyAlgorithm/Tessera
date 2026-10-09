---
title: Animating a character: clips, states and transitions
summary: Make a clip on the timeline, build an Animator Controller that moves between idle, run and jump, drive it from a script and watch it live.
difficulty: Intermediate
minutes: 25
order: 12
---
This uses the sample character (`Prefabs/character.tprefab`), which is a body made of child objects (Hips, Chest, UpperArm.L and so on) with an **Animator** on its root. Drag the prefab into a scene and select it.

## 1. Look at a clip

Open **Window > Animation**. It docks along the bottom, beside Project and Console. It shows the Animator's first clip; choose `walk` in the drop-down on the left if another is shown.

- The list on the left is the children the clip moves. Click the arrow beside one to see its position, rotation and scale.
- Each **diamond** on the right is a key. The top row shows every key in the clip.
- Click or drag the **ruler** along the top: the white marker moves and the character takes the pose for that time. The ruler counts in seconds and frames, so `0:30` is frame 30 of the first second.
- Scroll over the timeline to zoom in and out; drag with the middle mouse button to slide it.
- Press the **play** arrow to preview the loop. The buttons either side of it jump between keys.

## 2. Make your own clip

1. Open the clip drop-down and choose **Create New Clip...**. A clip is created in `Animations/` and added to the Animator's clips.
2. Turn **Record** on: the red dot beside Preview. The ruler turns red.
3. In the Hierarchy, select `UpperArm.R`. With the marker at 0, rotate it with the Rotate gizmo: it appears in the list with a key at 0.
4. Click the ruler at half the clip's length, and rotate the arm further up: a second key.
5. Click the end of the ruler and rotate the arm back down.
6. Turn Record off and press play: the arm waves.

If you would rather not arm Record each time, turn on **Auto Key** instead. It does the same and stays on, in this session and the next, until you turn it off.

For exact values, unfold the child in the list and type its numbers: that writes a key at the marker. Drag a diamond to change its timing; right-click it to delete it. At the bottom, set **Length** to how long the clip should last, and untick **Loop** for something that plays once.

Keys are stored as offsets from the pose the character has in the scene, so moving the whole character, or using the clip on another character with the same child names, just works.

## 3. Build a controller

In the Project panel choose **+ > Animator Controller** and name it `Hero`. The Animator window opens with one state, **Idle**, in orange: the default state.

1. Click **Idle** and set its **Clip** to `Animations/idle.tanim`.
2. Right-click the canvas, **Create State**, name it `Run`, clip `Animations/run.tanim`.
3. Create another, `Jump`, clip `Animations/jump.tanim`, and untick **Loop**.
4. Under **Parameters** press **+** and add a Float named `speed`, and a Trigger named `jump`.

Now the transitions:

1. Right-click **Idle**, **Make Transition**, click **Run**. Select the arrow. Untick **Has Exit Time**, press **+** beside Conditions, and set `speed` greater than `0.5`.
2. Make one back from **Run** to **Idle**: `speed` less than `0.5`, no exit time.
3. Right-click **Any State**, Make Transition, click **Jump**: condition `jump`. A transition from Any State can fire whatever the character is doing.
4. From **Jump** to **Idle**: leave **Has Exit Time** ticked with Exit Time `0.9`, and no conditions. It returns when the jump clip is nearly done.

Select the character and set its Animator's **Controller** to `Animations/Hero.tcontroller` (the `...` button picks it).

## 4. Try it without a script

Press Play and keep the character selected with the Animator window open. The current state is blue, with a bar showing how far through its clip it is.

In the Parameters list, drag `speed` above 0.5: the character runs, and the blue state moves to **Run**. Drag it back down. Press **fire** beside `jump`.

## 5. Drive it from a script

```beef
[Component]
class HeroAnimation : Component
{
    Animator mAnimator;
    Vector3 mLast;

    public override void Start()
    {
        mAnimator = GetComponent<Animator>();
        mLast = Transform.Position;
    }

    public override void Update()
    {
        // How fast the character is moving along the ground.
        var moved = Transform.Position - mLast;
        moved.y = 0;
        mLast = Transform.Position;
        if (Time.DeltaTime > 0)
            mAnimator.SetFloat("speed", moved.Length / Time.DeltaTime);
        if (Input.GetKeyDown(.Space))
            mAnimator.SetTrigger("jump");
    }
}
```

Add it to the character. The script only reports what the character is doing; the controller decides what that looks like.

The same can be done in a graph: **Engine > Animation > Animator** in the add-node menu has *Set Float*, *Set Trigger* and the rest.

## 6. Multiplayer

There is nothing to add. In a network session, parameters set on the server, or by the player who owns the character, reach every machine, and every machine shows the same state.

## What is not there

No curve editor, no blend trees and no layers: each state plays one clip, and the cross-fade of a transition is the blending. See the [Animator page](../docs.php?page=animator) for the full list.
