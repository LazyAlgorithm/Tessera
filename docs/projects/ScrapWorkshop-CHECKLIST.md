# ScrapWorkshop implementation checklist

This file is the durable progress record. A checked item means its stated evidence exists; implementation and play validation are separate.

- [x] Locate local Tessera engine and project format.
- [x] Create isolated ScrapWorkshop project; leave Steam files unchanged.
- [x] Import original wheel, driver seat, bearing, wood, metal, and concrete assets.
- [x] Record source assets in asset-manifest.json and retain original block definitions.
- [x] Implement flat workshop scene, editable starter chassis, grid placement/removal, material selection and collision rebuilds.
- [x] Implement assembly lift/release, height adjustment and recovery.
- [x] Implement initial raycast suspension, throttle, steering and brake.
- [x] Compile and resolve all errors (BeefBuild Debug completed successfully).
- [ ] Run and visually inspect workshop.
- [ ] Validate block add/remove, lift and driving behavior.
- [ ] Add construction save/load so player edits survive restarts.
- [ ] Import and integrate original character, skeleton and movement animations.
- [ ] Import and integrate original tools and tool animations.
- [ ] Integrate original HUD artwork (current controls use temporary engine text).
- [ ] Replace temporary lift geometry with original lift asset.
- [ ] Allow wheel, seat, bearing and engine placement with connectivity rules; current vehicle has fixed running gear.
- [ ] Validate vehicle assembly, materials, collision and camera after full import.
- [ ] Package local playable build and document remaining limitations.

## Resume

Project: `/home/zerker24/TesseraProjects/ScrapWorkshop`
Engine: `/home/zerker24/BeefProjects/Tessera`
Build: `BeefBuild -workspace=/home/zerker24/TesseraProjects/ScrapWorkshop -config=Debug`
Asset import: `python tools/import_assets.py`
Build log (initial): `/tmp/scrap-workshop-build.log`

Source and imports are saved on disk. Local execution pauses during system sleep; no automatic AI restart has been configured. Per-checklist ChatGPT app push notifications are not exposed by tools in this session.

## Latest checkpoint

Compilation passes. Graphical smoke test could not start: SDL reports `x11 not available` in this execution environment. Visual appearance, driving, lift interaction and placement are not yet validated. Character, animations, original tools and original HUD remain pending. No automatic monitor or notifications have been configured.
