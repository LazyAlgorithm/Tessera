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
		/// Contoured style: the chunk's samples at the step being built, with two more on every side (taken from the
		/// chunks around it, the edge of the tiles applied), and the point made for each cell.
		public int8[] padded = new int8[PaddedSide * PaddedSide * PaddedSide] ~ delete _;
		public bool[] paddedMissing = new bool[PaddedSide * PaddedSide * PaddedSide] ~ delete _;
		public int32[] cellVertex = new int32[(ChunkCells + 1) * (ChunkCells + 1) * (ChunkCells + 1)] ~ delete _;
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
		let separate = mLodOn && mColliders && mStyle != .Blocky;
		if (mStyle == .Blocky)
		{
			BuildBlocky(chunk, work);
			chunk.builtLod = 0;
		}
		else if (mStyle == .Contoured)
		{
			BuildContoured(chunk, work, step, chunk.vertices, chunk.indices);
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
					BuildContoured(chunk, work, 1, chunk.collisionVertices, chunk.collisionIndices);
			}
			if (mLodOn)
				AddOpenEdgeSkirts((2 * step + 1) * work.size, chunk.vertices, chunk.indices);
			chunk.builtLod = work.lod;
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

	const int32 Pad = 2;
	const int32 PaddedSide = ChunkCells + 1 + Pad * 2;

	/// Fills work.padded: every `step`th sample of the chunk and two more beyond each side, from the chunks around it
	/// (their samples, their sculpting on file, or the generator), with air outside the tiles.
	void FillPadded(Chunk chunk, MeshWork work, int32 step)
	{
		let n = ChunkCells / step;
		let side = n + 1 + Pad * 2;
		let padded = work.padded;
		let missing = work.paddedMissing;
		bool anyMissing = false;
		using (mMonitor.Enter())
		{
			int8*[27] sources = default;
			bool[27] absent = default;
			for (int32 oz = -1; oz <= 1; oz++)
				for (int32 oy = -1; oy <= 1; oy++)
					for (int32 ox = -1; ox <= 1; ox++)
					{
						let slot = (ox + 1) + (oy + 1) * 3 + (oz + 1) * 9;
						if (ox == 0 && oy == 0 && oz == 0)
						{
							sources[slot] = work.center.Ptr;
							continue;
						}
						let other = Int3(chunk.coord.x + ox, chunk.coord.y + oy, chunk.coord.z + oz);
						int8[] source = null;
						if (mChunks.TryGetValue(other, let live) && live.generated && live.density != null)
							source = live.density;
						else if (work.snap.Locate(other, let tileId, let local))
							source = FindSaved(tileId, local)?.density;
						sources[slot] = source != null ? source.Ptr : null;
						absent[slot] = source == null;
					}
			for (int k < side)
			{
				let rz = (k - Pad) * step;
				let oz = rz < 0 ? -1 : (rz > ChunkCells ? 1 : 0);
				for (int j < side)
				{
					let ry = (j - Pad) * step;
					let oy = ry < 0 ? -1 : (ry > ChunkCells ? 1 : 0);
					for (int i < side)
					{
						let rx = (i - Pad) * step;
						let ox = rx < 0 ? -1 : (rx > ChunkCells ? 1 : 0);
						let slot = (ox + 1) + (oy + 1) * 3 + (oz + 1) * 9;
						let at = i + j * side + k * side * side;
						if (absent[slot])
						{
							missing[at] = true;
							anyMissing = true;
							continue;
						}
						missing[at] = false;
						padded[at] = sources[slot][SampleIndex(rx - ox * ChunkCells, ry - oy * ChunkCells, rz - oz * ChunkCells)];
					}
				}
			}
		}
		let snap = work.snap;
		let size = work.size;
		if (anyMissing)
		{
			for (int k < side)
				for (int j < side)
					for (int i < side)
					{
						let at = i + j * side + k * side * side;
						if (!missing[at])
							continue;
						let p = work.origin + Vector3((i - Pad) * step, (j - Pad) * step, (k - Pad) * step) * size;
						padded[at] = Quantize(snap.Density(p.x, p.y, p.z), size);
					}
		}
		if (work.masked)
		{
			for (int k < side)
				for (int i < side)
				{
					if (snap.Inside(work.origin.x + (i - Pad) * step * size, work.origin.z + (k - Pad) * step * size))
						continue;
					for (int j < side)
						padded[i + j * side + k * side * side] = Air;
				}
		}
	}

	/// Dual contouring over cells `step` samples across. Each cell the surface passes through gets one point, placed
	/// from where the surface crosses the cell's edges and which way it faces there; each grid edge the surface crosses
	/// gets a quad joining the points of the four cells round it. The outermost points belong to cells of the chunks
	/// around this one, which make the same points from the same samples, so chunks meet without a seam.
	void BuildContoured(Chunk chunk, MeshWork work, int32 step, List<MeshVertex> vertices, List<uint32> indices)
	{
		FillPadded(chunk, work, step);
		let n = ChunkCells / step;
		let side = n + 1 + Pad * 2;
		let sideY = side, sideZ = side * side;
		let data = work.padded.Ptr;
		let cells = work.cellVertex;
		let cellSide = n + 1;
		Internal.MemSet(cells.Ptr, 0xFF, cells.Count * sizeof(int32));
		let size = work.size;
		let origin = work.origin;
		let sharpness = mSharpness;

		// ---- a point for every cell the surface passes through (cells -1 to n - 1 along each axis) ----
		for (int cz = -1; cz < n; cz++)
		{
			for (int cy = -1; cy < n; cy++)
			{
				for (int cx = -1; cx < n; cx++)
				{
					let at = (cx + Pad) + (cy + Pad) * sideY + (cz + Pad) * sideZ;
					float[8] corner = ?;
					int solid = 0;
					for (int c < 8)
					{
						let value = data[at + (c & 1) + ((c >> 1) & 1) * sideY + ((c >> 2) & 1) * sideZ];
						corner[c] = value;
						if (value > 0)
							solid |= 1 << c;
					}
					if (solid == 0 || solid == 255)
						continue;
					// Where the surface crosses each edge of the cell, and which way it faces there.
					Vector3 mass = .Zero, facing = .Zero;
					float a00 = 0, a01 = 0, a02 = 0, a11 = 0, a12 = 0, a22 = 0;
					Vector3 right = .Zero;
					int crossings = 0;
					for (int axis < 3)
					{
						let bit = 1 << axis;
						for (int c < 8)
						{
							if ((c & bit) != 0)
								continue;
							let d = c | bit;
							if (((solid >> c) & 1) == ((solid >> d) & 1))
								continue;
							let da = corner[c], db = corner[d];
							let t = Math.Abs(da - db) > 0.001f ? Mathf.Clamp01(da / (da - db)) : 0.5f;
							var point = Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1);
							point[axis] = t;
							let ia = at + (c & 1) + ((c >> 1) & 1) * sideY + ((c >> 2) & 1) * sideZ;
							let ib = at + (d & 1) + ((d >> 1) & 1) * sideY + ((d >> 2) & 1) * sideZ;
							let ga = Vector3((float)data[ia - 1] - data[ia + 1], (float)data[ia - sideY] - data[ia + sideY], (float)data[ia - sideZ] - data[ia + sideZ]);
							let gb = Vector3((float)data[ib - 1] - data[ib + 1], (float)data[ib - sideY] - data[ib + sideY], (float)data[ib - sideZ] - data[ib + sideZ]);
							var normal = Vector3.Lerp(ga, gb, t);
							let length = normal.Length;
							normal = length > 0.00001f ? normal * (1.0f / length) : Vector3(0, 1, 0);
							mass = mass + point;
							facing = facing + normal;
							let along = Vector3.Dot(normal, point);
							a00 += normal.x * normal.x; a01 += normal.x * normal.y; a02 += normal.x * normal.z;
							a11 += normal.y * normal.y; a12 += normal.y * normal.z; a22 += normal.z * normal.z;
							right = right + normal * along;
							crossings++;
						}
					}
					if (crossings == 0)
						continue;
					mass = mass * (1.0f / crossings);
					var point = mass;
					if (sharpness > 0)
					{
						// The point nearest to every crossing's plane, pulled a little towards the middle of the crossings
						// so that it is always well defined (flat ground has planes that all agree).
						let pull = 0.1f * crossings;
						let m00 = a00 + pull, m11 = a11 + pull, m22 = a22 + pull;
						let rx = right.x + pull * mass.x, ry = right.y + pull * mass.y, rz = right.z + pull * mass.z;
						let c00 = m11 * m22 - a12 * a12, c01 = a02 * a12 - a01 * m22, c02 = a01 * a12 - a02 * m11;
						let det = m00 * c00 + a01 * c01 + a02 * c02;
						if (Math.Abs(det) > 1.0e-9f)
						{
							let c11 = m00 * m22 - a02 * a02, c12 = a01 * a02 - m00 * a12, c22 = m00 * m11 - a01 * a01;
							var solved = Vector3((c00 * rx + c01 * ry + c02 * rz) / det, (c01 * rx + c11 * ry + c12 * rz) / det, (c02 * rx + c12 * ry + c22 * rz) / det);
							// Kept inside its cell: a point outside would fold the surface over its neighbours.
							solved = .(Mathf.Clamp01(solved.x), Mathf.Clamp01(solved.y), Mathf.Clamp01(solved.z));
							point = Vector3.Lerp(mass, solved, sharpness);
						}
					}
					let facingLength = facing.Length;
					let normal = facingLength > 0.00001f ? facing * (1.0f / facingLength) : Vector3(0, 1, 0);
					let position = origin + (Vector3(cx, cy, cz) + point) * (step * size);
					var color = SurfaceColor(position.y, normal.y);
					if (chunk.paint != null)
					{
						// Painted where the nearest solid corner is painted (corners outside the chunk read its edge).
						int best = -1;
						float bestDistance = float.MaxValue;
						for (int c < 8)
						{
							if (((solid >> c) & 1) == 0)
								continue;
							let distance = (Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1) - point).LengthSquared;
							if (distance < bestDistance)
							{
								bestDistance = distance;
								best = c;
							}
						}
						let px = Math.Clamp((cx + (best & 1)) * step, 0, ChunkCells), py = Math.Clamp((cy + ((best >> 1) & 1)) * step, 0, ChunkCells), pz = Math.Clamp((cz + ((best >> 2) & 1)) * step, 0, ChunkCells);
						let layer = chunk.paint[SampleIndex(px, py, pz)];
						if (layer != 0)
							color = LayerColor(layer);
					}
					cells[(cx + 1) + (cy + 1) * cellSide + (cz + 1) * cellSide * cellSide] = (int32)vertices.Count;
					vertices.Add(.(position, normal, color.ToABGR(), .(position.x, position.z)));
				}
			}
		}

		// ---- a quad across every grid edge the surface crosses (this chunk owns the edges that start inside it) ----
		for (int z < n)
		{
			for (int y < n)
			{
				for (int x < n)
				{
					let at = (x + Pad) + (y + Pad) * sideY + (z + Pad) * sideZ;
					let here = data[at] > 0;
					for (int axis < 3)
					{
						let there = data[at + (axis == 0 ? 1 : (axis == 1 ? sideY : sideZ))] > 0;
						if (here == there)
							continue;
						// The four cells round the edge, going round it: back along both other axes, then each in turn.
						int ux = 0, uy = 0, uz = 0, vx = 0, vy = 0, vz = 0;
						if (axis == 0) { uy = 1; vz = 1; }
						else if (axis == 1) { uz = 1; vx = 1; }
						else { ux = 1; vy = 1; }
						int Cell(int dx, int dy, int dz) => cells[(x + dx + 1) + (y + dy + 1) * cellSide + (z + dz + 1) * cellSide * cellSide];
						let q0 = Cell(-ux - vx, -uy - vy, -uz - vz);
						let q1 = Cell(-vx, -vy, -vz);
						let q2 = Cell(0, 0, 0);
						let q3 = Cell(-ux, -uy, -uz);
						if (q0 < 0 || q1 < 0 || q2 < 0 || q3 < 0)
							continue;
						// Split along the shorter diagonal, which keeps the two triangles from being slivers.
						let across = (vertices[q0].position - vertices[q2].position).LengthSquared <= (vertices[q1].position - vertices[q3].position).LengthSquared;
						uint32 a = (uint32)q0, b = (uint32)q1, c = (uint32)q2, d = (uint32)q3;
						if (!here)
						{
							// Facing the other way: go round the quad in the other direction.
							Swap!(b, d);
						}
						if (across)
						{
							indices.Add(a); indices.Add(b); indices.Add(c);
							indices.Add(a); indices.Add(c); indices.Add(d);
						}
						else
						{
							indices.Add(a); indices.Add(b); indices.Add(d);
							indices.Add(b); indices.Add(c); indices.Add(d);
						}
					}
				}
			}
		}
	}

	/// Skirts for contoured chunks: a strip down into the ground from every edge of the mesh that only one triangle
	/// uses, which is its rim. Chunks at different detail then meet without gaps showing.
	static void AddOpenEdgeSkirts(float depth, List<MeshVertex> vertices, List<uint32> indices)
	{
		Dictionary<uint64, int32> uses = scope .();
		let triangles = indices.Count / 3;
		for (int t < triangles)
		{
			for (int e < 3)
			{
				let ia = indices[t * 3 + e], ib = indices[t * 3 + (e + 1) % 3];
				let key = ia < ib ? ((uint64)ia << 32) | ib : ((uint64)ib << 32) | ia;
				if (uses.TryGetValue(key, let count))
					uses[key] = count + 1;
				else
					uses[key] = 1;
			}
		}
		for (int t < triangles)
		{
			for (int e < 3)
			{
				let ia = indices[t * 3 + e], ib = indices[t * 3 + (e + 1) % 3];
				let key = ia < ib ? ((uint64)ia << 32) | ib : ((uint64)ib << 32) | ia;
				if (uses[key] != 1)
					continue;
				var a = vertices[(int)ia];
				var b = vertices[(int)ib];
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
				if ((Faces(vertices[(int)ia].position) & Faces(vertices[(int)ib].position)) == 0)
					continue;
				var a = vertices[(int)ia];
				var b = vertices[(int)ib];
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
