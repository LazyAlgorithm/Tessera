# Foliage and wind

**Foliage** covers ground with plants: grass, flowers, bushes, rocks, trees. **Wind Zones** make them, and anything
else you choose, bend in the wind.

## Foliage

A Foliage component is one kind of plant, many times over. Every plant of a component is the same model, and the
graphics card draws them all together (instancing), so tens of thousands cost little. Each plant has its own turn,
size and shade, so they do not look stamped out.

1. Select the terrain (or any object) and add a **Foliage** component.
2. Choose its **Mesh**: `builtin:grass`, `builtin:bush`, `builtin:tree`, `builtin:pine`, or a model of your own.
3. Press **Paint** in the component, then drag over the ground in the Scene view. Hold **Shift** to erase.
4. Add another Foliage component for another kind of plant. Several can sit on the same object, each with its own
   Paint button.

**Fill Terrain** paints every terrain tile at once. **Clear** removes every plant of that component.

| Field | What it does |
|---|---|
| Mesh | The plant. Its foot must be at the model's origin: that is where it stands on the ground and what it bends from. |
| Material | A `.tmat` for the plants. Empty uses the model's own colours, two-sided and smoothly shaded. |
| Color, Color Variation | A tint for all of them, and how much they differ in shade from one to the next. |
| Min Scale, Max Scale | Each plant's size is somewhere between these. |
| Sway | How far the plants bend in the wind: 1 for grass, about 0.3 for bushes and trees, 0 for rocks. |
| Cast Shadows | Worth it for trees. A field of grass is better without. |
| View Distance | Plants further than this from the camera are not drawn. They thin out over the last third rather than stopping at a line. |
| Density | The brush: plants to each square metre painted. Grass wants 4 to 12; trees about 0.01. |
| Max Slope | The brush: ground steeper than this many degrees is left bare. |

The brush finds the ground on a Voxel Terrain (the object's own, else the scene's). With no terrain it paints on
level ground at the object's height; while the game is playing it uses colliders.

Plants are scenery. They have no colliders, they are saved with the scene, and they are the same on every machine.

From code:

```beef
let grass = GetComponent<Foliage>();
grass.Paint(point, 6);          // what the brush does: Density plants to the square metre, in a 6 m circle
grass.Erase(point, 3);          // removes the plants in a circle
grass.Add(point);               // one plant; Add(point, turnDegrees, scale) to choose
grass.Clear();
```

`Paint`, `Erase`, `Add` and `Clear` change only the machine they are called on: call them on every machine for a
change everyone should see.

### How many

All the plants of one component that are in view go to the graphics card in one draw. What costs is the number in
view at once, so set **View Distance** by kind: grass 60 to 90 m, bushes 150, trees 300 or more. Something like fifty
thousand plants in view is comfortable on a desktop graphics card; a phone wants far fewer and a shorter distance.

## Wind

Add a **Wind Zone** to an object. The wind blows the way the object faces (its blue arrow).

| Field | What it does |
|---|---|
| Shape | **Global** blows over the whole scene. **Sphere** blows inside a radius round the object, strongest in the middle and fading to nothing at the edge. |
| Strength | 0 is still air, 1 a breeze, 3 a strong wind, 6 a gale. |
| Gusts | How much the wind comes and goes, from steady (0) to gusty (1). The gustiest Global zone sets it for the scene. |
| Radius | How far a Sphere zone reaches. |

Zones add up: a Global zone for the day's weather, and Sphere zones for a gusty valley, a fan, a helicopter's
downdraught or the blast of something passing. Move, turn or animate a zone like any object.

What bends:

- **Foliage**, by its **Sway**.
- Any **Mesh Renderer** with **Wind Sway** above 0: a flag, a hanging sign, a tree placed by hand, reeds. It bends
  about its own origin, more the higher up, so put the origin at its foot.

The bending is done on the graphics card, so it costs the same for one plant as for fifty thousand. The four Sphere
zones nearest the camera take part; Global zones always do.

From code, `Wind.At(Scene, position)` is the wind at a point (a direction whose length is the strength), for
anything that should drift with it: smoke, a sail, a paper bag.

Wind is the same on every machine when the zones are. Zones saved in a scene are; a zone moved by a script moves on
other machines if its object is shared (a Network Identity).

## Limits

- Shadows of swaying plants do not sway, and the depth used by ambient occlusion and depth of field sees them
  standing still.
- Plants do not collide and cannot be walked into; put colliders on trees that must block the player.
- Painting and erasing are not on the editor's undo yet.
- Plants do not follow ground that is sculpted afterwards: erase and repaint there.
- Custom shaders made before this version bend only after they are compiled again.

Tests: `BeefBuild -workspace=Tests/Foliage -config=Debug -run`.
