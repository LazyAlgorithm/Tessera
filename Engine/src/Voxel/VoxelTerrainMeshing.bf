using System;
using System.Collections;

namespace Tessera;

/// Turning a terrain chunk's samples into meshes, on worker threads.
extension VoxelTerrain
{
	/// One worker's scratch space, and the samples just beyond the chunk it is meshing (from the neighbouring chunks,
	/// so normals and edges match on both sides of a border).
	class MeshWork
	{
		public int32[] edgeCache = new int32[SampleCount * 3] ~ delete _;
		/// The neighbours' samples one step out from each of the six faces, and `farDistance` steps out.
		public int8[] near = new int8[6 * FaceCount] ~ delete _;
		public int8[] far = new int8[6 * FaceCount] ~ delete _;
		/// Per column of the chunk: inside the tiles.
		public bool[] inside = new bool[FaceCount] ~ delete _;
		public int8[] center;
		public int32 farDistance = 1;
		public bool masked;
		public Snapshot snap;
		public Vector3 origin;
		public float size = 1;
		public int32 lod;
		public bool collision;

		/// A sample, which may be just outside the chunk on one axis.
		public int8 Raw(int x, int y, int z)
		{
			if ((uint)x <= (uint)ChunkCells && (uint)y <= (uint)ChunkCells && (uint)z <= (uint)ChunkCells)
				return center[SampleIndex(x, y, z)];
			int face, distance, a, b;
			if (x < 0) { face = 0; distance = -x; a = y; b = z; }
			else if (x > ChunkCells) { face = 1; distance = x - ChunkCells; a = y; b = z; }
			else if (y < 0) { face = 2; distance = -y; a = x; b = z; }
			else if (y > ChunkCells) { face = 3; distance = y - ChunkCells; a = x; b = z; }
			else if (z < 0) { face = 4; distance = -z; a = x; b = y; }
			else { face = 5; distance = z - ChunkCells; a = x; b = y; }
			a = Math.Clamp(a, 0, ChunkCells);
			b = Math.Clamp(b, 0, ChunkCells);
			return (distance <= 1 ? near : far)[face * FaceCount + a + b * Samples];
		}

		/// A sample with the edge of the tiles applied: air outside them.
		public int8 D(int x, int y, int z)
		{
			let value = Raw(x, y, z);
			if (!masked)
				return value;
			if ((uint)x <= (uint)ChunkCells && (uint)z <= (uint)ChunkCells)
				return inside[x + z * Samples] ? value : Air;
			return snap.Inside(origin.x + x * size, origin.z + z * size) ? value : Air;
		}
	}

	static Int3 FaceOffset(int face)
	{
		switch (face)
		{
		case 0: return .(-1, 0, 0);
		case 1: return .(1, 0, 0);
		case 2: return .(0, -1, 0);
		case 3: return .(0, 1, 0);
		case 4: return .(0, 0, -1);
		default: return .(0, 0, 1);
		}
	}

	/// The sample `distance` steps beyond a face, at (a, b) across it, in this chunk's sample coordinates.
	static void BeyondFace(int face, int distance, int a, int b, out int x, out int y, out int z)
	{
		switch (face)
		{
		case 0: x = -distance; y = a; z = b;
		case 1: x = ChunkCells + distance; y = a; z = b;
		case 2: x = a; y = -distance; z = b;
		case 3: x = a; y = ChunkCells + distance; z = b;
		case 4: x = a; y = b; z = -distance;
		default: x = a; y = b; z = ChunkCells + distance;
		}
	}

	static void CopyLayer(int8[] source, int8[] layer, int face, int distance)
	{
		let offset = FaceOffset(face);
		for (int b < Samples)
			for (int a < Samples)
			{
				BeyondFace(face, distance, a, b, let x, let y, let z);
				// The same sample in the neighbour's own coordinates.
				layer[face * FaceCount + a + b * Samples] = source[SampleIndex(x - offset.x * ChunkCells, y - offset.y * ChunkCells, z - offset.z * ChunkCells)];
			}
	}

	static void GenerateLayer(MeshWork work, int8[] layer, int face, int distance)
	{
		let snap = work.snap;
		for (int b < Samples)
			for (int a < Samples)
			{
				BeyondFace(face, distance, a, b, let x, let y, let z);
				let p = work.origin + Vector3(x, y, z) * work.size;
				layer[face * FaceCount + a + b * Samples] = Quantize(snap.Density(p.x, p.y, p.z), work.size);
			}
	}

	/// The samples beyond each face: from the neighbouring chunk, its sculpting on file, or the generator.
	void FillApron(Chunk chunk, MeshWork work, int32 farDistance)
	{
		work.farDistance = farDistance;
		bool[6] missing = default;
		using (mMonitor.Enter())
		{
			for (int face < 6)
			{
				let other = chunk.coord + FaceOffset(face);
				int8[] source = null;
				if (mChunks.TryGetValue(other, let live) && live.generated && live.density != null)
					source = live.density;
				else if (work.snap.Locate(other, let tileId, let local))
					source = FindSaved(tileId, local)?.density;
				if (source == null)
				{
					missing[face] = true;
					continue;
				}
				CopyLayer(source, work.near, face, 1);
				if (farDistance > 1)
					CopyLayer(source, work.far, face, farDistance);
			}
		}
		for (int face < 6)
		{
			if (!missing[face])
				continue;
			GenerateLayer(work, work.near, face, 1);
			if (farDistance > 1)
				GenerateLayer(work, work.far, face, farDistance);
		}
	}

	/// Called with mMonitor held, as a worker takes a chunk.
	void TakeJob(Chunk chunk, MeshWork work)
	{
		work.snap = mSnap;
		work.lod = chunk.lod;
		work.collision = chunk.shapeChanged;
		chunk.shapeChanged = false;
	}

	void BuildChunk(Chunk chunk, MeshWork work)
	{
		let snap = work.snap;
		if (!chunk.generated)
			GenerateDensity(chunk, snap);
		if (!mLodOn)
			work.lod = 0;
		let step = (int32)1 << Math.Clamp(work.lod, 0, 3);
		work.center = chunk.density;
		work.size = snap.voxelSize;
		work.origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * (ChunkCells * work.size);
		work.masked = snap.mode == .Fixed;
		if (work.masked)
		{
			for (int z < Samples)
				for (int x < Samples)
					work.inside[x + z * Samples] = snap.Inside(work.origin.x + x * work.size, work.origin.z + z * work.size);
		}
		FillApron(chunk, work, step);
		chunk.vertices.Clear();
		chunk.indices.Clear();
		let separate = mLodOn && mColliders && mStyle == .Smooth;
		if (mStyle == .Blocky)
		{
			BuildBlocky(chunk, work);
			chunk.builtLod = 0;
		}
		else
		{
			BuildSmooth(chunk, work, step, chunk.vertices, chunk.indices);
			if (separate && work.collision)
			{
				chunk.collisionVertices.Clear();
				chunk.collisionIndices.Clear();
				if (step == 1)
				{
					chunk.collisionVertices.AddRange(chunk.vertices);
					chunk.collisionIndices.AddRange(chunk.indices);
				}
				else
					BuildSmooth(chunk, work, 1, chunk.collisionVertices, chunk.collisionIndices);
			}
			if (mLodOn)
				AddSkirts(work, step, chunk.vertices, chunk.indices);
			chunk.builtLod = work.lod;
		}
		chunk.separateCollision = separate;
		chunk.builtCollision = separate ? work.collision : true;
	}

	/// Surface normal from the density gradient (points from solid towards empty).
	static Vector3 Gradient(MeshWork work, int x, int y, int z, int step)
	{
		return .(
			(float)work.D(x - step, y, z) - work.D(x + step, y, z),
			(float)work.D(x, y - step, z) - work.D(x, y + step, z),
			(float)work.D(x, y, z - step) - work.D(x, y, z + step));
	}

	/// Marching cubes over cells `step` samples across (1 is full detail).
	void BuildSmooth(Chunk chunk, MeshWork work, int32 step, List<MeshVertex> vertices, List<uint32> indices)
	{
		let size = work.size;
		let origin = work.origin;
		let edgeCache = work.edgeCache;
		Internal.MemSet(edgeCache.Ptr, 0xFF, edgeCache.Count * sizeof(int32));

		int[8] cornerX = default, cornerY = default, cornerZ = default;
		for (int c < 8)
		{
			cornerX[c] = MarchingTables.Corners[c * 3] * step;
			cornerY[c] = MarchingTables.Corners[c * 3 + 1] * step;
			cornerZ[c] = MarchingTables.Corners[c * 3 + 2] * step;
		}

		uint32[12] edgeVertex = default;
		for (int z = 0; z < ChunkCells; z += step)
		{
			for (int y = 0; y < ChunkCells; y += step)
			{
				for (int x = 0; x < ChunkCells; x += step)
				{
					int config = 0;
					for (int c < 8)
					{
						if (work.D(x + cornerX[c], y + cornerY[c], z + cornerZ[c]) <= 0)
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
						let ax = x + cornerX[a], ay = y + cornerY[a], az = z + cornerZ[a];
						let bx = x + cornerX[b], by = y + cornerY[b], bz = z + cornerZ[b];
						// Each grid edge is shared by up to four cells; cache its vertex by lower corner and axis.
						let lx = Math.Min(ax, bx), ly = Math.Min(ay, by), lz = Math.Min(az, bz);
						let axis = ax != bx ? 0 : (ay != by ? 1 : 2);
						let cacheIndex = SampleIndex(lx, ly, lz) * 3 + axis;
						var vertexIndex = edgeCache[cacheIndex];
						if (vertexIndex < 0)
						{
							let da = (float)work.D(ax, ay, az);
							let db = (float)work.D(bx, by, bz);
							let t = Mathf.Abs(da - db) > 0.001f ? Mathf.Clamp01(da / (da - db)) : 0.5f;
							let local = Vector3(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t);
							var normal = Vector3.Lerp(Gradient(work, ax, ay, az, step), Gradient(work, bx, by, bz, step), t);
							let length = normal.Length;
							normal = length > 0.00001f ? normal * (1.0f / length) : Vector3(0, 1, 0);
							let position = origin + local * size;
							vertexIndex = (int32)vertices.Count;
							var color = SurfaceColor(position.y, normal.y);
							if (chunk.paint != null)
							{
								let layer = chunk.paint[t < 0.5f ? SampleIndex(ax, ay, az) : SampleIndex(bx, by, bz)];
								if (layer != 0)
									color = LayerColor(layer);
							}
							vertices.Add(.(position, normal, color.ToABGR(), .(position.x, position.z)));
							edgeCache[cacheIndex] = vertexIndex;
						}
						edgeVertex[e] = (uint32)vertexIndex;
					}

					let row = config * 16;
					for (int i = 0; MarchingTables.Triangles[row + i] != -1; i += 3)
					{
						indices.Add(edgeVertex[MarchingTables.Triangles[row + i]]);
						indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 2]]);
						indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 1]]);
					}
				}
			}
		}
	}

	/// Chunks drawn at different detail do not meet exactly along their shared side. A skirt (a strip from the edge of
	/// the surface down into the ground, seen from both sides) on the chunks' sides covers the gap.
	static void AddSkirts(MeshWork work, int32 step, List<MeshVertex> vertices, List<uint32> indices)
	{
		let size = work.size;
		let depth = (2 * step + 1) * size;
		let limit = ChunkCells * size;
		let epsilon = size * 0.001f;
		int Faces(Vector3 position)
		{
			let p = position - work.origin;
			int faces = 0;
			if (Math.Abs(p.x) < epsilon) faces |= 1;
			if (Math.Abs(p.x - limit) < epsilon) faces |= 2;
			if (Math.Abs(p.z) < epsilon) faces |= 4;
			if (Math.Abs(p.z - limit) < epsilon) faces |= 8;
			return faces;
		}
		let triangles = indices.Count / 3;
		for (int t < triangles)
		{
			for (int e < 3)
			{
				let ia = indices[t * 3 + e];
				let ib = indices[t * 3 + (e + 1) % 3];
				if ((Faces(vertices[ia].position) & Faces(vertices[ib].position)) == 0)
					continue;
				var a = vertices[ia];
				var b = vertices[ib];
				a.position -= a.normal * depth;
				b.position -= b.normal * depth;
				let a2 = (uint32)vertices.Count;
				let b2 = a2 + 1;
				vertices.Add(a);
				vertices.Add(b);
				indices.Add(ia); indices.Add(ib); indices.Add(b2);
				indices.Add(ia); indices.Add(b2); indices.Add(a2);
				indices.Add(ia); indices.Add(b2); indices.Add(ib);
				indices.Add(ia); indices.Add(a2); indices.Add(b2);
			}
		}
	}

	void BuildBlocky(Chunk chunk, MeshWork work)
	{
		let size = work.size;
		let origin = work.origin;
		// A chunk owns the faces between each of its cells and the next cell along +X, +Y and +Z.
		for (int z < ChunkCells)
		{
			for (int y < ChunkCells)
			{
				for (int x < ChunkCells)
				{
					let solid = work.D(x, y, z) > 0;
					let p = origin + Vector3(x, y, z) * size;
					for (int axis < 3)
					{
						let nx = x + (axis == 0 ? 1 : 0), ny = y + (axis == 1 ? 1 : 0), nz = z + (axis == 2 ? 1 : 0);
						let neighbor = work.D(nx, ny, nz) > 0;
						if (solid == neighbor)
							continue;
						// The face sits on the +axis side of this cell, facing whichever side is empty.
						Vector3 u = default, v = default, n = default;
						if (axis == 0) { n = .(1, 0, 0); u = .(0, 1, 0); v = .(0, 0, 1); }
						else if (axis == 1) { n = .(0, 1, 0); u = .(0, 0, 1); v = .(1, 0, 0); }
						else { n = .(0, 0, 1); u = .(1, 0, 0); v = .(0, 1, 0); }
						let corner = p + n * size;
						let normal = solid ? n : -n;
						let cellY = solid ? p.y : p.y + (axis == 1 ? size : 0);
						var faceColor = SurfaceColor(cellY, normal.y > 0.5f ? 1.0f : (normal.y < -0.5f ? 0.0f : 0.4f));
						if (chunk.paint != null)
						{
							let layer = chunk.paint[solid ? SampleIndex(x, y, z) : SampleIndex(nx, ny, nz)];
							if (layer != 0)
								faceColor = LayerColor(layer);
						}
						let color = faceColor.ToABGR();
						let first = (uint32)chunk.vertices.Count;
						chunk.vertices.Add(.(corner, normal, color, .(0, 0)));
						chunk.vertices.Add(.(corner + u * size, normal, color, .(1, 0)));
						chunk.vertices.Add(.(corner + (u + v) * size, normal, color, .(1, 1)));
						chunk.vertices.Add(.(corner + v * size, normal, color, .(0, 1)));
						if (solid)
						{
							chunk.indices.Add(first); chunk.indices.Add(first + 1); chunk.indices.Add(first + 2);
							chunk.indices.Add(first); chunk.indices.Add(first + 2); chunk.indices.Add(first + 3);
						}
						else
						{
							chunk.indices.Add(first); chunk.indices.Add(first + 2); chunk.indices.Add(first + 1);
							chunk.indices.Add(first); chunk.indices.Add(first + 3); chunk.indices.Add(first + 2);
						}
					}
				}
			}
		}
	}

	void WorkerMain()
	{
		let work = new MeshWork();
		defer delete work;
		while (true)
		{
			Chunk chunk = null;
			using (mMonitor.Enter())
			{
				if (mQuit)
					return;
				if (mJobs.Count > 0)
				{
					chunk = mJobs.PopBack();
					chunk.state = .Working;
					chunk.dirty = false;
					mBusy++;
					TakeJob(chunk, work);
				}
			}
			if (chunk == null)
			{
				mWake.WaitFor(50);
				continue;
			}
			BuildChunk(chunk, work);
			using (mMonitor.Enter())
			{
				chunk.state = .Ready;
				mFinished.Add(chunk);
				mBusy--;
			}
		}
	}

	/// Without worker threads: builds queued chunks on this thread until the time budget is spent (always at least
	/// one, so the terrain keeps coming in on a slow device).
	void BuildInline()
	{
		let start = SDL.SDL_GetTicksNS();
		while (mJobs.Count > 0)
		{
			let chunk = mJobs.PopBack();
			chunk.dirty = false;
			TakeJob(chunk, mInlineWork);
			BuildChunk(chunk, mInlineWork);
			chunk.state = .Ready;
			mFinished.Add(chunk);
			if (SDL.SDL_GetTicksNS() - start > InlineBudgetNs)
				break;
		}
	}

	/// How long a web build spends building terrain chunks each frame.
	const uint64 InlineBudgetNs = 6 * 1000000;
}
