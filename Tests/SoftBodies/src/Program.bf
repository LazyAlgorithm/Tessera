using System;
using System.Collections;
using Tessera;

namespace SoftBodyTests;

class Program
{
	static bool Check(bool pass, StringView label)
	{
		Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}");
		return pass;
	}

	/// A square sheet in the object's XZ plane, `cells` squares across, `size` metres wide.
	static Mesh Sheet(int cells, float size)
	{
		let mesh = new Mesh();
		for (int z <= cells)
		{
			for (int x <= cells)
				mesh.AddVertex(.((x / (float)cells - 0.5f) * size, 0, (z / (float)cells - 0.5f) * size), .Up, .White, .(x / (float)cells, z / (float)cells));
		}
		for (int z < cells)
		{
			for (int x < cells)
			{
				let a = (uint32)(z * (cells + 1) + x);
				mesh.AddTriangle(a, a + (uint32)cells + 1, a + 1);
				mesh.AddTriangle(a + 1, a + (uint32)cells + 1, a + (uint32)cells + 2);
			}
		}
		return mesh;
	}

	/// A level sheet pinned along its far edge (its last row, z = +size/2): the rest swings down and hangs from it.
	static SoftBody Curtain(Scene scene, Mesh sheet, Vector3 position, int cells)
	{
		let object = scene.CreateGameObject("Curtain");
		object.Transform.Position = position;
		object.AddComponent<MeshRenderer>().RuntimeMesh = sheet;
		let soft = object.AddComponent<SoftBody>();
		soft.pins.Set(scope $"{cells * (cells + 1)}-{(cells + 1) * (cells + 1) - 1}");
		// Settles within the test rather than swinging on.
		soft.damping = 1;
		return soft;
	}

	static void Run(Scene scene, int ticks)
	{
		for (int i < ticks)
			scene.FixedUpdate();
	}

	static Vector3 Lowest(List<Vector3> points)
	{
		var lowest = points[0];
		for (let p in points)
		{
			if (p.y < lowest.y)
				lowest = p;
		}
		return lowest;
	}

	static Vector3 Average(List<Vector3> points)
	{
		var sum = Vector3.Zero;
		for (let p in points)
			sum = sum + p;
		return sum / points.Count;
	}

	static GameObject MakeJelly(Scene scene)
	{
		let ball = scene.CreateGameObject("Jelly");
		ball.AddComponent<NetworkIdentity>();
		ball.AddComponent<MeshRenderer>().mesh.Set("builtin:sphere");
		ball.AddComponent<SoftBody>().kind = .Jelly;
		return ball;
	}

	static void Floor(Scene scene)
	{
		let floor = scene.CreateGameObject("Floor");
		floor.Transform.Position = .(0, -0.5f, 0);
		floor.AddComponent<BoxCollider>().size = .(40, 1, 40);
	}

	/// Ticks both machines at a steady pace.
	static void Pump(Scene a, Scene b, int ticks)
	{
		for (int i < ticks)
		{
			for (let scene in Scene[?](a, b))
			{
				scene.FixedUpdate();
				scene.Update();
			}
			System.Threading.Thread.Sleep(4);
		}
	}

	public static int Main(String[] args)
	{
		bool ok = true;

		// ---- pins and stiffness written as text ----
		{
			let pinned = scope List<uint32>();
			SoftBody.ParsePins("0-3 7 9-10 200", 12, pinned);
			let text = scope String();
			SoftBody.FormatPins(pinned, text);
			ok &= Check(pinned.Count == 7 && text == "0-3 7 9-10", scope $"pins read from ranges and written back the same ({text})");
			let stiffness = scope List<float>() { 1, 1, 1, 1 };
			SoftBody.ParseStiffness("1=0.5 3=0.25 9=0", stiffness);
			let written = scope String();
			SoftBody.FormatStiffness(stiffness, written);
			ok &= Check(stiffness[1] == 0.5f && stiffness[3] == 0.25f && written == "1=0.5 3=0.25", scope $"a stiffness map read and written back ({written})");
		}

		// ---- a mesh's seams are joined ----
		{
			let sphere = Assets.GetMesh("builtin:sphere");
			let rest = scope List<Vector3>(), triangles = scope List<uint32>(), map = scope List<int32>();
			SoftBody.Weld(sphere, rest, triangles, map);
			let joined = sphere != null && rest.Count < sphere.Vertices.Count && map.Count == sphere.Vertices.Count && triangles.Count > 0;
			ok &= Check(joined, scope $"a sphere's vertices split at its seams are joined for the simulation ({sphere?.Vertices.Count} drawn, {rest.Count} simulated)");
		}

		// ---- cloth hangs from its pins, and follows them ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			let cells = 12;
			let sheet = scope Mesh();
			let made = Sheet(cells, 2);
			sheet.Vertices.AddRange(made.Vertices);
			sheet.Indices.AddRange(made.Indices);
			delete made;
			let curtain = Curtain(scene, sheet, .(0, 5, 0), cells);
			Run(scene, 1);
			ok &= Check(curtain.HasBody && curtain.SimulatedVertexCount == (cells + 1) * (cells + 1), scope $"a sheet becomes a soft body ({curtain.SimulatedVertexCount} vertices)");
			Run(scene, 300);
			curtain.[Friend]ReadBack();
			let positions = curtain.Positions;
			let top = positions[cells * (cells + 1)];
			let bottom = Lowest(positions);
			ok &= Check(Math.Abs(top.y - 5) < 0.02f && Math.Abs(top.z - 1) < 0.02f, scope $"its pinned edge stays where the object holds it ({top})");
			ok &= Check(bottom.y < 3.25f && bottom.y > 2.7f && Math.Abs(bottom.z - 1) < 0.25f, scope $"the rest swings down and hangs below it without stretching far (lowest {bottom}, 2 m of cloth)");
			// The object moves: its pins go with it, and the cloth after them.
			curtain.Transform.Position = .(3, 5, 0);
			Run(scene, 180);
			curtain.[Friend]ReadBack();
			let movedTop = curtain.Positions[cells * (cells + 1)];
			let movedMiddle = Average(curtain.Positions);
			ok &= Check(Math.Abs(movedTop.x - 2) < 0.05f && movedMiddle.x > 2.6f, scope $"moving the object moves its pins, and the cloth follows (top x {movedTop.x}, middle x {movedMiddle.x})");
			let renderer = curtain.GetComponent<MeshRenderer>();
			ok &= Check(renderer.RuntimeMesh != sheet && renderer.RuntimeMesh.Vertices.Count == sheet.Vertices.Count, "the renderer draws a copy of the mesh that follows the simulation");
			let before = scene.Physics.[Friend]mSoftBodies.Count;
			scene.DestroyImmediate(curtain.GameObject);
			ok &= Check(before == 1 && scene.Physics.[Friend]mSoftBodies.Count == 0, "destroying the object takes its soft body out of the world");
		}

		// ---- wind blows on cloth ----
		{
			float Drift(bool windy)
			{
				let scene = scope Scene();
				Scene.Active = scene;
				scene.StartPlay();
				if (windy)
				{
					let wind = scene.CreateGameObject("Wind").AddComponent<WindZone>();
					wind.strength = 3;
					wind.Transform.Rotation = Quaternion.LookRotation(.(0, 0, 1), .Up);
				}
				let sheet = scope Mesh();
				let made = Sheet(8, 2);
				sheet.Vertices.AddRange(made.Vertices);
				sheet.Indices.AddRange(made.Indices);
				delete made;
				let curtain = Curtain(scene, sheet, .(0, 5, 0), 8);
				Run(scene, 300);
				curtain.[Friend]ReadBack();
				return Average(curtain.Positions).z;
			}
			let still = Drift(false), blown = Drift(true);
			ok &= Check(Math.Abs(still - 1) < 0.15f && blown > still + 0.25f, scope $"a Wind Zone blows hanging cloth the way it faces (middle z {still} still, {blown} in wind)");
		}

		// ---- cloth drapes over things ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			let table = scene.CreateGameObject("Table");
			table.Transform.Position = .(0, 1, 0);
			table.AddComponent<BoxCollider>().size = .(1, 0.2f, 1);
			let sheet = scope Mesh();
			let made = Sheet(16, 2);
			sheet.Vertices.AddRange(made.Vertices);
			sheet.Indices.AddRange(made.Indices);
			delete made;
			let cloth = scene.CreateGameObject("Tablecloth");
			cloth.Transform.Position = .(0, 1.6f, 0);
			cloth.AddComponent<MeshRenderer>().RuntimeMesh = sheet;
			let soft = cloth.AddComponent<SoftBody>();
			soft.thickness = 0.02f;
			Run(scene, 300);
			soft.[Friend]ReadBack();
			// Over the table it lies on the top (1.1) without going into it, folds and all; its corners hang down past it.
			float lowestOver = float.MaxValue, sumOver = 0;
			int over = 0;
			for (let p in soft.Positions)
			{
				if (Math.Abs(p.x) > 0.45f || Math.Abs(p.z) > 0.45f)
					continue;
				lowestOver = Math.Min(lowestOver, p.y);
				sumOver += p.y;
				over++;
			}
			let corner = soft.Positions[0];
			ok &= Check(over > 20 && lowestOver > 1.09f && sumOver / over < 1.25f, scope $"cloth dropped on a table comes to rest on it ({over} vertices over it, lowest {lowestOver}, average {sumOver / Math.Max(over, 1)}; top 1.1)");
			ok &= Check(corner.y < 0.95f, scope $"and its corners hang over the edge (corner y {corner.y})");
		}

		// ---- a jelly ball keeps its volume, and holds up a crate ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			let floor = scene.CreateGameObject("Floor");
			floor.Transform.Position = .(0, -0.5f, 0);
			floor.AddComponent<BoxCollider>().size = .(10, 1, 10);
			let ball = scene.CreateGameObject("Jelly");
			ball.Transform.Position = .(0, 1, 0);
			ball.AddComponent<MeshRenderer>().mesh.Set("builtin:sphere");
			let jelly = ball.AddComponent<SoftBody>();
			jelly.kind = .Jelly;
			jelly.mass = 2;
			Run(scene, 240);
			jelly.[Friend]ReadBack();
			float lowest = float.MaxValue, highest = float.MinValue;
			for (let p in jelly.Positions)
			{
				lowest = Math.Min(lowest, p.y);
				highest = Math.Max(highest, p.y);
			}
			let height = highest - lowest;
			ok &= Check(lowest > -0.05f && lowest < 0.1f, scope $"a jelly ball falls and rests on the floor (bottom {lowest})");
			ok &= Check(height > 0.9f && height < 1.1f, scope $"keeping its shape (height {height} of 1)");
			let middle = Average(jelly.Positions);
			ok &= Check((ball.Transform.Position - middle).Length < 0.01f, scope $"a free soft body carries its object with it (object at {ball.Transform.Position}, body's middle {middle})");
			// A script teleports the object: the body goes with it.
			ball.Transform.Position = ball.Transform.Position + Vector3(4, 0, 0);
			Run(scene, 1);
			jelly.[Friend]ReadBack();
			let moved = Average(jelly.Positions);
			let carried = Math.Abs(moved.x - middle.x - 4) < 0.1f && moved.y > 0.3f && (ball.Transform.Position - moved).Length < 0.01f;
			ok &= Check(carried, scope $"moving its object moves the body with it (body's middle x {middle.x} to {moved.x})");
			// A crate dropped on it (where it rolled to as it settled) is caught up high, and squashes it.
			let under = Average(jelly.Positions);
			let crate = scene.CreateGameObject("Crate");
			crate.Transform.Position = .(under.x, 1.6f, under.z);
			crate.AddComponent<BoxCollider>().size = .(0.4f, 0.4f, 0.4f);
			crate.AddComponent<Rigidbody>().mass = 3;
			float squashed = height, caught = float.MaxValue;
			for (int tick < 45)
			{
				scene.FixedUpdate();
				jelly.[Friend]ReadBack();
				float top = float.MinValue, bottom = float.MaxValue;
				for (let p in jelly.Positions)
				{
					top = Math.Max(top, p.y);
					bottom = Math.Min(bottom, p.y);
				}
				squashed = Math.Min(squashed, top - bottom);
				caught = Math.Min(caught, crate.Transform.Position.y);
			}
			ok &= Check(caught > 0.8f, scope $"a crate dropped on it is caught on top, not let through (lowest {caught})");
			ok &= Check(squashed < height - 0.05f, scope $"and squashes it (height {squashed} under it, {height} before)");
			let touched = scope List<uint32>();
			scene.FixedUpdate();
			jelly.TouchingBodies(touched);
			ok &= Check(touched.Contains(crate.GetComponent<Rigidbody>().BodyId), scope $"it reports the bodies it touches ({touched.Count})");
		}

		// ---- a character walking through a curtain pushes it aside ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			let floor = scene.CreateGameObject("Floor");
			floor.Transform.Position = .(0, -0.5f, 0);
			floor.AddComponent<BoxCollider>().size = .(20, 1, 20);
			let sheet = scope Mesh();
			let made = Sheet(10, 2);
			sheet.Vertices.AddRange(made.Vertices);
			sheet.Indices.AddRange(made.Indices);
			delete made;
			// Hung from y 2.3 along z = 0 (its pinned row is at z = +1 on the object), so it reaches nearly to the floor.
			let curtain = Curtain(scene, sheet, .(0, 2.3f, -1), 10);
			Run(scene, 240);
			curtain.[Friend]ReadBack();
			let hanging = Average(curtain.Positions);
			let walker = scene.CreateGameObject("Walker");
			walker.Transform.Position = .(0, 0.05f, -2);
			let controller = walker.AddComponent<CharacterController>();
			Run(scene, 1);
			float pushed = hanging.z;
			for (int tick < 150)
			{
				controller.SimpleMove(.(0, 0, 2), Time.FixedDeltaTime);
				scene.FixedUpdate();
				curtain.[Friend]ReadBack();
				pushed = Math.Max(pushed, Average(curtain.Positions).z);
			}
			ok &= Check(walker.Transform.Position.z > 1.5f && pushed > hanging.z + 0.2f, scope $"a character walks through a hanging curtain and pushes it aside (curtain middle z {hanging.z} hanging, {pushed} at most; walker z {walker.Transform.Position.z})");
		}

		// ---- a free soft body on a networked object goes where the server says ----
		{
			Time.DeltaTime = Time.FixedDeltaTime;
			NetworkManager.RegisterPrefab("Jelly", new => MakeJelly);
			let port = (uint16)(47000 + (DateTime.Now.Ticks / 10000) % 900);
			let host = scope Scene();
			Floor(host);
			host.StartPlay();
			host.Network = new NetworkManager(host);
			ok &= Check(host.Network.StartServer(port, true), "a host starts");
			let client = scope Scene();
			Floor(client);
			client.StartPlay();
			client.Network = new NetworkManager(client);
			client.Network.StartClient("127.0.0.1", port);
			Pump(host, client, 60);
			host.Network.Spawn("Jelly", .(0, 1, 0), .Identity, 0);
			Pump(host, client, 180);
			let onHost = host.Find("Jelly"), onClient = client.Find("Jelly");
			ok &= Check(onClient != null && onClient.GetComponent<SoftBody>().HasBody, "the soft body is made on the client too");
			if (onClient != null)
			{
				// The server's script throws it across the room; the client's follows.
				onHost.Transform.Position = onHost.Transform.Position + Vector3(6, 0, 3);
				Pump(host, client, 120);
				let hostBody = onHost.GetComponent<SoftBody>(), clientBody = onClient.GetComponent<SoftBody>();
				let apart = (Average(hostBody.Positions) - Average(clientBody.Positions)).Length;
				ok &= Check(apart < 0.3f, scope $"the client's body follows where the server's is ({apart} m apart after it was moved 6.7 m)");
			}
			client.Network.Stop();
			host.Network.Stop();
		}

		Console.WriteLine(ok ? "ALL PASS" : "SOME FAILED");
		return ok ? 0 : 1;
	}
}
