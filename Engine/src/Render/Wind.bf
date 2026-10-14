using System;
using System.Collections;

namespace Tessera;

[Reflect(.All)]
enum WindShape : int32
{
	/// Blows over the whole scene.
	Global,
	/// Blows inside a sphere round the object, strongest in the middle and fading to nothing at Radius.
	Sphere
}

/// Wind. It blows the way the object faces (its blue arrow), and bends everything set to sway: Foliage, and any Mesh
/// Renderer with Wind Sway above 0. A Global zone covers the whole scene; a Sphere zone adds its wind inside a
/// radius, for a gusty valley, a fan, a helicopter's downdraught or the blast of something passing. Zones add up.
///
/// The bending is done on the graphics card, so it costs the same for one plant as for fifty thousand. The four
/// Sphere zones nearest the camera take part; Global zones always do. Wind is the same on every machine if the zones
/// are (zones in a scene are; one moved by a script moves on other machines if its object is shared).
[Component]
class WindZone : Component
{
	public WindShape shape = .Global;
	/// How hard it blows: 0 still air, 1 a breeze, 3 a strong wind, 6 a gale.
	public float strength = 1;
	/// How much the wind comes and goes: 0 steady, 1 in gusts. The gustiest Global zone sets it for the scene.
	[Range(0, 1)]
	public float gusts = 0.5f;
	/// How far a Sphere zone reaches.
	public float radius = 10;

	static List<WindZone> sAll = new .() ~ delete _;

	public override void OnRegister() => sAll.Add(this);
	public override void OnUnregister() => sAll.Remove(this);

	/// The wind this zone makes at a point (nothing outside a Sphere zone's reach).
	public Vector3 WindAt(Vector3 position)
	{
		let wind = Transform.Forward * strength;
		if (shape == .Global)
			return wind;
		let reach = Math.Max(radius * Math.Max(Math.Max(Transform.LocalScale.x, Transform.LocalScale.y), Transform.LocalScale.z), 0.0001f);
		return wind * Mathf.Clamp01(1 - (position - Transform.Position).Length / reach);
	}

	public override void OnDrawGizmos(bool selected)
	{
		let from = Transform.Position;
		let color = Color(0.55f, 0.85f, 1.0f, selected ? 1.0f : 0.5f);
		let forward = Transform.Forward, right = Transform.Right;
		let length = 1.0f + Math.Min(strength, 6) * 0.4f;
		let tip = from + forward * length;
		DebugDraw.Line(from, tip, color);
		DebugDraw.Line(tip, tip - forward * 0.3f + right * 0.15f, color);
		DebugDraw.Line(tip, tip - forward * 0.3f - right * 0.15f, color);
		if (shape == .Sphere && selected)
			DebugDraw.Sphere(from, radius, color);
	}

	public static List<WindZone> All => sAll;
}

/// Reading the wind from code, for anything that should drift with it: smoke, a sail, a paper bag.
static class Wind
{
	/// The wind at a point of a scene, every zone added up: a direction whose length is the strength.
	public static Vector3 At(Scene scene, Vector3 position)
	{
		var wind = Vector3.Zero;
		for (let zone in WindZone.All)
		{
			if (zone.GameObject == null || zone.GameObject.IsDestroyed || zone.Scene != scene || !zone.IsActiveAndEnabled)
				continue;
			wind = wind + zone.WindAt(position);
		}
		return wind;
	}

	/// What the renderer hands the graphics card: the scene's global wind (w: gustiness) and the four Sphere zones
	/// nearest a point (xyz centre, w reach; and their wind).
	public static void Gather(Scene scene, Vector3 near, out Vector4 global, ref Vector4[4] zones, ref Vector4[4] push)
	{
		var wind = Vector3.Zero;
		float gusts = 0;
		float[4] distance = .(float.MaxValue, float.MaxValue, float.MaxValue, float.MaxValue);
		for (int i < 4)
		{
			zones[i] = default;
			push[i] = default;
		}
		for (let zone in WindZone.All)
		{
			if (zone.GameObject == null || zone.GameObject.IsDestroyed || zone.Scene != scene || !zone.IsActiveAndEnabled)
				continue;
			let blowing = zone.Transform.Forward * zone.strength;
			if (zone.shape == .Global)
			{
				wind = wind + blowing;
				gusts = Math.Max(gusts, zone.gusts);
				continue;
			}
			let scale = zone.Transform.LocalScale;
			let reach = zone.radius * Math.Max(Math.Max(scale.x, scale.y), scale.z);
			if (reach <= 0)
				continue;
			// Kept in order of how near the camera each is; the furthest of five falls off the end.
			let away = Math.Max((zone.Transform.Position - near).Length - reach, 0);
			for (int slot < 4)
			{
				if (away >= distance[slot])
					continue;
				for (int move = 3; move > slot; move--)
				{
					distance[move] = distance[move - 1];
					zones[move] = zones[move - 1];
					push[move] = push[move - 1];
				}
				distance[slot] = away;
				let at = zone.Transform.Position;
				zones[slot] = .(at.x, at.y, at.z, reach);
				push[slot] = .(blowing.x, blowing.y, blowing.z, 0);
				break;
			}
		}
		global = .(wind.x, wind.y, wind.z, gusts);
	}
}
