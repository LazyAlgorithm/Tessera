---
title: Materials, a shader of your own, and a compute effect
summary: Make a PBR material with a normal map, write a surface shader that glows, and run a compute shader on a screen, with no engine changes.
difficulty: Intermediate
minutes: 25
order: 13
---
New projects come with a few examples in `Materials/`, `Shaders/` and `Textures/`. This tutorial builds the same things by hand so you know what each part does.

## 1. A material

1. Add a sphere: **GameObject > 3D Object > Sphere**.
2. In the Project panel choose **+ > Material** and name it `Metal`.
3. Select the sphere and set **Material** on its Mesh Renderer with the `...` button (or drag the material onto the field).

The material's settings now appear in the Inspector under the sphere's components. (Clicking the material file in the Project panel shows them too.) Edit them and watch the sphere:

- Untick **Flat Shading** for a smooth surface.
- Set **Color** to a warm yellow, **Metallic** to 1 and **Roughness** to about 0.3.

Add a second sphere and give it the same material: both change together. That is the point of a material. To tint one object differently, change the **Color** on its Mesh Renderer; it multiplies the material's.

## 2. PBR maps

In the material's section of the Inspector:

1. **Normal Map**: `Textures/hammered_normal.png`. The sphere looks dented, with no extra triangles.
2. **Metallic-Roughness**: `Textures/hammered_orm.png`, and set the **Roughness** slider to 1. The map multiplies the slider, so 1 uses the map as painted: the dents are rougher than the metal between them.
3. **Occlusion**: the same file. Its red channel darkens the creases.
4. Set **Tiling** to `2 2` to repeat the pattern.

Any normal map and any glTF-style occlusion/roughness/metallic image works the same way.

## 3. A shader of your own

Choose **+ > Shader** and name it `Pulse`. It opens in the code editor with a working example. Replace it with:

```glsl
property float speed = 2
property color glow = 0.2 0.8 1 1
property float bands = 6

surface {
    // Bands of light that climb the object.
    float pulse = 0.5 + 0.5 * sin(time * speed - worldPosition.y * bands);
    emissive += glow.rgb * pulse * pulse * 2.0;
}
```

Press **Save**. The Console says `Compiled Shaders/Pulse.tshader`. (Leave a mistake in, such as a missing semicolon, and the Console shows the compiler's message instead; objects keep their last working look.)

Make a material, set its **Shader** to `Shaders/Pulse.tshader`, and put it on a cylinder. The bands move even in edit mode. The three properties are at the bottom of the material's settings in the Inspector: drag **Speed**, change **Glow**.

You wrote no lighting code, and the cylinder is still lit and shadowed: your code only decides the surface, and the engine does the rest.

To move the mesh as well, add:

```glsl
vertex {
    position += normal * sin(time * speed + position.y * 6.0) * 0.02;
}
```

## 4. The same without code: a shader graph

Choose **+ > Shader Graph** and name it `Rim`. The Graph tab opens with a small working graph ending in **Surface Output**.

1. Right-click the canvas and add **Rim (Fresnel)** (under Shader Effects). Set its Power to `3`.
2. Add a **Color Property**, name it `rim`, and pick a bright colour as its default.
3. Add **Color RGB** and **Scale Vector**. Connect the property to Color RGB, that to Scale Vector's Vector, and Rim to its Amount.
4. Connect Scale Vector to **Emissive** on Surface Output, replacing what was there.
5. Press **Save**.

Make a material, set its Shader to `Shaders/Rim.tshader`, and put it on the sphere: its edges glow, and `Rim` is a colour in the material's Inspector. Albedo was left alone, so the material's own colour and texture still show.

## 5. Change it from a script

```beef
[Component]
class Alarm : Component
{
    public override void Update()
    {
        let renderer = GetComponent<MeshRenderer>();
        // Faster and redder while Space is held. This object gets its own copy of the material.
        let alarmed = Input.GetKey(.Space);
        renderer.SetMaterialFloat("speed", alarmed ? 12 : 2);
        renderer.SetMaterialColor("glow", alarmed ? .(1, 0.1f, 0.1f, 1) : .(0.2f, 0.8f, 1, 1));
    }
}
```

In a network session, when this runs on the server or on the owner's machine, everyone sees it.

In a graph, the same calls are under **Engine > Render > Mesh Renderer**.

## 6. A compute effect

1. Add a cube and scale it into a flat screen.
2. Give it `Materials/screen.tmat` (an unlit material), or make an unlit one.
3. Choose **+ > Compute Shader**, name it `Ripple`, and keep the example it starts with.
4. On the cube choose **Add Component > Compute Effect** and set **Shader** to `Shaders/Ripple.tcompute`.

A ring grows from the middle of the screen and fades behind itself. The fading is `result * 0.96`: `result` starts as what the pixel held on the previous step, so the image accumulates. Reading other places with `previous(uv + offset)` is how blurs, ripples and cellular automata are made.

Try changing the code to:

```glsl
compute {
    // Drift everything upward and feed new colour in at the bottom.
    result = previous(uv - vec2(0.0, 0.01)) * 0.985;
    if (uv.y < 0.03) {
        result = ink * (0.6 + 0.4 * sin(uv.x * 40.0 + time * 6.0 * speed));
    }
    result.a = 1.0;
}
```

Save, and the screen becomes rising flames of whatever colour **ink** is.

## What is not there

No environment maps (metals reflect the sky and ground colours), and shadows do not follow a shader's vertex movement. The [Materials page](../docs.php?page=materials) has the full list.
