# Responsive mobile UI — test checklist

Changes on this branch are intentionally **not deployed**. Ringfall's web deployment tracks Ringfall main and Tessera main, not this feature branch.

## Engine behavior
- UI coordinates use SDL logical window points; physical framebuffer pixels remain for the 3D renderer.
- `GUI.LogicalWidth`, `GUI.LogicalHeight`, `GUI.PixelRatio`, `GUI.IsPortrait`, `GUI.IsLandscape`, and `GUI.AspectRatio` expose the distinction.
- `UIDocument.referenceWidth` complements `referenceHeight`. When both are specified, uniform scaling uses the smaller fit factor. Existing height-only documents retain their original behavior.
- Ringfall's existing phone variant already requests a 1000×600 reference viewport in main.
- The web shell uses CSS safe-area insets on all four sides to avoid display cutouts and home indicators. SDL follows the resulting canvas box, and window resizing/reorientation should update layout.
- RenderView already renders 3D at independently configurable resolution before drawing UI; this branch does not alter it.

## Test before merge
1. Build Tessera with this branch and launch Ringfall using the existing phone variant.
2. Test iOS Safari and Android Chrome in portrait and landscape, including rotating during an active menu.
3. Check menu buttons, text, touch hit areas, scroll/clipping, notches, home indicators and text entry.
4. Compare a high-DPI phone, tablet and desktop; ensure UI dimensions are based on logical points.
5. Check game scene rendering and touch controls after rotation; confirm no 3D aspect distortion.
6. Check the browser build and static shell generation. Confirm build artifacts, no errors, and deployment remains unchanged.

## Known limitations
- The shell's safe-area approach depends on SDL tracking the canvas CSS size correctly. Verify on real devices.
- Fixed-width phone menu content may still require separate portrait-oriented .tcss layouts. Width-fit scaling prevents overflow but can make controls too small in portrait.
- No automated mobile browser/device test was run from this environment.
