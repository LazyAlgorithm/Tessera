using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Triangle mesh with CPU-side data and a GPU copy. Front faces wind clockwise (left-handed).
class Mesh
{
	public String Name = new .() ~ delete _;
	public List<MeshVertex> Vertices = new .() ~ delete _;
	public List<uint32> Indices = new .() ~ delete _;
	public Bounds Bounds = .(.Zero, .Zero);

	bgfx.VertexBufferHandle mVertexBuffer = .() { idx = uint16.MaxValue };
	bgfx.IndexBufferHandle mIndexBuffer = .() { idx = uint16.MaxValue };
	int32 mUploadedIndexCount;
	int32 mUploadedVertexCount;
	bgfx.DynamicVertexBufferHandle mDynamicBuffer = .() { idx = uint16.MaxValue };

	/// True for meshes whose vertices are rewritten every frame (skinned characters).
	public bool IsDynamic => mDynamicBuffer.Valid;
	public bgfx.DynamicVertexBufferHandle DynamicBuffer => mDynamicBuffer;

	/// Creates GPU buffers that UpdateDynamic can refill. The vertex count must stay the same afterwards.
	public void UploadDynamic()
	{
		ReleaseGpu();
		RecalculateBounds();
		if (Vertices.Count == 0 || Indices.Count == 0 || !Gfx.Initialized)
			return;
		mDynamicBuffer = bgfx.create_dynamic_vertex_buffer((uint32)Vertices.Count, &Gfx.MeshLayout, 0);
		bgfx.update_dynamic_vertex_buffer(mDynamicBuffer, 0, bgfx.copy(Vertices.Ptr, (uint32)(Vertices.Count * sizeof(MeshVertex))));
		mIndexBuffer = bgfx.create_index_buffer(bgfx.copy(Indices.Ptr, (uint32)(Indices.Count * 4)), 0x1000);
		mUploadedIndexCount = (int32)Indices.Count;
		mUploadedVertexCount = (int32)Vertices.Count;
	}

	/// Sends the current vertex list to the GPU again.
	public void UpdateDynamic()
	{
		if (mDynamicBuffer.Valid && Vertices.Count == mUploadedVertexCount)
			bgfx.update_dynamic_vertex_buffer(mDynamicBuffer, 0, bgfx.copy(Vertices.Ptr, (uint32)(Vertices.Count * sizeof(MeshVertex))));
	}

	public ~this()
	{
		ReleaseGpu();
	}

	public bool HasGpuData => (mVertexBuffer.Valid || mDynamicBuffer.Valid) && mIndexBuffer.Valid;
	public bgfx.VertexBufferHandle VertexBuffer => mVertexBuffer;
	public bgfx.IndexBufferHandle IndexBuffer => mIndexBuffer;
	public int32 IndexCount => mUploadedIndexCount;
	public int32 VertexCount => mUploadedVertexCount;

	public void Clear()
	{
		Vertices.Clear();
		Indices.Clear();
	}

	public uint32 AddVertex(Vector3 position, Vector3 normal, Color color, Vector2 uv = default)
	{
		Vertices.Add(.(position, normal, color.ToABGR(), uv));
		return (uint32)Vertices.Count - 1;
	}

	public void AddTriangle(uint32 a, uint32 b, uint32 c)
	{
		Indices.Add(a);
		Indices.Add(b);
		Indices.Add(c);
	}

	/// Adds a quad from four corners given clockwise when seen from the front.
	public void AddQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color color)
	{
		let normal = Vector3.Cross(b - a, c - a).Normalized;
		let i = AddVertex(a, normal, color, .(0, 0));
		AddVertex(b, normal, color, .(1, 0));
		AddVertex(c, normal, color, .(1, 1));
		AddVertex(d, normal, color, .(0, 1));
		AddTriangle(i, i + 1, i + 2);
		AddTriangle(i, i + 2, i + 3);
	}

	public void RecalculateBounds()
	{
		if (Vertices.Count == 0)
		{
			Bounds = .(.Zero, .Zero);
			return;
		}
		var bounds = Tessera.Bounds.Empty;
		for (let v in Vertices)
			bounds.Encapsulate(v.position);
		Bounds = bounds;
	}

	/// Smooth normals from face normals weighted by area.
	public void RecalculateNormals()
	{
		for (var v in ref Vertices)
			v.normal = .Zero;
		for (int i = 0; i + 2 < Indices.Count; i += 3)
		{
			let a = (int)Indices[i], b = (int)Indices[i + 1], c = (int)Indices[i + 2];
			let n = Vector3.Cross(Vertices[b].position - Vertices[a].position, Vertices[c].position - Vertices[a].position);
			Vertices[a].normal = Vertices[a].normal + n;
			Vertices[b].normal = Vertices[b].normal + n;
			Vertices[c].normal = Vertices[c].normal + n;
		}
		for (var v in ref Vertices)
			v.normal = v.normal.Normalized;
	}

	/// Sends the current vertex and index lists to the GPU, replacing any previous copy.
	public void Upload(bool keepCpuData = true)
	{
		ReleaseGpu();
		RecalculateBounds();
		if (Vertices.Count == 0 || Indices.Count == 0 || !Gfx.Initialized)
			return;
		mVertexBuffer = bgfx.create_vertex_buffer(bgfx.copy(Vertices.Ptr, (uint32)(Vertices.Count * sizeof(MeshVertex))), &Gfx.MeshLayout, 0);
		mIndexBuffer = bgfx.create_index_buffer(bgfx.copy(Indices.Ptr, (uint32)(Indices.Count * 4)), 0x1000);
		mUploadedIndexCount = (int32)Indices.Count;
		mUploadedVertexCount = (int32)Vertices.Count;
		if (!keepCpuData)
		{
			Vertices.Clear();
			Vertices.Capacity = 0;
			Indices.Clear();
			Indices.Capacity = 0;
		}
	}

	public void ReleaseGpu()
	{
		if (!Gfx.Initialized)
			return;
		if (mVertexBuffer.Valid)
			bgfx.destroy_vertex_buffer(mVertexBuffer);
		if (mIndexBuffer.Valid)
			bgfx.destroy_index_buffer(mIndexBuffer);
		if (mDynamicBuffer.Valid)
			bgfx.destroy_dynamic_vertex_buffer(mDynamicBuffer);
		mDynamicBuffer.idx = uint16.MaxValue;
		mVertexBuffer.idx = uint16.MaxValue;
		mIndexBuffer.idx = uint16.MaxValue;
		mUploadedIndexCount = 0;
		mUploadedVertexCount = 0;
	}

	/// Ray test against the CPU triangles in mesh space. Returns the distance or a negative value.
	public float Raycast(Ray ray)
	{
		float best = -1.0f;
		for (int i = 0; i + 2 < Indices.Count; i += 3)
		{
			let a = Vertices[(int)Indices[i]].position;
			let b = Vertices[(int)Indices[i + 1]].position;
			let c = Vertices[(int)Indices[i + 2]].position;
			let e1 = b - a;
			let e2 = c - a;
			let p = Vector3.Cross(ray.direction, e2);
			let det = Vector3.Dot(e1, p);
			if (Mathf.Abs(det) < 1.0e-9f)
				continue;
			let inv = 1.0f / det;
			let s = ray.origin - a;
			let u = Vector3.Dot(s, p) * inv;
			if (u < 0 || u > 1)
				continue;
			let q = Vector3.Cross(s, e1);
			let v = Vector3.Dot(ray.direction, q) * inv;
			if (v < 0 || u + v > 1)
				continue;
			let t = Vector3.Dot(e2, q) * inv;
			if (t > 1.0e-5f && (best < 0 || t < best))
				best = t;
		}
		return best;
	}
}
