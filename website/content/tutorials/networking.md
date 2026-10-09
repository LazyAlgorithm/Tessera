---
title: Two players in one world
summary: Make a scene multiplayer with a Network Session, spawn a networked player for everyone who joins, and test host and client on one machine.
difficulty: Intermediate
minutes: 30
order: 9
---
Tessera's networking is server-authoritative. The server runs the game from the inputs each client sends and broadcasts snapshots. Each client predicts its own player straight away, and when a snapshot disagrees it rewinds to the server's state and replays the inputs it has sent since. Other players are shown a moment in the past, gliding between snapshots. You write movement once, and the engine runs it in all three places.

## 1. Register a player

Projects made by the launcher have `Scripts/GameSetup.bf`, whose `Register` method runs once when the game starts, before any scene loads. Networked objects are registered there, because the server and every client must know the same names.

```beef
using System;
using Tessera;

namespace MyGame;

static class GameSetup
{
    public static void Register()
    {
        NetworkManager.RegisterPrefab("Player", new => CreatePlayer);
    }

    static GameObject CreatePlayer(Scene scene)
    {
        let player = scene.CreateGameObject("Player");
        let renderer = player.AddComponent<MeshRenderer>();
        renderer.mesh.Set("builtin:capsule");
        renderer.color = .FromBytes(235, 140, 60);

        // How the shape moves through the world: steps, slopes, falling.
        let controller = player.AddComponent<CharacterController>();
        controller.radius = 0.5f;
        controller.height = 2;
        // Marks the object as replicated and says who controls it.
        player.AddComponent<NetworkIdentity>();
        // Reads the owner's keys and moves the controller on every machine.
        player.AddComponent<CharacterMotor>();
        player.AddComponent<OwnerCamera>();
        return player;
    }
}
```

`NetworkManager.RegisterPrefabFile("Player", "Prefabs/Player.tprefab")` does the same with a prefab you built in the editor.

## 2. A camera for the local player

Every machine has every player, but the camera should follow only your own. `NetworkIdentity.IsOwner` tells them apart:

```beef
using System;
using Tessera;

namespace MyGame;

/// Puts the scene's camera behind this player, on the machine that controls it.
[Component]
class OwnerCamera : Component
{
    public float distance = 6;

    public override void LateUpdate()
    {
        let identity = GetComponent<NetworkIdentity>();
        let motor = GetComponent<CharacterMotor>();
        let camera = Scene.FindComponent<Camera>();
        // Offline there is no session, and the one player is ours.
        let mine = Scene.Network == null || (identity != null && identity.IsOwner);
        if (!mine || motor == null || camera == null)
            return;
        let look = Quaternion.Euler(motor.Pitch, motor.Yaw, 0);
        camera.Transform.Position = Transform.Position + Vector3(0, 0.6f, 0) - look * Vector3.Forward * distance;
        camera.Transform.Rotation = look;
    }
}
```

## 3. Make the scene multiplayer

1. Build a floor with a **Box Collider** and add a **Camera**.
2. Create an empty object named `Network Session` and add the **Network Session** component (Networking group).
3. Leave **Mode** on `Host`, **Port** on `7777` and **Player Prefab** on `Player`, the name registered above.
4. Choose **GameObject > Spawn Point** a few times and spread the points around the floor. Each player who joins appears at the next one, facing the way its arrow points. For teams, set **Team Count** on the session and give each point a **Team**.
5. Press **Play**. The toolbar shows the session, a player is spawned for you at a spawn point, and WASD, Shift, Space and right-mouse look work.

In Host mode this machine is both the server and a player. Nothing in the scene refers to the player object: the session spawns one for the host and one for each client that connects.

## 4. Test with two windows

Build the game (**File > Build Game (Release)**), then start the same executable twice:

```bash
./MyGame --host                      # window 1
./MyGame --connect 127.0.0.1         # window 2
```

| Option | Meaning |
|---|---|
| `--host` | Server and player in one. |
| `--server` | Dedicated server with no window. |
| `--connect <address>` | Join a server. |
| `--port <n>` | Use a different port. |
| `--lag <ms>` | Hold back everything this copy sends. |
| `--loss <percent>` | Drop that share of this copy's inputs and snapshots. |
| `--jitter <ms>` | Hold each input and snapshot back by up to that much more, at random, as an uneven connection does. |
| `--netstats` | Print traffic and corrections every second. |

Real connections are not perfect, so test with some delay and loss. Giving both windows `--lag 60 --loss 3` simulates about 120 ms round trip with 3% loss each way. Movement should still feel immediate in your own window, because it is predicted.

## 5. Your own player, the easy way

To write a player of your own, derive from `NetworkScript` and say what happens in one tick. The engine gathers the controls, sends them, runs the tick on the server and on the player's own machine, and corrects the player's machine when they disagree.

```beef
using System;
using Tessera;

namespace MyGame;

/// A floating drone: WASD to fly where you look, Space to rise, Ctrl to sink.
[Component]
class Drone : NetworkScript
{
    public float speed = 6;
    /// Shared with every player; changed on the server.
    [Sync] public int32 pings;

    public override void OnTick(TickInput input, float deltaTime)
    {
        var move = input.MoveDirection * speed;
        if (input.Jump) move.y += speed;
        if (input.Crouch) move.y -= speed;
        Transform.Position += move * deltaTime;
        Transform.Rotation = Quaternion.Euler(0, input.Yaw, 0);

        // Runs once, on the server, however many times the tick is replayed on the player's machine.
        if (IsServer && input.Pressed(.Use))
            pings++;
    }
}
```

Use `player.AddComponent<Drone>()` in `CreatePlayer` in place of the controller and `CharacterMotor`. That is all the networking code there is.

Three rules keep it working:

- Take controls only from the `TickInput`, never from `Input`. The tick also runs on the server for another player's controls.
- Move the object through its Transform, Rigidbody or Character Controller; those are what get corrected. Mark other values players need to see with `[Sync]`, and change them on the server.
- A tick can run more than once on the player's machine. Do one-off things inside `if (IsServer)` or `if (!IsReplaying)`.

### Changing the ready-made player

`CharacterMotor` is a player built the same way on a Character Controller. To adjust it instead of starting over, derive from it. This one adds a sneak key:

```beef
using System;
using Tessera;

namespace MyGame;

/// A player that moves slowly while Left Control is held.
[Component]
class Scout : CharacterMotor
{
    public float sneakFactor = 0.4f;
    const int SneakButton = 2;

    public override void GatherInput(ref NetInput input)
    {
        base.GatherInput(ref input);
        input.SetButton(SneakButton, Input.GetKey(.LeftControl));
    }

    protected override Vector3 WishVelocity(NetInput input)
    {
        let wish = base.WishVelocity(input);
        return input.GetButton(SneakButton) ? wish * sneakFactor : wish;
    }
}
```

## What you get without writing anything

With a Network Session in the scene, the engine shares these on its own:

- Physics props, character controllers and AI characters placed in the scene.
- Navigation and behaviour trees, which think on the server only.
- Terrain sculpting and voxel carving, including the pieces that break off.
- Character shape changes, animation clips, and prefabs that have a Network Identity.
- Fields marked `[Sync]`.

Players who join late are brought up to date. See [Networking](docs.php?page=networking) for the details and the limits.

## 6. Game events

Movement is synchronised for you. One-off events, such as a chat line or picking something up, are sent as messages:

```beef
using System;
using Tessera;

namespace MyGame;

static class Chat
{
    const uint8 ChatMessage = 1;

    /// Call from GameSetup.Register, on every machine.
    public static void Register()
    {
        NetworkManager.RegisterMessage(ChatMessage, new => OnChat);
    }

    /// Any machine: ask the server to pass a line on.
    public static void Say(Scene scene, StringView text)
    {
        if (scene.Network == null)
            return;
        let payload = scope NetWriter();
        payload.Write<int32>(0); // who said it; the server fills this in
        payload.WriteString(text);
        scene.Network.SendToServer(ChatMessage, payload);
    }

    static void OnChat(int32 sender, ref NetReader reader)
    {
        var from = reader.Read<int32>();
        let text = scope String();
        reader.ReadString(text);
        let network = Scene.Active?.Network;
        if (network != null && network.IsServer)
        {
            // The server trusts its own record of who sent the message, then relays it to every client.
            from = sender;
            let payload = scope NetWriter();
            payload.Write<int32>(from);
            payload.WriteString(text);
            network.SendToAll(ChatMessage, payload);
        }
        Log.Info(scope $"Player {from}: {text}");
    }
}
```

`SendToServer`, `SendToAll` and `SendToClient` are reliable and arrive in order. `sender` is the client's id, or 0 when the message came from the server or the host. A client must not be trusted to say who it is, which is why the server overwrites the id before relaying.

## What to remember

- Register prefabs and messages in `GameSetup.Register`, identically on every machine.
- The server owns the world. `Scene.Network.Spawn` and `Despawn` work only there, and `SetOwner` hands an object to a client.
- Only what the engine rewinds is predicted: transforms, rigid bodies and character controllers. Keep other gameplay state on the server, in `[Sync]` fields or messages.
- None of this is required: with no Network Session in the scene, the same scripts run as a single-player game.

See [Engine features](docs.php?page=engine) for the networking summary and [Character controller](docs.php?page=character-controller) for the movement side.
