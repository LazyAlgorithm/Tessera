---
title: Achievements, with or without Steam
summary: List your achievements in the editor, unlock them with one line of code, and test them before the game is on Steam.
difficulty: Beginner
minutes: 10
order: 11
---
Achievements in Tessera take one call. The same call works in the editor, in a build without Steam and in a Steam build, so you can add them from the first day.

![The Achievements window](assets/screenshots/achievements.jpg)

## 1. List them

1. Open **Window > Achievements**.
2. Click **+ Add** and fill in the row:
   - **ID**: the name code uses, in capitals with underscores, for example `FIRST_CATCH`.
   - **Name** and **Description**: what the player sees.
   - **Hidden**: tick for a secret achievement.
3. Add a couple more and click **Save**. The list is written to `Achievements.tach` in the project and ships with the game.

## 2. Unlock one from code

```beef
using System;
using Tessera;

namespace MyGame;

/// Unlocks an achievement the first time something touches this object, and counts every touch.
[Component]
class Trophy : Component
{
    public String achievement = new .("FIRST_CATCH") ~ delete _;
    public float radius = 1.5f;
    public String visitor = new .("Player") ~ delete _;

    bool mInside;

    public override void Update()
    {
        let other = Scene.Find(visitor);
        let inside = other != null && (other.Transform.Position - Transform.Position).Length < radius;
        if (inside && !mInside)
        {
            // True the first time only; later calls do nothing.
            if (Achievements.Unlock(achievement))
                Log.Info("First time here!");
            // A counter kept with the player's progress.
            let visits = Achievements.AddStat("visits");
            // Unlocks MARATHON on the tenth visit, and shows progress on the way on Steam.
            Achievements.SetProgress("MARATHON", visits, 10);
        }
        mInside = inside;
    }
}
```

Put **Trophy** on an object, press Play and walk the object named in **Visitor** into it. A pop-up appears at the top right of the game, and the Console says which achievement was unlocked.

## 3. Test without replaying

In the Achievements window each row has **Unlock** and **Lock**. Use them to check what your game does when an achievement arrives, or to lock one again and earn it properly. **Lock All** clears everything.

Progress is kept in a small file on your machine, so it survives restarting the editor.

To react in your own way, listen for the event:

```beef
Achievements.OnUnlocked.Add(new (id) => Log.Info(scope $"Unlocked {id}"));
```

## 4. Going on Steam

1. Open **File > Project Settings** and enter your **Steam App ID**. `480` is Valve's public test app and works for trying the connection.
2. Create each achievement on the Steamworks site with **exactly the same ID** as in the window. Steam does not let a game create them.
3. Run the game with the Steam client open. The same `Unlock` call now goes to the player's Steam account and Steam shows its own pop-up.

In the window, **Import from Steam** pulls in achievements your app already has there. While the editor is connected to Steam, the test buttons change the signed-in account, so use a test app or your own account.

A game with App ID 0 never loads Steam at all.

See [Steam and achievements](docs.php?page=steam) for the full list of calls and for multiplayer over Steam.
