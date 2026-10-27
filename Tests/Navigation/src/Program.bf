using System;
using System.Collections;
using System.IO;
using Tessera;

namespace NavigationTests;

class Program
{
	static bool Check(bool pass, StringView label)
	{
		Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}");
		return pass;
	}

	static NavigationSurface Floor(Scene scene, Vector3 at, Vector3 size, String name)
	{
		let floor = scene.CreateGameObject(name);
		floor.Transform.Position = at + Vector3(size.x * 0.5f, -0.5f, size.z * 0.5f);
		floor.AddComponent<BoxCollider>().size = .(size.x, 1, size.z);
		return null;
	}

	/// E14: smoothing, queries, obstacles, areas, links and avoidance.
	static bool Upgrades()
	{
		bool ok = true;
		let scene = scope Scene();
		Scene.Active = scene;
		// Two islands: a 20 x 12 floor with a wall part way across it, and a small one beyond a 3 metre gap.
		Floor(scene, .(0, 0, 0), .(20, 1, 12), "Main Floor");
		Floor(scene, .(23, 0, 0), .(5, 1, 5), "Island");
		let wall = scene.CreateGameObject("Wall");
		wall.Transform.Position = .(10, 1.5f, 4);
		wall.AddComponent<BoxCollider>().size = .(1, 3, 8);
		let surface = scene.CreateGameObject("Navigation").AddComponent<NavigationSurface>();
		surface.size = .(28, 5, 12);
		surface.cellSize = 0.5f;
		ok &= Check(surface.Bake(), "the islands bake");
		let data = surface.Data;
		List<Vector3> path = scope .();
		List<int32> legs = scope .();

		// ---- any-angle paths ----
		ok &= Check(data.FindPath(.(1, 0, 11), .(18, 0, 9.5f), path, legs, 2) && path.Count > 10 && legs.Count == path.Count, "a grid path has a point per cell, and a leg entry per point");
		data.Smooth(path, legs);
		ok &= Check(path.Count == 2 && legs.Count == 2, scope $"in the open, smoothing leaves one straight leg ({path.Count} points)");
		data.FindPath(.(1, 0, 1), .(18, 0, 1), path, legs, 2);
		data.Smooth(path, legs);
		// No leg comes within the agent's radius of the wall (x 9.5 to 10.5, z up to 8).
		bool clear = path.Count >= 3 && path.Count < 12;
		for (int i = 0; i + 1 < path.Count; i++)
		{
			for (int k <= 20)
			{
				let p = Vector3.Lerp(path[i], path[i + 1], k / 20.0f);
				let dx = Math.Max(Math.Max(9.5f - p.x, p.x - 10.5f), 0);
				let dz = Math.Max(p.z - 8, 0);
				clear &= dx * dx + dz * dz >= 0.29f * 0.29f;
			}
		}
		let shown = scope String();
		for (let p in path)
			shown.AppendF(" ({:0.00} {:0.00})", p.x, p.z);
		ok &= Check(clear, scope $"round the wall it keeps the corners it needs, and no leg cuts through:{shown}");
		ok &= Check(!data.Raycast(.(8, 0, 2), .(12, 0, 2), let hit) && hit.x < 10 - 0.5f && hit.x > 8, scope $"a raycast stops before the wall ({hit.x})");
		ok &= Check(data.Raycast(.(2, 0, 10), .(18, 0, 10), ?), "and goes through where there is none");
		ok &= Check(data.SamplePosition(.(3.1f, 2, 3.1f), 3, let sampled) && Math.Abs(sampled.y) < 0.1f && !data.SamplePosition(.(50, 0, 50), 2, ?), "SamplePosition finds the floor near a point");
		let random = scope Random(7);
		bool wander = true;
		for (int i < 20)
		{
			wander &= data.RandomPoint(.(4, 0, 4), 3, random, let point) && (Vector3(point.x, 0, point.z) - Vector3(4, 0, 4)).Length <= 3.6f && data.Usable(data.CellAt(point));
		}
		ok &= Check(wander, "RandomPoint picks usable spots within the radius");
		ok &= Check(data.RandomPoint(.(25, 0, 2), 6, random, let onIsland) && onIsland.x > 23, "and only ones reachable from the centre");

		// An agent with smoothing walks straight across open floor.
		let walker = scene.CreateGameObject("Walker");
		walker.Transform.Position = .(1, 0.02f, 11);
		let agent = walker.AddComponent<NavigationAgent>();
		agent.surface = surface;
		agent.SetDestination(.(18, 0.02f, 9.5f), 4, 0.1f);
		Time.DeltaTime = 0.05f;
		float off = 0;
		for (int i = 0; i < 200 && !agent.HasArrived; i++)
		{
			agent.Update();
			// Distance from the straight line between start and goal, on the ground.
			let p = walker.Transform.Position;
			let a = Vector3(1, 0, 11);
			let d = Vector3(17, 0, -1.5f).Normalized;
			let rel = Vector3(p.x, 0, p.z) - a;
			off = Math.Max(off, (rel - d * Vector3.Dot(rel, d)).Length);
		}
		ok &= Check(agent.HasArrived && off < 0.3f && agent.Path.Count == 2, scope $"a smoothing agent goes straight there (strays {off:0.00})");

		// ---- obstacles ----
		let crate = scene.CreateGameObject("Crate");
		crate.Transform.Position = .(5, 0.5f, 6);
		let obstacle = crate.AddComponent<NavigationObstacle>();
		obstacle.size = .(1, 1, 12);
		surface.RefreshOverlay();
		ok &= Check(data.Blocked(data.CellAt(.(5, 0, 6))) && !data.Usable(data.CellAt(.(5, 0, 3))) && data.Usable(data.CellAt(.(7, 0, 6))), "a carving obstacle blocks the cells under it and its agent's radius around it");
		ok &= Check(!data.FindPath(.(1, 0, 6), .(8, 0, 6), path, 2), "a path across the blocked strip fails");
		obstacle.size = .(1, 1, 4);
		surface.RefreshOverlay();
		float Length(List<Vector3> points)
		{
			float total = 0;
			for (int i = 0; i + 1 < points.Count; i++)
				total += (points[i + 1] - points[i]).Length;
			return total;
		}
		ok &= Check(data.FindPath(.(1, 0, 6), .(8, 0, 6), path, 2) && Length(path) > 7.6f, scope $"a smaller one is walked round, once the surface sees the change ({Length(path):0.0} m)");
		obstacle.Enabled = false;
		surface.RefreshOverlay();
		ok &= Check(!data.Blocked(data.CellAt(.(5, 0, 6))) && data.FindPath(.(1, 0, 6), .(8, 0, 6), path, 2) && path.Count <= 16, "and when it goes the cells are free again");
		obstacle.Enabled = true;
		// Moving and standing still.
		Time.DeltaTime = 0.1f;
		obstacle.Update();
		crate.Transform.Position = .(5, 0.5f, 7);
		obstacle.Update();
		ok &= Check(!obstacle.Carving && obstacle.Velocity.z > 5, "a moving obstacle does not carve, and knows how fast it goes");
		for (int i < 6)
			obstacle.Update();
		ok &= Check(obstacle.Carving && obstacle.CarvedPosition.z == 7, "once it has stood still for Stationary Time it carves where it stands");
		obstacle.Enabled = false;
		surface.RefreshOverlay();

		// ---- areas ----
		let mud = scene.CreateGameObject("Mud");
		mud.Transform.Position = .(4, 0, 6);
		let area = mud.AddComponent<NavigationArea>();
		area.size = .(2, 2, 4);
		area.cost = 10;
		surface.RefreshOverlay();
		ok &= Check(data.CostScale(data.CellAt(.(4, 0, 6))) == 10 && data.CostScale(data.CellAt(.(4, 0, 1))) == 1, "an area makes its cells cost more");
		data.FindPath(.(1, 0, 6), .(7, 0, 6), path, 2);
		bool avoided = true;
		for (let point in path)
			avoided &= !(Math.Abs(point.x - 4) < 1 && Math.Abs(point.z - 6) < 2);
		ok &= Check(avoided, "paths go round a costly area");
		area.cost = 1.05f;
		surface.RefreshOverlay();
		data.FindPath(.(1, 0, 6), .(7, 0, 6), path, 2);
		ok &= Check(path.Count <= 14, "but through a cheap one");
		area.blocked = true;
		surface.RefreshOverlay();
		ok &= Check(!data.Usable(data.CellAt(.(4, 0, 6))), "a blocked area is not walkable at all");
		area.Enabled = false;
		surface.RefreshOverlay();

		// ---- links ----
		ok &= Check(!data.FindPath(.(18, 0, 2), .(25, 0, 2), path, 2), "the island is out of reach without a link");
		let gap = scene.CreateGameObject("Gap Jump");
		gap.Transform.Position = .(19.6f, 0, 2.2f);
		let link = gap.AddComponent<NavigationLink>();
		link.end = .(3.8f, 0, 0);
		link.kind = .Jump;
		link.duration = 0.5f;
		surface.RefreshOverlay();
		ok &= Check(data.links.Count == 1 && data.FindPath(.(18, 0, 2), .(25, 0, 2), path, legs, 2) && legs.Contains(0) && surface.LinkOf(0) == link, "a link joins the island, and the path says which leg crosses it");
		ok &= Check(data.FindPath(.(25, 0, 2), .(18, 0, 2), path, 2), "both ways");
		let mid = link.Along(link.StartPoint, link.EndPoint, 0.5f);
		ok &= Check(mid.y > 0.9f && Math.Abs(link.Along(link.StartPoint, link.EndPoint, 1).y) < 0.001f, "a jump arcs above its ends");
		link.bidirectional = false;
		surface.RefreshOverlay();
		ok &= Check(data.FindPath(.(18, 0, 2), .(25, 0, 2), path, 2) && !data.FindPath(.(25, 0, 2), .(18, 0, 2), path, 2), "a one-way link goes only from its object to its end");
		let jumper = scene.CreateGameObject("Jumper");
		jumper.Transform.Position = .(17, 0.02f, 2);
		let jumps = jumper.AddComponent<NavigationAgent>();
		jumps.surface = surface;
		int started = 0, finished = 0;
		float highest = 0;
		jumps.OnLinkStarted.Add(new [&] (crossed) =>
			{
				started++;
			});
		jumps.OnLinkFinished.Add(new [&] (crossed) =>
			{
				finished++;
			});
		jumps.SetDestination(.(26, 0.02f, 2), 4, 0.1f);
		Time.DeltaTime = 0.05f;
		for (int i = 0; i < 300 && !jumps.HasArrived; i++)
		{
			jumps.Update();
			if (jumps.IsCrossingLink)
				highest = Math.Max(highest, jumper.Transform.Position.y);
		}
		ok &= Check(jumps.HasArrived && started == 1 && finished == 1 && highest > 0.8f && jumper.Transform.Position.x > 25, scope $"an agent jumps the gap and arrives, telling the game as it goes (top {highest:0.00})");
		jumps.useLinks = false;
		jumps.SetDestination(.(17, 0.02f, 2), 4, 0.1f);
		ok &= Check(jumps.PathFailed, "an agent that may not use links cannot leave the island");

		// ---- avoidance ----
		let left = scene.CreateGameObject("Left");
		left.Transform.Position = .(2, 0.02f, 9);
		let leftAgent = left.AddComponent<NavigationAgent>();
		leftAgent.surface = surface;
		let right = scene.CreateGameObject("Right");
		right.Transform.Position = .(8, 0.02f, 9);
		let rightAgent = right.AddComponent<NavigationAgent>();
		rightAgent.surface = surface;
		float Closest(bool avoid)
		{
			leftAgent.StopMovement();
			rightAgent.StopMovement();
			left.Transform.Position = .(2, 0.02f, 9);
			right.Transform.Position = .(8, 0.02f, 9);
			leftAgent.avoidOthers = rightAgent.avoidOthers = avoid;
			leftAgent.SetDestination(.(8, 0.02f, 9), 2, 0.1f);
			rightAgent.SetDestination(.(2, 0.02f, 9), 2, 0.1f);
			var closest = float.MaxValue;
			for (int i = 0; i < 300 && !(leftAgent.HasArrived && rightAgent.HasArrived); i++)
			{
				leftAgent.Update();
				rightAgent.Update();
				var gapBetween = left.Transform.Position - right.Transform.Position;
				gapBetween.y = 0;
				closest = Math.Min(closest, gapBetween.Length);
			}
			return leftAgent.HasArrived && rightAgent.HasArrived ? closest : -1;
		}
		let without = Closest(false);
		let with = Closest(true);
		ok &= Check(without >= 0 && without < 0.2f, scope $"without avoidance two agents walk through each other ({without:0.00})");
		ok &= Check(with >= 0.65f, scope $"with it they pass each other and both arrive ({with:0.00} apart at closest)");
		Scene.Active = null;
		return ok;
	}

	public static int Main(String[] args)
	{
		if (args.Count == 1)
		{
			Assets.ProjectPath.Set(args[0]);
			let sample = scope Scene();
			if (!SceneSerializer.LoadFromFile(sample, scope $"{args[0]}/Scenes/AIExample.tscene")) return 1;
			let surface = sample.Find("Navigation Surface").GetComponent<NavigationSurface>();
			if (!surface.Bake() || !surface.SaveData()) return 1;
			Console.WriteLine(scope $"PASS: example {surface.Data.cells.Count}-cell navigation baked without Play.");
			return 0;
		}
		bool ok = true;
		let error = scope String();
		let scene = scope Scene();
		Scene.Active = scene;
		let floor = scene.CreateGameObject("Floor");
		floor.Transform.Position = .(4, -0.5f, 4);
		floor.AddComponent<BoxCollider>().size = .(8, 1, 8);
		let wall = scene.CreateGameObject("Wall");
		wall.Transform.Position = .(4, 1.5f, 3);
		wall.AddComponent<BoxCollider>().size = .(1, 3, 6);
		let surface = scene.CreateGameObject("Navigation").AddComponent<NavigationSurface>();
		surface.size = .(8, 5, 8);
		surface.chunkSize = 2;
		ok &= Check(surface.Bake(), "editor bake works without entering play mode");
		ok &= Check(!scene.IsPlaying && scene.Physics.BodyCount == 0, "private bake world leaves scene physics untouched");
		List<Vector3> path = scope .();
		ok &= Check(surface.Data.FindPath(.(1.5f, 0, 1.5f), .(6.5f, 0, 1.5f), path) && path.Count > 10, "A star routes around wall on walking surface");
		bool around = false;
		for (let point in path)
		{
			if (point.z > 6)
				around = true;
		}
		ok &= Check(around, "route avoids blocked wall cells");
		surface.bakedData.Set("/tmp/tessera-navigation-test.tnav");
		defer
		{
			File.Delete(surface.bakedData);
		}
		ok &= Check(surface.SaveData(), "baked navigation saves to asset");
		let loaded = scope NavigationData();
		ok &= Check(loaded.Load(surface.bakedData, error) && loaded.FindPath(.(1.5f, 0, 1.5f), .(6.5f, 0, 1.5f), path), "saved data routes without runtime baking");
		let before = surface.Data.cells[surface.Data.Index(0, 0, 0)];
		let revision = surface.Data.Revision;
		wall.GetComponent<BoxCollider>().Enabled = false;
		ok &= Check(surface.Rebuild(.(.(3, 0, 0), .(5, 5, 6))) && surface.Data.Revision > revision, "dirty bounds rebuild affected chunks");
		ok &= Check(surface.Data.cells[0].position == before.position && surface.Data.cells[0].walkable == before.walkable, "distant cell survives chunk rebuild");
		ok &= Check(surface.Data.FindPath(.(1.5f, 0, 1.5f), .(6.5f, 0, 1.5f), path) && path.Count == 6, "rebuilt path uses newly opened shortcut");
		let generated = scene.CreateGameObject("Generated Mesh");
		generated.Transform.Position = .(4, 1.5f, 3);
		generated.Transform.LocalScale = .(1, 3, 6);
		let mesh = Primitives.CreateCube();
		defer
		{
			delete mesh;
		}
		generated.AddComponent<MeshRenderer>().RuntimeMesh = mesh;
		surface.Rebuild(.(.(3, 0, 0), .(5, 5, 6)));
		ok &= Check(surface.Data.FindPath(.(1.5f, 0, 1.5f), .(6.5f, 0, 1.5f), path) && path.Count > 10, "runtime mesh geometry blocks navigation without a collider");
		for (int i < mesh.Vertices.Count)
			mesh.Vertices[i].position.x += 20;
		mesh.RecalculateBounds();
		surface.Rebuild(.(.(3, 0, 0), .(5, 5, 6)));
		ok &= Check(surface.Data.FindPath(.(1.5f, 0, 1.5f), .(6.5f, 0, 1.5f), path) && path.Count == 6, "editable mesh geometry updates changed navigation chunks");
		let actor = scene.CreateGameObject("Actor Visual");
		actor.Transform.Position = .(2.5f, 0.5f, 1.5f);
		actor.AddComponent<NavigationAgent>();
		actor.AddComponent<MeshRenderer>();
		surface.Rebuild(.(.(2, 0, 1), .(3, 3, 2)));
		ok &= Check(Math.Abs(surface.Data.cells[surface.Data.Index(2, 0, 1)].position.y - 0.02f) < 0.01f, "actor visuals are excluded from static bake geometry");
		let flying = scope NavigationData();
		ok &= Check(flying.Configure(.(0, 0, 0), .(6, 6, 6), 1, true, 2, error), "flying volume configures 3D cells");
		let world = scope PhysicsWorld();
		ok &= Check(NavigationBaker.Rebuild(flying, world, 6, .(.Zero, .(6, 6, 6)), error) && flying.FindPath(.(0.5f, 0.5f, 0.5f), .(4.5f, 4.5f, 4.5f), path) && path.Count == 5, "flying route takes the 3D diagonal");
		let barrier = scene.CreateGameObject("Volume Barrier");
		barrier.Transform.Position = .(3, 3, 3);
		ShapeDesc shape = default;
		shape.kind = .Box;
		shape.halfExtents = .(0.3f, 4, 4);
		world.CreateBody(barrier.Transform, shape, null);
		NavigationBaker.Rebuild(flying, world, 6, .(.Zero, .(6, 6, 6)), error);
		ok &= Check(!flying.FindPath(.(0.5f, 0.5f, 0.5f), .(4.5f, 4.5f, 4.5f), path), "flight volume rejects route through sealed barrier");
		ok &= Check(!flying.Configure(.Zero, .(10000, 10000, 10000), 0.1f, true, 16, error), "oversized navigation allocation rejected");
		let mover = scene.CreateGameObject("Mover");
		mover.Transform.Position = .(1.5f, 0.02f, 1.5f);
		let nav = mover.AddComponent<NavigationAgent>();
		nav.surface = surface;
		nav.SetDestination(.(6.5f, 0.02f, 1.5f), 1, 0.1f);
		Time.DeltaTime = 0.1f;
		for (int i = 0; i < 80; i++)
			nav.Update();
		ok &= Check(nav.HasArrived && (mover.Transform.Position - Vector3(6.5f, 0.02f, 1.5f)).Length < 0.15f, "slow agent reaches destination despite repeated replanning");
		nav.SetDestination(.(6.7f, 0.02f, 1.7f), 1, 0.05f);
		for (int i = 0; i < 20; i++)
			nav.Update();
		ok &= Check(nav.HasArrived && !nav.PathFailed, "navigation arrives at snapped destination");
		bool opposite = true;
		for (int32 d = 0; d < NavigationData.DirectionCount; d++)
		{
			NavigationData.Offset(d, let ax, let ay, let az);
			NavigationData.Offset(NavigationData.Opposite(d), let bx, let by, let bz);
			opposite &= ax + bx == 0 && ay + by == 0 && az + bz == 0 && (ax != 0 || ay != 0 || az != 0) && NavigationData.Opposite(NavigationData.Opposite(d)) == d;
		}
		ok &= Check(opposite, "26 link directions pair up with their opposites");
		// Open volume: a long diagonal must cost about its own length, not the whole box.
		let open = scope NavigationData();
		open.Configure(.Zero, .(64, 64, 64), 1, true, 16, error);
		open.agentHeight = 0.6f;
		let emptyWorld = scope PhysicsWorld();
		NavigationBaker.Rebuild(open, emptyWorld, 64, .(.Zero, .(64, 64, 64)), error);
		ok &= Check(open.FindPath(.(0.5f, 0.5f, 0.5f), .(63.5f, 63.5f, 63.5f), path, 2, 500) && path.Count == 64 && !open.BudgetExceeded, "corner-to-corner flight found within a 500-cell budget");
		ok &= Check(open.FindPath(.(0.5f, 0.5f, 0.5f), .(63.5f, 20.5f, 40.5f), path, 2, 500) && path.Count == 64, "off-axis flight is as short as the grid allows");
		ok &= Check(!open.FindPath(.(0.5f, 0.5f, 0.5f), .(63.5f, 63.5f, 63.5f), path, 2, 10) && open.BudgetExceeded, "an exhausted budget is reported as such");
		let flightFile = "/tmp/tessera-navigation-flight.tnav";
		defer
		{
			File.Delete(flightFile);
		}
		let reloaded = scope NavigationData();
		ok &= Check(flying.Save(flightFile, error) && reloaded.Load(flightFile, error) && reloaded.cells.Count == flying.cells.Count, "flight volume saves and loads in the binary format");
		bool same = reloaded.flying && reloaded.width == flying.width && reloaded.agentHeight == flying.agentHeight;
		for (int i < reloaded.cells.Count)
			same &= reloaded.cells[i].walkable == flying.cells[i].walkable && reloaded.cells[i].links == flying.cells[i].links && (reloaded.cells[i].position - flying.cells[i].position).Length < 0.0001f;
		ok &= Check(same, "binary flight data matches what was baked");
		let walkFile = "/tmp/tessera-navigation-walk.tnav";
		defer
		{
			File.Delete(walkFile);
		}
		let walk = scope NavigationData();
		same = surface.Data.Save(walkFile, error) && walk.Load(walkFile, error) && walk.cells.Count == surface.Data.cells.Count;
		if (same)
		{
			for (int i < walk.cells.Count)
				same &= walk.cells[i].walkable == surface.Data.cells[i].walkable && walk.cells[i].links == surface.Data.cells[i].links && (walk.cells[i].position - surface.Data.cells[i].position).Length < 0.0001f;
		}
		ok &= Check(same, "binary walking data keeps floor heights and links");
		File.WriteAllText(walkFile, "navigation 1\ngrid 0 0 0 1 2 1 1 16 0 0.3 1.8 0.5 45 2\ncell 1 0.5 0.02 0.5 1\ncell 1 1.5 0.02 0.5 2\n");
		ok &= Check(walk.Load(walkFile, error) && walk.FindPath(.(0.5f, 0, 0.5f), .(1.5f, 0, 0.5f), path) && path.Count == 2, "version 1 text assets still load");
		File.WriteAllText(walkFile, "TNAV garbage");
		ok &= Check(!walk.Load(walkFile, error), "truncated binary asset rejected");
		// The sealed barrier from above splits the volume in two; the far side is rejected before any search.
		ok &= Check(flying.Region(flying.Nearest(.(0.5f, 0.5f, 0.5f), 1)) != flying.Region(flying.Nearest(.(4.5f, 4.5f, 4.5f), 1)) && !flying.FindPath(.(0.5f, 0.5f, 0.5f), .(4.5f, 4.5f, 4.5f), path, 2, 0) && !flying.BudgetExceeded, "unreachable region rejected without searching");
		ok &= Check(flying.FindPath(.(1.5f, 2.5f, 2.5f), .(3.4f, 2.5f, 2.5f), path, 2) && path.Back.x < 3, "goal beside the barrier snaps to the reachable side");
		let first = scope NavigationData();
		let second = scope NavigationData();
		first.Configure(.Zero, .(2, 2, 2), 1, true, 2, error);
		second.Configure(.Zero, .(2, 2, 2), 1, true, 2, error);
		NavigationBaker.Rebuild(first, emptyWorld, 2, .(.Zero, .(2, 2, 2)), error);
		NavigationBaker.Rebuild(second, emptyWorld, 2, .(.Zero, .(2, 2, 2)), error);
		ok &= Check(first.Revision != second.Revision, "a fresh bake never repeats another bake's revision");

		// Flying agent: follows a baked volume loaded from disk, on all three axes.
		let sky = scene.CreateGameObject("Sky").AddComponent<NavigationSurface>();
		sky.Transform.Position = .(100, 0, 0);
		sky.size = .(12, 12, 12);
		sky.flying = true;
		sky.agentHeight = 0.6f;
		let pillar = scene.CreateGameObject("Pillar");
		pillar.Transform.Position = .(106, 6, 106 - 100);
		pillar.AddComponent<BoxCollider>().size = .(2, 12, 2);
		ok &= Check(sky.Bake() && sky.Data.flying, "flight surface bakes from scene colliders");
		let flyer = scene.CreateGameObject("Flyer");
		flyer.Transform.Position = .(101.5f, 1.5f, 6.5f);
		let wings = flyer.AddComponent<NavigationAgent>();
		wings.surface = sky;
		wings.SetDestination(.(110.5f, 9.5f, 6.5f), 4, 0.1f);
		float clearance = float.MaxValue;
		for (int i = 0; i < 200 && !wings.HasArrived; i++)
		{
			wings.Update();
			let p = flyer.Transform.Position;
			clearance = Math.Min(clearance, Math.Max(Math.Abs(p.x - 106), Math.Abs(p.z - 6)) - 1);
		}
		ok &= Check(wings.HasArrived && (flyer.Transform.Position - Vector3(110.5f, 9.5f, 6.5f)).Length < 0.15f && clearance >= 0.3f, "flying agent climbs around a pillar and arrives");
		let searches = sky.Data.Revision;
		wings.SetDestination(.(101.5f, 1.5f, 1.5f), 4, 0.1f);
		let legs = wings.Path.Count;
		for (int i = 0; i < 10; i++)
			wings.Update();
		ok &= Check(legs >= 2 && wings.Path.Count == legs && sky.Data.Revision == searches, "an agent on course keeps its path between searches");
		pillar.GetComponent<BoxCollider>().Enabled = false;
		sky.Rebuild(.(.(105, 0, 5), .(107, 12, 7)));
		wings.SetDestination(.(110.5f, 6.5f, 6.5f), 4, 0.1f);
		for (int i = 0; i < 10; i++)
			wings.Update();
		wings.SetDestination(.(110.5f, 6.5f, 6.5f), 4, 0.1f);
		ok &= Check(!wings.PathFailed && wings.Path.Count >= 2, "agent replans after its surface is rebuilt");

		// Dynamic bodies: steering only while following, and walking arrival that ignores a pivot height mismatch.
		let ball = scene.CreateGameObject("Ball");
		ball.Transform.Position = .(1.5f, 0.6f, 6.5f);
		ball.AddComponent<SphereCollider>().radius = 0.3f;
		let body = ball.AddComponent<Rigidbody>();
		body.useGravity = false;
		body.linearDamping = 0;
		body.EnsureBody();
		let roller = ball.AddComponent<NavigationAgent>();
		roller.surface = surface;
		body.Velocity = .(0, 0, -2);
		roller.FixedUpdate();
		ok &= Check(body.HasBody && Math.Abs(body.Velocity.z + 2) < 0.001f, "idle agent leaves its body's velocity alone");
		roller.SetDestination(.(6.5f, 0.6f, 6.5f), 3, 0.1f);
		for (int i = 0; i < 400 && !roller.HasArrived; i++)
		{
			roller.FixedUpdate();
			scene.Physics.Step(Time.FixedDeltaTime);
		}
		ok &= Check(roller.HasArrived && Math.Abs(ball.Transform.Position.x - 6.5f) < 0.15f && Math.Abs(ball.Transform.Position.z - 6.5f) < 0.15f, "dynamic walking agent arrives with its pivot 0.6 above the floor");
		roller.FixedUpdate();
		body.Velocity = .(0, 0, -2);
		roller.FixedUpdate();
		ok &= Check(Math.Abs(body.Velocity.z + 2) < 0.001f, "arrived agent can be pushed");
		ok &= Upgrades();
		Scene.Active = null;
		return ok ? 0 : 1;
	}
}
