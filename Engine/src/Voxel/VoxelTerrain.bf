using System;
using System.Collections;
using System.Threading;

namespace Tessera;

/// Gradient noise used for terrain generation. Deterministic for a given seed on every platform.
static class Noise
{
	[Inline]
	static uint32 Hash(int32 x, int32 y, int32 z, uint32 seed)
	{
		var h = (uint32)x * 374761393 + (uint32)y * 668265263 + (uint32)z * 2147483647 + seed * 3266489917;
		h = (h ^ (h >> 13)) * 1274126177;
		return h ^ (h >> 16);
	}

	[Inline]
	static float Grad(uint32 hash, float x, float y, float z)
	{
		let h = hash & 15;
		let u = h < 8 ? x : y;
		let v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
		return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
	}

	[Inline]
	static float Fade(float t) => t * t * t * (t * (t * 6 - 15) + 10);

	/// Perlin noise in roughly -1..1.
	public static float Perlin(float x, float y, float z, uint32 seed)
	{
		let xi = (int32)Math.Floor(x);
		let yi = (int32)Math.Floor(y);
		let zi = (int32)Math.Floor(z);
		let xf = x - xi;
		let yf = y - yi;
		let zf = z - zi;
		let u = Fade(xf);
		let v = Fade(yf);
		let w = Fade(zf);
		let n000 = Grad(Hash(xi, yi, zi, seed), xf, yf, zf);
		let n100 = Grad(Hash(xi + 1, yi, zi, seed), xf - 1, yf, zf);
		let n010 = Grad(Hash(xi, yi + 1, zi, seed), xf, yf - 1, zf);
		let n110 = Grad(Hash(xi + 1, yi + 1, zi, seed), xf - 1, yf - 1, zf);
		let n001 = Grad(Hash(xi, yi, zi + 1, seed), xf, yf, zf - 1);
		let n101 = Grad(Hash(xi + 1, yi, zi + 1, seed), xf - 1, yf, zf - 1);
		let n011 = Grad(Hash(xi, yi + 1, zi + 1, seed), xf, yf - 1, zf - 1);
		let n111 = Grad(Hash(xi + 1, yi + 1, zi + 1, seed), xf - 1, yf - 1, zf - 1);
		let x00 = n000 + (n100 - n000) * u;
		let x10 = n010 + (n110 - n010) * u;
		let x01 = n001 + (n101 - n001) * u;
		let x11 = n011 + (n111 - n011) * u;
		let y0 = x00 + (x10 - x00) * v;
		let y1 = x01 + (x11 - x01) * v;
		return y0 + (y1 - y0) * w;
	}

	/// Fractal sum of Perlin octaves.
	public static float Fbm(float x, float y, float z, uint32 seed, int octaves)
	{
		float sum = 0;
		float amplitude = 1;
		float frequency = 1;
		float total = 0;
		for (int i < octaves)
		{
			sum += Perlin(x * frequency, y * frequency, z * frequency, seed + (uint32)i * 101) * amplitude;
			total += amplitude;
			amplitude *= 0.5f;
			frequency *= 2.0f;
		}
		return sum / total;
	}
}

[Reflect(.All)]
enum VoxelBrush : int32
{
	Raise,
	Lower,
	Smooth,
	Flatten,
	Paint
}

[Reflect(.All)]
enum TerrainMode : int32
{
	/// A set area that starts flat and is shaped by hand with the terrain tools.
	Fixed,
	/// Generated from noise around the camera, without end.
	Endless
}

[Reflect(.All)]
enum VoxelStyle : int32
{
	/// Marching cubes: smooth slopes, faceted by flat shading.
	Smooth,
	/// One cube per solid cell with hidden faces removed.
	Blocky
}

/// Streaming voxel terrain. Chunks around the viewer are generated and meshed on worker
/// threads; the main thread only uploads finished meshes within a per-frame budget.
/// Call ModifySphere to dig or build at runtime.
[Component]
class VoxelTerrain : Component
{
	public const int32 ChunkCells = 32;
	public const int32 Samples = ChunkCells + 1;
	const int32 SampleCount = Samples * Samples * Samples;

	/// Fixed: a set area that starts flat, for sculpting by hand. Endless: generated around the camera for ever.
	public TerrainMode mode = .Fixed;
	/// Fixed mode: how many chunks the terrain covers along X and Z. A chunk is 32 voxels across, so the default
	/// 4 x 4 at voxel size 1 is a 128 m square. The area starts at the object's position.
	public int32 sizeX = 4;
	public int32 sizeZ = 4;
	/// Fixed mode: how high the flat ground starts, above the object's position.
	public float flatHeight = 0.0f;
	public VoxelStyle style = .Smooth;
	public int32 seed = 1337;
	public float voxelSize = 1.0f;
	/// Horizontal streaming radius in chunks.
	public int32 viewDistance = 6;
	public int32 minChunkY = -1;
	public int32 maxChunkY = 2;
	public float terrainHeight = 28.0f;
	public float terrainScale = 0.012f;
	[Range(0, 1)]
	public float caveAmount = 0.35f;
	public float seaLevel = 0.0f;
	public Color grassColor = .FromBytes(104, 159, 74);
	public Color rockColor = .FromBytes(128, 122, 116);
	public Color sandColor = .FromBytes(214, 196, 142);
	public Color snowColor = .FromBytes(236, 240, 245);
	public Color dirtColor = .FromBytes(124, 92, 62);
	public bool generateColliders = true;
	/// Finished chunks uploaded to the GPU per frame.
	public int32 uploadsPerFrame = 4;
	/// Sculpted and painted chunks are stored in this file (relative to the project). Set when the scene is saved.
	[HideInInspector]
	public String editsFile = new .() ~ delete _;

	enum ChunkState { Queued, Working, Ready, Uploaded }

	class Chunk
	{
		public Int3 coord;
		public int8[] density ~ delete _;
		/// Painted layer per sample (0 = automatic color), allocated on first paint.
		public uint8[] paint ~ delete _;
		public bool edited;
		public bool generated;
		/// How many of the session's shared brush strokes this chunk has had applied (see mSessionBrushes).
		public int32 appliedBrushes;
		public ChunkState state;
		public bool dirty;
		public bool cancelled;
		public List<MeshVertex> vertices = new .() ~ delete _;
		public List<uint32> indices = new .() ~ delete _;
		public Mesh mesh ~ delete _;
		public GameObject gameObject;
	}

	class SavedChunk
	{
		public int8[] density ~ delete _;
		public uint8[] paint ~ delete _;
		public int32 appliedBrushes;
	}

	/// One brush stroke, in the terrain's own space.
	struct BrushStroke
	{
		public Vector3 center;
		public float radius;
		public float strength;
		public VoxelBrush mode;
		public int32 paintLayer;
		public float flattenLocal;
	}

	/// Every brush stroke of the current network session, in the order the server passed them on. Chunks stream in
	/// at different times on different machines, so a chunk that was not loaded when a stroke happened has the
	/// strokes it missed applied when it arrives; every machine ends up with the same terrain.
	List<BrushStroke> mSessionBrushes = new .() ~ delete _;

	/// Edited chunks that are not currently streamed in, plus everything read from editsFile.
	Dictionary<Int3, SavedChunk> mSaved = new .() ~ DeleteDictionaryAndValues!(_);
	String mLoadedEdits = new .() ~ delete _;
	/// True when sculpting or painting has not been written to editsFile yet.
	[NonSerialized]
	public bool HasUnsavedEdits;

	Dictionary<Int3, Chunk> mChunks = new .() ~ delete _;
	List<Chunk> mJobs = new .() ~ delete _;
	List<Chunk> mFinished = new .() ~ delete _;
	List<Chunk> mGraveyard = new .() ~ delete _;
	List<Thread> mThreads = new .() ~ delete _;
	/// Web builds have no worker threads: chunks are built on the main thread, a few milliseconds' worth a frame.
	bool mInline;
	int32[] mInlineEdgeCache ~ delete _;
	/// True once the terrain is registered and building chunks, on workers or inline.
	bool Streaming => mThreads.Count > 0 || mInline;
	Monitor mMonitor = new .() ~ delete _;
	WaitEvent mWake = new .() ~ delete _;
	bool mQuit;
	int32 mBusy;
	// Copies of the settings read by worker threads.
	VoxelStyle mStyle;
	uint32 mSeed;
	float mVoxelSize, mTerrainHeight, mTerrainScale, mCaveAmount, mSeaLevel;
	TerrainMode mMode;
	int32 mSizeX, mSizeZ;
	float mFlatHeight;
	DensityFunction mGenerator ~ delete _;
	int32 mGeneratorVersion;
	Color mGrass, mRock, mSand, mSnow, mDirt;
	int32 mSettingsHash;

	/// World position chunks are streamed around. The application sets this from the active camera.
	public static Vector3 ViewerPosition;

	public int32 ChunkCount => (int32)mChunks.Count;
	public int32 PendingChunks
	{
		get
		{
			using (mMonitor.Enter())
				return (int32)(mJobs.Count + mFinished.Count) + mBusy;
		}
	}

	public override void OnRegister()
	{
		CaptureSettings();
#if BF_PLATFORM_WASM
		mInline = true;
		mInlineEdgeCache = new int32[SampleCount * 3];
		return;
#else
		let workers = Math.Max(1, Math.Min(6, (int)Platform.BfpSystem_GetNumLogicalCPUs(null) - 2));
		for (int i < workers)
		{
			let thread = new Thread(new => WorkerMain);
			thread.SetName("VoxelWorker");
			thread.Start(false);
			mThreads.Add(thread);
		}
#endif
	}

	public override void OnUnregister()
	{
		using (mMonitor.Enter())
		{
			mQuit = true;
			mJobs.Clear();
		}
		for (let thread in mThreads)
			mWake.Set(true);
		for (let thread in mThreads)
		{
			thread.Join();
			delete thread;
		}
		mThreads.Clear();
		mInline = false;
		// Chunk objects are children; when the terrain object itself is being destroyed they are already gone.
		for (let child in Transform.Children)
		{
			if (!child.GameObject.Transient)
				continue;
			let renderer = child.GameObject.GetComponent<MeshRenderer>();
			if (renderer != null)
				renderer.RuntimeMesh = null;
			Scene.Destroy(child.GameObject);
		}
		for (let chunk in mChunks.Values)
			delete chunk;
		mChunks.Clear();
		for (let chunk in mGraveyard)
			delete chunk;
		mGraveyard.Clear();
		mFinished.Clear();
	}

	void CaptureSettings()
	{
		mStyle = style;
		mMode = mode;
		mSizeX = Math.Clamp(sizeX, 1, 64);
		mSizeZ = Math.Clamp(sizeZ, 1, 64);
		mFlatHeight = flatHeight;
		mSeed = (uint32)seed;
		mVoxelSize = Math.Max(voxelSize, 0.05f);
		mTerrainHeight = terrainHeight;
		mTerrainScale = terrainScale;
		mCaveAmount = caveAmount;
		mSeaLevel = seaLevel;
		mGrass = grassColor;
		mRock = rockColor;
		mSand = sandColor;
		mSnow = snowColor;
		mDirt = dirtColor;
		mSettingsHash = (int32)style ^ seed * 31 ^ (int32)(voxelSize * 1000) ^ (int32)(terrainHeight * 100) * 7
			^ (int32)(terrainScale * 100000) * 13 ^ (int32)(caveAmount * 1000) * 17 ^ (int32)(seaLevel * 100) * 19
			^ (int32)grassColor.ToABGR() ^ (int32)rockColor.ToABGR() * 3 ^ (int32)sandColor.ToABGR() * 5
			^ (int32)snowColor.ToABGR() * 7 ^ (int32)dirtColor.ToABGR() * 11
			^ (int32)mode * 104729 ^ mSizeX * 7919 ^ mSizeZ * 6007 ^ (int32)(flatHeight * 100) * 23 ^ mGeneratorVersion * 4001;
	}

	/// A Fixed terrain shows the box it fills while selected.
	public override void OnDrawGizmos(bool selected)
	{
		if (mode != .Fixed || !selected)
			return;
		let area = AreaSize;
		let cell = ChunkCells * Math.Max(voxelSize, 0.05f);
		Gizmos.Lines.Box(Bounds(.(0, minChunkY * cell, 0), .(area.x, (maxChunkY + 1) * cell, area.y)), Transform.LocalToWorld, .(0.45f, 0.80f, 0.45f, 0.8f));
	}

	/// Inspector edits rebuild the whole terrain.
	public override void OnValidate()
	{
		let previous = mSettingsHash;
		CaptureSettings();
		bool regenerate = previous != mSettingsHash;
		if (!editsFile.IsEmpty && mLoadedEdits != editsFile)
		{
			mLoadedEdits.Set(editsFile);
			let path = scope String();
			Assets.ResolvePath(editsFile, path);
			regenerate |= LoadEdits(path);
		}
		if (regenerate && Streaming)
			Regenerate();
	}

	public override void OnBeforeSave()
	{
		if (!HasUnsavedEdits)
			return;
		if (editsFile.IsEmpty)
			editsFile.AppendF("Scenes/{}_{}.voxels", Scene.Name, GameObject.Id);
		mLoadedEdits.Set(editsFile);
		let path = scope String();
		Assets.ResolvePath(editsFile, path);
		let folder = scope String();
		if (System.IO.Path.GetDirectoryPath(path, folder) case .Ok)
			System.IO.Directory.CreateDirectory(folder).IgnoreError();
		if (SaveEdits(path))
			HasUnsavedEdits = false;
	}

	/// Keeps an edited chunk's data when the chunk itself is unloaded. Call with mMonitor held.
	void Stash(Chunk chunk)
	{
		if (!chunk.edited || chunk.density == null)
			return;
		if (mSaved.TryGetValue(chunk.coord, let old))
			delete old;
		let saved = new SavedChunk();
		saved.density = new int8[SampleCount];
		chunk.density.CopyTo(saved.density);
		if (chunk.paint != null)
		{
			saved.paint = new uint8[SampleCount];
			chunk.paint.CopyTo(saved.paint);
		}
		saved.appliedBrushes = chunk.appliedBrushes;
		mSaved[chunk.coord] = saved;
	}

	/// Writes every sculpted or painted chunk to a file.
	public bool SaveEdits(StringView path)
	{
		List<uint8> data = scope .();
		SaveEdits(data);
		if (System.IO.File.WriteAll(path, data) case .Err)
		{
			Log.Error(scope $"Could not write terrain edits to {path}");
			return false;
		}
		return true;
	}

	/// The same as bytes, for a game that keeps its terrain somewhere of its own (inside a map file, say).
	/// Returns how many chunks were written.
	public int32 SaveEdits(List<uint8> data)
	{
		void Put<T>(T value) where T : struct
		{
			var v = value;
			let start = data.Count;
			data.Count += sizeof(T);
			Internal.MemCpy(data.Ptr + start, &v, sizeof(T));
		}
		void PutChunk(Int3 coord, int8[] density, uint8[] paint)
		{
			Put(coord.x); Put(coord.y); Put(coord.z);
			Put((uint8)(paint != null ? 1 : 0));
			let start = data.Count;
			data.Count += SampleCount;
			Internal.MemCpy(data.Ptr + start, density.Ptr, SampleCount);
			if (paint != null)
			{
				let paintStart = data.Count;
				data.Count += SampleCount;
				Internal.MemCpy(data.Ptr + paintStart, paint.Ptr, SampleCount);
			}
		}
		using (mMonitor.Enter())
		{
			int32 count = 0;
			for (let chunk in mChunks.Values)
			{
				if (chunk.edited && chunk.generated)
					count++;
			}
			for (let entry in mSaved)
			{
				if (!mChunks.TryGetValue(entry.key, let live) || !live.edited)
					count++;
			}
			Put((uint32)0x584f5654); // "TVOX"
			Put((int32)1);
			Put((int32)Samples);
			Put(count);
			for (let chunk in mChunks.Values)
			{
				if (chunk.edited && chunk.generated)
					PutChunk(chunk.coord, chunk.density, chunk.paint);
			}
			for (let entry in mSaved)
			{
				if (!mChunks.TryGetValue(entry.key, let live) || !live.edited)
					PutChunk(entry.key, entry.value.density, entry.value.paint);
			}
			return count;
		}
	}

	/// Reads edited chunks from a file. Returns true when anything was loaded.
	public bool LoadEdits(StringView path)
	{
		List<uint8> data = scope .();
		if (AssetPack.ReadAll(path, data) case .Err)
			return false;
		if (!LoadEdits(Span<uint8>(data.Ptr, data.Count)))
		{
			if (data.Count < 16 || *(uint32*)data.Ptr != 0x584f5654)
				Log.Warning(scope $"{path} is not a compatible terrain edit file.");
			return false;
		}
		return true;
	}

	/// Takes edited chunks from bytes that SaveEdits wrote. Call Regenerate afterwards for a terrain that is
	/// already there. Returns true when anything was loaded.
	public bool LoadEdits(Span<uint8> data)
	{
		var reader = NetReader(data.Ptr, data.Length);
		if (reader.Read<uint32>() != 0x584f5654 || reader.Read<int32>() != 1 || reader.Read<int32>() != Samples)
			return false;
		let count = reader.Read<int32>();
		int offset = 16;
		using (mMonitor.Enter())
		{
			for (let entry in mSaved)
				delete entry.value;
			mSaved.Clear();
			for (int i < count)
			{
				if (offset + 13 + SampleCount > data.Length)
					break;
				Int3 coord = .(0, 0, 0);
				Internal.MemCpy(&coord, data.Ptr + offset, 12);
				let hasPaint = data[offset + 12] != 0;
				offset += 13;
				let saved = new SavedChunk();
				saved.density = new int8[SampleCount];
				Internal.MemCpy(saved.density.Ptr, data.Ptr + offset, SampleCount);
				offset += SampleCount;
				if (hasPaint && offset + SampleCount <= data.Length)
				{
					saved.paint = new uint8[SampleCount];
					Internal.MemCpy(saved.paint.Ptr, data.Ptr + offset, SampleCount);
					offset += SampleCount;
				}
				if (mSaved.TryGetValue(coord, let old))
					delete old;
				mSaved[coord] = saved;
			}
			return mSaved.Count > 0;
		}
	}

	/// Throws away every chunk (including edits) and generates the terrain again.
	public void Regenerate()
	{
		using (mMonitor.Enter())
		{
			mJobs.Clear();
			for (let chunk in mChunks.Values)
			{
				chunk.cancelled = true;
				Stash(chunk);
				RetireObject(chunk);
				mGraveyard.Add(chunk);
			}
			mChunks.Clear();
			mFinished.Clear();
		}
	}

	// ---- density field ----

	/// The shape of the ground before any sculpting: more than zero is solid, less is air, and the surface is where
	/// it crosses zero, so "height - y" makes ground up to that height. x, y and z are in the terrain's own space.
	public delegate float DensityFunction(float x, float y, float z);

	/// Replaces the built-in ground with a function of your own, for a game that generates its world its own way:
	/// islands, a planet, tunnels. It works in both modes (Fixed still cuts it off at the edge of the area).
	/// It is called from worker threads, many times at once, so it must only read data that does not change while
	/// the terrain is generating. Pass null to go back to the built-in ground. The terrain takes ownership.
	public void SetGenerator(DensityFunction generator)
	{
		using (mMonitor.Enter())
		{
			delete mGenerator;
			mGenerator = generator;
		}
		mGeneratorVersion++;
		CaptureSettings();
		if (Streaming)
			Regenerate();
	}

	/// True when a chunk is part of the terrain: any chunk in Endless mode, the set area in Fixed mode.
	public bool InArea(Int3 coord) => mMode == .Endless || (coord.x >= 0 && coord.x < mSizeX && coord.z >= 0 && coord.z < mSizeZ);

	/// The size of a Fixed terrain in metres along X and Z.
	public Vector2 AreaSize => .(Math.Clamp(sizeX, 1, 64) * ChunkCells * Math.Max(voxelSize, 0.05f), Math.Clamp(sizeZ, 1, 64) * ChunkCells * Math.Max(voxelSize, 0.05f));

	float SampleDensity(float wx, float wy, float wz)
	{
		if (mMode == .Fixed)
		{
			// Nothing beyond the edge of the area: the ground stops there, like the side of a table.
			let limitX = mSizeX * ChunkCells * mVoxelSize, limitZ = mSizeZ * ChunkCells * mVoxelSize;
			let inset = mVoxelSize * 0.5f;
			if (wx < inset || wz < inset || wx > limitX - inset || wz > limitZ - inset)
				return -8.0f;
			return mGenerator != null ? mGenerator(wx, wy, wz) : mFlatHeight - wy;
		}
		if (mGenerator != null)
			return mGenerator(wx, wy, wz);
		let scale = mTerrainScale;
		let continental = Noise.Fbm(wx * scale, 0, wz * scale, mSeed, 5);
		let ridges = 1.0f - Mathf.Abs(Noise.Fbm(wx * scale * 2.3f, 17.0f, wz * scale * 2.3f, mSeed + 7, 3));
		let height = continental * mTerrainHeight + ridges * ridges * mTerrainHeight * 0.35f;
		var density = height - wy;
		if (mCaveAmount > 0 && density > -4.0f)
		{
			let cave = Noise.Fbm(wx * 0.045f, wy * 0.06f, wz * 0.045f, mSeed + 31, 3);
			density -= Math.Max(0, cave - (0.42f - mCaveAmount * 0.4f)) * 60.0f;
		}
		return density;
	}

	void GenerateDensity(Chunk chunk)
	{
		if (chunk.density == null)
			chunk.density = new int8[SampleCount];
		using (mMonitor.Enter())
		{
			// Sculpted chunks come back exactly as they were saved.
			if (mSaved.TryGetValue(chunk.coord, let saved))
			{
				saved.density.CopyTo(chunk.density);
				if (saved.paint != null)
				{
					if (chunk.paint == null)
						chunk.paint = new uint8[SampleCount];
					saved.paint.CopyTo(chunk.paint);
				}
				chunk.edited = true;
				chunk.appliedBrushes = saved.appliedBrushes;
				chunk.generated = true;
				return;
			}
		}
		let size = mVoxelSize;
		let origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * (ChunkCells * size);
		int index = 0;
		for (int z < Samples)
		{
			for (int y < Samples)
			{
				for (int x < Samples)
				{
					let d = SampleDensity(origin.x + x * size, origin.y + y * size, origin.z + z * size) / size;
					chunk.density[index++] = (int8)Mathf.Clamp(d * 24.0f, -127, 127);
				}
			}
		}
		chunk.generated = true;
	}

	[Inline]
	static int SampleIndex(int x, int y, int z) => x + y * Samples + z * Samples * Samples;

	Color LayerColor(uint8 layer)
	{
		switch (layer)
		{
		case 1: return mGrass;
		case 2: return mRock;
		case 3: return mSand;
		case 4: return mSnow;
		default: return mDirt;
		}
	}

	Color SurfaceColor(float worldY, float slopeUp)
	{
		if (slopeUp < 0.55f)
			return slopeUp < 0.2f ? mDirt : mRock;
		if (worldY < mSeaLevel + 1.5f * mVoxelSize)
			return mSand;
		if (worldY > mTerrainHeight * 0.75f)
			return mSnow;
		return mGrass;
	}

	// ---- meshing (worker threads) ----

	void BuildSmooth(Chunk chunk, int32[] edgeCache)
	{
		let density = chunk.density;
		let size = mVoxelSize;
		let origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * (ChunkCells * size);
		for (int i < edgeCache.Count)
			edgeCache[i] = -1;

		int[8] cornerIndex = default;
		for (int c < 8)
			cornerIndex[c] = SampleIndex(MarchingTables.Corners[c * 3], MarchingTables.Corners[c * 3 + 1], MarchingTables.Corners[c * 3 + 2]);

		uint32[12] edgeVertex = default;
		for (int z < ChunkCells)
		{
			for (int y < ChunkCells)
			{
				for (int x < ChunkCells)
				{
					let cellBase = SampleIndex(x, y, z);
					int config = 0;
					for (int c < 8)
					{
						if (density[cellBase + cornerIndex[c]] <= 0)
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
						// Each grid edge is shared by up to four cells; cache its vertex by lower corner and axis.
						let lx = Math.Min(ax, bx), ly = Math.Min(ay, by), lz = Math.Min(az, bz);
						let axis = ax != bx ? 0 : (ay != by ? 1 : 2);
						let cacheIndex = SampleIndex(lx, ly, lz) * 3 + axis;
						var vertexIndex = edgeCache[cacheIndex];
						if (vertexIndex < 0)
						{
							let da = (float)density[SampleIndex(ax, ay, az)];
							let db = (float)density[SampleIndex(bx, by, bz)];
							let t = Mathf.Abs(da - db) > 0.001f ? Mathf.Clamp01(da / (da - db)) : 0.5f;
							let local = Vector3(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t);
							let normal = Vector3.Lerp(Gradient(density, ax, ay, az), Gradient(density, bx, by, bz), t).Normalized;
							let position = origin + local * size;
							vertexIndex = (int32)chunk.vertices.Count;
							var color = SurfaceColor(position.y, normal.y);
							if (chunk.paint != null)
							{
								let layer = chunk.paint[t < 0.5f ? SampleIndex(ax, ay, az) : SampleIndex(bx, by, bz)];
								if (layer != 0)
									color = LayerColor(layer);
							}
							chunk.vertices.Add(.(position, normal, color.ToABGR(), .(position.x, position.z)));
							edgeCache[cacheIndex] = vertexIndex;
						}
						edgeVertex[e] = (uint32)vertexIndex;
					}

					let row = config * 16;
					for (int i = 0; MarchingTables.Triangles[row + i] != -1; i += 3)
					{
						chunk.indices.Add(edgeVertex[MarchingTables.Triangles[row + i]]);
						chunk.indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 2]]);
						chunk.indices.Add(edgeVertex[MarchingTables.Triangles[row + i + 1]]);
					}
				}
			}
		}
	}

	/// Surface normal from the density gradient (points from solid towards empty).
	static Vector3 Gradient(int8[] density, int x, int y, int z)
	{
		let x0 = Math.Max(x - 1, 0), x1 = Math.Min(x + 1, Samples - 1);
		let y0 = Math.Max(y - 1, 0), y1 = Math.Min(y + 1, Samples - 1);
		let z0 = Math.Max(z - 1, 0), z1 = Math.Min(z + 1, Samples - 1);
		return .(
			(float)density[SampleIndex(x0, y, z)] - density[SampleIndex(x1, y, z)],
			(float)density[SampleIndex(x, y0, z)] - density[SampleIndex(x, y1, z)],
			(float)density[SampleIndex(x, y, z0)] - density[SampleIndex(x, y, z1)]);
	}

	void BuildBlocky(Chunk chunk)
	{
		let density = chunk.density;
		let size = mVoxelSize;
		let origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * (ChunkCells * size);
		// A chunk owns the faces between each of its cells and the next cell along +X, +Y and +Z.
		for (int z < ChunkCells)
		{
			for (int y < ChunkCells)
			{
				for (int x < ChunkCells)
				{
					let solid = density[SampleIndex(x, y, z)] > 0;
					let p = origin + Vector3(x, y, z) * size;
					for (int axis < 3)
					{
						let nx = x + (axis == 0 ? 1 : 0), ny = y + (axis == 1 ? 1 : 0), nz = z + (axis == 2 ? 1 : 0);
						let neighbor = density[SampleIndex(nx, ny, nz)] > 0;
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
		int32[] edgeCache = new int32[SampleCount * 3];
		defer delete edgeCache;
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
				}
			}
			if (chunk == null)
			{
				mWake.WaitFor(50);
				continue;
			}
			BuildChunk(chunk, edgeCache);
			using (mMonitor.Enter())
			{
				chunk.state = .Ready;
				mFinished.Add(chunk);
				mBusy--;
			}
		}
	}

	void BuildChunk(Chunk chunk, int32[] edgeCache)
	{
		if (!chunk.generated)
			GenerateDensity(chunk);
		chunk.vertices.Clear();
		chunk.indices.Clear();
		if (mStyle == .Smooth)
			BuildSmooth(chunk, edgeCache);
		else
			BuildBlocky(chunk);
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
			BuildChunk(chunk, mInlineEdgeCache);
			chunk.state = .Ready;
			mFinished.Add(chunk);
			if (SDL.SDL_GetTicksNS() - start > InlineBudgetNs)
				break;
		}
	}

	/// How long a web build spends building terrain chunks each frame.
	const uint64 InlineBudgetNs = 6 * 1000000;

	// ---- streaming (main thread) ----

	public override void OnFrame()
	{
		if (!Streaming)
			return;
		let chunkWorld = ChunkCells * mVoxelSize;
		let local = Transform.InverseTransformPoint(ViewerPosition);
		let centerX = (int32)Math.Floor(local.x / chunkWorld);
		let centerZ = (int32)Math.Floor(local.z / chunkWorld);

		// Queue missing chunks, nearest first because jobs are popped from the back.
		List<Chunk> added = scope .();
		if (mMode == .Fixed)
		{
			// The whole area is kept, wherever the camera is.
			for (int32 cz = 0; cz < mSizeZ; cz++)
			{
				for (int32 cx = 0; cx < mSizeX; cx++)
				{
					for (int32 cy = minChunkY; cy <= maxChunkY; cy++)
					{
						let coord = Int3(cx, cy, cz);
						if (mChunks.ContainsKey(coord))
							continue;
						let chunk = new Chunk();
						chunk.coord = coord;
						chunk.state = .Queued;
						mChunks[coord] = chunk;
						added.Add(chunk);
					}
				}
			}
		}
		else for (int32 dz = -viewDistance; dz <= viewDistance; dz++)
		{
			for (int32 dx = -viewDistance; dx <= viewDistance; dx++)
			{
				if (dx * dx + dz * dz > viewDistance * viewDistance)
					continue;
				for (int32 cy = minChunkY; cy <= maxChunkY; cy++)
				{
					let coord = Int3(centerX + dx, cy, centerZ + dz);
					if (mChunks.ContainsKey(coord))
						continue;
					let chunk = new Chunk();
					chunk.coord = coord;
					chunk.state = .Queued;
					mChunks[coord] = chunk;
					added.Add(chunk);
				}
			}
		}
		if (added.Count > 0)
		{
			added.Sort(scope (a, b) =>
				{
					let da = (a.coord.x - centerX) * (a.coord.x - centerX) + (a.coord.z - centerZ) * (a.coord.z - centerZ);
					let db = (b.coord.x - centerX) * (b.coord.x - centerX) + (b.coord.z - centerZ) * (b.coord.z - centerZ);
					return db <=> da;
				});
			using (mMonitor.Enter())
			{
				for (let chunk in added)
					mJobs.Add(chunk);
			}
			for (let thread in mThreads)
				mWake.Set(false);
		}

		// Drop chunks that fell out of range.
		let dropDistance = viewDistance + 2;
		List<Int3> remove = scope .();
		for (let chunk in mChunks.Values)
		{
			let dx = chunk.coord.x - centerX;
			let dz = chunk.coord.z - centerZ;
			if (mMode == .Fixed ? !InArea(chunk.coord) : (dx * dx + dz * dz > dropDistance * dropDistance))
				remove.Add(chunk.coord);
		}
		if (remove.Count > 0)
		{
			using (mMonitor.Enter())
			{
				for (let coord in remove)
				{
					let chunk = mChunks[coord];
					mChunks.Remove(coord);
					mJobs.Remove(chunk);
					mFinished.Remove(chunk);
					chunk.cancelled = true;
					Stash(chunk);
					RetireObject(chunk);
					mGraveyard.Add(chunk);
				}
			}
		}

		// Free retired chunks once no worker can still be touching them.
		using (mMonitor.Enter())
		{
			for (int i = mGraveyard.Count - 1; i >= 0; i--)
			{
				let chunk = mGraveyard[i];
				if (chunk.state != .Working)
				{
					mFinished.Remove(chunk);
					mGraveyard.RemoveAt(i);
					delete chunk;
				}
			}
		}

		if (mInline)
			BuildInline();

		// Upload finished meshes within the frame budget.
		for (int i < Math.Max(uploadsPerFrame, 1))
		{
			Chunk chunk = null;
			using (mMonitor.Enter())
			{
				if (mFinished.Count > 0)
				{
					chunk = mFinished[0];
					mFinished.RemoveAt(0);
				}
			}
			if (chunk == null)
				break;
			if (chunk.cancelled)
				continue;
			UploadChunk(chunk);
			// A chunk that streamed in after shared brush strokes were made gets them now.
			if (chunk.generated && chunk.appliedBrushes < mSessionBrushes.Count)
				CatchUp(chunk);
			if (chunk.dirty)
				QueueRemesh(chunk);
		}
	}

	void RetireObject(Chunk chunk)
	{
		if (chunk.gameObject == null)
			return;
		let renderer = chunk.gameObject.GetComponent<MeshRenderer>();
		if (renderer != null)
			renderer.RuntimeMesh = null;
		Scene.Destroy(chunk.gameObject);
		chunk.gameObject = null;
	}

	void UploadChunk(Chunk chunk)
	{
		chunk.state = .Uploaded;
		if (chunk.indices.Count == 0)
		{
			if (chunk.gameObject != null)
				chunk.gameObject.SetActive(false);
			return;
		}
		if (chunk.mesh == null)
			chunk.mesh = new Mesh();
		Swap!(chunk.mesh.Vertices, chunk.vertices);
		Swap!(chunk.mesh.Indices, chunk.indices);
		chunk.mesh.Upload();

		if (chunk.gameObject == null)
		{
			chunk.gameObject = Scene.CreateGameObject("VoxelChunk", Transform);
			chunk.gameObject.Transient = true;
			let renderer = chunk.gameObject.AddComponent<MeshRenderer>();
			renderer.RuntimeMesh = chunk.mesh;
			renderer.flatShading = true;
			renderer.roughness = 0.95f;
			if (generateColliders)
				chunk.gameObject.AddComponent<MeshCollider>();
		}
		else
		{
			chunk.gameObject.SetActive(true);
			// Rebuild the collision mesh for the new surface.
			let collider = chunk.gameObject.GetComponent<MeshCollider>();
			if (collider != null)
				collider.Refresh();
		}
	}

	void QueueRemesh(Chunk chunk)
	{
		using (mMonitor.Enter())
		{
			if (chunk.state == .Working || chunk.state == .Ready)
			{
				// A worker is on it, or its result is waiting for upload: redo afterwards.
				chunk.dirty = true;
				return;
			}
			if (chunk.state == .Queued)
				return;
			chunk.dirty = false;
			chunk.state = .Queued;
			mJobs.Add(chunk);
		}
		mWake.Set(false);
	}

	/// Adds (amount > 0) or removes (amount < 0) material inside a sphere given in world space.
	public void ModifySphere(Vector3 worldCenter, float radius, float amount)
	{
		Brush(worldCenter, radius, Math.Abs(amount), amount >= 0 ? .Raise : .Lower);
	}

	/// Applies a sculpting or painting brush in real time; only the chunks it touches are re-meshed.
	/// paintLayer: 1 grass, 2 rock, 3 sand, 4 snow, 5 dirt, 0 back to automatic. flattenHeight is a world Y.
	///
	/// In multiplayer the edit is applied on every machine. Called on a client it is sent to the server first and
	/// takes effect when the server passes it back, a moment later.
	public void Brush(Vector3 worldCenter, float radius, float strength, VoxelBrush mode, int32 paintLayer = 1, float flattenHeight = 0)
	{
		if (NetworkSync.RouteBrush(this, worldCenter, radius, strength, mode, paintLayer, flattenHeight))
			return;
		BrushStroke stroke;
		stroke.center = Transform.InverseTransformPoint(worldCenter);
		stroke.radius = radius;
		stroke.strength = strength;
		stroke.mode = mode;
		stroke.paintLayer = paintLayer;
		stroke.flattenLocal = Transform.InverseTransformPoint(.(worldCenter.x, flattenHeight, worldCenter.z)).y;
		// In a session the stroke is remembered, so chunks that are not loaded yet get it when they arrive.
		let shared = NetworkSync.InSession(Scene);
		if (shared)
			mSessionBrushes.Add(stroke);
		let chunkWorld = ChunkCells * mVoxelSize;
		let reach = radius + mVoxelSize;
		let center = stroke.center;
		let minC = Int3((int32)Math.Floor((center.x - reach) / chunkWorld), (int32)Math.Floor((center.y - reach) / chunkWorld), (int32)Math.Floor((center.z - reach) / chunkWorld));
		let maxC = Int3((int32)Math.Floor((center.x + reach) / chunkWorld), (int32)Math.Floor((center.y + reach) / chunkWorld), (int32)Math.Floor((center.z + reach) / chunkWorld));
		for (int32 cz = minC.z; cz <= maxC.z; cz++)
		{
			for (int32 cy = minC.y; cy <= maxC.y; cy++)
			{
				for (int32 cx = minC.x; cx <= maxC.x; cx++)
				{
					if (!mChunks.TryGetValue(Int3(cx, cy, cz), let chunk) || !chunk.generated)
						continue;
					if (shared)
						CatchUp(chunk);
					else
						ApplyStroke(chunk, stroke);
				}
			}
		}
	}

	/// Applies the session strokes a chunk has not had yet, in order.
	void CatchUp(Chunk chunk)
	{
		for (int i = chunk.appliedBrushes; i < mSessionBrushes.Count; i++)
			ApplyStroke(chunk, mSessionBrushes[i]);
		chunk.appliedBrushes = (int32)mSessionBrushes.Count;
	}

	/// Applies one stroke to one chunk; nothing happens if the stroke does not reach it.
	void ApplyStroke(Chunk chunk, BrushStroke stroke)
	{
		let size = mVoxelSize;
		let chunkWorld = ChunkCells * size;
		let center = stroke.center;
		let radius = stroke.radius;
		let strength = stroke.strength;
		let mode = stroke.mode;
		let paintLayer = stroke.paintLayer;
		let flattenLocal = stroke.flattenLocal;
		let reach = radius + size;
		let cx = chunk.coord.x, cy = chunk.coord.y, cz = chunk.coord.z;
		let origin = Vector3(cx, cy, cz) * chunkWorld;
		let x0 = Math.Max(0, (int)Math.Floor((center.x - reach - origin.x) / size));
		let x1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.x + reach - origin.x) / size));
		let y0 = Math.Max(0, (int)Math.Floor((center.y - reach - origin.y) / size));
		let y1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.y + reach - origin.y) / size));
		let z0 = Math.Max(0, (int)Math.Floor((center.z - reach - origin.z) / size));
		let z1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.z + reach - origin.z) / size));
		if (mode == .Paint && chunk.paint == null)
			chunk.paint = new uint8[SampleCount];
		let density = chunk.density;
		bool changed = false;
		for (int z = z0; z <= z1; z++)
		{
			for (int y = y0; y <= y1; y++)
			{
				for (int x = x0; x <= x1; x++)
				{
					let p = origin + Vector3(x, y, z) * size;
					let falloff = 1.0f - (p - center).Length / radius;
					if (falloff <= 0)
						continue;
					let index = SampleIndex(x, y, z);
					var value = (float)density[index];
					switch (mode)
					{
					case .Raise: value += strength * falloff * 48.0f;
					case .Lower: value -= strength * falloff * 48.0f;
					case .Flatten:
						let target = Mathf.Clamp((flattenLocal - p.y) / size * 24.0f, -127, 127);
						value = Mathf.Lerp(value, target, Math.Min(1.0f, strength * falloff));
					case .Smooth:
						let xa = Math.Max(x - 1, 0), xb = Math.Min(x + 1, Samples - 1);
						let ya = Math.Max(y - 1, 0), yb = Math.Min(y + 1, Samples - 1);
						let za = Math.Max(z - 1, 0), zb = Math.Min(z + 1, Samples - 1);
						let average = ((float)density[SampleIndex(xa, y, z)] + density[SampleIndex(xb, y, z)]
							+ density[SampleIndex(x, ya, z)] + density[SampleIndex(x, yb, z)]
							+ density[SampleIndex(x, y, za)] + density[SampleIndex(x, y, zb)]) / 6.0f;
						value = Mathf.Lerp(value, average, Math.Min(1.0f, strength * falloff));
					case .Paint:
						chunk.paint[index] = (uint8)paintLayer;
					}
					density[index] = (int8)Mathf.Clamp(value, -127, 127);
					changed = true;
				}
			}
		}
		if (changed)
		{
			chunk.edited = true;
			HasUnsavedEdits = true;
			QueueRemesh(chunk);
		}
	}

	/// Trilinear density at a point in the terrain's local space; false where no chunk is loaded.
	bool SampleLocal(Vector3 p, out float density)
	{
		density = -1;
		let size = mVoxelSize;
		let chunkWorld = ChunkCells * size;
		let coord = Int3((int32)Math.Floor(p.x / chunkWorld), (int32)Math.Floor(p.y / chunkWorld), (int32)Math.Floor(p.z / chunkWorld));
		if (!mChunks.TryGetValue(coord, let chunk) || !chunk.generated)
			return false;
		let fx = (p.x - coord.x * chunkWorld) / size;
		let fy = (p.y - coord.y * chunkWorld) / size;
		let fz = (p.z - coord.z * chunkWorld) / size;
		let x = Math.Min((int)fx, ChunkCells - 1), y = Math.Min((int)fy, ChunkCells - 1), z = Math.Min((int)fz, ChunkCells - 1);
		let tx = fx - x, ty = fy - y, tz = fz - z;
		let d = chunk.density;
		float S(int ix, int iy, int iz) => (float)d[SampleIndex(ix, iy, iz)];
		let c00 = S(x, y, z) + (S(x + 1, y, z) - S(x, y, z)) * tx;
		let c10 = S(x, y + 1, z) + (S(x + 1, y + 1, z) - S(x, y + 1, z)) * tx;
		let c01 = S(x, y, z + 1) + (S(x + 1, y, z + 1) - S(x, y, z + 1)) * tx;
		let c11 = S(x, y + 1, z + 1) + (S(x + 1, y + 1, z + 1) - S(x, y + 1, z + 1)) * tx;
		let c0 = c00 + (c10 - c00) * ty;
		let c1 = c01 + (c11 - c01) * ty;
		density = c0 + (c1 - c0) * tz;
		return true;
	}

	/// Ray against the voxel surface itself (no physics needed, so it also works in the editor).
	public bool Raycast(Ray worldRay, float maxDistance, out Vector3 point)
	{
		point = default;
		let toLocal = Transform.WorldToLocal;
		let origin = toLocal.TransformPoint(worldRay.origin);
		let direction = toLocal.TransformDirection(worldRay.direction).Normalized;
		let step = mVoxelSize * 0.5f;
		float previous = 0;
		bool started = false;
		for (float t = 0; t < maxDistance; t += step)
		{
			float density;
			if (!SampleLocal(origin + direction * t, out density))
			{
				started = false;
				continue;
			}
			if (density > 0 && started)
			{
				// Bisect between the last empty sample and this solid one.
				float lo = previous, hi = t;
				for (int i < 6)
				{
					let mid = (lo + hi) * 0.5f;
					float d;
					if (SampleLocal(origin + direction * mid, out d) && d > 0)
						hi = mid;
					else
						lo = mid;
				}
				point = Transform.TransformPoint(origin + direction * hi);
				return true;
			}
			if (density > 0)
				return false; // The ray starts inside the ground.
			previous = t;
			started = true;
		}
		return false;
	}
}
