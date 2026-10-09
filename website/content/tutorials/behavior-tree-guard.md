---
title: A guard with a behaviour tree
summary: Build a guard that patrols, chases an intruder on sight and checks where it last saw them, and watch the tree light up as it runs.
difficulty: Intermediate
minutes: 30
order: 10
---
A behaviour tree is a picture of an AI's priorities. This tutorial builds a guard with three: chase what you can see, otherwise go and check where you last saw it, otherwise patrol.

![A behaviour tree shown live while the game runs](assets/screenshots/behavior.jpg)

## 1. The scene

You need a level with baked navigation and two characters. If you have not done [Click-to-move agents with navigation](tutorials.php?t=click-to-move), do that first; the level and agents are built the same way.

1. A floor and some walls, each with a **Box Collider**. Walls matter here: they are what the guard cannot see through.
2. A **Navigation Surface** covering the floor, baked (or with **Rebuild On Start** ticked).
3. An object named `Guard` with a **Navigation Agent** and a visible child mesh.
4. An object named `Intruder`, also with a Navigation Agent and a mesh. The guard will look for it by this name.
5. An empty object named `Guard Route` with three or four empty children placed where the guard should walk. Their order in the Hierarchy is the order of the patrol.

## 2. Create the tree

1. In the Project panel click **+** and choose **Behavior Tree**. Name it `Guard`.
2. The **Behavior** tab opens with an example tree. Delete everything under **Root** except the **Reactive Selector** (select a node and press Delete).

Flow runs downward. To connect two nodes, drag from the dot under the parent onto the child. Children run left to right, so where you place them matters.

## 3. Lowest priority first: patrol

1. Right-click the canvas, add a **Sequence** and connect the Reactive Selector to it.
2. Add **Patrol** under the Sequence. Select it and set **Waypoints** to `Guard Route` and **Speed** to `2.2`.
3. Add **Wait** under the Sequence, to the right of Patrol. Set **Seconds** `0.5` and **Up To** `1.5` for a random pause.
4. Click **Save**. Add a **Behavior Tree Runner** to the Guard (Add Component > AI) and set **Tree** to the file's path, for example `AI/Guard.tbt`.
5. Press **Play**. The guard walks its route, pausing at each point.

Each run of Patrol visits one waypoint and then succeeds, so the Sequence moves on to Wait; when the tree finishes it starts again and Patrol takes the next waypoint.

## 4. Highest priority: chase on sight

1. Add a **Reactive Sequence** under the Reactive Selector and drag it to the **left** of the patrol Sequence, so it is tried first.
2. Under it add **Can See**. Set **Object** to `Intruder`, **Range** `9` and **Field Of View** `110`.
3. To its right add **Move To Target**. Leave **Key** as `target` and **Follow** ticked; set **Speed** `4.5` and **Stop Distance** `1.2`.

Can See remembers what it found on the tree's blackboard as `target`, and Move To Target walks to whatever is stored there.

Why two reactive nodes?

- The **Reactive Selector** at the top rechecks its branches from the left every tick. The moment the chase branch can run, it interrupts the patrol.
- The **Reactive Sequence** rechecks Can See every tick. The moment the guard loses sight, the walk is stopped. With a plain Sequence the guard would keep chasing an intruder it can no longer see.

## 5. In between: check the last place

When the guard loses sight it should not go straight back to patrolling. Can See also stores where the target was, as `target.position`.

1. Add a plain **Sequence** under the Reactive Selector, between the other two branches.
2. Under it, left to right:
   - **Has Value** with **Key** `target.position`
   - **Move To Target** with **Key** `target.position`, **Follow** off, **Stop Distance** `0.5`
   - **Wait** with **Seconds** `1.5`
   - **Forget** with **Key** `target.position`

The branch only runs if there is a position to check. It walks there, waits, and forgets it, after which Has Value fails and the patrol resumes. If the guard sees the intruder on the way, the chase branch interrupts it.

## 6. Watch it think

Save, press **Play**, and keep the Behavior tab open. Select the Guard, or just leave nothing selected.

| Colour | Meaning |
|---|---|
| Amber, pulsing | Running now. |
| Green | Succeeded. |
| Red | Failed. |
| Grey | Stopped part-way by a branch with higher priority. |

While patrolling, Can See and Has Value are red and the patrol branch is amber. Move the Intruder into the guard's view (give it its own tree with a Patrol, or drag it in the Scene view while playing): Can See turns green, Move To Target turns amber and the patrol branch goes grey. Move it behind a wall and the middle branch takes over. The box at the bottom left shows what the guard remembers.

Colours fade over about a second, so you can see what just happened as well as what is happening.

You can tune while it runs: change a range or a speed and click **Save**. Running objects reload the tree at once.

## 7. Give the intruder a brain too

Create a second tree named `Intruder` with **Root > Sequence > Patrol, Wait**, make an `Intruder Route` object with waypoints that pass through the guard's area, and put a Behavior Tree Runner on the Intruder. Now the two meet without you touching anything.

## Running your own code from a tree

Add a **Call Method** node and type the name of a method on any component of the same object. A method that returns `bool` works as a condition; any other method is an action.

```beef
using System;
using Tessera;

namespace MyGame;

[Component]
class GuardActions : Component
{
    public int32 shouts;

    /// Call Method "Shout": an action.
    public void Shout()
    {
        shouts++;
        Log.Info(scope $"{GameObject.Name}: Halt!");
    }

    /// Call Method "HasShoutedEnough": a condition.
    public bool HasShoutedEnough() => shouts >= 3;
}
```

Put **Call Method** with **Method** `Shout` at the start of the chase branch, wrapped in a **Cooldown** of a few seconds so the guard does not shout every frame.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing lights up | The object has no Behavior Tree Runner, or its Tree path does not match the file. The toolbar says when no running object uses the tree. |
| Movement nodes turn red at once | The object has no Navigation Agent, or the surface is not baked. The Console says which. |
| Can See never succeeds | The name does not match exactly, the target is outside the cone in front of the guard, or a collider is in the way. Try Field Of View `360` to rule the cone out. |
| The guard chases through walls | The chase uses a plain Sequence, so sight is only checked once. Use a Reactive Sequence. |

See [Behaviour trees](docs.php?page=behavior-trees) for every node and for writing node kinds of your own.
