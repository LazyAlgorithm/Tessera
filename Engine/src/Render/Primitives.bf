using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Built-in primitive meshes, all centred on the origin with unit size.
static class Primitives
{
	public static Mesh CreateCube()
	{
		let mesh = new Mesh();
		mesh.Name.Set("Cube");
		let h = 0.5f;
		let c = Color.White;
		mesh.AddQuad(.(-h, -h, -h), .(-h, h, -h), .(h, h, -h), .(h, -h, -h), c); // back (-Z)
		mesh.AddQuad(.(h, -h, h), .(h, h, h), .(-h, h, h), .(-h, -h, h), c); // front (+Z)
		mesh.AddQuad(.(-h, -h, h), .(-h, h, h), .(-h, h, -h), .(-h, -h, -h), c); // left
		mesh.AddQuad(.(h, -h, -h), .(h, h, -h), .(h, h, h), .(h, -h, h), c); // right
		mesh.AddQuad(.(-h, h, -h), .(-h, h, h), .(h, h, h), .(h, h, -h), c); // top
		mesh.AddQuad(.(-h, -h, h), .(-h, -h, -h), .(h, -h, -h), .(h, -h, h), c); // bottom
		mesh.Upload();
		return mesh;
	}

	/// 10x10 unit plane facing +Y, like Unity's built-in plane.
	public static Mesh CreatePlane()
	{
		let mesh = new Mesh();
		mesh.Name.Set("Plane");
		let h = 5.0f;
		mesh.AddQuad(.(-h, 0, -h), .(-h, 0, h), .(h, 0, h), .(h, 0, -h), .White);
		mesh.Upload();
		return mesh;
	}

	public static Mesh CreateQuad()
	{
		let mesh = new Mesh();
		mesh.Name.Set("Quad");
		let h = 0.5f;
		mesh.AddQuad(.(-h, -h, 0), .(-h, h, 0), .(h, h, 0), .(h, -h, 0), .White);
		mesh.Upload();
		return mesh;
	}

	/// Low-poly UV sphere of diameter 1.
	public static Mesh CreateSphere(int segments = 16, int rings = 10)
	{
		let mesh = new Mesh();
		mesh.Name.Set("Sphere");
		for (int r = 0; r <= rings; r++)
		{
			let v = (float)r / rings;
			let phi = v * Mathf.PI;
			for (int s = 0; s <= segments; s++)
			{
				let u = (float)s / segments;
				let theta = u * Mathf.PI * 2.0f;
				let n = Vector3(Math.Sin(phi) * Math.Cos(theta), Math.Cos(phi), Math.Sin(phi) * Math.Sin(theta));
				mesh.AddVertex(n * 0.5f, n, .White, .(u, v));
			}
		}
		let stride = (uint32)segments + 1;
		for (uint32 r = 0; r < (uint32)rings; r++)
		{
			for (uint32 s = 0; s < (uint32)segments; s++)
			{
				let a = r * stride + s;
				let b = a + stride;
				mesh.AddTriangle(a, a + 1, b);
				mesh.AddTriangle(a + 1, b + 1, b);
			}
		}
		mesh.Upload();
		return mesh;
	}

	/// Cylinder of diameter 1 and height 2 (Unity proportions). topRadius 0 makes a cone.
	public static Mesh CreateCylinder(int segments = 16, float topRadius = 0.5f)
	{
		let mesh = new Mesh();
		mesh.Name.Set(topRadius > 0 ? "Cylinder" : "Cone");
		let bottomRadius = 0.5f;
		let slope = (bottomRadius - topRadius) / 2.0f;
		for (int s = 0; s <= segments; s++)
		{
			let u = (float)s / segments;
			let theta = u * Mathf.PI * 2.0f;
			let dir = Vector3(Math.Cos(theta), 0, Math.Sin(theta));
			let n = Vector3(dir.x, slope, dir.z).Normalized;
			mesh.AddVertex(.(dir.x * bottomRadius, -1, dir.z * bottomRadius), n, .White, .(u, 1));
			mesh.AddVertex(.(dir.x * topRadius, 1, dir.z * topRadius), n, .White, .(u, 0));
		}
		for (uint32 s = 0; s < (uint32)segments; s++)
		{
			let a = s * 2;
			mesh.AddTriangle(a, a + 1, a + 2);
			mesh.AddTriangle(a + 1, a + 3, a + 2);
		}
		AddCap(mesh, segments, -1, bottomRadius, false);
		if (topRadius > 0)
			AddCap(mesh, segments, 1, topRadius, true);
		mesh.Upload();
		return mesh;
	}

	static void AddCap(Mesh mesh, int segments, float y, float radius, bool top)
	{
		let n = Vector3(0, top ? 1 : -1, 0);
		let center = mesh.AddVertex(.(0, y, 0), n, .White, .(0.5f, 0.5f));
		for (int s = 0; s <= segments; s++)
		{
			let theta = (float)s / segments * Mathf.PI * 2.0f;
			mesh.AddVertex(.(Math.Cos(theta) * radius, y, Math.Sin(theta) * radius), n, .White, .(0.5f, 0.5f));
		}
		for (uint32 s = 0; s < (uint32)segments; s++)
		{
			if (top)
				mesh.AddTriangle(center, center + 2 + s, center + 1 + s);
			else
				mesh.AddTriangle(center, center + 1 + s, center + 2 + s);
		}
	}

	/// Capsule of diameter 1 and total height 2.
	public static Mesh CreateCapsule(int segments = 16, int rings = 6)
	{
		let mesh = new Mesh();
		mesh.Name.Set("Capsule");
		let radius = 0.5f;
		let halfHeight = 0.5f;
		let total = rings * 2 + 1;
		for (int r = 0; r <= total; r++)
		{
			// The top hemisphere uses the first rings + 1 rows, the bottom the rest.
			let upper = r <= rings;
			let ringIndex = upper ? r : r - 1;
			let phi = (float)ringIndex / (rings * 2) * Mathf.PI;
			let offset = upper ? halfHeight : -halfHeight;
			for (int s = 0; s <= segments; s++)
			{
				let u = (float)s / segments;
				let theta = u * Mathf.PI * 2.0f;
				let n = Vector3(Math.Sin(phi) * Math.Cos(theta), Math.Cos(phi), Math.Sin(phi) * Math.Sin(theta));
				mesh.AddVertex(n * radius + Vector3(0, offset, 0), n, .White, .(u, (float)r / total));
			}
		}
		let stride = (uint32)segments + 1;
		for (uint32 r = 0; r < (uint32)total; r++)
		{
			for (uint32 s = 0; s < (uint32)segments; s++)
			{
				let a = r * stride + s;
				let b = a + stride;
				mesh.AddTriangle(a, a + 1, b);
				mesh.AddTriangle(a + 1, b + 1, b);
			}
		}
		mesh.Upload();
		return mesh;
	}
}
