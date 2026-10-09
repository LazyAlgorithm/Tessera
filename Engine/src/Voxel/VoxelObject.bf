using System;
using System.Collections;

namespace Tessera;

[Reflect(.All)]
enum VoxelShape : int32
{
	Sphere,
	Box,
	Cylinder
}

/// A destructible object built from a small marching-cubes grid. Carve() removes material in
/// real time; pieces that are cut loose break off and fall as their own physics objects.
///
/// Collision: with a MeshCollider and no Rigidbody the object has exact (static) triangle
/// collision. Jolt cannot simulate moving triangle meshes, so pieces that break off collide
/// with a convex hull wrapped around their surface.
[Component]
class VoxelObject : Component
{
	public VoxelShape shape = .Sphere;
	/// Grid cells along each axis (8 to 48). Higher is smoother and slower to re-mesh.
	public int32 resolution = 24;
	/// Edge length of the grid in local units.
	public float size = 4.0f;
	public Color color = .FromBytes(150, 146, 140);
	/// Color of surfaces exposed by carving.
	public Color interiorColor = .FromBytes(96, 82, 70);
	/// Detach pieces that are no longer connected to the largest part (play mode only).
	public bool breakOffPieces = true;
	/// Loose pieces with fewer solid samples than this simply vanish.
	public int32 minimumPieceSize = 6;
	/// Anchored objects stay fixed in place (cliffs, walls) and only cut-off pieces fall.
	/// Otherwise the whole object becomes a physics body the first time it is carved.
	public bool anchored = false;

	int8[] mDensity ~ delete _;
	bool[] mCarved ~ delete _;
	Mesh mMesh ~ delete _;
	int32 mSamples;
	int32 mBuiltHash;
	bool mCustom;

	public bool IsEmpty => mMesh == null || mMesh.Indices.Count == 0;
	int Index(int x, int y, int z) => x + y * mSamples + z * mSamples * mSamples;
	float CellSize => size / (mSamples - 1);

	public override void OnRegister()
	{
		if (!mCustom)
			Fill();
		Rebuild();
	}

	public override void OnUnregister()
	{
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null && renderer.RuntimeMesh == mMesh)
			renderer.RuntimeMesh = null;
	}

	public override void OnValidate()
	{
		let hash = (int32)shape ^ resolution * 31 ^ (int32)(size * 1000) * 7 ^ (int32)color.ToABGR() * 3 ^ (int32)interiorColor.ToABGR() * 5;
		if (hash == mBuiltHash)
			return;
		if (!mCustom && (mDensity == null || (int32)shape ^ resolution * 31 ^ (int32)(size * 1000) * 7 != mShapeHash))
			Fill();
		Rebuild();
	}

	int32 mShapeHash;
	bool mAttachPending;
	/// Ids of the pieces that broke off this object, so a reset can clean them up.
	List<uint32> mPieces = new .() ~ delete _;

	/// Restores the untouched shape and removes every piece that broke off (and pieces of those pieces).
	public void ResetShape()
	{
		DestroyPieces();
		Fill();
		Rebuild();
	}

	void DestroyPieces()
	{
		for (let id in mPieces)
		{
			let piece = Scene.FindById(id);
			if (piece == null || piece.IsDestroyed)
				continue;
			piece.GetComponent<VoxelObject>()?.DestroyPieces();
			Scene.Destroy(piece);
		}
		mPieces.Clear();
	}

	public override void OnFrame()
	{
		if (!mAttachPending)
			return;
		mAttachPending = false;
		var renderer = GetComponent<MeshRenderer>();
		if (renderer == null)
		{
			renderer = GameObject.AddComponent<MeshRenderer>();
			renderer.roughness = 0.9f;
		}
		renderer.RuntimeMesh = mMesh;
		GetComponent<Collider>()?.Refresh();
	}

	/// Resets the grid to the untouched shape.
	public void Fill()
	{
		mSamples = Math.Max(8, Math.Min(resolution, 48)) + 1;
		delete mDensity;
		delete mCarved;
		let count = mSamples * mSamples * mSamples;
		mDensity = new int8[count];
		mCarved = new bool[count];
		mShapeHash = (int32)shape ^ resolution * 31 ^ (int32)(size * 1000) * 7;
		let half = (mSamples - 1) * 0.5f;
		// Leave a one-cell empty margin so the surface is closed on every side.
		let radius = half - 1.5f;
		for (int z < mSamples)
		{
			for (int y < mSamples)
			{
				for (int x < mSamples)
				{
					let p = Vector3(x - half, y - half, z - half);
					float d;
					switch (shape)
					{
					case .Sphere: d = radius - p.Length;
					case .Box: d = radius - Math.Max(Mathf.Abs(p.x), Math.Max(Mathf.Abs(p.y), Mathf.Abs(p.z)));
					case .Cylinder: d = Math.Min(radius - Math.Sqrt(p.x * p.x + p.z * p.z), radius - Mathf.Abs(p.y));
					}
					mDensity[Index(x, y, z)] = (int8)Mathf.Clamp(d * 32.0f, -127, 127);
				}
			}
		}
	}

	Vector3 Gradient(int x, int y, int z)
	{
		let x0 = Math.Max(x - 1, 0), x1 = Math.Min(x + 1, mSamples - 1);
		let y0 = Math.Max(y - 1, 0), y1 = Math.Min(y + 1, mSamples - 1);
		let z0 = Math.Max(z - 1, 0), z1 = Math.Min(z + 1, mSamples - 1);
		return .(
			(float)mDensity[Index(x0, y, z)] - mDensity[Index(x1, y, z)],
			(float)mDensity[Index(x, y0, z)] - mDensity[Index(x, y1, z)],
			(float)mDensity[Index(x, y, z0)] - mDensity[Index(x, y, z1)]);
	}

	/// Re-meshes the grid and refreshes the renderer and collider.
	public void Rebuild()
	{
		if (mDensity == null)
			return;
		mBuiltHash = (int32)shape ^ resolution * 31 ^ (int32)(size * 1000) * 7 ^ (int32)color.ToABGR() * 3 ^ (int32)interiorColor.ToABGR() * 5;
		if (mMesh == null)
			mMesh = new Mesh();
		mMesh.Clear();
		let cells = mSamples - 1;
		let cell = CellSize;
		let offset = Vector3(size * 0.5f);
		let outer = color.ToABGR();
		let inner = interiorColor.ToABGR();
		uint32[12] edgeVertex = default;
		for (int z < cells)
		{
			for (int y < cells)
			{
				for (int x < cells)
				{
					int config = 0;
					for (int c < 8)
					{
						if (mDensity[Index(x + MarchingTables.Corners[c * 3], y + MarchingTables.Corners[c * 3 + 1], z + MarchingTables.Corners[c * 3 + 2])] <= 0)
							config |= 1 << c;
					}
					let edgeMask = MarchingTables.Edges[config];
					if (edgeMask == 0)
						continue;
					for (int e < 12)
					{
						if ((edgeMask & (1 << e)) == 0)
							continue;
						let a = e & 7;
						let b = MarchingTables.EdgeEnd[e];
						let ax = x + MarchingTables.Corners[a * 3], ay = y + MarchingTables.Corners[a * 3 + 1], az = z + MarchingTables.Corners[a * 3 + 2];
						let bx = x + MarchingTables.Corners[b * 3], by = y + MarchingTables.Corners[b * 3 + 1], bz = z + MarchingTables.Corners[b * 3 + 2];
						let da = (float)mDensity[Index(ax, ay, az)];
						let db = (float)mDensity[Index(bx, by, bz)];
						let t = Mathf.Abs(da - db) > 0.001f ? Mathf.Clamp01(da / (da - db)) : 0.5f;
						let local = Vector3(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t) * cell - offset;
						let normal = Vector3.Lerp(Gradient(ax, ay, az), Gradient(bx, by, bz), t).Normalized;
						let carved = mCarved[Index(ax, ay, az)] || mCarved[Index(bx, by, bz)];
						edgeVertex[e] = (uint32)mMesh.Vertices.Count;
						mMesh.Vertices.Add(.(local, normal, carved ? inner : outer, .(local.x, local.z)));
					}
					let row = config * 16;
					for (int i = 0; MarchingTables.Triangles[row + i] != -1; i += 3)
					{
						mMesh.Indices.Add(edgeVertex[MarchingTables.Triangles[row + i]]);
						mMesh.Indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 2]]);
						mMesh.Indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 1]]);
					}
				}
			}
		}
		mMesh.Upload();

		// The renderer may not exist yet while a scene or prefab is still loading this object's
		// components, so attaching (or creating) it is finished in OnFrame.
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null)
			renderer.RuntimeMesh = mMesh;
		else
			mAttachPending = true;

		// Keep collision in step with the surface.
		let body = GetComponent<Rigidbody>();
		let boxCollider = GetComponent<BoxCollider>();
		if (boxCollider != null && mMesh.Vertices.Count > 0)
		{
			boxCollider.center = mMesh.Bounds.Center;
			boxCollider.size = Vector3.Max(mMesh.Bounds.Extents * 2.0f, .(0.05f));
		}
		if (body != null)
			body.RebuildBody();
		else
			GetComponent<Collider>()?.Refresh();
	}

	/// Removes material inside a sphere given in world space. Returns true if anything changed.
	///
	/// In multiplayer the carve happens on every machine. Called on a client it is sent to the server first and
	/// this returns false; the carve follows when the server passes it back.
	public bool Carve(Vector3 worldPoint, float radius)
	{
		if (mDensity == null)
			return false;
		if (NetworkSync.RouteCarve(this, worldPoint, radius))
			return false;
		return CarveLocal(Transform.InverseTransformPoint(worldPoint), radius);
	}

	/// Carve with the centre of the sphere given in the object's own space (the radius is still in world units).
	/// This is what a carve becomes on its way round a network session: every machine works from the same
	/// numbers, wherever exactly it has the object, so the result is the same on all of them. It is applied here
	/// and now, and not sent anywhere.
	public bool CarveLocal(Vector3 objectPoint, float radius)
	{
		if (mDensity == null)
			return false;
		let cell = CellSize;
		let scale = Transform.LocalToWorld.Right.Length;
		let localRadius = radius / Math.Max(scale, 1.0e-4f);
		let local = objectPoint + Vector3(size * 0.5f);
		let reach = localRadius + cell;
		let x0 = Math.Max(0, (int)Math.Floor((local.x - reach) / cell)), x1 = Math.Min(mSamples - 1, (int)Math.Ceiling((local.x + reach) / cell));
		let y0 = Math.Max(0, (int)Math.Floor((local.y - reach) / cell)), y1 = Math.Min(mSamples - 1, (int)Math.Ceiling((local.y + reach) / cell));
		let z0 = Math.Max(0, (int)Math.Floor((local.z - reach) / cell)), z1 = Math.Min(mSamples - 1, (int)Math.Ceiling((local.z + reach) / cell));
		bool changed = false;
		for (int z = z0; z <= z1; z++)
		{
			for (int y = y0; y <= y1; y++)
			{
				for (int x = x0; x <= x1; x++)
				{
					let distance = (Vector3(x, y, z) * cell - local).Length;
					// Signed distance to the carving sphere in cells, like the fill functions.
					let cut = (distance - localRadius) / cell * 32.0f;
					let index = Index(x, y, z);
					if (cut < mDensity[index])
					{
						if (mDensity[index] > -100)
							mCarved[index] = true;
						mDensity[index] = (int8)Mathf.Clamp(cut, -127, 127);
						changed = true;
					}
				}
			}
		}
		if (!changed)
			return false;
		if (breakOffPieces && Scene.IsPlaying)
			SplitLoosePieces();
		if (!anchored && Scene.IsPlaying)
			MakeDynamic();
		Rebuild();
		if (IsEmpty && Scene.IsPlaying)
			Scene.Destroy(GameObject);
		return true;
	}

	/// Swaps static triangle collision for a convex body so what is left of the object can fall and roll.
	void MakeDynamic()
	{
		if (GetComponent<Rigidbody>() != null)
			return;
		let staticCollider = GetComponent<MeshCollider>();
		if (staticCollider != null)
			GameObject.RemoveComponent(staticCollider);
		if (GetComponent<Collider>() == null)
			GameObject.AddComponent<ConvexCollider>();
		int32 solid = 0;
		for (let d in mDensity)
		{
			if (d > 0)
				solid++;
		}
		let body = GameObject.AddComponent<Rigidbody>();
		body.mass = Math.Max(0.5f, solid * 0.02f);
		// In multiplayer every machine carves at the same moment, so they all start sharing its motion from here.
		NetworkSync.EnsureShared(GameObject);
	}

	/// Flood-fills the solid samples; everything not connected to the largest group becomes a new falling object.
	void SplitLoosePieces()
	{
		let count = mSamples * mSamples * mSamples;
		int32[] labels = new int32[count];
		defer delete labels;
		List<int32> sizes = scope .();
		sizes.Add(0);
		List<int32> stack = scope .();
		let stepY = mSamples;
		let stepZ = mSamples * mSamples;
		for (int32 start = 0; start < (int32)count; start++)
		{
			if (mDensity[start] <= 0 || labels[start] != 0)
				continue;
			let label = (int32)sizes.Count;
			int32 members = 0;
			labels[start] = label;
			stack.Add(start);
			while (stack.Count > 0)
			{
				let index = stack.PopBack();
				members++;
				let x = index % mSamples;
				let y = (index / mSamples) % mSamples;
				let z = index / stepZ;
				void Visit(int32 neighbor)
				{
					if (mDensity[neighbor] > 0 && labels[neighbor] == 0)
					{
						labels[neighbor] = label;
						stack.Add(neighbor);
					}
				}
				if (x > 0) Visit(index - 1);
				if (x < mSamples - 1) Visit(index + 1);
				if (y > 0) Visit(index - (int32)stepY);
				if (y < mSamples - 1) Visit(index + (int32)stepY);
				if (z > 0) Visit(index - (int32)stepZ);
				if (z < mSamples - 1) Visit(index + (int32)stepZ);
			}
			sizes.Add(members);
		}
		if (sizes.Count <= 2)
			return;
		int32 largest = 1;
		for (int32 i = 2; i < (int32)sizes.Count; i++)
		{
			if (sizes[i] > sizes[largest])
				largest = i;
		}
		for (int32 label = 1; label < (int32)sizes.Count; label++)
		{
			if (label == largest)
				continue;
			if (sizes[label] >= minimumPieceSize)
				SpawnPiece(labels, label);
			for (int i < count)
			{
				if (labels[i] == label)
					mDensity[i] = -127;
			}
		}
	}

	void SpawnPiece(int32[] labels, int32 label)
	{
		let piece = Scene.CreateGameObject("Fragment");
		piece.Transient = true;
		mPieces.Add(piece.Id);
		piece.Transform.SetPositionAndRotation(Transform.Position, Transform.Rotation);
		piece.Transform.LocalScale = Transform.LocalScale;
		let source = GetComponent<MeshRenderer>();
		// Renderer first, so the piece's mesh is attached (and its collider can be built) immediately.
		piece.AddComponent<MeshRenderer>();
		let voxels = piece.AddComponent<VoxelObject>();
		voxels.shape = shape;
		voxels.resolution = resolution;
		voxels.size = size;
		voxels.color = color;
		voxels.interiorColor = interiorColor;
		voxels.minimumPieceSize = minimumPieceSize;
		voxels.anchored = false;
		voxels.mCustom = true;
		let count = mSamples * mSamples * mSamples;
		for (int i < count)
		{
			// Neighbours of the piece keep their (negative) density so its surface stays where it was.
			voxels.mDensity[i] = labels[i] == label ? mDensity[i] : (mDensity[i] > 0 ? (int8)-127 : mDensity[i]);
			voxels.mCarved[i] = mCarved[i];
		}
		piece.AddComponent<ConvexCollider>();
		let body = piece.AddComponent<Rigidbody>();
		body.mass = Math.Max(0.2f, CountLabel(labels, label) * 0.02f);
		// In multiplayer every machine breaks this piece off at the same moment; from here its motion is shared and
		// it can be carved in turn.
		NetworkSync.ShareFragment(piece);
		voxels.Rebuild();
		let renderer = piece.GetComponent<MeshRenderer>();
		if (renderer != null && source != null)
		{
			renderer.roughness = source.roughness;
			renderer.metallic = source.metallic;
		}
	}

	static float CountLabel(int32[] labels, int32 label)
	{
		int32 n = 0;
		for (let l in labels)
		{
			if (l == label)
				n++;
		}
		return n;
	}
}
