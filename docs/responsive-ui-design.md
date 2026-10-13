# Responsive UI design — Tessera and Ringfall

Status: **design specification**, not an implementation request. Record decisions here before changing the UI again. Target: Tessera engine; Ringfall is the reference game. Work on `dev`; production `main` changes require explicit approval.

## The bug we diagnosed

The web canvas was positioned against all four edges but given `width: auto; height: auto`. A canvas is a replaced element with an intrinsic size: those CSS rules did **not** resize it to the available screen. SDL consequently used a 1600×900 fallback window on a phone with a much smaller viewport, showing only the top-left portion of the game. This also explained apparent 3D zoom, clipping and apparent anti-aliasing problems.

**Correctness invariant:** The canvas's CSS box must match the actual available viewport (accounting for safe areas), and SDL's logical window size must follow that CSS box on load, resize and orientation changes. The drawing buffer must follow the chosen rendering resolution, independently of UI layout.

The earlier mobile workarounds (Ringfall phone references 900/1080, percentage widths based on a false 1600×900 viewport, and touch scale 0.8) were tuned against incorrect dimensions. They are **not** the desired long-term defaults and must be reassessed against the real viewport. Do not restore them as blanket fixes.

## Design goals

1. **Automatic screen adaptation:** Correct on desktop, tablets, iOS/Android phones, landscape and portrait. Rotation should reflow without restarting.
2. **Correct logical units:** UI layout and hit testing operate in consistent logical coordinates; framebuffer pixel density only affects sharpness, not apparent size.
3. **Responsive layouts, not global shrinking:** Screens rearrange or scroll when narrow rather than scaling entire interfaces down until text is unreadable.
4. **Consistent visual language:** Reuse the same UI elements, themes, callbacks and data bindings across device variants; override only layout/interaction where needed.
5. **Touch-first where appropriate:** Finger-sized targets, appropriate spacing and safe-area padding, with no loss of desktop mouse/keyboard/controller behavior.
6. **Per-game control:** Tessera supplies generic layout and scaling primitives; each game chooses its own visual style and layout variants.

## Web canvas and renderer

- Size the canvas explicitly to the viewport's available CSS dimensions. Respect the safe-area inset and ensure the inset is applied **once**, not both by the shell and UI.
- On every resize/orientation change, propagate the new logical size to SDL and Tessera before laying out UI.
- Keep **three distinct concepts**: CSS viewport size, SDL/UI logical size, and physical rendering-buffer resolution.
- High-DPI scaling may increase drawing-buffer resolution for clarity; it must not multiply the UI's layout coordinates.
- 3D aspect ratio follows the current viewport. Internal 3D resolution and anti-aliasing settings remain independently configurable; do not use UI scaling to repair 3D rendering.
- Avoid hardcoded 1600×900 or other desktop-sized fallback values during normal mobile operation. A fallback is acceptable only when a valid viewport genuinely cannot be measured, and should be logged.

## Tessera UI layout contract

- `UIDocument.referenceWidth` and `referenceHeight` provide **optional design references**, not substitutes for correct viewport measurement.
- When both are specified, scale uniformly to fit, never stretch X and Y independently. Height-only legacy documents retain compatible behavior.
- Use responsive containers, percentage widths, flexible rows/columns, wrapping, constraints and scrolling where appropriate.
- Provide breakpoint- or orientation-specific arrangements for structurally different layouts (for example, a two-column desktop settings screen versus a single-column portrait settings screen).
- Keep minimum readable text sizes and minimum usable touch target sizes; do not globally shrink below them just to fit more content.
- Recompute layout, clipping, input bounds and safe-area padding when dimensions or orientation change.
- Expose viewport size, pixel ratio, orientation, active variant and computed document scale for debugging.

## Ringfall reference behavior

- **Main menu:** Logo and primary actions fully visible in both orientations, no clipping or oversized elements. Landscape can use a left-side menu; portrait should reflow into a compact vertical composition rather than retain a desktop-width panel.
- **Play / Join / Lobby / Settings / Anvil:** Side-by-side sections may collapse into stacked sections or scroll in portrait. No fixed-width panels should spill off-screen.
- **Text entry:** Browser keyboard should not permanently hide the active field or critical actions.
- **Touch controls:** Joystick, aiming and action buttons sized by actual logical viewport and touch ergonomics, not by the old 1600×900 fallback. Respect safe areas, keep gameplay visible, and allow per-game adjustment.
- **Desktop:** Existing layouts and controls should not regress because a phone-specific fix was applied.

## Testing and acceptance criteria

1. Confirm actual canvas CSS bounds, SDL logical dimensions and physical drawing-buffer dimensions on real devices and emulated phones; these should be coherent and update on rotation.
2. Test iPhone portrait and landscape (including notch and home-indicator areas), Android phone, tablet and desktop.
3. Verify every Ringfall screen, not only the main menu: Play, Join, Lobby, Settings, Anvil and in-game HUD.
4. Check touch targets and hit testing match visible buttons; test scrolling, text entry, rotation mid-game, and safe-area behavior.
5. Compare 3D framing and sharpness before and after UI changes; investigate anti-aliasing separately from layout.
6. Record viewport/scale diagnostic screenshots when reporting a bug. Remove or disable debug overlays for production.
7. Build and test on `dev`; do not merge to `main` without user approval.

## Implementation guidance

Fix viewport measurement and canvas sizing **first**, then remove compensating per-game scale overrides, then implement responsive screen layouts. Avoid further arbitrary reference-resolution tweaks unless measured viewport and computed layout prove they are necessary.

This document captures the agreed design direction. It does not claim all of these behaviors are implemented or tested.
