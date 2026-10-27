using System;
using System.Collections;
using System.IO;

namespace Tessera;

/// Chunk-addressable surface grid, or a volume grid for flying agents.
/// Positions are agent feet for walking, and centers for flying.
class NavigationData
{
	public struct Cell { public bool walkable; public Vector3 position; public uint32 links; }
	/// Link directions: 0-5 are the axes, 6-9 the horizontal diagonals, 10-25 every offset that also moves up or down.
	public const int32 DirectionCount = 26;
	public Vector3 origin;
	public float cellSize = 1, agentRadius = 0.3f, agentHeight = 1.8f, maxStep = 0.5f, maxSlope = 45;
	public int32 width = 32, height = 1, depth = 32, chunkSize = 16;
	public bool flying;
	/// Unique across every NavigationData, so an agent notices a rebake that replaced the object as well as an in-place rebuild.
	public int32 Revision;
	static int32 sRevisions;
	public void Touch()
	{
		Revision = ++sRevisions;
	}

	/// True when the last FindPath stopped at its visit budget instead of proving the goal unreachable.
	public bool BudgetExceeded;
	// Search scratch, kept between searches; a stamp marks the entries the current search has written.
	List<float> mCost = new .() ~ delete _;
	List<int32> mParent = new .() ~ delete _;
	List<int32> mSeen = new .() ~ delete _;
	List<int32> mClosed = new .() ~ delete _;
	List<HeapItem> mOpen = new .() ~ delete _;
	int32 mSearch;
	// Connected-region label per cell, rebuilt lazily after the grid changes.
	List<int32> mRegions = new .() ~ delete _;
	int32 mRegionRevision = -1;
	public List<Cell> cells = new .() ~ delete _;

	/// A way across that the grid does not have (a jump, a ladder, a teleporter): from one cell to another, at a
	/// cost. Set from Navigation Link components by the surface; not saved with the grid.
	public struct Link
	{
		public int32 from, to;
		public float cost;
		public bool twoWay;
		/// Which link it is, for the agent crossing it (the surface's index of its Navigation Link).
		public int32 id;
	}

	public List<Link> links = new .() ~ delete _;
	// Cell -> the links that start (or, two-way, end) there, rebuilt with SetLinks.
	Dictionary<int32, List<int32>> mLinksAt = new .() ~ DeleteDictionaryAndValues!(_);
	// Runtime overlays, not saved: how many obstacles block each cell, and each cell's cost multiplier (areas).
	// Empty until something uses them.
	List<uint16> mBlocked = new .() ~ delete _;
	List<float> mCostScale = new .() ~ delete _;
	List<int32> mParentLink = new .() ~ delete _;

	/// A cell an agent may use now: walkable in the bake and not blocked by an obstacle.
	public bool Usable(int32 index) => index >= 0 && index < cells.Count && cells[index].walkable && (mBlocked.Count != cells.Count || mBlocked[index] == 0);
	public bool Blocked(int32 index) => mBlocked.Count == cells.Count && index >= 0 && index < cells.Count && mBlocked[index] > 0;
	/// How much more a step into a cell costs than its length (1 normally; more in a costly area).
	public float CostScale(int32 index) => mCostScale.Count == cells.Count && index >= 0 && index < cells.Count ? mCostScale[index] : 1;

	/// Forgets every obstacle and area (before the surface marks them again).
	public void ClearOverlay()
	{
		mBlocked.Clear();
		mCostScale.Clear();
	}

	/// The cells whose floor (or centre, flying) lies inside a box, turned by a rotation about its centre, with the
	/// agent's radius added around it. Calls the function with each one's index.
	public void CellsInBox(Vector3 center, Quaternion rotation, Vector3 halfExtents, bool cylinder, delegate void(int32) each)
	{
		if (cells.Count != width * height * depth)
			return;
		let grow = agentRadius;
		let inverse = rotation.Normalized.Conjugate;
		// The box's reach in the world, to know which cells to look at.
		var reach = Vector3.Zero;
		for (int corner < 8)
		{
			let local = Vector3((corner & 1) != 0 ? halfExtents.x : -halfExtents.x, (corner & 2) != 0 ? halfExtents.y : -halfExtents.y, (corner & 4) != 0 ? halfExtents.z : -halfExtents.z);
			let world = rotation * local;
			reach = .(Math.Max(reach.x, Math.Abs(world.x)), Math.Max(reach.y, Math.Abs(world.y)), Math.Max(reach.z, Math.Abs(world.z)));
		}
		reach += .(grow, grow, grow);
		// Nothing to do for a box wholly outside the grid.
		let extent = Vector3(width * cellSize, flying ? height * cellSize : float.MaxValue, depth * cellSize);
		if (center.x + reach.x < origin.x || center.x - reach.x > origin.x + extent.x || center.z + reach.z < origin.z || center.z - reach.z > origin.z + extent.z)
			return;
		if (flying && (center.y + reach.y < origin.y || center.y - reach.y > origin.y + extent.y))
			return;
		int32 Bound(float p, int32 limit) => (int32)Mathf.Clamp(Math.Floor(p / cellSize), 0, limit - 1);
		let x0 = Bound(center.x - reach.x - origin.x, width);
		let x1 = Bound(center.x + reach.x - origin.x, width);
		let z0 = Bound(center.z - reach.z - origin.z, depth);
		let z1 = Bound(center.z + reach.z - origin.z, depth);
		let y0 = flying ? Bound(center.y - reach.y - origin.y, height) : 0;
		let y1 = flying ? Bound(center.y + reach.y - origin.y, height) : 0;
		// Walking: an agent standing on the cell is in the box when its body (feet to head) overlaps it.
		let headroom = flying ? 0 : agentHeight;
		for (int32 y = y0; y <= y1; y++)
		{
			for (int32 z = z0; z <= z1; z++)
			{
				for (int32 x = x0; x <= x1; x++)
				{
					let index = Index(x, y, z);
					if (!cells[index].walkable)
						continue;
					let local = inverse * (cells[index].position - center);
					if (flying)
					{
						if (Math.Abs(local.y) > halfExtents.y + grow)
							continue;
					}
					// Walking: the agent standing there (feet up to head) overlaps the box.
					else if (local.y > halfExtents.y || local.y + headroom < -halfExtents.y)
						continue;
					if (cylinder)
					{
						if (local.x * local.x + local.z * local.z > (halfExtents.x + grow) * (halfExtents.x + grow))
							continue;
					}
					else if (Math.Abs(local.x) > halfExtents.x + grow || Math.Abs(local.z) > halfExtents.z + grow)
						continue;
					each(index);
				}
			}
		}
	}

	/// Blocks the cells an obstacle covers (Navigation Obstacle with Carve). Undone by ClearOverlay.
	public void Block(Vector3 center, Quaternion rotation, Vector3 halfExtents, bool cylinder)
	{
		if (mBlocked.Count != cells.Count)
		{
			mBlocked.Clear();
			mBlocked.Resize(cells.Count);
		}
		CellsInBox(center, rotation, halfExtents, cylinder, scope [&] (index) =>
			{
				if (mBlocked[index] < uint16.MaxValue)
					mBlocked[index]++;
			});
	}

	/// Makes the cells in a box cost more to cross (a Navigation Area): agents go round unless the way round is
	/// longer than the extra. The highest multiplier of the areas over a cell counts.
	public void SetCost(Vector3 center, Quaternion rotation, Vector3 halfExtents, float multiplier)
	{
		if (mCostScale.Count != cells.Count)
		{
			mCostScale.Clear();
			mCostScale.Resize(cells.Count);
			for (int i < mCostScale.Count)
				mCostScale[i] = 1;
		}
		let scale = Math.Clamp(multiplier, 1, 1000);
		// Areas mark where agents stand, not their whole body.
		let radius = agentRadius;
		agentRadius = 0;
		CellsInBox(center, rotation, halfExtents, false, scope [&] (index) =>
			{
				mCostScale[index] = Math.Max(mCostScale[index], scale);
			});
		agentRadius = radius;
	}

	/// Sets the off-grid links (replacing those before). Their ends are cell indices.
	public void SetLinks(Span<Link> newLinks)
	{
		links.Clear();
		for (let link in newLinks)
		{
			if (link.from >= 0 && link.to >= 0 && link.from < cells.Count && link.to < cells.Count && link.from != link.to && link.cost.IsFinite)
				links.Add(link);
		}
		for (let (key, value) in mLinksAt)
			delete value;
		mLinksAt.Clear();
		for (int32 i < (int32)links.Count)
		{
			void At(int32 cell, int32 link)
			{
				List<int32> list;
				if (!mLinksAt.TryGetValue(cell, out list))
				{
					list = new .();
					mLinksAt[cell] = list;
				}
				list.Add(link);
			}
			At(links[i].from, i);
			if (links[i].twoWay)
				At(links[i].to, i);
		}
		// Regions are joined across links.
		mRegionRevision = -1;
	}

	/// The cell a point is in (walking: the column it stands over), or -1 outside the grid.
	public int32 CellAt(Vector3 point)
	{
		let x = (int32)Math.Floor((point.x - origin.x) / cellSize);
		let z = (int32)Math.Floor((point.z - origin.z) / cellSize);
		let y = flying ? (int32)Math.Floor((point.y - origin.y) / cellSize) : 0;
		return Inside(x, y, z) ? Index(x, y, z) : -1;
	}

	/// The link direction for a step of (-1..1) cells on each axis, or -1.
	public static int32 DirectionOf(int32 dx, int32 dy, int32 dz)
	{
		for (int32 direction < DirectionCount)
		{
			Offset(direction, let x, let y, let z);
			if (x == dx && y == dy && z == dz)
				return direction;
		}
		return -1;
	}

	/// True when an agent can go straight from a to b: every cell the line crosses is usable and linked to the one
	/// before it (so the agent's shape fits all the way), and, walking, the floor stays close to the line's height.
	/// The point where the line stops is `reached`.
	public bool LineClear(Vector3 a, Vector3 b, out Vector3 reached)
	{
		reached = a;
		var previous = CellAt(a);
		if (!Usable(previous))
			return false;
		int32 lastSquare = -1;
		var delta = b - a;
		if (!flying)
			delta.y = 0;
		let length = delta.Length;
		let steps = (int)Math.Ceiling(length / (cellSize * 0.25f));
		let tolerance = Math.Max(maxStep * 0.6f, cellSize * 0.2f);
		for (int s = 1; s <= steps; s++)
		{
			let t = (float)s / steps;
			let point = Vector3.Lerp(a, b, t);
			// Between cell centres the line can pass nearer a wall than any centre does: it must lie among usable
			// cells that are all linked to each other, whose swept links cover the space between them.
			if (!Among(point, ref lastSquare))
				return false;
			let cell = CellAt(point);
			if (cell == previous)
				continue;
			if (!Usable(cell))
				return false;
			let px = previous % width, pz = (previous / width) % depth, py = previous / (width * depth);
			let cx = cell % width, cz = (cell / width) % depth, cy = cell / (width * depth);
			let dx = cx - px, dy = cy - py, dz = cz - pz;
			if (Math.Abs(dx) > 1 || Math.Abs(dy) > 1 || Math.Abs(dz) > 1)
				return false;
			let direction = DirectionOf(dx, dy, dz);
			if (direction < 0 || !Uses(direction) || (cells[previous].links & (1u << direction)) == 0)
				return false;
			// A long straight leg over a hill would cut through it (or float over a dip).
			if (!flying && Math.Abs(cells[cell].position.y - point.y) > tolerance)
				return false;
			reached = point;
			previous = cell;
		}
		reached = b;
		return true;
	}

	/// Whether a point lies in a square (flying: a cube) of usable cells whose centres surround it, each linked to the
	/// others along the square's sides and across it. `last` skips a square already checked.
	bool Among(Vector3 point, ref int32 last)
	{
		let bx = (int32)Math.Floor((point.x - origin.x) / cellSize - 0.5f);
		let bz = (int32)Math.Floor((point.z - origin.z) / cellSize - 0.5f);
		let by = flying ? (int32)Math.Floor((point.y - origin.y) / cellSize - 0.5f) : 0;
		let layers = (int32)(flying ? 2 : 1);
		// At the grid's edge there is no full square; the cell itself is checked by the caller.
		if (!Inside(bx, by, bz) || !Inside(bx + 1, by + layers - 1, bz + 1))
			return true;
		let square = Index(bx, by, bz);
		if (square == last)
			return true;
		last = square;
		int32[8] corners = default;
		int count = 0;
		for (int32 y < layers)
		{
			for (int32 z < 2)
			{
				for (int32 x < 2)
				{
					let index = Index(bx + x, by + y, bz + z);
					if (!Usable(index))
						return false;
					corners[count++] = index;
				}
			}
		}
		// Every pair of corners that are grid neighbours must be linked (one way is enough: links are symmetric).
		for (int i < count)
		{
			for (int j = i + 1; j < count; j++)
			{
				let a = corners[i], b = corners[j];
				let direction = DirectionOf(b % width - a % width, b / (width * depth) - a / (width * depth), (b / width) % depth - (a / width) % depth);
				if (direction < 0 || !Uses(direction))
					continue;
				if ((cells[a].links & (1u << direction)) == 0 && (cells[b].links & (1u << Opposite(direction))) == 0)
					return false;
			}
		}
		return true;
	}

	/// Straightens a path of cell centres where the agent can go directly: each point is joined to the farthest one
	/// after it with a clear line. Points where a link starts or ends are kept (legLinks, from FindPath, says which
	/// legs are links; it is kept in step).
	public void Smooth(List<Vector3> path, List<int32> legLinks = null)
	{
		if (path.Count < 3)
			return;
		let points = scope List<Vector3>();
		let kept = scope List<int32>();
		points.Add(path[0]);
		kept.Add(-1);
		int i = 0;
		while (i < path.Count - 1)
		{
			// A link is crossed as it is.
			if (legLinks != null && legLinks[i] >= 0)
			{
				kept[kept.Count - 1] = legLinks[i];
				points.Add(path[i + 1]);
				kept.Add(-1);
				i++;
				continue;
			}
			var best = i + 1;
			for (int j = i + 2; j < path.Count; j++)
			{
				// Not past the start of a link.
				if (legLinks != null && legLinks[j - 1] >= 0)
					break;
				if (!LineClear(path[i], path[j], ?))
					break;
				best = j;
			}
			points.Add(path[best]);
			kept.Add(-1);
			i = best;
		}
		path.Clear();
		path.AddRange(points);
		if (legLinks != null)
		{
			legLinks.Clear();
			legLinks.AddRange(kept);
		}
	}

	public int32 Index(int32 x, int32 y, int32 z) => x + width * (z + depth * y);
	public bool Inside(int32 x, int32 y, int32 z) => x >= 0 && x < width && y >= 0 && y < height && z >= 0 && z < depth;
	public Vector3 Center(int32 x, int32 y, int32 z) => origin + .((x + 0.5f) * cellSize, (y + 0.5f) * cellSize, (z + 0.5f) * cellSize);
	public static void Offset(int32 direction, out int32 x, out int32 y, out int32 z)
	{
		x = 0;
		y = 0;
		z = 0;
		switch (direction)
		{
		case 0:
			x = 1;
		case 1: x = -1;
		case 2: z = 1;
		case 3: z = -1;
		case 4: y = 1;
		case 5: y = -1;
		case 6,7,8,9:
			x = direction < 8 ? 1 : -1;
			z = (direction & 1) == 0 ? 1 : -1;
		default:
			// Eight horizontal offsets one layer up, then the same eight one layer down.
			let k = (direction - 10) % 8;
			Offset(k < 4 ? k : k + 2, out x, out y, out z);
			y = direction < 18 ? 1 : -1;
		}
	}

	public static int32 Opposite(int32 direction)
	{
		if (direction < 6) return direction ^ 1;
		if (direction < 10) return 15 - direction;
		let k = (direction - 10) % 8;
		return 10 + (direction < 18 ? 8 : 0) + (k < 4 ? k ^ 1 : 11 - k);
	}

	/// Walking surfaces link along X/Z only, diagonals included.
	public bool Uses(int32 direction) => flying || direction < 4 || (direction >= 6 && direction < 10);
	/// Shortest possible travel between two cells over this grid's link directions; never more than the real cost.
	float Estimate(int32 a, int32 b)
	{
		var dx = (float)Math.Abs(a % width - b % width);
		var dz = (float)Math.Abs((a / width) % depth - (b / width) % depth);
		var dy = (float)Math.Abs(a / (width * depth) - b / (width * depth));
		if (dx < dy)
			Swap!(dx, dy);
		if (dx < dz)
			Swap!(dx, dz);
		if (dy < dz)
			Swap!(dy, dz);
		return (dx + 0.41421356f * dy + 0.31783725f * dz) * cellSize;
	}

	public int32 Neighbor(int32 index, int32 direction)
	{
		let x = index % width;
		let z = (index / width) % depth;
		let y = index / (width * depth);
		Offset(direction, let dx, let dy, let dz);
		return Inside(x + dx, y + dy, z + dz) ? Index(x + dx, y + dy, z + dz) : -1;
	}

	public bool Configure(Vector3 minimum, Vector3 size, float spacing, bool flight, int32 chunk, String error)
	{
		if (!minimum.x.IsFinite || !minimum.y.IsFinite || !minimum.z.IsFinite || !spacing.IsFinite || spacing < 0.05f || !size.x.IsFinite || !size.y.IsFinite || !size.z.IsFinite || size.x <= 0 || size.y <= 0 || size.z <= 0)
		{
			error.Set("Navigation size and cell spacing must be finite and positive.");
			return false;
		}
		let w = Math.Ceiling(size.x / spacing);
		let h = flight ? Math.Ceiling(size.y / spacing) : 1;
		let d = Math.Ceiling(size.z / spacing);
		if (w * h * d > 1000000 || w > 4096 || h > 4096 || d > 4096)
		{
			error.Set("Navigation grid exceeds one million cells. Increase cell size or reduce bounds.");
			return false;
		}
		origin = minimum;
		cellSize = spacing;
		flying = flight;
		chunkSize = Math.Max(chunk, 1);
		width = (int32)w;
		height = (int32)h;
		depth = (int32)d;
		cells.Clear();
		cells.Resize(width * height * depth);
		return true;
	}

	/// Closest usable cell within maxDistance. The cell the point is in wins when it is usable, so a point beside a thin
	/// wall is not moved across it. A region limits the answer to cells connected to that region.
	public int32 Nearest(Vector3 point, float maxDistance, int32 region = -1)
	{
		if (!maxDistance.IsFinite || maxDistance < 0 || !point.x.IsFinite || !point.y.IsFinite || !point.z.IsFinite || cells.Count != width * height * depth) return -1;
		if (region >= 0)
			EnsureRegions();
		int32 best = -1;
		float distance = maxDistance * maxDistance;
		int32 Bound(float p, int32 limit) => (int32)Mathf.Clamp(Math.Floor(p / cellSize), 0, limit - 1);
		let cx = (int32)Math.Floor((point.x - origin.x) / cellSize);
		let cz = (int32)Math.Floor((point.z - origin.z) / cellSize);
		let cy = flying ? (int32)Math.Floor((point.y - origin.y) / cellSize) : 0;
		if (Inside(cx, cy, cz))
		{
			let i = Index(cx, cy, cz);
			if (Usable(i) && (region < 0 || mRegions[i] == region) && (cells[i].position - point).LengthSquared <= distance) return i;
		}
		let x0 = Bound(point.x - origin.x - maxDistance, width);
		let x1 = Bound(point.x - origin.x + maxDistance, width);
		let z0 = Bound(point.z - origin.z - maxDistance, depth);
		let z1 = Bound(point.z - origin.z + maxDistance, depth);
		let y0 = flying ? Bound(point.y - origin.y - maxDistance, height) : 0;
		let y1 = flying ? Bound(point.y - origin.y + maxDistance, height) : 0;
		for (int32 y = y0; y <= y1; y++)
		{
			for (int32 z = z0; z <= z1; z++)
			{
				for (int32 x = x0; x <= x1; x++)
				{
					let i = Index(x, y, z);
					if (!Usable(i) || (region >= 0 && mRegions[i] != region)) continue;
					let d = (cells[i].position - point).LengthSquared;
					if (d <= distance)
					{
						distance = d;
						best = i;
					}
				}
			}
		}
		return best;
	}

	struct HeapItem
	{
		public int32 id;
		public float priority;
		public this(int32 id, float priority)
		{
			this.id = id;
			this.priority = priority;
		}
	}

	static void Push(List<HeapItem> heap, HeapItem item)
	{
		heap.Add(item);
		int index = heap.Count - 1;
		while (index > 0)
		{
			let parent = (index - 1) / 2;
			if (heap[parent].priority <= item.priority) break;
			heap[index] = heap[parent];
			index = parent;
		}
		heap[index] = item;
	}

	static HeapItem Pop(List<HeapItem> heap)
	{
		let result = heap[0];
		let tail = heap.Back;
		heap.RemoveAt(heap.Count - 1);
		if (heap.Count > 0)
		{
			int index = 0;
			while (index * 2 + 1 < heap.Count)
			{
				var child = index * 2 + 1;
				if (child + 1 < heap.Count && heap[child + 1].priority < heap[child].priority)
					child++;
				if (tail.priority <= heap[child].priority) break;
				heap[index] = heap[child];
				index = child;
			}
			heap[index] = tail;
		}
		return result;
	}

	/// Labels cells so two cells with different labels can never reach each other. Links are treated as two-way here, so
	/// equal labels do not promise a route; they only make the common unreachable case free.
	void EnsureRegions()
	{
		if (mRegionRevision == Revision && mRegions.Count == cells.Count) return;
		mRegions.Clear();
		mRegions.Resize(cells.Count);
		for (int i < cells.Count)
			mRegions[i] = -1;
		List<int32> stack = scope .();
		int32 next = 0;
		for (int32 seed = 0; seed < (int32)cells.Count; seed++)
		{
			if (!cells[seed].walkable || mRegions[seed] >= 0) continue;
			mRegions[seed] = next;
			stack.Add(seed);
			while (stack.Count > 0)
			{
				let id = stack.PopBack();
				for (int32 direction = 0; direction < DirectionCount; direction++)
				{
					if (!Uses(direction)) continue;
					let other = Neighbor(id, direction);
					if (other < 0 || !cells[other].walkable || mRegions[other] >= 0) continue;
					if ((cells[id].links & (1u << direction)) == 0 && (cells[other].links & (1u << Opposite(direction))) == 0) continue;
					mRegions[other] = next;
					stack.Add(other);
				}
			}
			next++;
		}
		// Links join the regions at their ends: relabel each to the smallest it is joined to.
		if (!links.IsEmpty)
		{
			let joined = scope List<int32>();
			for (int32 r < next)
				joined.Add(r);
			int32 Root(int32 r)
			{
				var at = r;
				while (joined[at] != at)
					at = joined[at];
				return at;
			}
			for (let link in links)
			{
				let a = mRegions[link.from], b = mRegions[link.to];
				if (a < 0 || b < 0)
					continue;
				let ra = Root(a), rb = Root(b);
				if (ra != rb)
					joined[Math.Max(ra, rb)] = Math.Min(ra, rb);
			}
			for (int i < mRegions.Count)
			{
				if (mRegions[i] >= 0)
					mRegions[i] = Root(mRegions[i]);
			}
		}
		mRegionRevision = Revision;
	}

	public int32 Region(int32 cell)
	{
		EnsureRegions();
		return cell >= 0 && cell < mRegions.Count ? mRegions[cell] : -1;
	}

	/// One point per cell from the cell nearest `from` to the cell nearest `to`. The goal snaps to a cell connected to the
	/// start when one is in range, and a goal in another region fails without searching.
	public bool FindPath(Vector3 from, Vector3 to, List<Vector3> path, float snapDistance = 2, int32 maxVisited = 200000) => FindPath(from, to, path, null, snapDistance, maxVisited);

	/// FindPath that also says, for each leg (point i to i + 1), which link it crosses (its id), or -1 for a step
	/// across the grid.
	public bool FindPath(Vector3 from, Vector3 to, List<Vector3> path, List<int32> legLinks, float snapDistance = 2, int32 maxVisited = 200000)
	{
		path.Clear();
		legLinks?.Clear();
		BudgetExceeded = false;
		if (cells.Count != width * height * depth) return false;
		let start = Nearest(from, snapDistance);
		if (start < 0) return false;
		EnsureRegions();
		let goal = Nearest(to, snapDistance, mRegions[start]);
		if (goal < 0) return false;
		if (mSeen.Count != cells.Count)
		{
			mCost.Clear();
			mCost.Resize(cells.Count);
			mParent.Clear();
			mParent.Resize(cells.Count);
			mSeen.Clear();
			mSeen.Resize(cells.Count);
			mClosed.Clear();
			mClosed.Resize(cells.Count);
			mParentLink.Clear();
			mParentLink.Resize(cells.Count);
			for (int i < cells.Count)
			{
				mSeen[i] = 0;
				mClosed[i] = 0;
			}
			mSearch = 0;
		}
		mSearch++;
		mOpen.Clear();
		mCost[start] = 0;
		mParent[start] = -1;
		mParentLink[start] = -1;
		mSeen[start] = mSearch;
		Push(mOpen, .(start, 0));
		int visited = 0;
		while (mOpen.Count > 0)
		{
			let id = Pop(mOpen).id;
			if (mClosed[id] == mSearch) continue;
			if (visited >= maxVisited)
			{
				BudgetExceeded = true;
				break;
			}
			mClosed[id] = mSearch;
			visited++;
			if (id == goal)
			{
				var cursor = goal;
				while (cursor >= 0)
				{
					path.Add(cells[cursor].position);
					// The leg into this cell, read backwards: it is put the right way round below.
					if (legLinks != null && mParent[cursor] >= 0)
						legLinks.Add(mParentLink[cursor]);
					cursor = mParent[cursor];
				}
				for (int i = 0; i < path.Count / 2; i++)
				{
					let p = path[i];
					path[i] = path[path.Count - 1 - i];
					path[path.Count - 1 - i] = p;
				}
				if (legLinks != null)
				{
					for (int i = 0; i < legLinks.Count / 2; i++)
						Swap!(legLinks[i], legLinks[legLinks.Count - 1 - i]);
					// One entry per point, so the last point (no leg after it) has -1.
					legLinks.Add(-1);
				}
				return true;
			}
			for (int32 direction = 0; direction < DirectionCount; direction++)
			{
				if (!Uses(direction) || (cells[id].links & (1u << direction)) == 0) continue;
				let next = Neighbor(id, direction);
				if (next < 0 || mClosed[next] == mSearch || !Usable(next)) continue;
				let g = mCost[id] + (cells[next].position - cells[id].position).Length * CostScale(next);
				if (mSeen[next] == mSearch && g >= mCost[next]) continue;
				mCost[next] = g;
				mParent[next] = id;
				mParentLink[next] = -1;
				mSeen[next] = mSearch;
				// The slight overweight breaks ties toward the goal, so open space is not flooded.
				Push(mOpen, .(next, g + Estimate(next, goal) * 1.001f));
			}
			// Links from this cell.
			if (mLinksAt.TryGetValue(id, let here))
			{
				for (let index in here)
				{
					let link = links[index];
					let next = link.from == id ? link.to : link.from;
					if (mClosed[next] == mSearch || !Usable(next)) continue;
					let g = mCost[id] + Math.Max(link.cost, 0.01f);
					if (mSeen[next] == mSearch && g >= mCost[next]) continue;
					mCost[next] = g;
					mParent[next] = id;
					mParentLink[next] = link.id;
					mSeen[next] = mSearch;
					Push(mOpen, .(next, g + Estimate(next, goal) * 1.001f));
				}
			}
		}
		return false;
	}

	/// The nearest usable point within maxDistance (a cell's floor, or centre flying). False when there is none.
	public bool SamplePosition(Vector3 point, float maxDistance, out Vector3 found)
	{
		let cell = Nearest(point, maxDistance);
		found = cell >= 0 ? cells[cell].position : point;
		return cell >= 0;
	}

	/// A random usable point within radius of a centre, reachable from it (for wandering). False when there is none.
	public bool RandomPoint(Vector3 center, float radius, Random random, out Vector3 found)
	{
		found = center;
		let start = Nearest(center, Math.Max(radius, cellSize * 2));
		if (start < 0)
			return false;
		let region = Region(start);
		// Picks a few spots and takes the first that lands on a usable, connected cell.
		for (int attempt < 32)
		{
			let angle = (float)random.NextDouble() * Math.PI_f * 2;
			let distance = Math.Sqrt((float)random.NextDouble()) * radius;
			var point = center + .(Math.Cos(angle) * distance, 0, Math.Sin(angle) * distance);
			if (flying)
				point.y += ((float)random.NextDouble() * 2 - 1) * radius;
			let cell = CellAt(point);
			if (Usable(cell) && Region(cell) == region)
			{
				found = cells[cell].position;
				return true;
			}
		}
		found = cells[start].position;
		return true;
	}

	/// How far an agent can go straight from a towards b before something stops it: true when nothing does.
	public bool Raycast(Vector3 from, Vector3 to, out Vector3 hit) => LineClear(from, to, out hit);

	static void Put(List<uint8> bytes, uint32 value)
	{
		for (int shift = 0; shift < 32; shift += 8)
			bytes.Add((uint8)(value >> shift));
	}

	static void Put(List<uint8> bytes, float value)
	{
		var copy = value;
		Put(bytes, *(uint32*)&copy);
	}

	static uint32 Get(List<uint8> bytes, ref int cursor)
	{
		let v = (uint32)bytes[cursor] | ((uint32)bytes[cursor + 1] << 8) | ((uint32)bytes[cursor + 2] << 16) | ((uint32)bytes[cursor + 3] << 24);
		cursor += 4;
		return v;
	}

	static float GetFloat(List<uint8> bytes, ref int cursor)
	{
		var bits = Get(bytes, ref cursor);
		return *(float*)&bits;
	}

	bool ValidGrid(int64 count) => width > 0 && height > 0 && depth > 0 && width <= 4096 && height <= 4096 && depth <= 4096 && (int64)width * height * depth <= 1000000 && cellSize >= 0.05f && cellSize.IsFinite && chunkSize >= 1 && (flying || height == 1) && count == (int64)width * height * depth && origin.x.IsFinite && origin.y.IsFinite && origin.z.IsFinite;
	/// Binary: "TNAV", version 2, the grid settings, then one word per cell (links, top bit = usable) plus the floor
	/// height for walking cells. Everything else about a cell follows from its index.
	public bool Save(StringView path, String error)
	{
		List<uint8> bytes = scope .();
		bytes.Reserve(64 + cells.Count * (flying ? 4 : 8));
		bytes.Add((uint8)'T');
		bytes.Add((uint8)'N');
		bytes.Add((uint8)'A');
		bytes.Add((uint8)'V');
		Put(bytes, (uint32)2);
		Put(bytes, origin.x);
		Put(bytes, origin.y);
		Put(bytes, origin.z);
		Put(bytes, cellSize);
		Put(bytes, (uint32)width);
		Put(bytes, (uint32)height);
		Put(bytes, (uint32)depth);
		Put(bytes, (uint32)chunkSize);
		Put(bytes, flying ? 1u : 0u);
		Put(bytes, agentRadius);
		Put(bytes, agentHeight);
		Put(bytes, maxStep);
		Put(bytes, maxSlope);
		for (let c in cells)
		{
			Put(bytes, (c.links & 0x7FFFFFFF) | (c.walkable ? 0x80000000u : 0u));
			if (!flying)
				Put(bytes, c.position.y);
		}
		if (File.WriteAll(path, bytes) case .Err)
		{
			error.Set("Cannot write navigation asset.");
			return false;
		}
		return true;
	}

	public bool Load(StringView path, String error)
	{
		List<uint8> bytes = scope .();
		if (AssetPack.ReadAll(path, bytes) case .Err)
		{
			error.Set("Cannot read navigation asset.");
			return false;
		}
		if (bytes.Count < 4 || bytes[0] != (uint8)'T' || bytes[1] != (uint8)'N' || bytes[2] != (uint8)'A' || bytes[3] != (uint8)'V') return LoadText(StringView((char8*)bytes.Ptr, bytes.Count), error);
		const int HeaderSize = 60;
		int cursor = 4;
		cells.Clear();
		if (bytes.Count < HeaderSize || Get(bytes, ref cursor) != 2)
		{
			error.Set("Unsupported navigation asset version.");
			return false;
		}
		origin.x = GetFloat(bytes, ref cursor);
		origin.y = GetFloat(bytes, ref cursor);
		origin.z = GetFloat(bytes, ref cursor);
		cellSize = GetFloat(bytes, ref cursor);
		width = (int32)Get(bytes, ref cursor);
		height = (int32)Get(bytes, ref cursor);
		depth = (int32)Get(bytes, ref cursor);
		chunkSize = (int32)Get(bytes, ref cursor);
		flying = Get(bytes, ref cursor) == 1;
		agentRadius = GetFloat(bytes, ref cursor);
		agentHeight = GetFloat(bytes, ref cursor);
		maxStep = GetFloat(bytes, ref cursor);
		maxSlope = GetFloat(bytes, ref cursor);
		let count = (int64)(bytes.Count - HeaderSize) / (flying ? 4 : 8);
		if (!ValidGrid(count) || (int64)bytes.Count != HeaderSize + count * (flying ? 4 : 8))
		{
			width = height = depth = 0;
			error.Set("Invalid navigation dimensions.");
			return false;
		}
		cells.Resize((int)count);
		for (int32 y = 0; y < height; y++)
		{
			for (int32 z = 0; z < depth; z++)
			{
				for (int32 x = 0; x < width; x++)
				{
					let word = Get(bytes, ref cursor);
					Cell cell = default;
					cell.walkable = (word & 0x80000000) != 0;
					cell.links = word & 0x7FFFFFFF;
					cell.position = Center(x, y, z);
					if (!flying)
					{
						cell.position.y = GetFloat(bytes, ref cursor);
						if (!cell.position.y.IsFinite)
						{
							cells.Clear();
							error.Set("Navigation cell has a non-finite position.");
							return false;
						}
					}
					cells[Index(x, y, z)] = cell;
				}
			}
		}
		Touch();
		return true;
	}

	/// Reads the version 1 text format written by earlier builds. Those assets have no diagonal links; bake again to add them.
	bool LoadText(StringView text, String error)
	{
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer
		{
			for (let item in storage)
				delete item;
		}
		bool header = false, grid = false;
		cells.Clear();
		for (let line in text.Split('\n'))
		{
			tokens.Clear();
			SceneSerializer.Tokenize(line, tokens, storage);
			if (tokens.Count == 0) continue;
			if (tokens.Count == 2 && tokens[0] == "navigation" && tokens[1] == "1" && !header)
				header = true;
			else if (tokens.Count == 15 && tokens[0] == "grid" && header && !grid)
			{
				origin = .(SceneSerializer.ParseFloat(tokens[1]), SceneSerializer.ParseFloat(tokens[2]), SceneSerializer.ParseFloat(tokens[3]));
				cellSize = SceneSerializer.ParseFloat(tokens[4]);
				width = SceneSerializer.ParseInt(tokens[5]);
				height = SceneSerializer.ParseInt(tokens[6]);
				depth = SceneSerializer.ParseInt(tokens[7]);
				chunkSize = SceneSerializer.ParseInt(tokens[8]);
				flying = tokens[9] == "1";
				agentRadius = SceneSerializer.ParseFloat(tokens[10]);
				agentHeight = SceneSerializer.ParseFloat(tokens[11]);
				maxStep = SceneSerializer.ParseFloat(tokens[12]);
				maxSlope = SceneSerializer.ParseFloat(tokens[13]);
				if (width <= 0 || height <= 0 || depth <= 0 || width > 4096 || height > 4096 || depth > 4096 || (int64)width * height * depth > 1000000 || cellSize < 0.05f || !cellSize.IsFinite || chunkSize < 1 || (!flying && height != 1) || SceneSerializer.ParseInt(tokens[14]) != (int64)width * height * depth || !origin.x.IsFinite || !origin.y.IsFinite || !origin.z.IsFinite)
				{
					error.Set("Invalid navigation dimensions.");
					return false;
				}
				grid = true;
			}
			else if (tokens.Count == 6 && tokens[0] == "cell" && grid && cells.Count < width * height * depth)
				cells.Add(.() { walkable = tokens[1] == "1", position = .(SceneSerializer.ParseFloat(tokens[2]), SceneSerializer.ParseFloat(tokens[3]), SceneSerializer.ParseFloat(tokens[4])), links = (uint32)SceneSerializer.ParseInt(tokens[5]) & 0x3F });
			else
			{
				error.Set("Malformed navigation asset.");
				return false;
			}
		}
		for (let cell in cells)
		{
			if (!cell.position.x.IsFinite || !cell.position.y.IsFinite || !cell.position.z.IsFinite)
			{
				error.Set("Navigation cell has a non-finite position.");
				return false;
			}
		}
		if (!grid || cells.Count != width * height * depth)
		{
			error.Set("Incomplete navigation asset.");
			return false;
		}
		Touch();
		return true;
	}
}
