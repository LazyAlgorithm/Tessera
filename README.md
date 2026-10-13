# Tessera

<img src="icon.png" width="96" alt="Tessera icon">

A 3D game engine and editor written in [Beef](https://www.beeflang.org), aimed at low-poly games with voxel worlds and server-authoritative multiplayer.

## Run it

```bash
./build.sh     # native libraries, shaders, launcher (first time, or after changing native/ or shaders)
./tessera      # project launcher: open a recent project, add one, or create one
```

Opening a project compiles its scripts and starts its editor. `Samples/Sandbox` is a ready-made project with a voxel world, a destructible boulder, pushable crates and a networked player.

Requirements on Linux: BeefBuild on `PATH` (or `BEEFBUILD` set), CMake, Ninja, a C++20 compiler, X11 development headers, and a Vulkan driver.

## Portable editor packages (early beta)

After building the native dependencies, create a clean editor folder with:

```bash
python3 tools/package_engine.py --platform linux --folder dist/Tessera-Linux
python3 tools/package_engine.py --platform windows --folder dist/Tessera-Windows
```

Windows builds from Linux use the toolchain prepared by `tools/windows/setup.sh`.
On Windows, use `python` instead of `python3` and build the Windows native libraries first.
The editor's Build window also uses this packager when **Build: Editor** is selected.

Start `Tessera` on Linux or `Tessera.exe` on Windows directly from the package folder.
The folder can be moved: it includes assets, templates, shaderc, and the engine/editor
source and native archives needed to compile project scripts. It excludes native
dependency source, tests, samples, website files, object files, and debug symbols.
BeefBuild and Python 3.11+ remain prerequisites for editing and building projects;
Windows also needs Microsoft C++ Build Tools. System graphics drivers are required.
`--skip-build --config Debug` explicitly packages a previously built debug launcher;
normal packages build a fresh Release launcher and stop if the compiler fails.

## Editor

| Panel | What it does |
| --- | --- |
| Hierarchy | Object tree. Drag to re-parent, right-click to create, duplicate or delete. Folders (GameObject > Folder) group objects without having a transform or components. |
| Scene | Right-drag to fly (WASD, Q/E, Shift), middle-drag to pan, wheel to dolly, F to frame. W/E/R switch Move/Rotate/Scale; hold Ctrl to snap. |
| Game | What the first enabled Camera sees. Click it while playing to send input to the game. A game that locks the mouse (`Input.LockCursor`) keeps it inside this view; Esc frees it, and the toolbar's Lock Mouse button turns locking off altogether. |
| Inspector | Components and their public fields. With nothing selected it shows the scene's lighting, sky and fog. |
| Project | Folder tree and icon grid. Materials and shaders are shown as a ball drawn with them, and models and prefabs as a rendered picture of themselves. Click a material to edit it in the Inspector; double-click a prefab to edit it on its own. Drag models into the Scene or Hierarchy, images onto a Texture field, items onto folders to move them, and files from your desktop into the window to import them. |
| Scripts | Code editor (Visual Studio dark style): syntax colouring, bracket matching, foldable blocks, find/replace, completion that knows the engine and your scripts (type `Audio.` or `myLight.` for its members), undo/redo. Double-click a script in Project to open it. Saving compiles in the background and marks errors on their lines. |
| Behavior | Behaviour trees for AI, drawn like graphs and shown live while the game plays; see `docs/behavior-trees.md`. |
| Graph | Visual scripting. Right-click to add nodes, drag between pins to connect, Alt+click a pin to disconnect, Delete removes a node, middle-drag pans, the wheel zooms at the mouse. Save also compiles the graph into a Beef component. |
| UI | Visual editor for `.tui` interface documents: element tree, live preview, properties and stylesheet. |
| Console | Engine and script log. |

Play, Pause and Step are in the toolbar. Play mode never changes the saved scene. Ctrl+Z / Ctrl+Y undo and redo scene edits.
Script edits reload automatically while the editor runs (see the script reload page). `File > Reload Scripts` (Ctrl+R) forces a reload, `File > Full Rebuild & Restart` is needed after engine or project-settings changes, and `File > Build Game (Release)` makes a release executable.

### Terrain tools

GameObject > Voxel Terrain adds a flat, fixed-size terrain (128 m square by default; set Size X and Size Z). Select it and pick Raise, Lower, Smooth, Flatten or Paint in the Inspector, then drag in the Scene view. Set Mode to Endless for generated terrain without end, or give it your own generator; see `docs/terrain.md`. Sculpted and painted chunks are written to a `.voxels` file next to the scene when you save.

## Writing components

```beef
using Tessera;
namespace MyGame;

[Component]                      // required on every component class
class Spinner : Component
{
    public Vector3 degreesPerSecond = .(0, 45, 0);   // public fields are saved and shown in the Inspector

    public override void Update()
    {
        Transform.Rotate(degreesPerSecond * Time.DeltaTime);
    }
}
```

Callbacks: `Awake`, `OnEnable`, `Start`, `FixedUpdate` (60 Hz), `Update`, `LateUpdate`, `OnGUI`, `OnDisable`, `OnDestroy`.
Field attributes: `[ShowInInspector]`, `[HideInInspector]`, `[NonSerialized]`, `[Range(min, max)]`.
Supported field types: `float`, `int32`, `bool`, `Vector2`, `Vector3`, `Quaternion`, `Color`, `String`, and enums marked `[Reflect(.All)]`.

## What is in the engine

- **Rendering** (bgfx): forward HDR pipeline with 4x MSAA, a sun with four shadow cascades, up to 16 point and spot lights, metallic/roughness shading, per-triangle flat shading for the low-poly look, procedural sky, fog, bloom (a glow around bright and emissive things; set Bloom and Bloom Threshold in the scene's lighting settings, or `Scene.Environment.bloom` from code; off by default), tonemapping, see-through objects (give a Mesh Renderer a color alpha below 1), automatic instancing of identical mesh/material pairs, frustum culling, glTF/GLB models and textures.
- **Materials, shaders and compute**: materials (`.tmat`) shared between objects and edited live in the Inspector; shader graphs for making shaders without code; a metallic-roughness PBR shader with normal, metallic-roughness, occlusion and emissive maps; your own surface shaders (`.tshader`) that keep the engine's lighting, shadows and fog; and compute shaders (`.tcompute`) that run per pixel on the graphics card, usable with no script through the Compute Effect component. See `docs/materials.md`.
- **Voxels**: `VoxelTerrain` streams 32-cell chunks around the camera, generated and meshed on worker threads with marching cubes (or blocky cubes), editable at runtime with `Brush` / `ModifySphere`. `VoxelObject` is a destructible marching-cubes object: `Carve` it and disconnected pieces break off as physics bodies.
- **Physics** (Jolt, deterministic build): `Rigidbody`, box/sphere/capsule/convex/mesh colliders, raycasts and shape casts, and a `CharacterController` (capsule or rounded box) that walks up steps and slopes; see `docs/character-controller.md`.
- **AI**: baked navigation for walking and flying agents (`docs/navigation.md`) and behaviour trees with patrol, chase, detection and blackboard nodes (`docs/behavior-trees.md`).
- **Scenes at run time**: `SceneManager.LoadAdditive` adds another scene file to the one that is playing (levels kept in their own scenes, each editable by itself), `Unload` takes it out, and `SceneManager.Load` changes scene. See `docs/scenes.md`.
- **Joints and debris**: the **Joint** component holds two rigid bodies together at a point, freely or with a swing limit (chains, doors, ragdolls); `Joint.Connect` does it from code. A Rigidbody with **Debris** on rests on scenery but is ignored by everything that moves and by rays and shape queries (corpses, dropped items). See `docs/joints.md`.
- **Spawn points**: `SpawnPoint` components with teams and start-only points; `SpawnPoints.Next`, `Random` and `Place` choose one, and network sessions use them for joining players. See `docs/spawn-points.md`.
- **Audio** (miniaudio, built in): `AudioSource` on anything that makes sound and an `AudioListener` for the ears, with stereo panning or optional, tunable HRTF for headphones (MIT KEMAR measurements), distance rolloff, Doppler, directional cones, occlusion behind colliders, air absorption, reverb zones, six mixer groups and streaming. WAV, OGG, MP3 and FLAC. See `docs/audio.md`.
- **Voice chat** (Opus, built in): off by default; turn it on and players in a session can talk, with an open microphone or push to talk on a key you choose, proximity and team-only voice decided by the server, per-player muting and a microphone test. See `docs/voice-chat.md`.
- **Particles**: `ParticleSystem` draws each system as one instanced call and previews in the editor.
- **Mouse lock**: `Input.LockCursor = true` keeps the mouse inside the window and hides the pointer while the mouse steers the view; `Input.MouseDelta` goes on reporting movement. Set it false while a menu is open. While it is locked, menus and editor panels are not sent the mouse or the keyboard, so nothing under the hidden pointer is hovered or clicked. It is released when play stops, and `Input.CursorLocked` says whether it has really taken hold.
- **Game UI**: override `OnGUI` and use `GUI.Label`, `GUI.Button`, `GUI.Bar`, `GUI.Box`, `GUI.Toggle`, `GUI.Slider`.
- **Prefabs**: right-click an object > Save as Prefab, then drag the `.tprefab` into a scene, double-click it to open it alone for editing (a bar in the Hierarchy has Save, Revert and Back to Scene; the scene waits as you left it; the editor switches to the Scene view, where its own camera flies round the prefab, since a prefab has no camera for the Game view), or call `Prefab.Instantiate(scene, "path.tprefab", position, rotation)`. `NetworkManager.RegisterPrefabFile` spawns one over the network.
- **Game messages**: `NetworkManager.RegisterMessage` plus `SendToServer` / `SendToAll` / `SendToClient` carry reliable game events; `SetOwner` hands an object to a client.
- **Multiplayer, built in and optional**: with a `NetworkSession` in the scene, physics bodies, character controllers, AI, voxel edits, animation, prefab spawning and `[Sync]` fields are shared with no extra code, over UDP or Steam; without one nothing changes. Write a player by deriving from `NetworkScript` and filling in one tick. See `docs/networking.md`.
- **Input actions and controllers**: the game asks for "Jump" or "Move" and the project's `Input.tinput` (Window > Input Actions) says which keys, mouse buttons and controller buttons mean it, so one script works from keyboard and mouse and from any controller. Xbox, PlayStation and Switch pads work with no set-up, with rumble and the right button names; UI documents are worked with the d-pad and a button; `NetworkScript` players use a controller with no code. See `docs/input.md`.
- **Anti-cheat** (optional): on top of networking in which the server moves every player and decides what matters, a Project Settings switch adds watching for invalid controls, speed hacks, message floods, changed game files, debuggers, injected libraries, edited memory (`GuardedInt`) and automated aim, with logging, removal and bans. It runs inside the game, not in the kernel; `docs/anti-cheat.md` says what that means.
- **Steam** (optional): achievements with `Achievements.Unlock("ID")`, an Achievements window, Workshop content with `Workshop.MountInstalled()`, `Browse` and `Publish`, and a Steam transport for multiplayer; see `docs/steam.md`. `Assets.AddSearchPath` mounts any mod folder without Steam.
- **Shadow-only meshes**: `MeshRenderer.shadowOnly` casts a mesh's shadow without drawing it, for the parts of a first-person player's own body that must not get in front of the camera.
- **Networking internals** (ENet): add a `NetworkSession` to a scene. The server simulates from client inputs and sends snapshots holding only what changed, packed small; clients predict their own objects, rewinding and replaying when a snapshot disagrees, and show everything else a moment in the past, moving evenly between snapshots. A client's tick clock follows the server's, and `BeginLagCompensation` / `EndLagCompensation` let the server judge a shot against what the shooter saw. Put movement in `NetworkBehaviour.Simulate`. `CharacterMotor` is a ready-made networked character that drives a `CharacterController`.

Run a built game with `--server` (dedicated, no window), `--host`, or `--connect <address>`; `--port <n>` changes the port.

### Testing multiplayer on one machine

Start the same game executable twice; no second build is needed:

```bash
./MyGame --host                      # window 1
./MyGame --connect 127.0.0.1         # window 2
```

Add `--lag <ms>` to hold back everything that copy sends, `--jitter <ms>` to hold each packet back by up to that much more at random, and `--loss <percent>` to drop that share of its inputs and snapshots; `--netstats` prints the traffic and corrections every second. Use the same values on both to simulate a real connection, for example `--lag 60 --loss 3` on each gives about 120 ms round trip with 3% loss each way.

## Visual scripting

Create a graph with Project > + > Graph. Each graph compiles to an ordinary Beef component with the graph's name (the generated `.bf` is hidden in the Project window; right-click the graph for View Generated Code or Convert to Script). Save in the Graph tab saves the graph and compiles it; the editor's automatic script reload then picks the component up, so add it to objects like any other component without rebuilding.

Any public static method can be a node:

```beef
[GraphLibrary]
static class MyNodes
{
    [GraphNode] public static float Pulse(float time, float speed) => Math.Sin(time * speed) * 0.5f + 0.5f;
    [GraphNode] public static void Shout(String text) => Log.Info(text);
}
```

Parameters become inputs and the return value the output (float, int32, bool, Vector3, String). Methods that return nothing are action nodes with flow pins.

### Everything code can do

You do not have to write those by hand. The add-node menu has two more entries, filled in by reading source files:

- **Engine**: every public method, property and field of the engine, grouped by area (AI, Animation, Audio, Net, Physics, ...) and then by class. About 1,550 nodes: play a sound, cast a ray, move a character controller, set an Animator parameter, unlock an achievement, find a spawn point.
- **Game**: the same for your own scripts, by class.

Nothing lists these by hand, so an engine feature added later, or a script you write, has nodes as soon as it is saved. Every generated node is compiled as real code by the test suite.

- A method on a component has an input for the component. Left unconnected it means **this object's own** (shown as "self"), so *Audio Source: Play* with nothing plugged in plays this object's sound.
- Each component class also has **Get From Object** and **Add To Object**.
- A method that returns a value and does something (a ray cast) is an action with a **Result** output; `out` parameters are outputs too.
- Pins carry numbers, whole numbers, booleans, text, vectors, rotations, colours, enum values (picked from a list) and objects. A whole number plugs into a number pin and back.

Also built in: **For Loop** and **While Loop**, comparisons and logic, whole-number maths, vector and rotation helpers, **Key Held / Pressed / Released** for any key, logging, and events for the rest of a component's life (On Awake, On Enable, On Disable, On Destroy, On GUI).

### Multiplayer in graphs

A graph calls the same engine functions as code, so what is shared automatically from code is shared from a graph: sounds, animation, voxel edits, spawning. For the rest:

- **Networked** on a variable shares its value from the server.
- **On Tick** (under Network) turns the graph into a Network Script: its outputs are the player's synced controls (Move, Move Direction, Yaw, Jump, Fire...), and the engine handles sending input, prediction and correction. Nothing else has to be set.
- **Send Network Event** runs the matching **On Network Event** on every machine. The server can send for any object; a client only for one it owns.
- **Is Server**, **Is Mine** and **In Session** for the cases that must differ.

### Variables

The Variables panel in the top right of the Graph tab (toolbar: Variables / Hide Variables) declares values the graph keeps between frames. Click + Add, then give the variable a name, a type (Number, Vector, Boolean or Text) and a default. Get and Set place nodes that read and write it; variable nodes are also under Variables in the add-node menu, bound by their Name value.

Each variable compiles to a public field of the graph's component, so once the graph is saved and scripts have reloaded it appears in the Inspector and can be set per object and saved with the scene like any script field. The default in the panel is only the value new components start with. Renaming a variable renames its nodes but is a new field to scenes that already saved the old name; changing its type drops links that no longer fit; removing it removes its nodes. A subgraph's variables live on the component of the graph that uses it, and share a field with a host variable of the same name.

## Interfaces (UI documents)

A `.tui` file is HTML-like markup; its CSS-like stylesheet is either a `<style>` block inside it or a `.tcss` file of the same name beside it (the UI tab's Open CSS button creates that file):

```html
<style>
.card { width: 320; padding: 20; gap: 10; background-color: #1b2028f2; border-radius: 8 }
</style>
<panel class="card" onload="OnOpen">
    <text style="font-size: 24">My Game</text>
    <input bind="playerName" />
    <button onclick="OnPlay">Play</button>
</panel>
```

Put a **UI Document** component and your own component on the same object. `onclick` / `onload` name methods on that component (optionally taking the `UIElement`), and `bind` names one of its public fields. Set the UI Document's **Reference Height** (1080, say) to have the document scale with the window, so it looks the same at any resolution; left at 0, sizes are real pixels. From code, `GetComponent<UIDocument>().Find("id")` returns an element whose `text`, `visible` and styles you can change. Tags: panel, text, button, image, input, bar, slider, toggle and canvas. A `slider` (attributes `min`, `max`, `step`) and a `toggle` call `onchange` with the element, whose `value` is the new setting, or write straight into a `bind` field. A `canvas` calls `ondraw` every frame so that code can draw into its rectangle (`screenX`, `screenY`, `screenWidth`, `screenHeight`): a radar, a graph. In the UI tab a canvas shows as an outline with its name, so it can be placed like anything else. `repeat="8"` on an element makes eight copies of it, with `{i}` and `{n}` in its attributes and text replaced by each copy's number, for lists and grids. `SetClass("selected", true)` switches a class on an element from code. Layout: flex-direction, gap, padding, margin, width/height (px or %), flex-grow, align-items, justify-content, and position: absolute with left/top/right/bottom. Stylesheets may hold `/* comments */`. An object can carry several UI Documents (a heads-up display, a menu for each screen): they are drawn in the order of the components, and a disabled one is neither drawn nor clickable, so showing a screen is `document.Enabled = true`. See `UI/sample_menu.tui` and `Scripts/SampleMenu.bf` in any new project.

## Animation

- **Rigged models** (Blender: export glTF 2.0 `.glb` with the armature and animations): drag the file into the Scene, or add a **Skinned Mesh Renderer** and set its model. Clips in the file are listed in the Inspector; call `Play("Run")` from code. Skinning runs on the CPU, up to four bones per vertex.
- **Bone hierarchies of rigid parts**: the **Animator** component plays `.tanim` clips on child objects by name (the sample character in `Prefabs/character.tprefab`).
- **Animator Controllers** (`.tcontroller`): a state machine of clips with parameters, conditions, exit times and cross-fades, edited in **Window > Animator** and watched live while the game runs. Scripts call `SetFloat`, `SetBool`, `SetTrigger`.
- **Window > Animation**: a timeline for making clips, laid out like Unity's: transport buttons and a property list on the left, a zoomable frame ruler and key diamonds on the right, and Record or Auto Key to key whatever you move.

See `docs/animator.md`. Animator parameters and states are shared in multiplayer with no setup.

## Projects

The Project window shows the project's `Assets` folder (on disk: `src/`). Scripts anywhere inside it are compiled; models, textures, scenes and prefabs live beside them. The Beef workspace files are generated on every build.

Libraries: put a Beef library folder in the project's `Libraries/` folder, or use File > Project Settings to download one from a Git address, reference a folder, or add linker flags for C libraries.

Sample: `Samples/Sandbox` (voxel world, networking).

## Layout

```
Engine/      runtime library and shaders
Editor/      editor, project system, project templates
Launcher/    project hub executable
native/      CMake build of third-party code plus the small C/C++ shim
third_party/ bgfx, SDL3, Jolt (JoltC), ENet, Dear ImGui (cimgui), ImGuizmo, cgltf, stb, miniaudio, KEMAR HRTF data, Opus
Samples/     example projects
Tests/       CPU regression fixtures
website/     project website for XAMPP (PHP + MariaDB): docs, tutorials, screenshots
```

Each type has its own file, or shares one with the small types that only it uses, so a class is found by its name.

`Engine/src`:

| Folder | Contents |
|---|---|
| Core | Application loop, GameApp, Log, Time, Input |
| Scene | Scene, GameObject, Transform, Component, the component registry, serializer, scene manager, prefabs, spawn points |
| Math | Vectors, Quaternion, Matrix4, Color, Mathf, bounds/ray/frustum |
| Render | RenderView, Camera, Light, MeshRenderer, Material and ShaderAsset, Compute, Mesh, Primitives, particles, debug and gizmo drawing |
| Animation | AnimationClip, Animator, AnimatorController, SkinnedModel, SkinnedMeshRenderer |
| Physics | PhysicsWorld and its queries, Colliders, Rigidbody, Joint, CharacterController |
| Audio | Audio engine, AudioSource, AudioListener, AudioReverbZone |
| AI | Navigation data, baker, surface and agent; behaviour tree data, nodes and runner |
| Net | NetworkManager, identities, serialization, session, transports, automatic sync, tick scripts, character motor |
| UI | UI documents and elements, immediate-mode GUI |
| Voxel | Voxel terrain (fixed or endless) and voxel objects |
| Scripting | Script hot reload, graph node attributes |
| Assets | Asset cache and path resolution |
| Platform | Bindings: bgfx, SDL3, Dear ImGui, Jolt, ENet, Steam; achievements; Workshop |

`Editor/src`:

| Folder | Contents |
|---|---|
| App | EditorApp (state and lifecycle) and its parts: scene operations, prefab editing, building, layout and menus, popups; undo; icons; the shared entry point |
| Panels | Hierarchy, Inspector, Console, Project, Game view, Scene view |
| Project | Project files, generator and templates, settings, recent projects, folder monitor, shell helper |
| Graph | Visual scripting: graph editor, canvas, node library, graph model and compiler |
| Behavior | Behaviour tree editor and live debugging view |
| Animation | Animator window (state machines) and Animation window (clip timeline) |
| Scripts | Code editor, the code index it and the graphs read from source (ApiIndex), script reload, script-to-component lookup |
| Tools | Terrain tools, navigation tools, achievements window, material inspector, shader compiler, asset previews |
| UI | UI document editor |

### Shipping

- **A game:** File > Build... (choose Linux or Windows, whether it starts fullscreen, and a folder; `GameWindow.Fullscreen` switches while the game runs), or `python3 tools/build_player.py <project> [--platform windows] --output <folder>`. The result is a folder with one executable, its asset packs (`game.tpak`: the project's assets and the engine's shaders, compressed, scrambled and checksummed rather than loose files, plus a pack for each scene's own files so that an update to one map changes one small file) and `THIRD_PARTY_LICENSES.txt`, and nothing else: it can be moved or sent to somebody. See `docs/standalone-player.md`.
- **The editor, for another machine:** File > Build... with Build set to Editor, or `tools/package_engine.sh --platform linux|windows --folder <folder>`: a folder with the launcher, the engine and editor source, the native libraries and the tools.
- **The engine:** `tools/package_engine.sh [folder]` packs a built copy (launcher, engine and editor source, prebuilt native libraries, samples, tools, docs) into one archive for another Linux x64 machine. That machine needs the Beef toolchain, because each project compiles its scripts with the engine, and Python 3.11+ for Build Game. A project that names an engine folder which is not there finds the engine again by itself.
- **Licences:** `tools/make_licenses.py` gathers the licence of every bundled library into `THIRD_PARTY_LICENSES.txt`; `build.sh` runs it, and every packaged game gets a copy.
- **Windows:** games and the editor are built for Windows from Linux, after a one-time `tools/windows/setup.sh`; see `docs/windows.md`. Built games run on Windows machines; the editor has been checked under Wine only.

### Website

`website/` is a small PHP site with a MariaDB database. `sudo website/setup.sh` copies it to XAMPP's `htdocs/tessera`, creates the `tessera_site` database and loads the content; it is then at `http://localhost/tessera/`. Documentation pages are imported from this README and `docs/`, tutorials from `website/content/tutorials/*.md`, and the page list is `website/content/manifest.php`. After editing any of them, `website/update.sh` reloads the content without sudo; changes to the site's own PHP, styles or images need `website/setup.sh` again (no sudo after the first run, which hands the installed folder to your user).

## Platforms

Developed and tested on Linux x64 with Vulkan. Windows x64 builds (games and the editor) are cross-compiled on Linux and use Vulkan; see `docs/windows.md`. The dependencies also support macOS, Android and iOS, and shaders are already compiled for Vulkan, OpenGL, OpenGL ES and Metal, but those platforms still need their own link settings in the project template and have not been built. Direct3D shaders must be compiled on Windows (`tools/compile_shaders.sh`).

## Known limits

- The OpenGL backend crashes at startup on NVIDIA drivers under a Wayland desktop (inside the driver's EGL layer); Vulkan is the working backend on Linux.
- The Windows editor has been run under Wine only (built games run on Windows machines), and Windows uses Vulkan only (no Direct3D shaders). `docs/windows.md` lists what is not done.
- Audio occlusion is a single ray and there are no computed reflections; see `docs/audio.md`.
- Objects already placed from a prefab are copies: editing the prefab changes what is placed from then on, not what is already in a scene.
- Materials have no environment maps (metals mirror the sky and ground colours), and shadows ignore a shader's vertex movement and cutouts; see `docs/materials.md`.
- Skinned models are deformed on the CPU, which suits low-poly characters but not crowds of detailed ones; morph targets are not supported.
- Graphs cannot use lists, delegates or generic methods, graph variables cannot hold object references, and UI documents have no scrolling, text wrapping or animations (a canvas can draw anything they lack).
- Automatic script reload works in Linux and Windows x64 Debug editors, and engine changes need Full Rebuild & Restart. Every component class needs `[Component]`.
- Undo covers objects, components, fields and scene settings, but not terrain sculpting or voxel carving.
- Voxel terrain has no level of detail, and smoothing can leave hairline seams at chunk borders.
- Network: a client does not predict physics objects it does not own (they move when the server says so), and there is no encryption or NAT traversal of the engine's own (the Steam transport provides both).
- Joints are ball joints with an optional swing limit; there are no hinges, sliders, springs or motors, and a hard knock can push a limb a little past its limit. Vehicle wheels are simulated with suspension rays.
- Script completion works out a variable's type from its declaration or assignment on one line; it does not follow chains (`a.b.`) or infer from method return types.
- Built games still link the editor code.
