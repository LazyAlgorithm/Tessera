using System;

namespace Tessera;

[CRepr]
struct Vector2
{
	public float x;
	public float y;

	public this() { x = 0; y = 0; }
	public this(float x, float y) { this.x = x; this.y = y; }

	public static Vector2 Zero => .(0, 0);
	public static Vector2 One => .(1, 1);

	public float Length => Math.Sqrt(x * x + y * y);
	public float LengthSquared => x * x + y * y;
	public Vector2 Normalized
	{
		get
		{
			let length = Length;
			return length > 1.0e-6f ? Vector2(x / length, y / length) : Vector2(0, 0);
		}
	}
	public static float Dot(Vector2 a, Vector2 b) => a.x * b.x + a.y * b.y;
	public static bool operator ==(Vector2 a, Vector2 b) => a.x == b.x && a.y == b.y;
	public static bool operator !=(Vector2 a, Vector2 b) => a.x != b.x || a.y != b.y;

	public static Vector2 operator +(Vector2 a, Vector2 b) => .(a.x + b.x, a.y + b.y);
	public static Vector2 operator -(Vector2 a, Vector2 b) => .(a.x - b.x, a.y - b.y);
	public static Vector2 operator *(Vector2 a, float s) => .(a.x * s, a.y * s);
	public static Vector2 operator /(Vector2 a, float s) => .(a.x / s, a.y / s);
}

[CRepr]
struct Vector3
{
	public float x;
	public float y;
	public float z;

	public this() { x = 0; y = 0; z = 0; }
	public this(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
	public this(float v) { x = v; y = v; z = v; }

	public static Vector3 Zero => .(0, 0, 0);
	public static Vector3 One => .(1, 1, 1);
	public static Vector3 Up => .(0, 1, 0);
	public static Vector3 Down => .(0, -1, 0);
	public static Vector3 Right => .(1, 0, 0);
	public static Vector3 Left => .(-1, 0, 0);
	public static Vector3 Forward => .(0, 0, 1);
	public static Vector3 Back => .(0, 0, -1);

	public float LengthSquared => x * x + y * y + z * z;
	public float Length => Math.Sqrt(x * x + y * y + z * z);

	public Vector3 Normalized
	{
		get
		{
			let len = Length;
			if (len < 1.0e-12f)
				return .(0, 0, 0);
			let inv = 1.0f / len;
			return .(x * inv, y * inv, z * inv);
		}
	}

	public float this[int index]
	{
		get => index == 0 ? x : (index == 1 ? y : z);
		set mut
		{
			if (index == 0) x = value;
			else if (index == 1) y = value;
			else z = value;
		}
	}

	public static Vector3 operator +(Vector3 a, Vector3 b) => .(a.x + b.x, a.y + b.y, a.z + b.z);
	public static Vector3 operator -(Vector3 a, Vector3 b) => .(a.x - b.x, a.y - b.y, a.z - b.z);
	public static Vector3 operator -(Vector3 a) => .(-a.x, -a.y, -a.z);
	public static Vector3 operator *(Vector3 a, Vector3 b) => .(a.x * b.x, a.y * b.y, a.z * b.z);
	public static Vector3 operator /(Vector3 a, Vector3 b) => .(a.x / b.x, a.y / b.y, a.z / b.z);
	public static Vector3 operator *(Vector3 a, float s) => .(a.x * s, a.y * s, a.z * s);
	public static Vector3 operator *(float s, Vector3 a) => .(a.x * s, a.y * s, a.z * s);
	public static Vector3 operator /(Vector3 a, float s) => .(a.x / s, a.y / s, a.z / s);
	public static bool operator ==(Vector3 a, Vector3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
	public static bool operator !=(Vector3 a, Vector3 b) => a.x != b.x || a.y != b.y || a.z != b.z;

	[Inline] public static float Dot(Vector3 a, Vector3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

	[Inline] public static Vector3 Cross(Vector3 a, Vector3 b) =>
		.(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	public static float Distance(Vector3 a, Vector3 b) => (a - b).Length;
	public static Vector3 Lerp(Vector3 a, Vector3 b, float t) => a + (b - a) * t;
	public static Vector3 Min(Vector3 a, Vector3 b) => .(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Min(a.z, b.z));
	public static Vector3 Max(Vector3 a, Vector3 b) => .(Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y), Mathf.Max(a.z, b.z));
	public static Vector3 Abs(Vector3 a) => .(Mathf.Abs(a.x), Mathf.Abs(a.y), Mathf.Abs(a.z));

	public static Vector3 MoveTowards(Vector3 current, Vector3 target, float maxDelta)
	{
		let delta = target - current;
		let dist = delta.Length;
		if (dist <= maxDelta || dist < 1.0e-9f)
			return target;
		return current + delta * (maxDelta / dist);
	}

	public override void ToString(String str)
	{
		str.AppendF("({0:0.###}, {1:0.###}, {2:0.###})", x, y, z);
	}
}

[CRepr]
struct Vector4
{
	public float x;
	public float y;
	public float z;
	public float w;

	public this() { x = 0; y = 0; z = 0; w = 0; }
	public this(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
	public this(Vector3 v, float w) { x = v.x; y = v.y; z = v.z; this.w = w; }
	public static bool operator ==(Vector4 a, Vector4 b) => a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
	public static bool operator !=(Vector4 a, Vector4 b) => a.x != b.x || a.y != b.y || a.z != b.z || a.w != b.w;

	public Vector3 XYZ => .(x, y, z);
}

/// Integer lattice coordinate, used for voxel chunks and cells.
struct Int3 : IHashable
{
	public int32 x;
	public int32 y;
	public int32 z;

	public this(int32 x, int32 y, int32 z) { this.x = x; this.y = y; this.z = z; }

	public static Int3 operator +(Int3 a, Int3 b) => .(a.x + b.x, a.y + b.y, a.z + b.z);
	public static Int3 operator -(Int3 a, Int3 b) => .(a.x - b.x, a.y - b.y, a.z - b.z);
	public static bool operator ==(Int3 a, Int3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
	public static bool operator !=(Int3 a, Int3 b) => a.x != b.x || a.y != b.y || a.z != b.z;

	public int GetHashCode()
	{
		return (int)(((uint32)x * 73856093) ^ ((uint32)y * 19349663) ^ ((uint32)z * 83492791));
	}
}
