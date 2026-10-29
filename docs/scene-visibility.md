# Scene visibility and locks

Two buttons sit in a column at the left of the Hierarchy, beside each object. They show while the pointer is on the
row, and stay showing while switched on.

- **Eye**: hides the object from the Scene view. It is not disabled: the game and the Game view still have it, and
  scripts see it as before. Its meshes, shadows, decals, foliage, particles and gizmos are left out of the Scene view
  (and the Model Views), and clicks in the Scene view go through it.
- **Lock**: the object is still drawn, but clicking it in the Scene view does nothing, so you can work on things
  in front of or behind it. Clicking it in the Hierarchy still selects it.

Pressing either button on a parent sets its children too. Hold the button down and drag up or down the column to
set every row the pointer passes over the same way (hide or show, lock or unlock), as in Unity.

Both are your own editor settings, not part of the scene: they are kept per scene in
`scene_visibility_<project>.txt` in the editor's settings folder, so they come back the next time the editor opens
and are never shared through the scene file or version control.

For engine code, `RenderView.hiddenHere` is the set of object ids one view leaves out (`HidesHere` checks one), so
the Scene view can hide objects that the Game view still draws.

Test switches: `--visibility-test` (logs `VISIBILITY-TEST PASS` or `FAIL`; uses a settings file of its own),
`--scene-hide <object name>`, `--scene-lock <object name>` (as pressing that object's eye or lock).
