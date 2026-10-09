---
title: Prefabs and a spawner
summary: Save an object as a prefab, then write a spawner that drops copies into the scene and cleans them up again.
difficulty: Beginner
minutes: 15
order: 7
---
A prefab is an object, with its children and components, saved to a `.tprefab` file. You can drag it into any scene or create copies from code. This tutorial makes a crate prefab and a spawner that rains crates.

## 1. Make the prefab

1. Build the object in the scene: a cube with a **Box Collider** and a **Rigidbody**, so it falls and stacks. Name it `Crate`.
2. Right-click it in the **Hierarchy** and choose **Save as Prefab**. A `Crate.tprefab` file appears in the Project panel.
3. Delete the original from the scene. To place one by hand again, drag the prefab from the Project panel into the Scene or Hierarchy.

A prefab is a copy at the moment you saved it. After changing the object, save it as a prefab again to update the file.

## 2. A script that removes old crates

Without this the scene fills up. Create a script named `DestroyAfter`:

```beef
using System;
using Tessera;

namespace MyGame;

/// Removes its object after a number of seconds.
[Component]
class DestroyAfter : Component
{
    public float seconds = 8;

    public override void Update()
    {
        seconds -= Time.DeltaTime;
        if (seconds <= 0)
            Scene.Destroy(GameObject);
    }
}
```

Put a crate back in the scene, add **Destroy After** to it, save it as a prefab again and delete the scene copy.

## 3. The spawner

Create a script named `Spawner`:

```beef
using System;
using System.Collections;
using Tessera;

namespace MyGame;

/// Creates copies of a prefab at random points around its own position.
[Component]
class Spawner : Component
{
    /// Prefab file, relative to the project's asset folder.
    public String prefab = new .("Crate.tprefab") ~ delete _;
    public float interval = 0.5f;
    public float radius = 4;
    public int32 maxAlive = 25;

    float mTimer;
    Random mRandom = new .() ~ delete _;
    // Ids, not references: an object may be destroyed by something else before we look again.
    List<uint32> mSpawned = new .() ~ delete _;

    public override void Update()
    {
        mTimer -= Time.DeltaTime;
        if (mTimer > 0)
            return;
        mTimer = interval;

        for (int i = mSpawned.Count - 1; i >= 0; i--)
        {
            if (Scene.FindById(mSpawned[i]) == null)
                mSpawned.RemoveAt(i);
        }
        if (mSpawned.Count >= maxAlive)
            return;

        let angle = (float)(mRandom.NextDouble() * Math.PI_d * 2);
        let distance = (float)mRandom.NextDouble() * radius;
        let position = Transform.Position + Vector3(Math.Cos(angle), 0, Math.Sin(angle)) * distance;
        let spin = Quaternion.Euler(0, (float)mRandom.NextDouble() * 360, 0);
        let copy = Prefab.Instantiate(Scene, prefab, position, spin);
        if (copy != null)
            mSpawned.Add(copy.Id);
    }
}
```

What matters here:

- `Prefab.Instantiate(scene, path, position, rotation)` returns the new object, or null (with an error in the Console) if the file is missing. The path is relative to the project's asset folder, so a prefab in a `Prefabs` folder is `Prefabs/Crate.tprefab`.
- The spawner remembers each copy's `Id` and asks the scene whether it still exists, rather than holding on to objects that `DestroyAfter` may already have removed.
- `Scene.Destroy` removes an object and its children.

## 4. Try it

1. Create an empty object named `Spawner` about 6 metres above a floor that has a collider.
2. Add the **Spawner** script. Check that **Prefab** matches where your file is.
3. Press **Play**. Crates drop in a circle, pile up, and disappear after eight seconds, so the count settles below **Max Alive**.

## Prefabs in multiplayer

A prefab spawned this way exists only on the machine that created it. For objects every player must see, register the file once at startup and let the server spawn it:

```beef
NetworkManager.RegisterPrefabFile("Crate", "Crate.tprefab");
// later, on the server:
Scene.Network.Spawn("Crate", position, .Identity, 0);
```

[Two players in one world](tutorials.php?t=networking) covers the rest.
