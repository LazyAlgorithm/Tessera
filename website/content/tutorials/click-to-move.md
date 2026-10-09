---
title: Click-to-move agents with navigation
summary: Bake a navigation surface around some obstacles and write a short script that sends agents to wherever you click.
difficulty: Intermediate
minutes: 25
order: 8
---
By the end you will have a floor with obstacles, a baked navigation surface, and agents that walk around the obstacles to the point you click.

![A baked navigation surface: the blue overlay is walkable floor](assets/screenshots/navigation.jpg)

## 1. Build the level

1. Make a floor: a cube scaled to about `30, 1, 30` at height `-0.5`, with a **Box Collider**. The collider matters twice: the bake reads it, and the mouse click is a ray cast against it.
2. Add a few obstacles: cubes with Box Colliders, scaled into walls and crates. Leave gaps at least a metre wide so there is a way through.
3. Point the **Main Camera** down at the floor, for example position `0, 22, -20` rotated 50 degrees about X.

## 2. Bake the navigation surface

1. Create an empty object (GameObject > Create Empty) and name it `Navigation Surface`.
2. Click **Add Component** and pick **Navigation Surface** from the AI group.
3. Its position is the *minimum corner* of the bake volume, not the centre. For the floor above use position `-15, -1, -15` and **Size** `30, 6, 30`. The cyan box in the Scene view shows the volume.
4. Set **Cell Size** to `0.5`. Smaller cells follow obstacles more closely and cost more memory and bake time.
5. Click **Bake & Save Navigation**.

Walkable floor is now drawn as a blue overlay, with a darker line along every edge an agent cannot cross. If an area you expected to be walkable is bare, check **Agent Radius** and **Agent Height**: a cell is only walkable where the whole agent fits.

> Baked data does not follow later edits. After moving an obstacle, bake again, or tick **Rebuild On Start** to bake every time the scene starts.

## 3. Add agents

1. Create an empty object named `Agent` and stand it on the floor (height `0`).
2. Add a **Navigation Agent** component and drag the Navigation Surface object onto its **Surface** field. If you leave it empty, the agent uses the first active surface in the scene.
3. Give it something to look at: add a child object with a capsule mesh, positioned `0, 0.9, 0` and scaled `0.6, 0.9, 0.6`.
4. Duplicate the agent once or twice and move the copies apart.

An agent with no Rigidbody moves its own transform along the path. Objects that carry a Navigation Agent are left out of the bake, so agents never block each other's navigation.

## 4. The click script

Create a script named `ClickToMove` and replace its contents, using your project's namespace:

```beef
using System;
using Tessera;

namespace MyGame;

/// Left-click in the Game view to send every agent in the scene to that spot.
[Component]
class ClickToMove : Component
{
    public Camera camera;
    public float speed = 3.5f;
    public float stoppingDistance = 0.15f;
    /// Radius of the ring the agents stop on, so they do not stand inside each other.
    public float spacing = 0.9f;

    public override void Start()
    {
        if (camera == null) camera = Scene.FindComponent<Camera>();
    }

    public override void Update()
    {
        if (!Input.GetMouseButtonDown(0) || camera == null || GUI.Width < 1 || GUI.Height < 1)
            return;
        // GUI's rectangle is the game picture: the whole window in a built game, the Game tab in the editor.
        let mouse = Input.MousePosition;
        let u = (mouse.x - GUI.Origin.x) / GUI.Width;
        let v = (mouse.y - GUI.Origin.y) / GUI.Height;
        if (u < 0 || u > 1 || v < 0 || v > 1)
            return;
        let ray = camera.GetCameraData(GUI.Width / GUI.Height).ViewportPointToRay(u, v);
        RaycastHit hit;
        if (!Scene.Physics.Raycast(ray.origin, ray.direction, 500, out hit))
            return;

        int count = 0;
        for (let component in Scene.Components)
            if (component is NavigationAgent) count++;
        int index = 0;
        for (let component in Scene.Components)
        {
            let agent = component as NavigationAgent;
            if (agent == null)
                continue;
            var destination = hit.point;
            if (count > 1)
            {
                let angle = (float)index / count * Math.PI_f * 2;
                destination += Vector3(Math.Cos(angle), 0, Math.Sin(angle)) * spacing;
            }
            agent.SetDestination(destination, speed, stoppingDistance);
            index++;
        }
    }
}
```

How it works:

- `Input.MousePosition` is in window pixels. Subtracting `GUI.Origin` and dividing by `GUI.Width` and `GUI.Height` turns it into a 0..1 position inside the game picture, which is what `ViewportPointToRay` expects.
- `Scene.Physics.Raycast` finds the first collider under the cursor. That point becomes the destination.
- `SetDestination(point, speed, stoppingDistance)` asks the agent for a path. The destination snaps to the nearest reachable cell within the agent's **Snap Distance**, so clicking on top of a crate sends the agent beside it.

Save the script, create an empty object named `Click To Move` and add the component to it.

## 5. Play

Press **Play**, click the Game view once so it receives input, then click anywhere on the floor. The agents walk around the walls to a ring around the click.

To react when an agent arrives or cannot get there, check it from any script:

```beef
if (agent.HasArrived) { /* reached the snapped destination */ }
if (agent.PathFailed) { /* no route: the click was in an unreachable area */ }
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing happens on click | The Game view does not have focus, or the floor has no collider for the ray to hit. |
| Agents do not move and `PathFailed` is true | The surface was never baked, or the agent starts further than Snap Distance from any walkable cell. |
| Agents walk through a new obstacle | The bake is older than the obstacle. Bake again or tick Rebuild On Start. |
| Agents refuse a narrow gap | The gap is narrower than twice the Agent Radius plus a cell. Widen it or reduce Cell Size. |

## Where to go next

[Navigation](docs.php?page=navigation) covers flight volumes, rebuilding only the chunks that changed, dynamic Rigidbody agents, and how the path search works.
