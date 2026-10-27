using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// A grid of baked light probes (docs/baked-lighting.md): at each point, the light arriving from every direction (the
/// sky and what it bounced off), kept as a constant plus a direction for each of red, green and blue (spherical
/// harmonics to the first band, already scaled for diffuse lighting): the ambient light for a normal n is
/// `max(a + dot(b, n), 0)`. Moving things and surfaces without a lightmap read it per pixel, blended between the
/// eight probes round them.
class LightProbeGrid
{
	public const int Coefficients = 12;
	/// The first and last probes' positions; probes are evenly spaced between them.
	public Vector3 min, max;
	public int32 countX = 1, countY = 1, countZ = 1;
	/// Coefficients for each probe, x fastest then y then z: red a, bx, by, bz, then green, then blue.
	public List<float> values = new .() ~ delete _;

	bgfx.TextureHandle mTexture = .() { idx = uint16.MaxValue };

	public ~this()
	{
		if (mTexture.Valid && Gfx.Initialized)
			bgfx.destroy_texture(mTexture);
	}

	public int32 Count => countX * countY * countZ;
	public int Index(int x, int y, int z) => (z * countY + y) * countX + x;

	public Vector3 Position(int x, int y, int z)
	{
		Vector3 t = .(countX > 1 ? (float)x / (countX - 1) : 0.5f, countY > 1 ? (float)y / (countY - 1) : 0.5f, countZ > 1 ? (float)z / (countZ - 1) : 0.5f);
		return .(min.x + (max.x - min.x) * t.x, min.y + (max.y - min.y) * t.y, min.z + (max.z - min.z) * t.z);
	}

	/// The ambient light at a point for a surface facing `normal`, blended between the probes round it (as the
	/// shader does).
	public Vector3 Sample(Vector3 position, Vector3 normal)
	{
		float[Coefficients] blended = default;
		float Cell(float p, float lo, float hi, int count, out int first)
		{
			if (count <= 1)
			{
				first = 0;
				return 0;
			}
			let t = Math.Clamp((p - lo) / Math.Max(hi - lo, 1e-6f), 0, 1) * (count - 1);
			first = Math.Min((int)t, count - 2);
			return t - first;
		}
		let fx = Cell(position.x, min.x, max.x, countX, let x0);
		let fy = Cell(position.y, min.y, max.y, countY, let y0);
		let fz = Cell(position.z, min.z, max.z, countZ, let z0);
		for (int corner < 8)
		{
			let dx = corner & 1, dy = (corner >> 1) & 1, dz = (corner >> 2) & 1;
			let x = Math.Min(x0 + dx, countX - 1), y = Math.Min(y0 + dy, countY - 1), z = Math.Min(z0 + dz, countZ - 1);
			let weight = (dx == 1 ? fx : 1 - fx) * (dy == 1 ? fy : 1 - fy) * (dz == 1 ? fz : 1 - fz);
			if (weight <= 0)
				continue;
			let start = Index(x, y, z) * Coefficients;
			for (int i < Coefficients)
				blended[i] += values[start + i] * weight;
		}
		return .(Math.Max(blended[0] + blended[1] * normal.x + blended[2] * normal.y + blended[3] * normal.z, 0),
			Math.Max(blended[4] + blended[5] * normal.x + blended[6] * normal.y + blended[7] * normal.z, 0),
			Math.Max(blended[8] + blended[9] * normal.x + blended[10] * normal.y + blended[11] * normal.z, 0));
	}

	/// The `.tprobes` file: a header, then one line of twelve numbers for each probe.
	public void Write(String output)
	{
		output.Append("tprobes 1\n");
		output.AppendF("min {} {} {}\n", min.x, min.y, min.z);
		output.AppendF("max {} {} {}\n", max.x, max.y, max.z);
		output.AppendF("count {} {} {}\n", countX, countY, countZ);
		for (int p < Count)
		{
			for (int i < Coefficients)
				output.AppendF(i == 0 ? "{0:0.#####}" : " {0:0.#####}", values[p * Coefficients + i]);
			output.Append('\n');
		}
	}

	static float Number(StringView text) => float.Parse(text) case .Ok(let value) ? value : 0;

	public bool Parse(StringView text)
	{
		values.Clear();
		var header = true;
		for (var line in text.Split('\n'))
		{
			line.Trim();
			if (line.IsEmpty)
				continue;
			let parts = scope List<StringView>(line.Split(' ', .RemoveEmptyEntries));
			if (header)
			{
				switch (parts[0])
				{
				case "tprobes":
					continue;
				case "min","max","count":
					if (parts.Count < 4)
						return false;
					float[3] v = default;
					for (int i < 3)
						v[i] = Number(parts[i + 1]);
					if (parts[0] == "min")
						min = .(v[0], v[1], v[2]);
					else if (parts[0] == "max")
						max = .(v[0], v[1], v[2]);
					else
					{
						countX = Math.Max((int32)v[0], 1);
						countY = Math.Max((int32)v[1], 1);
						countZ = Math.Max((int32)v[2], 1);
					}
					continue;
				default:
					header = false;
				}
			}
			if (parts.Count != Coefficients)
				return false;
			for (let part in parts)
				values.Add(Number(part));
		}
		return values.Count == Count * Coefficients;
	}

	/// The grid as a 3D texture for the shader: countX by countY by three blocks of countZ (red, green, blue).
	public bgfx.TextureHandle Texture
	{
		get
		{
			if (!mTexture.Valid && Gfx.Initialized && Count > 0)
			{
				let texels = Count * 3;
				let data = bgfx.alloc((uint32)(texels * 8));
				let halves = (uint16*)data.data;
				for (int channel < 3)
				{
					for (int z < countZ)
					{
						for (int y < countY)
						{
							for (int x < countX)
							{
								let source = Index(x, y, z) * Coefficients + channel * 4;
								let target = (((channel * countZ + z) * countY + y) * countX + x) * 4;
								for (int i < 4)
									halves[target + i] = Half(values[source + i]);
							}
						}
					}
				}
				mTexture = bgfx.create_texture_3d((uint16)countX, (uint16)countY, (uint16)(countZ * 3), false, .RGBA16F, Gfx.SamplerClamp, data, 0);
			}
			return mTexture;
		}
	}

	/// A float as a 16-bit float (rounded to nearest).
	public static uint16 Half(float value)
	{
		var value;
		let bits = *(uint32*)&value;
		let sign = (uint16)((bits >> 16) & 0x8000);
		let exponent = (int32)((bits >> 23) & 0xff) - 127 + 15;
		var mantissa = bits & 0x7fffff;
		if (exponent <= 0)
		{
			if (exponent < -10)
				return sign;
			mantissa |= 0x800000;
			int32 shiftBy = 14 - exponent;
			let shift = (uint32)shiftBy;
			return sign | (uint16)((mantissa + (1u << (shift - 1))) >> shift);
		}
		if (exponent >= 31)
			return sign | 0x7bff;
		let rounded = ((uint32)exponent << 10 | (mantissa >> 13)) + ((mantissa >> 12) & 1);
		return sign | (uint16)Math.Min(rounded, 0x7bffu);
	}
}

/// The light probe grids scenes use (SceneEnvironment.lightProbes), loaded once each, and binding them for drawing.
static class LightProbes
{
	static Dictionary<String, LightProbeGrid> sGrids = new .() ~
		{
			for (let pair in _)
			{
				delete pair.key;
				delete pair.value;
			}
			delete _;
		};
	static bgfx.TextureHandle sEmpty = .() { idx = uint16.MaxValue };

	/// The grid in a `.tprobes` file (null if there is none, or it cannot be read).
	public static LightProbeGrid Get(StringView path)
	{
		if (path.IsEmpty)
			return null;
		if (sGrids.TryGetValueAlt(path, let found))
			return found;
		LightProbeGrid grid = new .();
		let text = scope String();
		if (!Assets.ReadText(path, text) || !grid.Parse(text))
			DeleteAndNullify!(grid);
		sGrids[new String(path)] = grid;
		return grid;
	}

	/// Reads a grid's file again next time (after baking).
	public static void Forget(StringView path)
	{
		if (sGrids.GetAndRemoveAlt(path) case .Ok(let pair))
		{
			delete pair.key;
			delete pair.value;
		}
	}

	/// Sets the shader's probe grid for the next draw (none: the ambient colours).
	public static void Bind(LightProbeGrid grid)
	{
		bgfx.TextureHandle texture = grid != null ? grid.Texture : .() { idx = uint16.MaxValue };
		Vector4 lo = default, scale = default, count = default;
		if (grid != null && texture.Valid)
		{
			let size = grid.max - grid.min;
			lo = .(grid.min, 1);
			scale = .(size.x > 1e-6f ? 1 / size.x : 0, size.y > 1e-6f ? 1 / size.y : 0, size.z > 1e-6f ? 1 / size.z : 0, 0);
			count = .(grid.countX, grid.countY, grid.countZ, 0);
		}
		else
		{
			if (!sEmpty.Valid)
			{
				uint16[4] zero = default;
				sEmpty = bgfx.create_texture_3d(1, 1, 1, false, .RGBA16F, Gfx.SamplerClamp, bgfx.copy(&zero, 8), 0);
			}
			texture = sEmpty;
		}
		bgfx.set_uniform(RenderResources.uLightProbeMin, &lo, 1);
		bgfx.set_uniform(RenderResources.uLightProbeScale, &scale, 1);
		bgfx.set_uniform(RenderResources.uLightProbeCount, &count, 1);
		bgfx.set_texture(12, RenderResources.sLightProbes, texture, uint32.MaxValue);
	}

	public static void Release()
	{
		for (let pair in sGrids)
		{
			delete pair.key;
			delete pair.value;
		}
		sGrids.Clear();
		if (sEmpty.Valid && Gfx.Initialized)
			bgfx.destroy_texture(sEmpty);
		sEmpty.idx = uint16.MaxValue;
	}
}
