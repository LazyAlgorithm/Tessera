---
title: Your first component
summary: Write a Beef script that spins an object, expose its speed in the Inspector, and watch edits reload while the editor runs.
difficulty: Beginner
minutes: 10
order: 1
---
A component is a Beef class that the engine calls every frame. This tutorial writes one from scratch.

## 1. Create the script

1. Open your project from the launcher (`./tessera`).
2. In the **Project** panel, open the `Scripts` folder, click **+** and choose **Script**. Name it `Spinner`.
3. Double-click the new file. It opens in the **Scripts** tab.

## 2. Write the component

Replace the file's contents with this, using your project's name as the namespace:

```beef
using System;
using Tessera;

namespace MyGame;

[Component]
class Spinner : Component
{
    public Vector3 degreesPerSecond = .(0, 45, 0);

    public override void Update()
    {
        Transform.Rotate(degreesPerSecond * Time.DeltaTime);
    }
}
```

Three things matter here:

- `[Component]` is required. Without it the class never appears under Add Component.
- Public fields are saved with the scene and shown in the Inspector.
- `Update` runs once per rendered frame, so multiplying by `Time.DeltaTime` makes the speed the same at any frame rate.

Save with **Ctrl+S**. The editor compiles in the background and marks any error on its line.

## 3. Put it on an object

1. Select an object in the **Hierarchy**, for example a crate.
2. In the **Inspector**, click **Add Component** and pick **Spinner**.
3. Set **Degrees Per Second** to something like `0, 90, 0`.
4. Press **Play**. The object turns. Press **Stop**; play mode never changes the saved scene.

## 4. Change it while the editor runs

Add a second field and a key that doubles the speed:

```beef
[Range(1, 5)] public float boost = 2;

public override void Update()
{
    let speed = Input.GetKey(.Space) ? boost : 1;
    Transform.Rotate(degreesPerSecond * (speed * Time.DeltaTime));
}
```

Save. On Linux Debug editors the script library reloads on its own: the new **Boost** slider appears in the Inspector and the values you already set are kept. Press Play, click the Game view so it receives input, and hold Space.

> If the Inspector does not update, look at the Console for a compile error, or choose File > Reload Scripts.

## Where to go next

- [Writing components](docs.php?page=components) lists every callback and the field types the Inspector understands.
- [Automatic script reload](docs.php?page=script-reload) explains what survives a reload and what needs a restart.
