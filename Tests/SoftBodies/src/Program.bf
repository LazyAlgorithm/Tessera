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
	/// A box, half its size each way, each face cut into `cells` squares across (so it can dent and bend).
	static Mesh Box(Vector3 half, int cells)
	{
		let mesh = new Mesh();
		for (int face < 6)
		{
			let axis = face / 2;
			let sign = (face % 2 == 0) ? 1.0f : -1.0f;
			let start = (uint32)mesh.Vertices.Count;
			for (int j <= cells)
			{
				for (int i <= cells)
				{
					float[3] p = default;
					p[axis] = sign;
					p[(axis + 1) % 3] = i / (float)cells * 2 - 1;
					p[(axis + 2) % 3] = j / (float)cells * 2 - 1;
					float[3] n = default;
					n[axis] = sign;
					mesh.AddVertex(.(p[0] * half.x, p[1] * half.y, p[2] * half.z), .(n[0], n[1], n[2]), .White, .(i / (float)cells, j / (float)cells));
				}
			}
			for (int j < cells)
			{
				for (int i < cells)
				{
					let a = start + (uint32)(j * (cells + 1) + i);
					let c = a + (uint32)cells + 1;
					// Wound to face outward on either side.
					if (sign > 0)
					{
						mesh.AddTriangle(a, a + 1, c);
						mesh.AddTriangle(a + 1, c + 1, c);
					}
					else
					{
						mesh.AddTriangle(a, c, a + 1);
						mesh.AddTriangle(a + 1, c, c + 1);
					}
				}
			}
		}
		return mesh;
	}

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

		// ---- a jelly cube, as it comes, stays a cube and does not bounce about ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			Floor(scene);
			let cube = Box(.(0.5f, 0.5f, 0.5f), 8);
			defer delete cube;
			let object = scene.CreateGameObject("Jello");
			object.Transform.Position = .(0, 1.5f, 0);
			object.AddComponent<MeshRenderer>().RuntimeMesh = cube;
			let jelly = object.AddComponent<SoftBody>();
			jelly.kind = .Jelly;
			bool landed = false;
			float bounce = 0;
			for (int tick < 240)
			{
				scene.FixedUpdate();
				jelly.[Friend]ReadBack();
				let low = Lowest(jelly.Positions).y;
				landed |= low < 0.05f;
				if (landed)
					bounce = Math.Max(bounce, low);
			}
			// The faces' middles against a cube's (half its size from the middle; a ball's would be 0.87).
			let middle = Average(jelly.Positions);
			float faceMiddle = 0;
			int faces = 0;
			for (int i < jelly.Positions.Count)
			{
				let rest = jelly.[Friend]mRest[i];
				if ((Math.Abs(rest.x) < 0.01f ? 1 : 0) + (Math.Abs(rest.y) < 0.01f ? 1 : 0) + (Math.Abs(rest.z) < 0.01f ? 1 : 0) == 2)
				{
					faceMiddle += (jelly.Positions[i] - middle).Length;
					faces++;
				}
			}
			faceMiddle /= faces;
			ok &= Check(faceMiddle < 0.55f && bounce < 0.15f, scope $"a jelly cube dropped 1 m keeps its shape (faces' middles {faceMiddle} m out, a cube's 0.5) and hops once at most ({bounce} m)");

			// At rest, it goes to sleep; something landing on it wakes it, and it holds that up.
			int waited = 240;
			while (!jelly.IsSleeping && waited < 600)
			{
				scene.FixedUpdate();
				waited++;
			}
			ok &= Check(jelly.IsSleeping, scope $"a resting jelly goes to sleep ({waited / 60.0f:0.0} s after it was dropped)");
			jelly.[Friend]ReadBack();
			let under = Average(jelly.Positions);
			let crate = scene.CreateGameObject("Crate");
			crate.Transform.Position = .(under.x, 2, under.z);
			crate.AddComponent<BoxCollider>().size = .(0.3f, 0.3f, 0.3f);
			crate.AddComponent<Rigidbody>().mass = 0.5f;
			bool woke = false;
			float caught = float.MaxValue;
			for (int tick < 90)
			{
				scene.FixedUpdate();
				woke |= !jelly.IsSleeping;
				caught = Math.Min(caught, crate.Transform.Position.y);
			}
			ok &= Check(woke && caught > 0.6f, scope $"a crate landing on the sleeping jelly wakes it and is held up (lowest {caught})");
		}

		// ---- soft bodies meet each other: a jelly cube on another, and cloth over one ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			Floor(scene);
			let cubeMesh = Box(.(0.5f, 0.5f, 0.5f), 8);
			defer delete cubeMesh;
			SoftBody Jello(Scene scene, Mesh mesh, Vector3 at)
			{
				let object = scene.CreateGameObject("Jello");
				object.Transform.Position = at;
				object.AddComponent<MeshRenderer>().RuntimeMesh = mesh;
				let jelly = object.AddComponent<SoftBody>();
				jelly.kind = .Jelly;
				return jelly;
			}
			let below = Jello(scene, cubeMesh, .(0, 0.55f, 0));
			let above = Jello(scene, cubeMesh, .(0.1f, 2, 0.05f));
			Run(scene, 240);
			below.[Friend]ReadBack();
			above.[Friend]ReadBack();
			float belowTop = -99;
			for (let p in below.Positions)
				belowTop = Math.Max(belowTop, p.y);
			let aboveBottom = Lowest(above.Positions).y;
			ok &= Check(aboveBottom > belowTop - 0.05f && aboveBottom > 0.8f, scope $"a jelly cube dropped on another rests on it (its bottom {aboveBottom}, the other's top {belowTop})");

			let sheet = Sheet(12, 2);
			defer delete sheet;
			let cloth = scene.CreateGameObject("Cloth");
			cloth.Transform.Position = .(4, 2, 0);
			cloth.AddComponent<MeshRenderer>().RuntimeMesh = sheet;
			let blanket = cloth.AddComponent<SoftBody>();
			blanket.damping = 1;
			let under = Jello(scene, cubeMesh, .(4, 0.55f, 0));
			Run(scene, 240);
			blanket.[Friend]ReadBack();
			under.[Friend]ReadBack();
			float underTop = -99;
			for (let p in under.Positions)
				underTop = Math.Max(underTop, p.y);
			// The cloth's middle (over the cube) lies on the cube's top.
			float middleY = 0;
			int over = 0;
			for (let p in blanket.Positions)
			{
				if (Math.Abs(p.x - 4) < 0.3f && Math.Abs(p.z) < 0.3f)
				{
					middleY += p.y;
					over++;
				}
			}
			middleY /= Math.Max(over, 1);
			ok &= Check(over > 0 && middleY > underTop - 0.05f, scope $"cloth dropped over a jelly cube drapes on it (cloth over it at {middleY}, its top {underTop})");
		}

		// ---- a rubber ball (jelly with more air in) keeps its volume, and holds up a crate ----
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
			jelly.pressure = 300;
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

		// ---- a car's shell dents where it hits a wall, keeps the dent, and can be repaired ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			Floor(scene);
			let wall = scene.CreateGameObject("Wall");
			wall.Transform.Position = .(0, 1.5f, 8);
			wall.AddComponent<BoxCollider>().size = .(6, 3, 1);
			let car = scene.CreateGameObject("Car");
			car.Transform.Position = .(0, 0.65f, 0);
			// The collider a little inside the body at the front and back, and below it underneath (as wheels would be).
			car.AddComponent<BoxCollider>().size = .(1.6f, 1.4f, 3.6f);
			let body = car.AddComponent<Rigidbody>();
			body.mass = 1000;
			let shellMesh = Box(.(0.9f, 0.6f, 2), 8);
			defer delete shellMesh;
			car.AddComponent<MeshRenderer>().RuntimeMesh = shellMesh;
			let shell = car.AddComponent<SoftBody>();
			shell.kind = .Shell;
			shell.springBack = 0.03f;
			Run(scene, 60);
			let restingAt = car.Transform.Position;
			Run(scene, 60);
			int parked = 120;
			while (!shell.IsSleeping && parked < 600)
			{
				scene.FixedUpdate();
				parked++;
			}
			ok &= Check(shell.IsSleeping, scope $"a parked car's shell goes to sleep ({parked / 60.0f:0.0} s)");
			let carMoved = (car.Transform.Position - restingAt).Length;
			let resting = shell.HasBody && shell.DeepestDent() < 0.01f && carMoved < 0.01f;
			ok &= Check(resting, scope $"a shell rests on its car without denting or pushing it ({shell.SimulatedVertexCount} vertices, deepest dent {shell.DeepestDent()}, car moved {carMoved})");
			for (int tick < 90)
			{
				if (car.Transform.Position.z < 5.4f)
					body.Velocity = .(0, body.Velocity.y, 12);
				scene.FixedUpdate();
			}
			shell.[Friend]ReadBack();
			let dents = scope List<Vector3>();
			shell.GetDents(dents);
			float front = 0, back = 0;
			for (int i < dents.Count)
			{
				if (shell.[Friend]mRest[i].z > 1.9f)
					front = Math.Max(front, dents[i].Length);
				if (shell.[Friend]mRest[i].z < -1.9f)
					back = Math.Max(back, dents[i].Length);
			}
			ok &= Check(front > 0.08f && back < 0.03f, scope $"driven into a wall, its front dents and its back does not (front {front} m, back {back} m)");
			Run(scene, 120);
			let later = shell.DeepestDent();
			ok &= Check(later > front * 0.9f, scope $"the dent stays ({later} m two seconds later)");
			shell.GetDents(dents);
			// Backed away from the wall, then mended.
			car.Transform.Position = car.Transform.Position - Vector3(0, 0, 3);
			body.Velocity = .Zero;
			Run(scene, 2);
			shell.Repair();
			Run(scene, 30);
			ok &= Check(shell.DeepestDent() < 0.005f, scope $"Repair takes the dents out ({shell.DeepestDent()})");
			shell.SetDents(dents);
			Run(scene, 30);
			ok &= Check(Math.Abs(shell.DeepestDent() - later) < 0.01f, scope $"dents saved with GetDents come back with SetDents ({shell.DeepestDent()} of {later})");
		}

		// ---- ropes ----
		{
			let scene = scope Scene();
			Scene.Active = scene;
			scene.StartPlay();
			Floor(scene);
			GameObject Post(Scene scene, Vector3 at)
			{
				let post = scene.CreateGameObject("Post");
				post.Transform.Position = at;
				return post;
			}
			GameObject Crate(Scene scene, Vector3 at, float mass)
			{
				let crate = scene.CreateGameObject("Crate");
				crate.Transform.Position = at;
				crate.AddComponent<BoxCollider>().size = .(0.6f, 0.6f, 0.6f);
				crate.AddComponent<Rigidbody>().mass = mass;
				return crate;
			}

			// Hanging free from a post.
			let hook = Post(scene, .(-6, 5, 0));
			let free = hook.AddComponent<Rope>();
			free.length = 3;
			// Between two posts, with slack.
			let left = Post(scene, .(-3, 4, 0));
			let right = Post(scene, .(-1, 4, 0));
			let sagging = left.AddComponent<Rope>();
			sagging.length = 3;
			sagging.endAttachedTo = right.Transform;
			// Holding up a crate.
			let beam = Post(scene, .(3, 5, 0));
			let load = Crate(scene, .(3, 2.5f, 0), 10);
			let holding = Rope.Attach(beam, load, .Zero, .(0, 0.3f, 0), 2.2f);
			Run(scene, 180);
			free.[Friend]ReadBack();
			sagging.[Friend]ReadBack();
			let hangs = hook.Transform.Position.y - free.Points.Back.y;
			ok &= Check(free.HasBody && hangs > 2.85f && hangs < 3.1f && Math.Abs(free.Points.Back.x + 6) < 0.1f, scope $"a rope hangs straight down from a post ({hangs} m of 3, {free.Points.Count} points)");
			float lowest = 99;
			for (let p in sagging.Points)
				lowest = Math.Min(lowest, p.y);
			ok &= Check(lowest < 3.4f && lowest > 2.5f, scope $"a rope between two posts sags in the middle (lowest {lowest}, posts at 4)");
			let hanging = (load.Transform.Position + Vector3(0, 0.3f, 0) - beam.Transform.Position).Length;
			ok &= Check(hanging > 2.1f && hanging < 2.3f && holding.IsTaut, scope $"a rope holds up a crate, taut ({hanging} m from the beam, rope 2.2)");
			ok &= Check(holding.Pull > 60 && holding.Pull < 140, scope $"and reports the crate's weight as its pull ({holding.Pull} N for 10 kg)");
			holding.[Friend]ReadBack();
			ok &= Check(holding.GetComponent<MeshRenderer>().RuntimeMesh.Vertices.Count == holding.Points.Count * 8, "it draws itself as a tube");
			// Swung sideways, it swings on the rope rather than stretching it.
			load.GetComponent<Rigidbody>().Velocity = .(3, 0, 0);
			float furthest = 0, swungTo = 0;
			for (int tick < 90)
			{
				scene.FixedUpdate();
				furthest = Math.Max(furthest, (load.Transform.Position + Vector3(0, 0.3f, 0) - beam.Transform.Position).Length);
				swungTo = Math.Max(swungTo, load.Transform.Position.x - 3);
			}
			ok &= Check(swungTo > 0.5f && furthest < 2.3f, scope $"pushed, the crate swings on the rope ({swungTo} m out) without stretching it (at most {furthest} m)");
			// Let go, it falls.
			holding.Release();
			Run(scene, 60);
			ok &= Check(load.Transform.Position.y < 0.5f, scope $"Release lets the crate fall ({load.Transform.Position.y})");

			// Towing: a truck (moved by a script, no Rigidbody) drags a crate along the floor.
			let truck = Post(scene, .(-8, 0.5f, 6));
			let trailer = Crate(scene, .(-12, 0.3f, 6), 20);
			Rope.Attach(truck, trailer, .Zero, .Zero, 4.2f);
			for (int tick < 180)
			{
				truck.Transform.Position = truck.Transform.Position + Vector3(2 * Time.FixedDeltaTime, 0, 0);
				scene.FixedUpdate();
			}
			let towed = trailer.Transform.Position.x + 12;
			let gap = (truck.Transform.Position - trailer.Transform.Position).Length;
			ok &= Check(towed > 3.5f && gap < 4.4f, scope $"towing: a truck drags a crate behind it ({towed} m, {gap} m apart on a 4.2 m rope)");

			// Lifting: a helicopter (a dynamic Rigidbody flying up) lifts a crate off the floor, and feels its weight.
			let copter = Crate(scene, .(8, 3, 6), 200);
			copter.Name.Set("Helicopter");
			let flier = copter.GetComponent<Rigidbody>();
			let cargo = Crate(scene, .(8, 0.3f, 6), 20);
			let sling = Rope.Attach(copter, cargo, .(0, -0.3f, 0), .(0, 0.3f, 0), 2.5f);
			for (int tick < 180)
			{
				// Lift: its own weight, and a little more.
				flier.AddForce(.(0, 200 * 9.81f + 400, 0));
				scene.FixedUpdate();
			}
			ok &= Check(cargo.Transform.Position.y > 1 && sling.Pull > 100, scope $"lifting: a helicopter lifts a crate on a rope (crate at {cargo.Transform.Position.y} m, pull {sling.Pull} N)");

			// Dropped on a box (held at neither end), a rope lies on it.
			let block = scene.CreateGameObject("Block");
			block.Transform.Position = .(0, 0.5f, -6);
			block.AddComponent<BoxCollider>().size = .(2, 1, 2);
			let above = Post(scene, .(0, 3, -6));
			let draped = above.AddComponent<Rope>();
			draped.length = 1.5f;
			draped.holdStart = false;
			Run(scene, 180);
			draped.[Friend]ReadBack();
			let bottom = Lowest(draped.Points).y;
			ok &= Check(bottom > 0.95f && bottom < 1.1f, scope $"a rope dropped on a box lies on it (lowest {bottom}, box top 1)");

			// Each end on its own: a rope held only at its far end by a crate, its start hanging free; then its
			// start tied to a post too.
			let lone = Post(scene, .(12, 0, -6));
			let loose = lone.AddComponent<Rope>();
			loose.length = 2;
			loose.holdStart = false;
			let carrier = Post(scene, .(12, 4, -6));
			loose.endAttachedTo = carrier.Transform;
			Run(scene, 120);
			loose.[Friend]ReadBack();
			let dangles = carrier.Transform.Position.y - Lowest(loose.Points).y;
			ok &= Check(dangles > 1.85f && dangles < 2.1f, scope $"held only at its end, a rope hangs from that end ({dangles} m of 2)");
			let other = Post(scene, .(13, 4, -6));
			loose.AttachStart(other.Transform);
			Run(scene, 60);
			loose.[Friend]ReadBack();
			ok &= Check((loose.Points[0] - other.Transform.Position).Length < 0.05f && (loose.Points.Back - carrier.Transform.Position).Length < 0.05f, "AttachStart ties its other end to something else");
			// What an end is tied to is destroyed: that end lets go.
			scene.Destroy(carrier);
			scene.Update();
			Run(scene, 60);
			scene.Update();
			ok &= Check(loose.HasBody && loose.endAttachedTo == null && Lowest(loose.Points).y < 2.3f, scope $"when what an end holds is destroyed, it lets go and hangs (lowest {Lowest(loose.Points).y})");
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
