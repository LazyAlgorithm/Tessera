using System;
using System.Collections;
using Tessera;

namespace ScrapYard;

[Reflect(.All)]
enum PartType : int32
{
	Plastic,
	Wood,
	Metal,
	Concrete,
	Glass,
	Wheel,
	Thruster,
	Seat
}

/// What each part is: its footprint on the grid, weight, model and name.
/// Blocks are a quarter of a metre, like Scrap Mechanic's; functional parts span several cells.
static class PartInfo
{
	public const float Grid = 0.25f;
	public const int32 Count = 8;

	public static Int3 Size(PartType type)
	{
		switch (type)
		{
		case .Wheel: return .(1, 3, 3);
		case .Thruster, .Seat: return .(2, 2, 2);
		default: return .(1, 1, 1);
		}
	}

	/// Kilograms per grid cell the part fills.
	public static float Weight(PartType type)
	{
		switch (type)
		{
		case .Plastic: return 1.0f;
		case .Wood: return 1.5f;
		case .Metal: return 5.0f;
		case .Concrete: return 4.0f;
		case .Glass: return 2.5f;
		case .Wheel: return 1.2f;
		case .Thruster: return 2.0f;
		case .Seat: return 1.0f;
		}
	}

	public static StringView Name(PartType type)
	{
		switch (type)
		{
		case .Plastic: return "Plastic";
		case .Wood: return "Wood";
		case .Metal: return "Metal";
		case .Concrete: return "Concrete";
		case .Glass: return "Glass";
		case .Wheel: return "Wheel";
		case .Thruster: return "Thruster";
		case .Seat: return "Seat";
		}
	}

	public static StringView Model(PartType type)
	{
		switch (type)
		{
		case .Plastic: return "Models/block_plastic.glb";
		case .Wood: return "Models/block_wood.glb";
		case .Metal: return "Models/block_metal.glb";
		case .Concrete: return "Models/block_concrete.glb";
		case .Glass: return "Models/block_glass.glb";
		case .Wheel: return "Models/wheel.glb";
		case .Thruster: return "Models/thruster.glb";
		case .Seat: return "Models/seat.glb";
		}
	}

	public static bool IsBlock(PartType type) => (int32)type <= (int32)PartType.Glass;

	/// Lowest cell a part covers when placed at an anchor cell (odd sizes are centred on the anchor).
	public static Int3 Min(Int3 anchor, PartType type)
	{
		let size = Size(type);
		return .(anchor.x - (size.x - 1) / 2, anchor.y - (size.y - 1) / 2, anchor.z - (size.z - 1) / 2);
	}

	/// Centre of the part in the creation's local space.
	public static Vector3 Center(Int3 anchor, PartType type)
	{
		let size = Size(type);
		let min = Min(anchor, type);
		return Vector3(min.x + (size.x - 1) * 0.5f, min.y + (size.y - 1) * 0.5f, min.z + (size.z - 1) * 0.5f) * Grid;
	}
}

/// A construction made of parts on a quarter-metre grid. All parts are welded into a single
/// rigid body (a compound collider), and wheels and thrusters push that body around.
///
/// Wheels are simulated as suspension rays under each wheel part: a spring holds the body up,
/// engine force pushes along the wheel's heading and grip resists sliding sideways.
[Component]
class Creation : NetworkBehaviour
{
	public struct Part
	{
		public Int3 cell; // anchor
		public PartType type;
		public GameObject visual;
		public float spin;
	}

	public float enginePower = 14.0f;
	public float grip = 9.0f;
	public float steerAngle = 28.0f;
	/// Thrust per thruster as a multiple of the creation's own weight.
	public float thrusterPower = 1.4f;

	[NonSerialized] public List<Part> Parts = new .() ~ delete _;
	// Driver input, set by whoever sits in a seat.
	[NonSerialized] public float Throttle;
	[NonSerialized] public float Steer;
	[NonSerialized] public bool Boost;
	[NonSerialized] public bool HasDriver;
	/// Client id of whoever sits in the seat, or -1.
	[NonSerialized] public int32 DriverId = -1;

	public uint32 NetId
	{
		get
		{
			let identity = Identity;
			return identity != null ? identity.NetId : GameObject.Id;
		}
	}

	/// The driver's machine samples the controls...
	public override void GatherInput(ref NetInput input)
	{
		if (!HasDriver || DriverId != GameNet.LocalId)
			return;
		input.moveZ = GameNet.AutoDrive ? 1.0f : Input.GetAxis("Vertical");
		input.moveX = Input.GetAxis("Horizontal");
		input.SetButton(0, Input.GetKey(.Space));
	}

	/// ...and the server (plus the driver's own prediction) turns them into throttle and steering.
	public override void Simulate(NetInput input, float deltaTime)
	{
		if (!HasDriver)
			return;
		Throttle = input.moveZ;
		Steer = input.moveX;
		Boost = input.GetButton(0);
	}

	public void ClearControls()
	{
		Throttle = 0;
		Steer = 0;
		Boost = false;
	}

	public bool HasSeat
	{
		get
		{
			for (let part in Parts)
			{
				if (part.type == .Seat)
					return true;
			}
			return false;
		}
	}

	public float Speed
	{
		get
		{
			let body = GetComponent<Rigidbody>();
			return (body != null && body.HasBody) ? body.Velocity.Length : 0;
		}
	}

	static bool Covers(Part part, Int3 cell)
	{
		let min = PartInfo.Min(part.cell, part.type);
		let size = PartInfo.Size(part.type);
		return cell.x >= min.x && cell.x < min.x + size.x && cell.y >= min.y && cell.y < min.y + size.y && cell.z >= min.z && cell.z < min.z + size.z;
	}

	/// Index of the part filling a cell, or -1.
	public int FindPart(Int3 cell)
	{
		for (int i < Parts.Count)
		{
			if (Covers(Parts[i], cell))
				return i;
		}
		return -1;
	}

	public bool Has(Int3 cell) => FindPart(cell) >= 0;

	/// True when every cell the part would fill is free.
	public bool CanPlace(Int3 anchor, PartType type)
	{
		let min = PartInfo.Min(anchor, type);
		let size = PartInfo.Size(type);
		for (int32 x = 0; x < size.x; x++)
			for (int32 y = 0; y < size.y; y++)
				for (int32 z = 0; z < size.z; z++)
					if (Has(.(min.x + x, min.y + y, min.z + z)))
						return false;
		return true;
	}

	/// Welds a new part onto the creation, anchored at a cell.
	public void Add(Int3 cell, PartType type)
	{
		if (!CanPlace(cell, type))
			return;
		Part part;
		part.cell = cell;
		part.type = type;
		part.spin = 0;
		part.visual = Scene.CreateGameObject(scope String(PartInfo.Name(type)), Transform);
		part.visual.Transient = true;
		part.visual.Transform.LocalPosition = PartInfo.Center(cell, type);
		// Block models are one unit across; the other models are authored at twice their in-game size.
		part.visual.Transform.LocalScale = .(PartInfo.IsBlock(type) ? PartInfo.Grid : 0.5f);
		// Sample models live in Assets/Models; swap the paths in PartInfo.Model for your own art.
		let renderer = part.visual.AddComponent<MeshRenderer>();
		renderer.mesh.Set(PartInfo.Model(type));
		if (type == .Glass)
		{
			// An alpha below 1 makes the renderer draw the part see-through.
			renderer.color = .(1, 1, 1, 0.35f);
			renderer.roughness = 0.15f;
		}
		Parts.Add(part);
		Refresh();
	}

	/// Removes the part filling a cell. Returns its anchor through outAnchor.
	public bool Remove(Int3 cell)
	{
		let index = FindPart(cell);
		if (index < 0)
			return false;
		Scene.Destroy(Parts[index].visual);
		Parts.RemoveAt(index);
		if (Parts.Count > 0)
			Refresh();
		else if (Scene.Network != null && Scene.Network.IsServer)
			Scene.Network.Despawn(GameObject);
		else if (Scene.Network == null || Scene.Network.Mode == .Offline)
			Scene.Destroy(GameObject);
		return true;
	}

	/// Rebuilds the welded collision shape and mass after the part list changed.
	void Refresh()
	{
		let collider = GetComponent<CompoundCollider>();
		let body = GetComponent<Rigidbody>();
		if (collider == null || body == null)
			return;
		collider.ClearBoxes();
		float mass = 0;
		for (let part in Parts)
		{
			let size = PartInfo.Size(part.type);
			collider.AddBox(PartInfo.Center(part.cell, part.type), Vector3(size.x, size.y, size.z) * PartInfo.Grid);
			mass += size.x * size.y * size.z * PartInfo.Weight(part.type);
		}
		body.mass = Math.Max(1.0f, mass);
		body.RebuildBody();
	}

	public override void FixedUpdate()
	{
		let body = GetComponent<Rigidbody>();
		if (body == null || !body.HasBody)
			return;
		// Without a network session nobody calls Simulate, so read the controls here.
		if (HasDriver && (Scene.Network == null || Scene.Network.Mode == .Offline))
		{
			NetInput input = default;
			GatherInput(ref input);
			Simulate(input, Time.FixedDeltaTime);
		}
		if (GameNet.Verbose && HasDriver && Time.Tick % 60 == 0)
			Log.Info(scope $"creation {NetId & 0xffff}: driver {DriverId} position {Transform.Position} speed {Speed:0.0} throttle {Throttle} parts {Parts.Count}");
		int wheelCount = 0;
		float wheelZ = 0;
		for (let part in Parts)
		{
			if (part.type == .Wheel)
			{
				wheelCount++;
				wheelZ += part.cell.z;
			}
		}
		let up = Transform.Up;
		let forward = Transform.Forward;
		if (wheelCount > 0)
		{
			let middleZ = wheelZ / wheelCount;
			let share = body.mass / wheelCount;
			// Spring that carries its share of the weight at 0.3 units of compression, near critical damping.
			let restLength = 0.3f;
			let stiffness = share * 9.81f / 0.15f;
			let damping = 2.0f * Math.Sqrt(stiffness * share) * 0.6f;
			for (var part in ref Parts)
			{
				if (part.type != .Wheel)
					continue;
				let center = Transform.TransformPoint(PartInfo.Center(part.cell, .Wheel));
				RaycastHit hit;
				// Start just under the wheel's own collision box (three cells tall).
				if (!Scene.Physics.Raycast(center - up * (PartInfo.Grid * 1.5f + 0.02f), -up, restLength, out hit) || hit.gameObject == GameObject)
					continue;
				let velocity = body.GetPointVelocity(hit.point);
				let spring = Math.Max(0, stiffness * (restLength - hit.distance) - damping * Vector3.Dot(velocity, up));
				// Front wheels turn with the steering input.
				let steerable = wheelCount > 1 && part.cell.z > middleZ;
				var heading = steerable ? Quaternion.AngleAxis(Steer * steerAngle, up) * forward : forward;
				// Push along the ground, not along the tilted chassis, or a nose-up car lifts itself into a wheelie.
				heading = Vector3(heading.x, 0, heading.z).Normalized;
				let side = Vector3.Cross(Vector3.Up, heading);
				let along = Vector3.Dot(velocity, heading);
				let sideways = Vector3.Dot(velocity, side);
				var drive = Throttle * enginePower * share;
				if (Throttle == 0)
					drive = -along * share * (HasDriver ? 1.2f : 4.0f); // rolling resistance, parking brake when empty
				body.AddForceAtPosition(up * spring, hit.point);
				// Traction acts near axle height, which keeps hard acceleration from flipping light vehicles.
				body.AddForceAtPosition(heading * drive - side * (sideways * share * grip), hit.point + up * 0.3f);
				part.spin += along * Time.FixedDeltaTime / 0.375f * Mathf.Rad2Deg;
				part.visual.Transform.LocalRotation = Quaternion.Euler(0, steerable ? Steer * steerAngle : 0, 0) * Quaternion.Euler(part.spin, 0, 0);
			}
		}
		if (Boost)
		{
			for (let part in Parts)
			{
				if (part.type == .Thruster)
					body.AddForceAtPosition(forward * (body.mass * 9.81f * thrusterPower), Transform.TransformPoint(PartInfo.Center(part.cell, .Thruster)));
			}
		}
	}
}
