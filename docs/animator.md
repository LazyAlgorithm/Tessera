# Animator and Animation windows

Animation in Tessera has three parts, arranged as in Unity:

- an **Animation Clip** (`.tanim`) is keyframes: how the children of an object move over time;
- an **Animator Controller** (`.tcontroller`) is a state machine: which clip plays, and when to change;
- the **Animator** component runs them on an object.

**Window > Animation** edits clips on a timeline. **Window > Animator** edits controllers as a graph. Both are also opened by double-clicking the asset in the Project panel.

## The Animator window

Create a controller with **Project > + > Animator Controller**, then set it as the **Controller** of an object's Animator. Selecting an object whose Animator has a controller shows that controller.

| In the window | What it is |
|---|---|
| Orange box | The default state, entered from **Entry** when the Animator starts. |
| Grey boxes | Other states. Each plays one clip. |
| **Any State** | Stands for whatever state is current: a transition from it can fire at any time. |
| Arrows | Transitions. Two between the same states run side by side. |
| Left panel | Parameters, and the settings of the selected state or transition. |

- **Right-click the canvas:** Create State.
- **Right-click a state:** Make Transition (then click the state it goes to), Set as Default State, Delete.
- **Click** a state or an arrow to edit it. **Delete** removes the selection. Drag states to arrange them. Middle-drag pans and the wheel zooms.

Changes are saved as you make them.

A **state** has a name, a clip, a speed and a loop setting. The clip is a `.tanim` file, or the name of a clip inside the object's skinned model (those are listed too when such an object is selected).

A **transition** has:

- **Conditions**, all of which must hold: a parameter compared with a value (greater than, less than, equals, not equal), a boolean that is true or false, or a trigger.
- **Has Exit Time** and **Exit Time**: wait until the state has played that fraction of its clip (1 is the end).
- **Duration**: seconds of cross-fade into the next state.

A transition with no condition and no exit time never fires, as in Unity.

**Parameters** are Float, Int, Bool or Trigger. A trigger stays set until a transition uses it, then clears itself.

### While the game runs

With an object selected, its current state turns blue with a bar showing progress through the clip, and the parameter list shows that Animator's live values. Editing a value there sets it on the running object, and **fire** sets a trigger, so a state machine can be tried without writing a script. Editing the controller while playing takes effect at once.

## The Animation window

Select an object with an Animator, or a child of one. If it has none, the window says so and its **Create** button adds an Animator and a first clip. The window is laid out like Unity's:

| Where | What |
|---|---|
| Top left | **Preview**, **Record** (the red dot), first / previous key, **Play**, next / last key, and the frame number at the time marker. |
| Second row | The clip (with **Create New Clip...** at the bottom of the list), the sample rate, **Add Key**, and **Auto Key**. |
| Left list | The children the clip moves. Unfold one to see its **Position**, **Rotation** and **Scale** at the marker. **Add Property** adds a child. |
| Right | The ruler in `seconds:frames`, a summary row with every key, and a row of key diamonds for each line of the list. |
| Bottom | The clip's **Length** and **Loop**, and **Frame All** to fit the clip in view. |

- **Moving in time:** click or drag the ruler. The object is posed at that time in the Scene view. The marker snaps to frames of the clip's sample rate (60 by default, saved with the clip).
- **Zooming:** scroll over the timeline to zoom, middle-drag to pan. The ruler's labels follow the zoom.
- **Keys:** click a diamond to select it and go to its time, drag it to retime it, right-click it or press Delete to remove it. A key holds position, rotation and scale together, so the three rows of a child share their diamonds.
- **Typing values:** change a number in the left list and a key is written at the marker.
- **Record:** while it is on, moving, turning or scaling a child (with the gizmo or the Inspector) writes a key at the marker. The ruler is tinted red.
- **Auto Key:** the same, but it stays on: whenever a clip is open, anything you move is keyed, without arming Record each time. The choice is remembered between sessions. The button is amber while it is on.
- Keying a child the clip did not move before adds it to the list. If the marker is not at the start, it also gets a key at time 0 holding its untouched pose, so it moves *to* the new key instead of sitting in the new pose for the whole clip. A key placed past the end lengthens the clip.
- **Add Key** keys the selected child where it is now, or every listed child when the Animator's own object is selected.
- **Preview** off puts the object back in its scene pose until the marker is moved again.
- Clicking a name in the list selects that child in the scene. Right-click a name for **Remove Properties**.
- There is no Curves view: keys are blended in straight lines.

Keys are offsets from the pose the object has in the scene, matched to children **by name**. One clip therefore works on any character whose children have the same names. When the window closes, or another object is selected, the object returns to its scene pose, so a previewed pose is never saved into the scene by accident.

## From scripts

```beef
let animator = GetComponent<Animator>();
animator.SetFloat("speed", velocity.Length);
animator.SetBool("grounded", controller.IsGrounded);
animator.SetInteger("lives", lives);
animator.SetTrigger("jump");

if (animator.CurrentState == "Jump" && animator.NormalizedTime > 0.5f) { /* past the top of the jump */ }
animator.Play("Idle");            // jump straight to a state
animator.CrossFade("Run", 0.3f);  // or fade to it
```

Also `GetFloat`, `GetBool`, `GetInteger`, `ResetTrigger`, `IsInTransition`, `StateTime` and `CurrentStateIndex`. Setting a parameter the controller does not have is ignored.

An Animator with **no controller** works as it always did: list clip files in **Clips**, and call `Play("Walk")`.

Controllers can be built in code as well (`AnimatorController.AddState`, `AddParameter`, `AddTransition`, `AddCondition`, `Save`), which is what the tests do.

## Multiplayer

Nothing to set up. Parameters set on the server, or by the player who owns the object, reach every machine; that machine alone decides the transitions, and the others follow it into each state. A client setting parameters on an object it does not own changes nothing.

## Visual scripting

Every method above is a node under **Engine > Animation > Animator** in a graph's add-node menu (Set Float, Set Trigger, Current State, Normalized Time and so on), generated from the engine source like all other nodes.

## Limits

- **No curves view.** The timeline is a dopesheet: keys are interpolated linearly, and there are no tangents to edit.
- **Transforms only.** Clips animate the position, rotation and scale of child objects. They do not animate other properties (a light's colour, a material), and there are no animation events.
- **One layer, no blend trees.** A state plays one clip; there are no layers, masks, sub-state machines or 1D/2D blend trees. A transition's cross-fade is the only blending.
- **Skinned models** play their own clips: a state can name one, but those clips cannot be edited in the Animation window.
- Undo does not cover edits made in these two windows.

## Tests

`BeefBuild -workspace=Tests/Animator -config=Debug -run` (28 checks): key ordering and interpolation, the auto-keying rules, saving and loading clips and controllers, clips from before scale existed, conditions, triggers, exit time, Any State, cross-fade blending, state speed, editing a controller while it runs, and previewing. The Network fixture checks parameters and states across machines.
