using System;
using System.Collections;
using Tessera;

namespace ScrapYard;

/// Building and seat changes go through here so they work the same offline, as host and as a client.
/// Clients only ever ask; the server (or the offline game) decides, applies and tells everyone.
static class GameNet
{
	public enum Op : uint8 { Place, Remove, New, Enter, Leave }

	const uint8 MsgRequest = 1;
	const uint8 MsgPart = 2;
	const uint8 MsgSeat = 3;

	/// Test helpers: drive forward automatically, and log vehicle state once a second.
	public static bool AutoDrive;
	public static bool Verbose;

	static Scene World => Scene.Active;
	static NetworkManager Net => (World != null && World.Network != null && World.Network.Mode != .Offline) ? World.Network : null;

	/// This machine's client id (0 offline and for the host).
	public static int32 LocalId => Net != null ? Net.LocalClientId : 0;

	public static void Register()
	{
		NetworkManager.RegisterMessage(MsgRequest, new => OnRequest);
		NetworkManager.RegisterMessage(MsgPart, new => OnPart);
		NetworkManager.RegisterMessage(MsgSeat, new => OnSeat);
		let trace = scope String();
		Verbose = Environment.GetEnvironmentVariable("SCRAP_TRACE", trace) case .Ok && !trace.IsEmpty;
	}

	public static Creation FindCreation(uint32 netId)
	{
		for (let component in World.Components)
		{
			if (let creation = component as Creation)
			{
				if (creation.NetId == netId)
					return creation;
			}
		}
		return null;
	}

	public static GameObject FindPlayer(int32 clientId)
	{
		if (Net == null)
			return World.Find("Player");
		for (let identity in Net.Identities)
		{
			if (identity.ownerId == clientId && identity.PrefabName == "Player")
				return identity.GameObject;
		}
		return null;
	}

	/// The creation this client is currently driving, if any.
	public static Creation FindDriven(int32 clientId)
	{
		for (let component in World.Components)
		{
			if (let creation = component as Creation)
			{
				if (creation.HasDriver && creation.DriverId == clientId)
					return creation;
			}
		}
		return null;
	}

	// ---- requests (any machine) ----

	public static void Request(Op op, uint32 netId, Int3 cell, PartType type, Vector3 position, float yaw)
	{
		if (Net == null)
		{
			Apply(0, op, netId, cell, type, position, yaw);
			return;
		}
		let writer = scope NetWriter();
		writer.Write((uint8)op);
		writer.Write(netId);
		writer.Write(cell.x);
		writer.Write(cell.y);
		writer.Write(cell.z);
		writer.Write((int32)type);
		writer.Write(position);
		writer.Write(yaw);
		Net.SendToServer(MsgRequest, writer);
	}

	static void OnRequest(int32 sender, ref NetReader reader)
	{
		let op = (Op)reader.Read<uint8>();
		let netId = reader.Read<uint32>();
		let cell = Int3(reader.Read<int32>(), reader.Read<int32>(), reader.Read<int32>());
		let type = (PartType)reader.Read<int32>();
		let position = reader.Read<Vector3>();
		let yaw = reader.Read<float>();
		if (reader.Ok)
			Apply(sender, op, netId, cell, type, position, yaw);
	}

	// ---- authority (server, host or offline game) ----

	static void Apply(int32 sender, Op op, uint32 netId, Int3 cell, PartType type, Vector3 position, float yaw)
	{
		// Never trust sizes or enum values from the wire.
		if ((int32)type < 0 || (int32)type >= PartInfo.Count || Math.Abs(cell.x) > 64 || Math.Abs(cell.y) > 64 || Math.Abs(cell.z) > 64)
			return;
		switch (op)
		{
		case .New:
			let creation = SpawnCreation(position, yaw);
			if (creation != null)
				AddPart(creation, .(0, 0, 0), type);
		case .Place:
			let creation = FindCreation(netId);
			if (creation != null && creation.CanPlace(cell, type))
				AddPart(creation, cell, type);
		case .Remove:
			let creation = FindCreation(netId);
			let index = creation != null ? creation.FindPart(cell) : -1;
			if (index >= 0)
			{
				// Losing the last part, or the seat someone sits in, puts the driver back on foot.
				if (creation.HasDriver && (creation.Parts.Count == 1 || creation.Parts[index].type == .Seat))
					SetDriver(creation, -1);
				SendPart(-1, creation.NetId, creation.Parts[index].cell, type, false);
				creation.Remove(cell);
			}
		case .Enter:
			let creation = FindCreation(netId);
			if (creation != null && creation.HasSeat && !creation.HasDriver && FindDriven(sender) == null)
				SetDriver(creation, sender);
		case .Leave:
			let creation = FindDriven(sender);
			if (creation != null)
				SetDriver(creation, -1);
		}
	}

	public static Creation SpawnCreation(Vector3 position, float yaw)
	{
		let rotation = Quaternion.Euler(0, yaw, 0);
		GameObject gameObject;
		if (Net != null)
			gameObject = Net.Spawn("Creation", position, rotation, 0);
		else
		{
			gameObject = GameSetup.CreateCreation(World);
			gameObject.Transform.SetPositionAndRotation(position, rotation);
		}
		return gameObject != null ? gameObject.GetComponent<Creation>() : null;
	}

	public static void AddPart(Creation creation, Int3 cell, PartType type)
	{
		creation.Add(cell, type);
		SendPart(-1, creation.NetId, cell, type, true);
	}

	/// target -1 sends to every client.
	static void SendPart(int32 target, uint32 netId, Int3 cell, PartType type, bool add)
	{
		if (Net == null || !Net.IsServer)
			return;
		let writer = scope NetWriter();
		writer.Write(netId);
		writer.Write((uint8)(add ? 1 : 0));
		writer.Write(cell.x);
		writer.Write(cell.y);
		writer.Write(cell.z);
		writer.Write((int32)type);
		if (target < 0)
			Net.SendToAll(MsgPart, writer);
		else
			Net.SendToClient(target, MsgPart, writer);
	}

	static void OnPart(int32 sender, ref NetReader reader)
	{
		let netId = reader.Read<uint32>();
		let add = reader.Read<uint8>() != 0;
		let cell = Int3(reader.Read<int32>(), reader.Read<int32>(), reader.Read<int32>());
		let type = (PartType)reader.Read<int32>();
		let creation = reader.Ok ? FindCreation(netId) : null;
		if (creation == null)
			return;
		if (add)
			creation.Add(cell, type);
		else
			creation.Remove(cell);
	}

	static void SetDriver(Creation creation, int32 driverId)
	{
		let previous = creation.DriverId;
		ApplySeat(creation, driverId, previous);
		if (Net != null && Net.IsServer)
		{
			// The driver's inputs now steer the vehicle; the server takes it back when they leave.
			Net.SetOwner(creation.Identity, driverId >= 0 ? driverId : 0);
			SendSeat(-1, creation.NetId, driverId, previous);
		}
	}

	static void SendSeat(int32 target, uint32 netId, int32 driverId, int32 previous)
	{
		let writer = scope NetWriter();
		writer.Write(netId);
		writer.Write(driverId);
		writer.Write(previous);
		if (target < 0)
			Net.SendToAll(MsgSeat, writer);
		else
			Net.SendToClient(target, MsgSeat, writer);
	}

	static void OnSeat(int32 sender, ref NetReader reader)
	{
		let netId = reader.Read<uint32>();
		let driverId = reader.Read<int32>();
		let previous = reader.Read<int32>();
		let creation = reader.Ok ? FindCreation(netId) : null;
		if (creation != null)
			ApplySeat(creation, driverId, previous);
	}

	/// Seat bookkeeping shared by every machine: the driver's character is put away while driving.
	static void ApplySeat(Creation creation, int32 driverId, int32 previous)
	{
		creation.DriverId = driverId;
		creation.HasDriver = driverId >= 0;
		creation.ClearControls();
		if (driverId >= 0)
		{
			let player = FindPlayer(driverId);
			if (player != null)
				player.SetActive(false);
		}
		else if (previous >= 0)
		{
			let player = FindPlayer(previous);
			if (player != null)
			{
				player.Transform.Position = creation.Transform.Position - creation.Transform.Right * 2.0f + Vector3(0, 1.5f, 0);
				player.SetActive(true);
			}
		}
	}

	/// Server: brings a player who just joined up to date with everything that has been built.
	public static void SendWorld(int32 clientId)
	{
		for (let component in World.Components)
		{
			if (let creation = component as Creation)
			{
				for (let part in creation.Parts)
					SendPart(clientId, creation.NetId, part.cell, part.type, true);
				if (creation.HasDriver)
					SendSeat(clientId, creation.NetId, creation.DriverId, -1);
			}
		}
	}
}
