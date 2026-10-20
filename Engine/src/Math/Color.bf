using System;

namespace Tessera;

/// Linear RGBA color with float channels.
[CRepr]
struct Color
{
	public float r;
	public float g;
	public float b;
	public float a;

	public this()
	{
		r = 1;
		g = 1;
		b = 1;
		a = 1;
	}

	public this(float r, float g, float b, float a = 1.0f)
	{
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
	}

	public static Color White => .(1, 1, 1, 1);
	public static Color Black => .(0, 0, 0, 1);
	public static Color Red => .(1, 0, 0, 1);
	public static Color Green => .(0, 1, 0, 1);
	public static Color Blue => .(0, 0, 1, 1);
	public static Color Yellow => .(1, 0.92f, 0.016f, 1);
	public static Color Gray => .(0.5f, 0.5f, 0.5f, 1);
	/// Fully see-through black.
	public static Color Clear => .(0, 0, 0, 0);

	/// The colour's red, green and blue times a number (alpha is kept).
	public static Color operator *(Color c, float s) => .(c.r * s, c.g * s, c.b * s, c.a);
	/// The colour a fraction t of the way from a to b.
	public static Color Lerp(Color a, Color b, float t) =>
		.(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);

	/// Builds a color from 0..255 sRGB-style bytes, e.g. Color.FromBytes(204, 96, 48).
	public static Color FromBytes(uint8 r, uint8 g, uint8 b, uint8 a = 255) =>
		.(r / 255.0f, g / 255.0f, b / 255.0f, a / 255.0f);

	/// Packs to the 0xAABBGGRR layout bgfx uses for normalized uint8 vertex colors.
	public uint32 ToABGR()
	{
		let rr = (uint32)(Mathf.Clamp01(r) * 255.0f + 0.5f);
		let gg = (uint32)(Mathf.Clamp01(g) * 255.0f + 0.5f);
		let bb = (uint32)(Mathf.Clamp01(b) * 255.0f + 0.5f);
		let aa = (uint32)(Mathf.Clamp01(a) * 255.0f + 0.5f);
		return (aa << 24) | (bb << 16) | (gg << 8) | rr;
	}

	/// Packs to 0xRRGGBBAA, the layout bgfx view clears expect.
	public uint32 ToRGBA()
	{
		let rr = (uint32)(Mathf.Clamp01(r) * 255.0f + 0.5f);
		let gg = (uint32)(Mathf.Clamp01(g) * 255.0f + 0.5f);
		let bb = (uint32)(Mathf.Clamp01(b) * 255.0f + 0.5f);
		let aa = (uint32)(Mathf.Clamp01(a) * 255.0f + 0.5f);
		return (rr << 24) | (gg << 16) | (bb << 8) | aa;
	}
}
