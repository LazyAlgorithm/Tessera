using System;
using System.Collections;
using Bgfx;

namespace Tessera;

[Reflect(.All)]
enum LightType : int32
{
	Directional,
	Point,
	Spot
}

/// Directional, point or spot light. The first enabled directional light is the sun and casts cascaded shadows.
[Component]
class Light : Component
{
	public LightType type = .Directional;
	public Color color = .(1.0f, 0.96f, 0.88f);
	public float intensity = 1.0f;
	public float range = 10.0f;
    /// Physical inverse-square distance attenuation; intensity is then measured per square metre.
    public bool inverseSquare = false;
    /// Baked diffuse already supplies this light on surfaces with a lightmap.
    public bool bakedOnly = false;
    public int32 shadowMaskChannel = -1;
    /// Negative keeps the engine default, 80% of Spot Angle.
    public float innerSpotAngle = -1;
	[Range(1, 170)]
	public float spotAngle = 45.0f;
	public bool castShadows = true;
	[Range(0, 1)]
	public float shadowStrength = 1.0f;

	public override void OnRegister() => Scene.Lights.Add(this);
	public override void OnUnregister() => Scene.Lights.Remove(this);

	public override void OnDrawGizmos(bool selected)
	{
		let position = Transform.Position;
		let tint = Color(color.r, color.g, color.b, 1);
		switch (type)
		{
		case .Directional:
			let forward = Transform.Forward;
			let right = Transform.Right * 0.3f;
			let up = Transform.Up * 0.3f;
			Gizmos.Lines.Line(position, position + forward * 1.5f, tint);
			Gizmos.Lines.Line(position + right, position + right + forward * 1.2f, tint);
			Gizmos.Lines.Line(position - right, position - right + forward * 1.2f, tint);
			Gizmos.Lines.Line(position + up, position + up + forward * 1.2f, tint);
			Gizmos.Lines.Line(position - up, position - up + forward * 1.2f, tint);
		case .Point:
			Gizmos.Lines.Sphere(position, selected ? range : 0.25f, tint);
		case .Spot:
			let forward = Transform.Forward;
			let radius = Math.Tan(spotAngle * 0.5f * Mathf.Deg2Rad) * range;
			let end = position + forward * range;
			Gizmos.Lines.Circle(end, forward, radius, tint);
			Gizmos.Lines.Line(position, end + Transform.Right * radius, tint);
			Gizmos.Lines.Line(position, end - Transform.Right * radius, tint);
			Gizmos.Lines.Line(position, end + Transform.Up * radius, tint);
			Gizmos.Lines.Line(position, end - Transform.Up * radius, tint);
		}
	}
}
