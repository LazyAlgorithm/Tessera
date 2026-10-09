# Terrain

**GameObject > Voxel Terrain** adds a terrain. It is a **fixed area that starts flat**, like a new terrain in Unity: shape it with the terrain tools in the Inspector (raise, lower, smooth, flatten, paint), and what you make is saved with the scene.

## The area

| Field | Default | Meaning |
|---|---|---|
| Mode | Fixed | Fixed: a set area. Endless: generated around the camera for ever. |
| Size X, Size Z | 4, 4 | Fixed mode: chunks along each axis. A chunk is 32 voxels, so 4 x 4 at voxel size 1 is 128 m square. Up to 64. |
| Flat Height | 0 | Fixed mode: the height the ground starts at, above the object. |
| Min Chunk Y, Max Chunk Y | -1, 2 | How far down and up the terrain reaches, in chunks: with the defaults, 32 m below the object to 96 m above. |
| Voxel Size | 1 | Metres per voxel. Smaller is finer and costs more. |

The area starts at the object's position and extends along +X and +Z; the menu item centres it on the origin. A selected terrain shows its box. The whole area is always loaded, wherever the camera is, and there is no ground beyond its edge.

Changing the size, height or mode in the Inspector rebuilds the terrain; sculpting already done is kept where it still fits.

## Endless terrain

Set **Mode** to **Endless** for a world generated from noise around the camera: `seed`, `terrainHeight`, `terrainScale`, `caveAmount` and `viewDistance` shape it. This is what the open-world sample scene uses. Scenes saved before terrains had a mode keep their endless terrain.

## Your own generator

How a world is generated differs from game to game, so the shape can be replaced:

```beef
let terrain = GetComponent<VoxelTerrain>();
// More than zero is solid, less is air; the surface is where it crosses zero.
terrain.SetGenerator(new (x, y, z) => {
    let hill = Math.Sin(x * 0.05f) * Math.Cos(z * 0.05f) * 12;
    return hill - y;
});
```

- It works in both modes. Fixed mode still ends the ground at the edge of the area.
- Coordinates are in the terrain's own space, in metres.
- It runs on worker threads, several at once: read only data that does not change while the terrain is generating.
- `SetGenerator(null)` goes back to the built-in ground. Setting a generator rebuilds the terrain.
- The generator is code, so it is not saved in the scene: set it in `Awake` or `Start` each run. Sculpting on top of it is saved as usual.

## Editing at run time

`terrain.ModifySphere(point, radius, amount)` digs (negative) or builds (positive), and `terrain.Brush(...)` gives the other brushes. In a network session both are shared automatically; see [Networking](networking).

## Limits

- No level of detail, and smoothing can leave hairline seams at chunk borders.
- A fixed terrain is rectangular and loads all of itself: 64 x 64 chunks is the most it allows, and far less is sensible.
- The edge of a fixed terrain is a sheer side, not a skirt.
- Undo does not cover sculpting.

## Tests

`BeefBuild -workspace=Tests/Terrain -config=Debug -run` (14 checks): the fixed default and its size, flat start, no ground beyond the edge, raising and digging, resizing, custom generators in both modes, endless mode following the camera, and scenes old and new keeping their mode.
