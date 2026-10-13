using System;
using System.Collections;
using System.IO;
using System.Threading;

namespace Tessera;

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
	/// Square tiles placed by hand, flat until sculpted (or shaped by the terrain's generator).
	Fixed,
	/// Generated around the camera without end, by the terrain's generator.
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

/// One square tile of a terrain's grid.
struct TerrainTile
{
	/// Stays the same for the tile's whole life, wherever it is moved: its sculpting is filed under it.
	public int32 id;
	/// Its place in the grid, counted in tiles from the terrain object's position.
	public int32 x;
	public int32 z;

	public this(int32 id, int32 x, int32 z)
	{
		this.id = id;
		this.x = x;
		this.z = z;
	}
}

/// Voxel terrain made of square tiles on one grid, like Unity's terrain, with caves and overhangs. Tiles are placed
/// in the editor (the Tiles tool), sculpted and painted across their edges as one surface, and saved one file per
/// tile. Chunks are generated and meshed on worker threads; the main thread only uploads finished meshes.
/// Call Brush or ModifySphere to dig or build at runtime.
[Component]
class VoxelTerrain : Component
{
	public const int32 ChunkCells = 32;
	public const int32 Samples = ChunkCells + 1;
	const int32 SampleCount = Samples * Samples * Samples;
	const int32 FaceCount = Samples * Samples;
	/// What a sample holds where there is no ground at all: outside the tiles.
	const int8 Air = -127;

	/// Fixed: tiles placed by hand. Endless: generated around the camera for ever.
	public TerrainMode mode = .Fixed;
	/// How many chunks a tile has along each side; every tile of the grid is the same size. The default 4 at voxel
	/// size 1 makes tiles 128 m square. Choose it before sculpting: sculpting is kept per tile.
	[Range(1, 16)]
	public int32 tileSize = 4;
	/// How high flat ground starts, above the object's position.
	public float flatHeight = 0.0f;
	/// Fixed mode: load only the tiles near the camera (and near each player, on a server), within View Distance.
	/// Off: every tile is there all the time.
	public bool streamTiles = false;
	/// The class that shapes ground nobody has sculpted, one marked [TerrainGenerator]. Empty: flat ground in Fixed
	/// mode, the sample noise (seed, terrain height, scale, caves) in Endless mode. Chosen in the Terrain Tools.
	[HideInInspector]
	public String generator = new .() ~ delete _;
	public VoxelStyle style = .Smooth;
	public float voxelSize = 1.0f;
	/// Streaming radius in chunks: Endless mode, and Fixed mode with Stream Tiles.
	public int32 viewDistance = 6;
	public int32 minChunkY = -1;
	public int32 maxChunkY = 2;
	/// Chunks further than this many chunks from the camera are drawn with fewer triangles: half the detail beyond
	/// it, a quarter beyond twice as far, an eighth beyond four times. 0 draws everything in full. Collision always
	/// has the full detail. Smooth style only.
	[Range(0, 32)]
	public int32 lodDistance = 4;
	public int32 seed = 1337;
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
	/// The tiles, "id x z" each, separated by ';'. Changed with the Tiles tool, or AddTile, RemoveTile and MoveTile.
	[HideInInspector]
	public String tiles = new .() ~ delete _;
	[HideInInspector]
	public int32 nextTileId = 1;
	/// From before tiles: a rectangle of sizeX by sizeZ chunks. It is the terrain's shape while `tiles` is empty, so
	/// older scenes, and code that sets these, keep working; the first tile edit or scene save writes the tiles out.
	[HideInInspector]
	public int32 sizeX = 4;
	[HideInInspector]
	public int32 sizeZ = 4;
	/// Where sculpting is kept: a folder (relative to the project) with a file for each tile. Set when the scene is saved.
	[HideInInspector]
	public String editsFolder = new .() ~ delete _;
	/// From before tiles, when all the sculpting was in one file. It is read, and moved into editsFolder on the next save.
	[HideInInspector]
	public String editsFile = new .() ~ delete _;

	enum ChunkState { Queued, Working, Ready, Uploaded }

	class Chunk
	{
		public Int3 coord;
		/// The tile it is part of (-1 in Endless mode) and its place in that tile: how its sculpting is filed.
		public int32 tileId;
		public Int3 local;
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
		/// Its samples were being made when its sculpting changed: made again once that is done.
		public bool stale;
		/// The level of detail wanted (0 full, 1 half, 2 quarter, 3 eighth) and the one the mesh has.
		public int32 lod;
		public int32 builtLod = -1;
		/// The ground changed since the collision mesh was made.
		public bool shapeChanged = true;
		/// Set by the worker: whether this build made collision, and whether that is a mesh of its own.
		public bool builtCollision;
		public bool separateCollision;
		public List<MeshVertex> vertices = new .() ~ delete _;
		public List<uint32> indices = new .() ~ delete _;
		public List<MeshVertex> collisionVertices = new .() ~ delete _;
		public List<uint32> collisionIndices = new .() ~ delete _;
		public Mesh mesh ~ delete _;
		public Mesh collisionMesh ~ delete _;
		public GameObject gameObject;
	}

	class SavedChunk
	{
		public int8[] density ~ delete _;
		public uint8[] paint ~ delete _;
		public int32 appliedBrushes;
	}

	/// What the worker threads read, made on the main thread and never changed afterwards: a new one replaces it.
	class Snapshot
	{
		public TerrainMode mode;
		public int32 tileSize = 4;
		public float voxelSize = 1;
		public float flatHeight;
		public TerrainGenerator generator;
		public Dictionary<int64, int32> tiles = new .() ~ delete _;

		public int32 TileAt(int32 tx, int32 tz) => tiles.TryGetValue(TileKey(tx, tz), let id) ? id : 0;
		public float TileWorld => tileSize * ChunkCells * voxelSize;

		bool Occupied(float x, float z)
		{
			let w = TileWorld;
			return tiles.ContainsKey(TileKey((int32)Math.Floor(x / w), (int32)Math.Floor(z / w)));
		}

		/// True where there may be ground: inside the tiles, ending half a voxel before an edge with no tile beyond.
		public bool Inside(float x, float z)
		{
			if (mode == .Endless)
				return true;
			let inset = voxelSize * 0.5f;
			return Occupied(x - inset, z - inset) && Occupied(x + inset, z - inset) && Occupied(x - inset, z + inset) && Occupied(x + inset, z + inset);
		}

		/// The ground before sculpting, as samples hold it (the edge of the tiles is applied when meshing).
		public float Density(float x, float y, float z) => generator != null ? generator.Density(x, y, z) : flatHeight - y;

		/// Where a chunk's sculpting is filed. False for a chunk outside every tile.
		public bool Locate(Int3 coord, out int32 tileId, out Int3 local)
		{
			if (mode == .Endless)
			{
				tileId = -1;
				local = coord;
				return true;
			}
			let tx = FloorDiv(coord.x, tileSize), tz = FloorDiv(coord.z, tileSize);
			tileId = TileAt(tx, tz);
			local = .(coord.x - tx * tileSize, coord.y, coord.z - tz * tileSize);
			return tileId != 0;
		}
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

	/// Chunks as they were before and after some sculpting, for undo (BeginEditRecord, EndEditRecord).
	public class EditRecord
	{
		public class State
		{
			/// Null: not sculpted, so generated again.
			public int8[] density ~ delete _;
			public uint8[] paint ~ delete _;
		}
		public Dictionary<Int3, State> before = new .() ~ DeleteDictionaryAndValues!(_);
		public Dictionary<Int3, State> after = new .() ~ DeleteDictionaryAndValues!(_);
		public int32 Count => (int32)before.Count;
	}

	/// Every brush stroke of the current network session, in the order the server passed them on. Chunks stream in
	/// at different times on different machines, so a chunk that was not loaded when a stroke happened has the
	/// strokes it missed applied when it arrives; every machine ends up with the same terrain.
	List<BrushStroke> mSessionBrushes = new .() ~ delete _;

	/// Sculpting by tile id (-1: Endless mode, by chunk), then by chunk within the tile. Holds what is read from the
	/// files and chunks that are not loaded; loaded chunks hold their own. Tiles that are removed keep theirs here
	/// until the scene is saved, so undoing the removal brings the sculpting back.
	Dictionary<int32, Dictionary<Int3, SavedChunk>> mStore = new .() ~ { for (let entry in _) DeleteDictionaryAndValues!(entry.value); delete _; };
	String mLoadedEdits = new .() ~ delete _;
	String mLoadedFolder = new .() ~ delete _;
	/// True when sculpting, painting or tile changes have not been written to the files yet.
	[NonSerialized]
	public bool HasUnsavedEdits;

	List<TerrainTile> mTiles = new .() ~ delete _;
	String mAppliedTiles = new .() ~ delete _;
	int32 mAppliedSizeX, mAppliedSizeZ, mAppliedTileSize;
	Snapshot mSnap ~ delete _;
	/// Snapshots and generators replaced while a worker may still be reading them; freed when no worker is busy.
	List<Object> mRetired = new .() ~ DeleteContainerAndItems!(_);
	TerrainGenerator mNamedGenerator ~ delete _;
	String mNamedGeneratorName = new .() ~ delete _;
	TerrainGenerator mCodeGenerator ~ delete _;
	NoiseTerrainGenerator mSampleGenerator ~ delete _;
	int32 mGeneratorVersion;
	EditRecord mRecording;

	Dictionary<Int3, Chunk> mChunks = new .() ~ delete _;
	List<Chunk> mJobs = new .() ~ delete _;
	List<Chunk> mFinished = new .() ~ delete _;
	List<Chunk> mGraveyard = new .() ~ delete _;
	List<Thread> mThreads = new .() ~ delete _;
	/// Web builds have no worker threads: chunks are built on the main thread, a few milliseconds' worth a frame.
	bool mInline;
	MeshWork mInlineWork ~ delete _;
	/// True once the terrain is registered and building chunks, on workers or inline.
	bool Streaming => mThreads.Count > 0 || mInline;
	Monitor mMonitor = new .() ~ delete _;
	WaitEvent mWake = new .() ~ delete _;
	bool mQuit;
	int32 mBusy;
	// Copies of the settings read by worker threads.
	VoxelStyle mStyle;
	float mVoxelSize = 1, mTerrainHeight, mSeaLevel;
	bool mLodOn, mColliders;
	Color mGrass, mRock, mSand, mSnow, mDirt;
	int32 mSettingsHash;

	/// World position chunks are streamed around. The application sets this from the active camera.
	public static Vector3 ViewerPosition;
	/// More places to stream and give detail around, as well as ViewerPosition: a server fills it with its players.
	public static List<Vector3> Viewers = new .() ~ delete _;

	public int32 ChunkCount => (int32)mChunks.Count;
	public int32 PendingChunks
	{
		get
		{
			using (mMonitor.Enter())
				return (int32)(mJobs.Count + mFinished.Count) + mBusy;
		}
	}

	[Inline]
	static int32 FloorDiv(int32 a, int32 b) => a >= 0 ? a / b : -((-a + b - 1) / b);
	[Inline]
	static int64 TileKey(int32 x, int32 z) => ((int64)x << 32) | (int64)(uint32)z;
	[Inline]
	static int SampleIndex(int x, int y, int z) => x + y * Samples + z * Samples * Samples;
	static T[] Copy<T>(T[] source)
	{
		let copy = new T[source.Count];
		source.CopyTo(copy);
		return copy;
	}
	[Inline]
	static int8 Quantize(float density, float size) => (int8)Mathf.Clamp(density / size * 24.0f, -127, 127);

	public override void OnRegister()
	{
		ApplyTilesText();
		CaptureSettings();
#if BF_PLATFORM_WASM
		mInline = true;
		if (mInlineWork == null)
			mInlineWork = new MeshWork();
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
		mQuit = false;
		// Chunk objects are children; when the terrain object itself is being destroyed they are already gone.
		for (let child in Transform.Children)
		{
			if (!child.GameObject.Transient)
				continue;
			let renderer = child.GameObject.GetComponent<MeshRenderer>();
			if (renderer != null)
				renderer.RuntimeMesh = null;
			let collider = child.GameObject.GetComponent<MeshCollider>();
			if (collider != null)
				collider.CollisionMesh = null;
			Scene.Destroy(child.GameObject);
		}
		for (let chunk in mChunks.Values)
		{
			Stash(chunk);
			delete chunk;
		}
		mChunks.Clear();
		for (let chunk in mGraveyard)
			delete chunk;
		mGraveyard.Clear();
		mFinished.Clear();
		ClearAndDeleteItems!(mRetired);
	}

	void CaptureSettings()
	{
		if (mNamedGeneratorName != generator)
		{
			if (mNamedGenerator != null)
				mRetired.Add(mNamedGenerator);
			mNamedGenerator = TerrainGenerator.Create(generator);
			mNamedGeneratorName.Set(generator);
			if (mNamedGenerator == null && !generator.IsEmpty)
				Log.Warning(scope $"Terrain generator '{generator}' was not found: is the class marked [TerrainGenerator]?");
		}
		TerrainGenerator active = mCodeGenerator ?? mNamedGenerator;
		if (active == null && mode == .Endless)
		{
			if (mSampleGenerator == null)
				mSampleGenerator = new .();
			active = mSampleGenerator;
		}
		active?.Begin(this);

		let snap = new Snapshot();
		snap.mode = mode;
		snap.tileSize = Math.Clamp(tileSize, 1, 64);
		snap.voxelSize = Math.Max(voxelSize, 0.05f);
		snap.flatHeight = flatHeight;
		snap.generator = active;
		for (let tile in mTiles)
			snap.tiles[TileKey(tile.x, tile.z)] = tile.id;
		using (mMonitor.Enter())
		{
			if (mSnap != null)
				mRetired.Add(mSnap);
			mSnap = snap;
		}

		mStyle = style;
		mVoxelSize = snap.voxelSize;
		mTerrainHeight = terrainHeight;
		mSeaLevel = seaLevel;
		mColliders = generateColliders;
		mLodOn = lodDistance > 0 && style == .Smooth;
		mGrass = grassColor;
		mRock = rockColor;
		mSand = sandColor;
		mSnow = snowColor;
		mDirt = dirtColor;
		mSettingsHash = (int32)style ^ (int32)(voxelSize * 1000) ^ (int32)(terrainHeight * 100) * 7 ^ (int32)(seaLevel * 100) * 19
			^ (int32)grassColor.ToABGR() ^ (int32)rockColor.ToABGR() * 3 ^ (int32)sandColor.ToABGR() * 5
			^ (int32)snowColor.ToABGR() * 7 ^ (int32)dirtColor.ToABGR() * 11 ^ (int32)mode * 104729 ^ snap.tileSize * 7919
			^ (int32)(flatHeight * 100) * 23 ^ mGeneratorVersion * 4001 ^ (int32)generator.GetHashCode() * 13
			^ (generateColliders ? 1 << 20 : 0);
		// The sample generator's settings matter only when it is the one in use.
		if (active == mSampleGenerator && active != null)
			mSettingsHash ^= seed * 31 ^ (int32)(terrainScale * 100000) * 13 ^ (int32)(caveAmount * 1000) * 17 ^ (int32)(terrainHeight * 10) * 29;
	}

	/// A selected terrain shows its tiles.
	public override void OnDrawGizmos(bool selected)
	{
		if (mode != .Fixed || !selected)
			return;
		if (mSnap == null)
			ApplyTilesText();
		let w = TileWorldSize;
		let cell = ChunkCells * Math.Max(voxelSize, 0.05f);
		for (let tile in mTiles)
			Gizmos.Lines.Box(Bounds(.(tile.x * w, minChunkY * cell, tile.z * w), .((tile.x + 1) * w, (maxChunkY + 1) * cell, (tile.z + 1) * w)), Transform.LocalToWorld, .(0.45f, 0.80f, 0.45f, 0.8f));
	}

	/// Inspector edits rebuild what they change.
	public override void OnValidate()
	{
		let wasLod = mLodOn;
		if (mAppliedTiles != tiles || (tiles.IsEmpty && (mAppliedSizeX != sizeX || mAppliedSizeZ != sizeZ || mAppliedTileSize != tileSize)))
			ApplyTilesText();
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
		if (!editsFolder.IsEmpty && mLoadedFolder != editsFolder)
		{
			mLoadedFolder.Set(editsFolder);
			regenerate |= LoadEditFolder();
		}
		if (regenerate && Streaming)
			Regenerate();
		else if (wasLod != mLodOn)
		{
			// Collision has its own mesh only with level of detail on.
			for (let chunk in mChunks.Values)
			{
				if (!mLodOn)
					chunk.lod = 0;
				chunk.shapeChanged = true;
				QueueRemesh(chunk);
			}
		}
	}

	// ---- tiles ----

	/// The size of a tile in metres along X and Z.
	public float TileWorldSize => Math.Clamp(tileSize, 1, 64) * ChunkCells * Math.Max(voxelSize, 0.05f);

	public int32 TileCount
	{
		get
		{
			if (mSnap == null)
				ApplyTilesText();
			return (int32)mTiles.Count;
		}
	}

	/// Adds every tile to the list.
	public void GetTiles(List<TerrainTile> list)
	{
		if (mSnap == null)
			ApplyTilesText();
		list.AddRange(mTiles);
	}

	/// The id of the tile at a place in the grid, or 0 where there is none.
	public int32 TileAt(int32 x, int32 z)
	{
		if (mSnap == null)
			ApplyTilesText();
		for (let tile in mTiles)
		{
			if (tile.x == x && tile.z == z)
				return tile.id;
		}
		return 0;
	}

	public bool FindTile(int32 id, out TerrainTile tile)
	{
		if (mSnap == null)
			ApplyTilesText();
		for (let t in mTiles)
		{
			if (t.id == id)
			{
				tile = t;
				return true;
			}
		}
		tile = default;
		return false;
	}

	/// The grid place under a point in world space (on the terrain's ground plane).
	public void TileOfPoint(Vector3 world, out int32 x, out int32 z)
	{
		let local = Transform.InverseTransformPoint(world);
		let w = TileWorldSize;
		x = (int32)Math.Floor(local.x / w);
		z = (int32)Math.Floor(local.z / w);
	}

	/// Adds a flat tile at a place in the grid. Returns its id, or 0 if the place is taken.
	public int32 AddTile(int32 x, int32 z)
	{
		if (TileAt(x, z) != 0)
			return 0;
		int32 id = nextTileId;
		for (let tile in mTiles)
			id = Math.Max(id, tile.id + 1);
		nextTileId = id + 1;
		using (mMonitor.Enter())
		{
			// A tile made after an undone one can be given its id: it starts flat all the same.
			if (mStore.GetAndRemove(id) case .Ok(let old))
				DeleteDictionaryAndValues!(old.value);
		}
		let list = scope List<TerrainTile>(mTiles);
		list.Add(.(id, x, z));
		SetTiles(list);
		return id;
	}

	/// Takes a tile away, leaving a hole. Its sculpting is kept until the scene is saved, so undo can bring it back.
	public bool RemoveTile(int32 id)
	{
		let list = scope List<TerrainTile>(mTiles);
		for (int i < list.Count)
		{
			if (list[i].id == id)
			{
				list.RemoveAt(i);
				SetTiles(list);
				return true;
			}
		}
		return false;
	}

	/// Moves a tile, with its sculpting, to an empty place in the grid.
	public bool MoveTile(int32 id, int32 x, int32 z)
	{
		let other = TileAt(x, z);
		if (other != 0)
			return other == id;
		let list = scope List<TerrainTile>(mTiles);
		for (int i < list.Count)
		{
			if (list[i].id == id)
			{
				list[i].x = x;
				list[i].z = z;
				SetTiles(list);
				return true;
			}
		}
		return false;
	}

	/// Replaces the whole set of tiles. Tiles keep their sculpting by id, wherever they are.
	public void SetTiles(Span<TerrainTile> newTiles)
	{
		if (mSnap == null)
			ApplyTilesText();
		let text = scope String();
		int32 highest = 0;
		for (let tile in newTiles)
		{
			if (!text.IsEmpty)
				text.Append(';');
			text.AppendF("{} {} {}", tile.id, tile.x, tile.z);
			highest = Math.Max(highest, tile.id);
		}
		tiles.Set(text);
		nextTileId = Math.Max(nextTileId, highest + 1);
		ApplyTilesText();
		HasUnsavedEdits = true;
	}

	/// The tiles as `tiles` (or, while that is empty, sizeX and sizeZ) say, put into effect.
	void ApplyTilesText()
	{
		let list = scope List<TerrainTile>();
		if (!tiles.IsEmpty)
		{
			for (let entry in tiles.Split(';'))
			{
				var parts = entry.Split(' ', .RemoveEmptyEntries);
				let id = int32.Parse(parts.GetNext().GetValueOrDefault()).GetValueOrDefault();
				let x = int32.Parse(parts.GetNext().GetValueOrDefault()).GetValueOrDefault();
				let z = int32.Parse(parts.GetNext().GetValueOrDefault()).GetValueOrDefault();
				if (id <= 0)
					continue;
				bool taken = false;
				for (let tile in list)
					taken |= tile.id == id || (tile.x == x && tile.z == z);
				if (!taken)
					list.Add(.(id, x, z));
			}
		}
		else
		{
			// A rectangle of chunks from before tiles: tiles as big as fit it exactly, numbered by place.
			let sx = Math.Clamp(sizeX, 1, 256), sz = Math.Clamp(sizeZ, 1, 256);
			var size = Math.Clamp(tileSize, 1, 64);
			if (sx % size != 0 || sz % size != 0)
			{
				int32 a = sx, b = sz;
				while (b != 0)
				{
					let r = a % b;
					a = b;
					b = r;
				}
				size = Math.Min(a, 64);
				tileSize = size;
			}
			for (int32 z < sz / size)
				for (int32 x < sx / size)
					list.Add(.(1 + x + z * 256, x, z));
		}
		mAppliedTiles.Set(tiles);
		mAppliedSizeX = sizeX;
		mAppliedSizeZ = sizeZ;
		mAppliedTileSize = tileSize;

		if (mSnap == null)
		{
			mTiles.Set(list);
			return;
		}

		// What moved or went: their chunks are put away under their tile first, then the new layout takes over.
		Dictionary<int32, TerrainTile> before = scope .();
		for (let tile in mTiles)
			before[tile.id] = tile;
		HashSet<int32> gone = scope .();
		List<TerrainTile> changed = scope .();
		for (let tile in mTiles)
		{
			bool kept = false;
			for (let now in list)
			{
				if (now.id == tile.id)
				{
					kept = now.x == tile.x && now.z == tile.z;
					break;
				}
			}
			if (!kept)
			{
				gone.Add(tile.id);
				changed.Add(tile);
			}
		}
		for (let tile in list)
		{
			if (!before.TryGetValue(tile.id, let old) || old.x != tile.x || old.z != tile.z)
				changed.Add(tile);
		}
		if (changed.Count == 0)
		{
			mTiles.Set(list);
			return;
		}
		using (mMonitor.Enter())
		{
			List<Chunk> drop = scope .();
			for (let chunk in mChunks.Values)
			{
				if (gone.Contains(chunk.tileId))
					drop.Add(chunk);
			}
			for (let chunk in drop)
				DropChunk(chunk);
		}
		mTiles.Set(list);
		CaptureSettings();
		// Chunks along the changed tiles' edges now end (or no longer end) there.
		let size = Math.Clamp(tileSize, 1, 64);
		for (let chunk in mChunks.Values)
		{
			for (let tile in changed)
			{
				if (chunk.coord.x >= tile.x * size - 1 && chunk.coord.x <= (tile.x + 1) * size && chunk.coord.z >= tile.z * size - 1 && chunk.coord.z <= (tile.z + 1) * size)
				{
					chunk.shapeChanged = true;
					QueueRemesh(chunk);
					break;
				}
			}
		}
	}

	/// Writes the tiles out to `tiles`, if they still come from the old rectangle.
	void WriteTilesOut()
	{
		if (!tiles.IsEmpty || mode != .Fixed)
			return;
		if (mSnap == null)
			ApplyTilesText();
		let list = scope List<TerrainTile>(mTiles);
		SetTiles(list);
	}

	// ---- sculpting kept per tile ----

	SavedChunk FindSaved(int32 tileId, Int3 local)
	{
		if (mStore.TryGetValue(tileId, let chunks) && chunks.TryGetValue(local, let saved))
			return saved;
		return null;
	}

	/// Files a chunk's sculpting, replacing what was there. Call with mMonitor held.
	void PutSaved(int32 tileId, Int3 local, SavedChunk saved)
	{
		Dictionary<Int3, SavedChunk> chunks;
		if (!mStore.TryGetValue(tileId, out chunks))
		{
			chunks = new .();
			mStore[tileId] = chunks;
		}
		if (chunks.TryGetValue(local, let old))
			delete old;
		chunks[local] = saved;
	}

	void RemoveSaved(int32 tileId, Int3 local)
	{
		if (mStore.TryGetValue(tileId, let chunks) && chunks.GetAndRemove(local) case .Ok(let entry))
			delete entry.value;
	}

	/// Keeps an edited chunk's data, for when the chunk itself is unloaded or saved. Call with mMonitor held.
	void Stash(Chunk chunk)
	{
		if (!chunk.edited || chunk.density == null || !chunk.generated)
			return;
		let saved = new SavedChunk();
		saved.density = new int8[SampleCount];
		chunk.density.CopyTo(saved.density);
		if (chunk.paint != null)
		{
			saved.paint = new uint8[SampleCount];
			chunk.paint.CopyTo(saved.paint);
		}
		saved.appliedBrushes = chunk.appliedBrushes;
		PutSaved(chunk.tileId, chunk.local, saved);
	}

	/// Files the sculpting of every loaded chunk.
	void Flush()
	{
		using (mMonitor.Enter())
		{
			for (let chunk in mChunks.Values)
				Stash(chunk);
		}
	}

	/// Takes a chunk out of the terrain, keeping its sculpting. Call with mMonitor held.
	void DropChunk(Chunk chunk)
	{
		mChunks.Remove(chunk.coord);
		mJobs.Remove(chunk);
		mFinished.Remove(chunk);
		chunk.cancelled = true;
		Stash(chunk);
		RetireObject(chunk);
		mGraveyard.Add(chunk);
	}

	/// Reads the sculpting files named in the fields, if that has not happened yet (a terrain made in code, or one
	/// saved before it was ever validated): saving must not write over what it never read.
	void EnsureEditsRead()
	{
		if (mSnap == null)
		{
			ApplyTilesText();
			CaptureSettings();
		}
		if (!editsFile.IsEmpty && mLoadedEdits != editsFile)
		{
			mLoadedEdits.Set(editsFile);
			let path = scope String();
			Assets.ResolvePath(editsFile, path);
			if (LoadEdits(path) && Streaming)
				Regenerate();
		}
		if (!editsFolder.IsEmpty && mLoadedFolder != editsFolder)
		{
			mLoadedFolder.Set(editsFolder);
			if (LoadEditFolder() && Streaming)
				Regenerate();
		}
	}

	public override void OnBeforeSave()
	{
		EnsureEditsRead();
		let legacy = !editsFile.IsEmpty;
		WriteTilesOut();
		if (!HasUnsavedEdits && !legacy)
			return;
		Flush();
		bool any = false;
		using (mMonitor.Enter())
		{
			for (let entry in mStore)
				any |= entry.value.Count > 0;
		}
		if (editsFolder.IsEmpty && !any)
		{
			// Nothing sculpted: no files.
			HasUnsavedEdits = false;
			editsFile.Clear();
			mLoadedEdits.Clear();
			return;
		}
		if (editsFolder.IsEmpty)
			editsFolder.AppendF("Scenes/{}_{}.terrain", Scene.Name, GameObject.Id);
		mLoadedFolder.Set(editsFolder);
		let path = scope String();
		Assets.ResolvePath(editsFolder, path);
		if (WriteEditFolder(path))
		{
			HasUnsavedEdits = false;
			editsFile.Clear();
			mLoadedEdits.Clear();
		}
	}

	static void TileFileName(int32 tileId, String name)
	{
		if (tileId < 0)
			name.Append("endless.voxels");
		else
			name.AppendF("tile_{}.voxels", tileId);
	}

	/// Writes a file for each tile with sculpting, and removes the files of tiles that are gone.
	public bool WriteEditFolder(StringView folder)
	{
		Flush();
		Directory.CreateDirectory(folder).IgnoreError();
		if (!Directory.Exists(folder))
		{
			Log.Error(scope $"Could not make the terrain folder {folder}");
			return false;
		}
		HashSet<String> keep = scope .();
		defer { for (let name in keep) delete name; }
		bool ok = true;
		List<int32> ids = scope .();
		for (let tile in mTiles)
			ids.Add(tile.id);
		if (mode == .Endless)
			ids.Add(-1);
		for (let id in ids)
		{
			List<uint8> data = scope .();
			using (mMonitor.Enter())
			{
				if (!mStore.TryGetValue(id, let chunks) || chunks.Count == 0)
					continue;
				EncodeTile(id, chunks, data);
			}
			let name = new String();
			TileFileName(id, name);
			keep.Add(name);
			if (File.WriteAll(scope $"{folder}/{name}", data) case .Err)
			{
				Log.Error(scope $"Could not write terrain sculpting to {folder}/{name}");
				ok = false;
			}
		}
		for (let entry in Directory.EnumerateFiles(folder, "*.voxels"))
		{
			let name = entry.GetFileName(.. scope .());
			if (!keep.Contains(name))
				File.Delete(entry.GetFilePath(.. scope .())).IgnoreError();
		}
		return ok;
	}

	/// Reads the file of every tile from editsFolder. Returns true when anything was loaded.
	bool LoadEditFolder()
	{
		let folder = scope String();
		Assets.ResolvePath(editsFolder, folder);
		bool any = false;
		List<int32> ids = scope .();
		for (let tile in mTiles)
			ids.Add(tile.id);
		ids.Add(-1);
		for (let id in ids)
		{
			let name = scope String();
			TileFileName(id, name);
			List<uint8> data = scope .();
			if (AssetPack.ReadAll(scope $"{folder}/{name}", data) case .Err)
				continue;
			if (!DecodeTile(Span<uint8>(data.Ptr, data.Count)))
				Log.Warning(scope $"{folder}/{name} is not a terrain sculpting file this version can read.");
			else
				any = true;
		}
		return any;
	}

	const uint32 FileMagic = 0x584f5654; // "TVOX"

	static void Put<T>(List<uint8> data, T value) where T : struct
	{
		var v = value;
		let start = data.Count;
		data.Count += sizeof(T);
		Internal.MemCpy(data.Ptr + start, &v, sizeof(T));
	}

	static void PutChunk(List<uint8> data, Int3 coord, int8[] density, uint8[] paint)
	{
		Put(data, coord.x); Put(data, coord.y); Put(data, coord.z);
		Put(data, (uint8)(paint != null ? 1 : 0));
		var start = data.Count;
		data.Count += SampleCount;
		Internal.MemCpy(data.Ptr + start, density.Ptr, SampleCount);
		if (paint != null)
		{
			start = data.Count;
			data.Count += SampleCount;
			Internal.MemCpy(data.Ptr + start, paint.Ptr, SampleCount);
		}
	}

	/// One tile's file: "TVOX", version 2, samples per side, the tile id, then its chunks by their place in the tile.
	static void EncodeTile(int32 tileId, Dictionary<Int3, SavedChunk> chunks, List<uint8> data)
	{
		Put(data, FileMagic);
		Put(data, (int32)2);
		Put(data, (int32)Samples);
		Put(data, tileId);
		Put(data, (int32)chunks.Count);
		for (let entry in chunks)
			PutChunk(data, entry.key, entry.value.density, entry.value.paint);
	}

	/// Reads chunks written by PutChunk, from offset on; calls back for each.
	static int ReadChunks(Span<uint8> data, int start, int32 count, delegate void(Int3 coord, SavedChunk saved) take)
	{
		var offset = start;
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
			take(coord, saved);
		}
		return offset;
	}

	bool DecodeTile(Span<uint8> data)
	{
		if (data.Length < 20)
			return false;
		var reader = NetReader(data.Ptr, data.Length);
		if (reader.Read<uint32>() != FileMagic || reader.Read<int32>() != 2 || reader.Read<int32>() != Samples)
			return false;
		let tileId = reader.Read<int32>();
		let count = reader.Read<int32>();
		using (mMonitor.Enter())
		{
			if (mStore.GetAndRemove(tileId) case .Ok(let old))
				DeleteDictionaryAndValues!(old.value);
			ReadChunks(data, 20, count, scope (coord, saved) => PutSaved(tileId, coord, saved));
		}
		return true;
	}

	/// Writes every sculpted or painted chunk to one file (the format from before tiles, which LoadEdits reads).
	public bool SaveEdits(StringView path)
	{
		List<uint8> data = scope .();
		SaveEdits(data);
		if (File.WriteAll(path, data) case .Err)
		{
			Log.Error(scope $"Could not write terrain edits to {path}");
			return false;
		}
		return true;
	}

	/// The same as bytes, for a game that keeps its terrain somewhere of its own (inside a map file, say). Chunks are
	/// stored by where they are, not by tile. Returns how many chunks were written.
	public int32 SaveEdits(List<uint8> data)
	{
		if (mSnap == null)
			ApplyTilesText();
		Flush();
		let size = Math.Clamp(tileSize, 1, 64);
		int32 count = 0;
		List<uint8> body = scope .();
		using (mMonitor.Enter())
		{
			if (mode == .Endless)
			{
				if (mStore.TryGetValue(-1, let chunks))
				{
					for (let entry in chunks)
					{
						PutChunk(body, entry.key, entry.value.density, entry.value.paint);
						count++;
					}
				}
			}
			else for (let tile in mTiles)
			{
				if (!mStore.TryGetValue(tile.id, let chunks))
					continue;
				for (let entry in chunks)
				{
					PutChunk(body, .(entry.key.x + tile.x * size, entry.key.y, entry.key.z + tile.z * size), entry.value.density, entry.value.paint);
					count++;
				}
			}
		}
		Put(data, FileMagic);
		Put(data, (int32)1);
		Put(data, (int32)Samples);
		Put(data, count);
		data.AddRange(body);
		return count;
	}

	/// Reads edited chunks from a file that SaveEdits(path) wrote. Returns true when anything was loaded.
	public bool LoadEdits(StringView path)
	{
		List<uint8> data = scope .();
		if (AssetPack.ReadAll(path, data) case .Err)
			return false;
		if (!LoadEdits(Span<uint8>(data.Ptr, data.Count)))
		{
			if (data.Count < 16 || *(uint32*)data.Ptr != FileMagic)
				Log.Warning(scope $"{path} is not a compatible terrain edit file.");
			return false;
		}
		return true;
	}

	/// Takes edited chunks from bytes that SaveEdits wrote, in place of all the sculpting the terrain had: each goes
	/// to the tile where it is. Call Regenerate afterwards for a terrain that is already there. Returns true when
	/// anything was loaded.
	public bool LoadEdits(Span<uint8> data)
	{
		if (data.Length < 16)
			return false;
		var reader = NetReader(data.Ptr, data.Length);
		if (reader.Read<uint32>() != FileMagic || reader.Read<int32>() != 1 || reader.Read<int32>() != Samples)
			return false;
		let count = reader.Read<int32>();
		if (mSnap == null)
		{
			ApplyTilesText();
			CaptureSettings();
		}
		let snap = mSnap;
		bool any = false;
		using (mMonitor.Enter())
		{
			for (let entry in mStore)
				DeleteDictionaryAndValues!(entry.value);
			mStore.Clear();
			ReadChunks(data, 16, count, scope [&] (coord, saved) =>
				{
					if (snap.Locate(coord, let tileId, let local))
					{
						PutSaved(tileId, local, saved);
						any = true;
					}
					else
						delete saved;
				});
		}
		return any;
	}

	/// Throws away every loaded chunk and makes the terrain again from the settings and the sculpting.
	public void Regenerate()
	{
		if (mAppliedTiles != tiles || (tiles.IsEmpty && (mAppliedSizeX != sizeX || mAppliedSizeZ != sizeZ)))
			ApplyTilesText();
		CaptureSettings();
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

	// ---- the ground ----

	/// The shape of the ground before any sculpting: more than zero is solid, less is air, and the surface is where
	/// it crosses zero, so "height - y" makes ground up to that height. x, y and z are in the terrain's own space.
	public delegate float DensityFunction(float x, float y, float z);

	/// Replaces the ground's shape with a function, for a game that makes its world in code (a TerrainGenerator
	/// class named in the Generator field does the same, and can be chosen in the editor). It is called from worker
	/// threads, many times at once, so it must only read data that does not change while the terrain is
	/// generating. Pass null to go back to the Generator field. The terrain takes ownership.
	public void SetGenerator(DensityFunction shape)
	{
		if (mCodeGenerator != null)
		{
			using (mMonitor.Enter())
				mRetired.Add(mCodeGenerator);
		}
		mCodeGenerator = shape != null ? new FunctionTerrainGenerator(shape) : null;
		mGeneratorVersion++;
		if (mSnap != null)
			CaptureSettings();
		if (Streaming)
			Regenerate();
	}

	/// Replaces the ground of one tile with what a generator makes, as if it had been sculpted that way; the edge it
	/// shares with other tiles takes the new ground too, so there is no gap. The caller keeps the generator.
	public bool ApplyGenerator(TerrainGenerator source, int32 tileId)
	{
		if (source == null)
			return false;
		TerrainTile tile;
		if (!FindTile(tileId, out tile))
			return false;
		source.Begin(this);
		let size = Math.Clamp(tileSize, 1, 64);
		let step = mVoxelSize;
		let chunkWorld = ChunkCells * step;
		Dictionary<Int3, int8[]> made = scope .();
		defer { for (let entry in made) delete entry.value; }
		Dictionary<Int3, uint8[]> painted = scope .();
		defer { for (let entry in painted) delete entry.value; }
		for (int32 lz < size)
			for (int32 lx < size)
				for (int32 cy = minChunkY; cy <= maxChunkY; cy++)
				{
					let coord = Int3(tile.x * size + lx, cy, tile.z * size + lz);
					let density = new int8[SampleCount];
					let paint = source.Paints ? new uint8[SampleCount] : null;
					let origin = Vector3(coord.x, coord.y, coord.z) * chunkWorld;
					int index = 0;
					for (int z < Samples)
						for (int y < Samples)
							for (int x < Samples)
							{
								let wx = origin.x + x * step, wy = origin.y + y * step, wz = origin.z + z * step;
								density[index] = Quantize(source.Density(wx, wy, wz), step);
								if (paint != null)
									paint[index] = source.Paint(wx, wy, wz);
								index++;
							}
					made[coord] = density;
					if (paint != null)
						painted[coord] = paint;
				}
		using (mMonitor.Enter())
		{
			for (let entry in made)
			{
				let coord = entry.key;
				let local = Int3(coord.x - tile.x * size, coord.y, coord.z - tile.z * size);
				mChunks.TryGetValue(coord, let chunk);
				if (chunk != null && chunk.generated)
				{
					Record(chunk.coord);
					entry.value.CopyTo(chunk.density);
					if (painted.TryGetValue(coord, let paint))
					{
						if (chunk.paint == null)
							chunk.paint = new uint8[SampleCount];
						paint.CopyTo(chunk.paint);
					}
					else
						DeleteAndNullify!(chunk.paint);
					chunk.edited = true;
					chunk.shapeChanged = true;
				}
				else
				{
					Record(coord);
					let saved = new SavedChunk();
					saved.density = new int8[SampleCount];
					entry.value.CopyTo(saved.density);
					if (painted.TryGetValue(coord, let paint))
					{
						saved.paint = new uint8[SampleCount];
						paint.CopyTo(saved.paint);
					}
					PutSaved(tileId, local, saved);
					// A chunk on its way: it is made again with the new ground.
					if (chunk != null)
						chunk.stale = true;
				}
			}
		}
		for (let entry in made)
		{
			if (mChunks.TryGetValue(entry.key, let chunk))
				QueueRemesh(chunk);
		}
		// The neighbours' copies of the shared edge.
		for (let chunk in mChunks.Values)
		{
			if (made.ContainsKey(chunk.coord) || !chunk.generated)
				continue;
			bool touched = false;
			for (int32 dz = -1; dz <= 1; dz++)
				for (int32 dy = -1; dy <= 1; dy++)
					for (int32 dx = -1; dx <= 1; dx++)
					{
						let other = Int3(chunk.coord.x + dx, chunk.coord.y + dy, chunk.coord.z + dz);
						if (!made.TryGetValue(other, let density))
							continue;
						if (!touched)
							Record(chunk.coord);
						painted.TryGetValue(other, let paint);
						if (paint != null && chunk.paint == null)
							chunk.paint = new uint8[SampleCount];
						CopyShared(chunk.density, chunk.paint, density, paint, dx, dy, dz);
						touched = true;
					}
			if (touched)
			{
				chunk.edited = true;
				chunk.shapeChanged = true;
				QueueRemesh(chunk);
			}
		}
		HasUnsavedEdits = true;
		return true;
	}

	/// Copies the samples a chunk shares with its neighbour at (dx, dy, dz) from the neighbour's arrays.
	static void CopyShared(int8[] density, uint8[] paint, int8[] fromDensity, uint8[] fromPaint, int32 dx, int32 dy, int32 dz)
	{
		void Range(int32 d, out int mine0, out int mine1, out int theirs0)
		{
			if (d < 0) { mine0 = 0; mine1 = 0; theirs0 = ChunkCells; }
			else if (d > 0) { mine0 = ChunkCells; mine1 = ChunkCells; theirs0 = 0; }
			else { mine0 = 0; mine1 = ChunkCells; theirs0 = 0; }
		}
		Range(dx, let x0, let x1, let tx);
		Range(dy, let y0, let y1, let ty);
		Range(dz, let z0, let z1, let tz);
		for (int z = z0; z <= z1; z++)
			for (int y = y0; y <= y1; y++)
				for (int x = x0; x <= x1; x++)
				{
					let mine = SampleIndex(x, y, z);
					let theirs = SampleIndex(tx + x - x0, ty + y - y0, tz + z - z0);
					density[mine] = fromDensity[theirs];
					if (paint != null && fromPaint != null)
						paint[mine] = fromPaint[theirs];
				}
	}

	/// True when a chunk is part of the terrain: any chunk in Endless mode, a chunk of a tile in Fixed mode.
	public bool InArea(Int3 coord)
	{
		if (mSnap == null)
			ApplyTilesText();
		if (mode == .Endless)
			return true;
		let size = Math.Clamp(tileSize, 1, 64);
		return TileAt(FloorDiv(coord.x, size), FloorDiv(coord.z, size)) != 0;
	}

	/// The size in metres, along X and Z, of the rectangle the tiles span.
	public Vector2 AreaSize
	{
		get
		{
			if (mSnap == null)
				ApplyTilesText();
			if (mTiles.Count == 0)
				return .Zero;
			int32 x0 = int32.MaxValue, z0 = int32.MaxValue, x1 = int32.MinValue, z1 = int32.MinValue;
			for (let tile in mTiles)
			{
				x0 = Math.Min(x0, tile.x); x1 = Math.Max(x1, tile.x);
				z0 = Math.Min(z0, tile.z); z1 = Math.Max(z1, tile.z);
			}
			let w = TileWorldSize;
			return .((x1 - x0 + 1) * w, (z1 - z0 + 1) * w);
		}
	}

	/// Fills a chunk's samples: its sculpting if it has any, otherwise the generator's ground, taking the samples it
	/// shares with sculpted neighbours from them so the surface meets theirs. Runs on worker threads.
	void GenerateDensity(Chunk chunk, Snapshot snap)
	{
		if (chunk.density == null)
			chunk.density = new int8[SampleCount];
		using (mMonitor.Enter())
		{
			// Sculpted chunks come back exactly as they were saved.
			let saved = FindSaved(chunk.tileId, chunk.local);
			if (saved != null)
			{
				saved.density.CopyTo(chunk.density);
				if (saved.paint != null)
				{
					if (chunk.paint == null)
						chunk.paint = new uint8[SampleCount];
					saved.paint.CopyTo(chunk.paint);
				}
				else
					DeleteAndNullify!(chunk.paint);
				chunk.edited = true;
				chunk.appliedBrushes = saved.appliedBrushes;
				chunk.generated = true;
				return;
			}
		}
		let size = snap.voxelSize;
		let origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * (ChunkCells * size);
		let generator = snap.generator;
		let paints = generator != null && generator.Paints;
		if (paints && chunk.paint == null)
			chunk.paint = new uint8[SampleCount];
		else if (!paints)
			DeleteAndNullify!(chunk.paint);
		int index = 0;
		for (int z < Samples)
		{
			for (int y < Samples)
			{
				for (int x < Samples)
				{
					let wx = origin.x + x * size, wy = origin.y + y * size, wz = origin.z + z * size;
					chunk.density[index] = Quantize(snap.Density(wx, wy, wz), size);
					if (paints)
						chunk.paint[index] = generator.Paint(wx, wy, wz);
					index++;
				}
			}
		}
		chunk.edited = false;
		using (mMonitor.Enter())
		{
			for (int32 dz = -1; dz <= 1; dz++)
				for (int32 dy = -1; dy <= 1; dy++)
					for (int32 dx = -1; dx <= 1; dx++)
					{
						if (dx == 0 && dy == 0 && dz == 0)
							continue;
						let other = Int3(chunk.coord.x + dx, chunk.coord.y + dy, chunk.coord.z + dz);
						int8[] density = null;
						uint8[] paint = null;
						if (mChunks.TryGetValue(other, let live) && live != chunk)
						{
							if (live.generated && live.edited && live.density != null)
							{
								density = live.density;
								paint = live.paint;
							}
						}
						else if (snap.Locate(other, let tileId, let local))
						{
							let saved = FindSaved(tileId, local);
							if (saved != null)
							{
								density = saved.density;
								paint = saved.paint;
							}
						}
						if (density == null)
							continue;
						if (paint != null && chunk.paint == null)
							chunk.paint = new uint8[SampleCount];
						CopyShared(chunk.density, chunk.paint, density, paint, dx, dy, dz);
					}
		}
		chunk.generated = true;
	}

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

	// ---- streaming (main thread) ----

	/// Where the viewers are, in chunks of the terrain's own space.
	void ViewerChunks(List<Vector2> list)
	{
		let chunkWorld = ChunkCells * mVoxelSize;
		void Add(Vector3 world)
		{
			let local = Transform.InverseTransformPoint(world);
			let p = Vector2(local.x / chunkWorld, local.z / chunkWorld);
			for (let other in list)
			{
				if (Math.Abs(other.x - p.x) < 0.5f && Math.Abs(other.y - p.y) < 0.5f)
					return;
			}
			list.Add(p);
		}
		Add(ViewerPosition);
		for (let viewer in Viewers)
		{
			if (list.Count >= 64)
				break;
			Add(viewer);
		}
	}

	/// The level of detail for a distance in chunks.
	int32 LodFor(float distance)
	{
		if (!mLodOn)
			return 0;
		let d = (float)lodDistance;
		if (distance < d) return 0;
		if (distance < d * 2) return 1;
		if (distance < d * 4) return 2;
		return 3;
	}

	Chunk MakeChunk(Int3 coord, int32 tileId, Int3 local)
	{
		let chunk = new Chunk();
		chunk.coord = coord;
		chunk.tileId = tileId;
		chunk.local = local;
		chunk.state = .Queued;
		using (mMonitor.Enter())
			mChunks[coord] = chunk;
		return chunk;
	}

	public override void OnFrame()
	{
		if (!Streaming)
			return;
		// The mode was changed from code without OnValidate.
		if (mode != mSnap.mode)
			Regenerate();
		let snap = mSnap;
		List<Vector2> viewers = scope .();
		ViewerChunks(viewers);
		float Nearest(Int3 coord)
		{
			float best = float.MaxValue;
			for (let v in viewers)
			{
				let dx = coord.x + 0.5f - v.x, dz = coord.z + 0.5f - v.y;
				best = Math.Min(best, dx * dx + dz * dz);
			}
			return Math.Sqrt(best);
		}
		bool Near(Int3 coord, int32 radius)
		{
			for (let v in viewers)
			{
				let dx = coord.x - (int32)Math.Floor(v.x), dz = coord.z - (int32)Math.Floor(v.y);
				if (dx * dx + dz * dz <= radius * radius)
					return true;
			}
			return false;
		}

		// Queue missing chunks, nearest first because jobs are popped from the back.
		List<Chunk> added = scope .();
		if (mode == .Fixed)
		{
			let size = snap.tileSize;
			for (let tile in mTiles)
			{
				for (int32 lz < size)
				{
					for (int32 lx < size)
					{
						let column = Int3(tile.x * size + lx, 0, tile.z * size + lz);
						if (streamTiles && !Near(column, viewDistance))
							continue;
						for (int32 cy = minChunkY; cy <= maxChunkY; cy++)
						{
							let coord = Int3(column.x, cy, column.z);
							if (!mChunks.ContainsKey(coord))
								added.Add(MakeChunk(coord, tile.id, .(lx, cy, lz)));
						}
					}
				}
			}
		}
		else
		{
			for (let v in viewers)
			{
				let centerX = (int32)Math.Floor(v.x), centerZ = (int32)Math.Floor(v.y);
				for (int32 dz = -viewDistance; dz <= viewDistance; dz++)
				{
					for (int32 dx = -viewDistance; dx <= viewDistance; dx++)
					{
						if (dx * dx + dz * dz > viewDistance * viewDistance)
							continue;
						for (int32 cy = minChunkY; cy <= maxChunkY; cy++)
						{
							let coord = Int3(centerX + dx, cy, centerZ + dz);
							if (!mChunks.ContainsKey(coord))
								added.Add(MakeChunk(coord, -1, coord));
						}
					}
				}
			}
		}
		if (added.Count > 0)
		{
			for (let chunk in added)
				chunk.lod = LodFor(Nearest(chunk.coord));
			added.Sort(scope (a, b) => Nearest(b.coord) <=> Nearest(a.coord));
			using (mMonitor.Enter())
			{
				for (let chunk in added)
					mJobs.Add(chunk);
			}
			for (let thread in mThreads)
				mWake.Set(false);
		}

		// Drop chunks that are no longer wanted: out of range, or of a tile that is not there now.
		let dropDistance = viewDistance + 2;
		List<Chunk> remove = scope .();
		for (let chunk in mChunks.Values)
		{
			bool drop;
			if (mode == .Fixed)
			{
				drop = !snap.Locate(chunk.coord, let tileId, let local) || tileId != chunk.tileId || (chunk.coord.y < minChunkY || chunk.coord.y > maxChunkY)
					|| (streamTiles && !Near(chunk.coord, dropDistance));
			}
			else
				drop = chunk.tileId != -1 || !Near(chunk.coord, dropDistance);
			if (drop)
				remove.Add(chunk);
		}
		if (remove.Count > 0)
		{
			using (mMonitor.Enter())
			{
				for (let chunk in remove)
					DropChunk(chunk);
			}
		}

		// Level of detail by distance, with a little give so a chunk at a boundary does not flicker between two.
		if (mLodOn)
		{
			for (let chunk in mChunks.Values)
			{
				let distance = Nearest(chunk.coord);
				let wanted = LodFor(distance);
				if (wanted == chunk.lod)
					continue;
				if (wanted > chunk.lod ? LodFor(distance - 0.5f) <= chunk.lod : LodFor(distance + 0.5f) >= chunk.lod)
					continue;
				chunk.lod = wanted;
				if (chunk.state == .Uploaded)
					QueueRemesh(chunk);
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
			if (mBusy == 0 && mRetired.Count > 0)
				ClearAndDeleteItems!(mRetired);
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
			if (chunk.stale)
			{
				chunk.stale = false;
				chunk.generated = false;
				chunk.state = .Uploaded;
				QueueRemesh(chunk);
				continue;
			}
			UploadChunk(chunk);
			// A chunk that streamed in after shared brush strokes were made gets them now.
			if (chunk.generated && chunk.appliedBrushes < mSessionBrushes.Count)
				CatchUp(chunk);
			if (chunk.dirty || chunk.lod != chunk.builtLod)
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
		let collider = chunk.gameObject.GetComponent<MeshCollider>();
		if (collider != null)
			collider.CollisionMesh = null;
		Scene.Destroy(chunk.gameObject);
		chunk.gameObject = null;
	}

	void UploadChunk(Chunk chunk)
	{
		chunk.state = .Uploaded;
		let separate = chunk.separateCollision;
		if (chunk.builtCollision && separate)
		{
			if (chunk.collisionMesh == null)
				chunk.collisionMesh = new Mesh();
			Swap!(chunk.collisionMesh.Vertices, chunk.collisionVertices);
			Swap!(chunk.collisionMesh.Indices, chunk.collisionIndices);
		}
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
			if (mColliders)
				chunk.gameObject.AddComponent<MeshCollider>().CollisionMesh = separate ? chunk.collisionMesh : null;
		}
		else
		{
			chunk.gameObject.SetActive(true);
			// Rebuild the collision for the new surface (not when only the drawing detail changed).
			let collider = chunk.gameObject.GetComponent<MeshCollider>();
			if (collider != null && chunk.builtCollision)
			{
				collider.CollisionMesh = separate ? chunk.collisionMesh : null;
				collider.Refresh();
			}
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

	// ---- sculpting ----

	/// Adds (amount > 0) or removes (amount < 0) material inside a sphere given in world space.
	public void ModifySphere(Vector3 worldCenter, float radius, float amount)
	{
		Brush(worldCenter, radius, Math.Abs(amount), amount >= 0 ? .Raise : .Lower);
	}

	/// Applies a sculpting or painting brush in real time; only the chunks it touches are re-meshed, and it carries
	/// on across chunk and tile edges as one surface.
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
		List<Chunk> touched = scope .();
		for (int32 cz = minC.z; cz <= maxC.z; cz++)
			for (int32 cy = minC.y; cy <= maxC.y; cy++)
				for (int32 cx = minC.x; cx <= maxC.x; cx++)
				{
					if (mChunks.TryGetValue(Int3(cx, cy, cz), let chunk) && chunk.generated)
						touched.Add(chunk);
				}
		if (shared)
		{
			for (let chunk in touched)
				CatchUp(chunk);
			return;
		}
		// Smoothing reads the neighbours of each sample, across chunk edges: every chunk reads the ground as it was
		// before this stroke, so the copies of a shared edge get the same values.
		Dictionary<Int3, int8[]> before = null;
		if (mode == .Smooth)
		{
			before = scope:: .();
			for (let chunk in touched)
				before[chunk.coord] = Copy(chunk.density);
			// Neighbours just outside the stroke's chunks are read too.
			for (let chunk in touched)
				for (int32 dz = -1; dz <= 1; dz++)
					for (int32 dy = -1; dy <= 1; dy++)
						for (int32 dx = -1; dx <= 1; dx++)
						{
							let other = Int3(chunk.coord.x + dx, chunk.coord.y + dy, chunk.coord.z + dz);
							if (!before.ContainsKey(other) && mChunks.TryGetValue(other, let near) && near.generated)
								before[other] = Copy(near.density);
						}
		}
		defer { if (before != null) for (let entry in before) delete entry.value; }
		for (let chunk in touched)
			ApplyStroke(chunk, stroke, before);
	}

	/// Applies the session strokes a chunk has not had yet, in order.
	void CatchUp(Chunk chunk)
	{
		for (int i = chunk.appliedBrushes; i < mSessionBrushes.Count; i++)
			ApplyStroke(chunk, mSessionBrushes[i], null);
		chunk.appliedBrushes = (int32)mSessionBrushes.Count;
	}

	/// A sample of the ground before the stroke, which may be in a neighbouring chunk.
	static int8 Before(Dictionary<Int3, int8[]> before, Int3 coord, int8[] own, int x, int y, int z)
	{
		if ((uint)x < (uint)Samples && (uint)y < (uint)Samples && (uint)z < (uint)Samples)
			return before.TryGetValue(coord, let mine) ? mine[SampleIndex(x, y, z)] : own[SampleIndex(x, y, z)];
		var c = coord;
		var px = x, py = y, pz = z;
		if (px < 0) { c.x--; px += ChunkCells; } else if (px > ChunkCells) { c.x++; px -= ChunkCells; }
		if (py < 0) { c.y--; py += ChunkCells; } else if (py > ChunkCells) { c.y++; py -= ChunkCells; }
		if (pz < 0) { c.z--; pz += ChunkCells; } else if (pz > ChunkCells) { c.z++; pz -= ChunkCells; }
		if (before.TryGetValue(c, let other))
			return other[SampleIndex(px, py, pz)];
		return own[SampleIndex(Math.Clamp(x, 0, ChunkCells), Math.Clamp(y, 0, ChunkCells), Math.Clamp(z, 0, ChunkCells))];
	}

	/// Applies one stroke to one chunk; nothing happens if the stroke does not reach it.
	void ApplyStroke(Chunk chunk, BrushStroke stroke, Dictionary<Int3, int8[]> before)
	{
		let size = mVoxelSize;
		let chunkWorld = ChunkCells * size;
		let center = stroke.center;
		let radius = stroke.radius;
		let strength = stroke.strength;
		let mode = stroke.mode;
		let reach = radius + size;
		let origin = Vector3(chunk.coord.x, chunk.coord.y, chunk.coord.z) * chunkWorld;
		let x0 = Math.Max(0, (int)Math.Floor((center.x - reach - origin.x) / size));
		let x1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.x + reach - origin.x) / size));
		let y0 = Math.Max(0, (int)Math.Floor((center.y - reach - origin.y) / size));
		let y1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.y + reach - origin.y) / size));
		let z0 = Math.Max(0, (int)Math.Floor((center.z - reach - origin.z) / size));
		let z1 = Math.Min(Samples - 1, (int)Math.Ceiling((center.z + reach - origin.z) / size));
		if (x0 > x1 || y0 > y1 || z0 > z1)
			return;
		Record(chunk.coord);
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
						let target = Mathf.Clamp((stroke.flattenLocal - p.y) / size * 24.0f, -127, 127);
						value = Mathf.Lerp(value, target, Math.Min(1.0f, strength * falloff));
					case .Smooth:
						float average;
						if (before != null)
						{
							let c = chunk.coord;
							value = Before(before, c, density, x, y, z);
							average = ((float)Before(before, c, density, x - 1, y, z) + Before(before, c, density, x + 1, y, z)
								+ Before(before, c, density, x, y - 1, z) + Before(before, c, density, x, y + 1, z)
								+ Before(before, c, density, x, y, z - 1) + Before(before, c, density, x, y, z + 1)) / 6.0f;
						}
						else
						{
							int sum = 0;
							sum += density[SampleIndex(Math.Max(x - 1, 0), y, z)];
							sum += density[SampleIndex(Math.Min(x + 1, (int)ChunkCells), y, z)];
							sum += density[SampleIndex(x, Math.Max(y - 1, 0), z)];
							sum += density[SampleIndex(x, Math.Min(y + 1, (int)ChunkCells), z)];
							sum += density[SampleIndex(x, y, Math.Max(z - 1, 0))];
							sum += density[SampleIndex(x, y, Math.Min(z + 1, (int)ChunkCells))];
							average = sum / 6.0f;
						}
						value = Mathf.Lerp(value, average, Math.Min(1.0f, strength * falloff));
					case .Paint:
						chunk.paint[index] = (uint8)stroke.paintLayer;
					}
					density[index] = (int8)Mathf.Clamp(value, -127, 127);
					changed = true;
				}
			}
		}
		if (changed)
		{
			chunk.edited = true;
			chunk.shapeChanged = true;
			HasUnsavedEdits = true;
			QueueRemesh(chunk);
		}
	}

	// ---- undo ----

	/// Starts noting which chunks change, as they were before, until EndEditRecord: one undo step of sculpting.
	public void BeginEditRecord()
	{
		delete mRecording;
		mRecording = new .();
	}

	/// Stops noting and returns what changed (yours to delete), or null if nothing did.
	public EditRecord EndEditRecord()
	{
		let record = mRecording;
		mRecording = null;
		if (record == null)
			return null;
		let snap = mSnap;
		List<Int3> same = scope .();
		for (let entry in record.before)
		{
			let state = Capture(entry.key, snap);
			let was = entry.value;
			bool equal = (state.density == null) == (was.density == null) && (state.paint == null) == (was.paint == null);
			if (equal && state.density != null)
				equal = Internal.MemCmp(state.density.Ptr, was.density.Ptr, SampleCount) == 0;
			if (equal && state.paint != null)
				equal = Internal.MemCmp(state.paint.Ptr, was.paint.Ptr, SampleCount) == 0;
			if (equal)
			{
				delete state;
				same.Add(entry.key);
			}
			else
				record.after[entry.key] = state;
		}
		for (let coord in same)
		{
			if (record.before.GetAndRemove(coord) case .Ok(let entry))
				delete entry.value;
		}
		if (record.before.Count == 0)
		{
			delete record;
			return null;
		}
		return record;
	}

	/// Notes a chunk as it is now, the first time it changes while recording.
	void Record(Int3 coord)
	{
		if (mRecording == null || mRecording.before.ContainsKey(coord))
			return;
		mRecording.before[coord] = Capture(coord, mSnap);
	}

	EditRecord.State Capture(Int3 coord, Snapshot snap)
	{
		let state = new EditRecord.State();
		int8[] density = null;
		uint8[] paint = null;
		if (mChunks.TryGetValue(coord, let chunk) && chunk.generated)
		{
			if (chunk.edited)
			{
				density = chunk.density;
				paint = chunk.paint;
			}
		}
		else if (snap.Locate(coord, let tileId, let local))
		{
			let saved = FindSaved(tileId, local);
			if (saved != null)
			{
				density = saved.density;
				paint = saved.paint;
			}
		}
		if (density != null)
			state.density = Copy(density);
		if (paint != null)
			state.paint = Copy(paint);
		return state;
	}

	/// Puts chunks back as a record had them: before (undo) or after (redo).
	public void ApplyEditRecord(EditRecord record, bool undo)
	{
		let snap = mSnap;
		if (record == null || snap == null)
			return;
		List<Chunk> remesh = scope .();
		using (mMonitor.Enter())
		{
			// Every chunk first, then the meshing: a chunk made again must not read a neighbour's old edge.
			for (let entry in undo ? record.before : record.after)
			{
				let coord = entry.key;
				let state = entry.value;
				if (!snap.Locate(coord, let tileId, let local))
					continue;
				mChunks.TryGetValue(coord, let chunk);
				if (state.density == null)
				{
					RemoveSaved(tileId, local);
					if (chunk != null)
					{
						// Not sculpted: made again from the generator.
						if (chunk.generated)
							chunk.generated = false;
						else
							chunk.stale = true;
						chunk.edited = false;
					}
				}
				else if (chunk != null && chunk.generated)
				{
					state.density.CopyTo(chunk.density);
					if (state.paint != null)
					{
						if (chunk.paint == null)
							chunk.paint = new uint8[SampleCount];
						state.paint.CopyTo(chunk.paint);
					}
					else
						DeleteAndNullify!(chunk.paint);
					chunk.edited = true;
				}
				else
				{
					let saved = new SavedChunk();
					saved.density = Copy(state.density);
					if (state.paint != null)
						saved.paint = Copy(state.paint);
					PutSaved(tileId, local, saved);
					if (chunk != null)
						chunk.stale = true;
				}
				if (chunk != null)
				{
					chunk.shapeChanged = true;
					remesh.Add(chunk);
				}
			}
		}
		for (let chunk in remesh)
			QueueRemesh(chunk);
		HasUnsavedEdits = true;
	}

	/// The sculpting this terrain holds, loaded or not, taken out of it: the editor keeps it while undo makes the
	/// terrain object again, then gives it to the new one with GiveEdits, so sculpting not saved yet is not lost.
	public Object TakeEdits()
	{
		Flush();
		let kept = new KeptEdits();
		using (mMonitor.Enter())
			Swap!(kept.store, mStore);
		kept.unsaved = HasUnsavedEdits;
		return kept;
	}

	public void GiveEdits(Object edits)
	{
		let kept = edits as KeptEdits;
		if (kept == null)
		{
			delete edits;
			return;
		}
		using (mMonitor.Enter())
			Swap!(kept.store, mStore);
		HasUnsavedEdits |= kept.unsaved;
		// What the files say is already in what was given.
		mLoadedFolder.Set(editsFolder);
		mLoadedEdits.Set(editsFile);
		delete kept;
		if (Streaming)
			Regenerate();
	}

	class KeptEdits
	{
		public Dictionary<int32, Dictionary<Int3, SavedChunk>> store = new .() ~ { for (let entry in _) DeleteDictionaryAndValues!(entry.value); delete _; };
		public bool unsaved;
	}

	// ---- looking inside (tests and debugging) ----

	/// How many samples that neighbouring loaded chunks share differ between the two chunks' copies, in density or
	/// paint. 0 means sculpting and painting meet exactly at every chunk and tile edge.
	public int32 SeamMismatches()
	{
		int32 count = 0;
		for (let chunk in mChunks.Values)
		{
			if (!chunk.generated || chunk.density == null)
				continue;
			for (int axis < 3)
			{
				let other = chunk.coord + (axis == 0 ? Int3(1, 0, 0) : (axis == 1 ? Int3(0, 1, 0) : Int3(0, 0, 1)));
				if (!mChunks.TryGetValue(other, let next) || !next.generated || next.density == null)
					continue;
				for (int b < Samples)
					for (int a < Samples)
					{
						int i, j;
						if (axis == 0) { i = SampleIndex(ChunkCells, a, b); j = SampleIndex(0, a, b); }
						else if (axis == 1) { i = SampleIndex(a, ChunkCells, b); j = SampleIndex(a, 0, b); }
						else { i = SampleIndex(a, b, ChunkCells); j = SampleIndex(a, b, 0); }
						let paintA = chunk.paint != null ? chunk.paint[i] : 0;
						let paintB = next.paint != null ? next.paint[j] : 0;
						if (chunk.density[i] != next.density[j] || paintA != paintB)
							count++;
					}
			}
		}
		return count;
	}

	/// The mesh a loaded chunk is drawn with, or null.
	public Mesh ChunkMesh(Int3 coord) => mChunks.TryGetValue(coord, let chunk) && chunk.state == .Uploaded ? chunk.mesh : null;

	/// The mesh a loaded chunk collides with when it is not the drawn one (level of detail on), or null.
	public Mesh ChunkCollisionMesh(Int3 coord) => mChunks.TryGetValue(coord, let chunk) && chunk.separateCollision ? chunk.collisionMesh : null;

	/// The level of detail a loaded chunk's mesh was made at (0 full), or -1.
	public int32 ChunkLod(Int3 coord) => mChunks.TryGetValue(coord, let chunk) ? chunk.builtLod : -1;

	// ---- reading the ground ----

	/// Trilinear density at a point in the terrain's local space; false where no chunk is loaded.
	bool SampleLocal(Vector3 p, out float density)
	{
		density = -1;
		let size = mVoxelSize;
		let chunkWorld = ChunkCells * size;
		let coord = Int3((int32)Math.Floor(p.x / chunkWorld), (int32)Math.Floor(p.y / chunkWorld), (int32)Math.Floor(p.z / chunkWorld));
		if (!mChunks.TryGetValue(coord, let chunk) || !chunk.generated)
			return false;
		if (mSnap != null && !mSnap.Inside(p.x, p.z))
		{
			density = Air;
			return true;
		}
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

	/// The density at a point in world space, as the ground is now (more than zero is solid); false where no chunk is
	/// loaded.
	public bool DensityAt(Vector3 world, out float density) => SampleLocal(Transform.InverseTransformPoint(world), out density);

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
