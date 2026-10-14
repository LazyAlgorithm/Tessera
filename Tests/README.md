# CPU regression tests

Build native dependencies first using the engine's normal build setup. These fixtures use BeefBuild and the local native archives, without a display or GPU.

For Layers, Viewmodel, PostProcessing, SkinnedMaterials, Http, Saving, Navigation, CharacterController, BehaviorTree, Network, Audio, Voice, Animator, Material, Terrain, SpawnPoints, Achievements, References, InspectorTypes, ScriptCatalog, CodeEditor, GraphApi, GraphVariables, ShapeQueries, Scenes, Joints, UIDocuments and InputActions:

```sh
BeefBuild -workspace=Tests/Navigation -config=Debug -run
```

Use the desired fixture folder.

The asset pack test builds packs with `tools/pack_assets.py` and has the engine read text, bytes, an image, a model and sounds back out of them, and refuse a pack that was changed:

```sh
python3 Tests/AssetPack/run.py
```

The anti-cheat test runs an honest player and then one cheat at a time (invalid controls, a speed hack, a flood, a silent game, changed files, automated aim) against a real loopback session:

```sh
python3 Tests/AntiCheat/run.py
```

The script reload integration test uses the real compiler and keeps one host process alive across six generations:

```sh
python3 Tests/ScriptReload/run.py
python3 Tests/ScriptReload/run.py --windows   # the same against a Windows host (under Wine when run on Linux)
```

It covers compile failure, method edits, a new script, added/retyped/removed fields, inspector attribute changes, references, static state, Play and physics preservation, and full-width integer/double/vector values. `--keep` preserves its temporary workspace for debugging.
