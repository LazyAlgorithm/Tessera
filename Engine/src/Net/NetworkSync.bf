using System;
using System.Collections;

namespace Tessera;

/// Marks a field of a component as shared: on an object with a Network Identity, the value the server has is
/// copied to every client whenever it changes. Change it on the server; a client's own changes are overwritten.
/// Works for numbers, bool, enums, vectors, colours and String.
[AttributeUsage(.Field, .ReflectAttribute)]
struct SyncAttribute : Attribute
{
}

/// Makes engine features work in multiplayer without game code: when a network session is running, the calls
/// below route themselves through the server and reach every machine. With no session they do nothing.
///
///   VoxelTerrain.Brush / ModifySphere, VoxelObject.Carve    applied on every machine in the server's order
///   CharacterController.SetBox / SetCapsule / ApplyShape     decided by the server, shown everywhere
///   SkinnedMeshRenderer.Play, Animator.Play                  a clip started on the server or by an object's owner plays everywhere
///   Prefab.Instantiate, Scene.Destroy                        for objects with a Network Identity, on the server
///   NavigationAgent, BehaviorTreeRunner                      think on the server only; clients see the movement
///   [Sync] fields                                            copied from the server when they change
///
/// Players that join later are brought up to date with all of it.
static class NetworkSync
{
	// Message ids the engine keeps for itself; games should use ids below 240.
	public const uint8 MsgTerrainBrush = 250;
	public const uint8 MsgVoxelCarve = 251;
	public const uint8 MsgCharacterShape = 252;
	public const uint8 MsgAnimation = 253;
	public const uint8 MsgField = 254;
	public const uint8 MsgAudio = 249;
	public const uint8 MsgEvent = 247;
	public const uint8 MsgAnimator = 246;
	public const uint8 MsgMaterial = 245;
	public const uint8 MsgDialogue = 244;

	static bool sRegistered;
	/// True while a change that arrived from the network is being applied, so it is not sent out again.
	static bool sApplying;
	public static bool IsApplying => sApplying;

	static NetworkManager Active(Scene scene)
	{
		let network = scene?.Network;
		return network != null && network.Mode != .Offline ? network : null;
	}

	/// True while a network session is running on this scene, on the server or a client.
	public static bool InSession(Scene scene) => Active(scene) != null;

	/// True on a client of a running session: the server does the thinking for AI there.
	public static bool IsClientOf(Scene scene)
	{
		let network = Active(scene);
		return network != null && !network.IsServer;
	}

	public static void EnsureRegistered()
	{
		if (sRegistered)
			return;
		sRegistered = true;
		NetworkManager.RegisterMessage(MsgTerrainBrush, new => OnTerrainBrush);
		NetworkManager.RegisterMessage(MsgVoxelCarve, new => OnVoxelCarve);
		NetworkManager.RegisterMessage(MsgCharacterShape, new => OnCharacterShape);
		NetworkManager.RegisterMessage(MsgAnimation, new => OnAnimation);
		NetworkManager.RegisterMessage(MsgField, new => OnField);
		NetworkManager.RegisterMessage(MsgAudio, new => OnAudio);
		VoiceChat.EnsureRegistered();
		NetworkManager.RegisterMessage(MsgEvent, new => OnEvent);
		NetworkManager.RegisterMessage(MsgAnimator, new => OnAnimator);
		NetworkManager.RegisterMessage(MsgMaterial, new => OnMaterial);
		NetworkManager.RegisterMessage(MsgDialogue, new => OnDialogue);
	}

	/// Called when a session starts. Scene objects that move by themselves get a Network Identity if they lack one,
	/// so physics props, AI characters and controllers are shared without being set up by hand. Every machine loads
	/// the same scene, so they all pick the same objects and the same ids.
	public static void Prepare(NetworkManager network)
	{
		EnsureRegistered();
		if (!network.AutoReplicate)
			return;
		List<GameObject> wanted = scope .();
		for (let object in network.Scene.Objects)
		{
			if (!object.ActiveInHierarchy) continue;
			if (object.GetComponent<NetworkIdentity>() != null)
				continue;
			let body = object.GetComponent<Rigidbody>();
			if ((body != null && !body.isKinematic) || object.GetComponent<CharacterController>() != null
				|| object.GetComponent<AIMovementDriver>() != null || object.GetComponent<BehaviorTreeRunner>() != null
				|| object.GetComponent<NetworkBehaviour>() != null || (object.GetComponent<DialogueRunner>()?.shared ?? false))
				wanted.Add(object);
		}
		for (let object in wanted)
			object.AddComponent<NetworkIdentity>();
	}

	/// Gives an object that has started moving on its own during a session a Network Identity, so its motion is
	/// shared. Call it on every machine at the same moment (for example from something that is itself synced).
	public static void EnsureShared(GameObject object)
	{
		if (Active(object.Scene) != null && object.GetComponent<NetworkIdentity>() == null)
			object.AddComponent<NetworkIdentity>();
	}

	/// For an object every machine creates itself while applying a shared event, such as a piece carved off a voxel
	/// object: gives it an identity whose id all machines arrive at by counting the same events.
	public static void ShareFragment(GameObject object)
	{
		let network = Active(object.Scene);
		if (network == null)
			return;
		var identity = object.GetComponent<NetworkIdentity>();
		if (identity == null)
			identity = object.AddComponent<NetworkIdentity>();
		network.AdoptFragment(identity);
	}

	// ---- naming things across machines ----

	/// An object every machine can find: by its Network Identity when it has one (spawned objects get different
	/// object ids on each machine), otherwise by the id it was given in the scene file.
	static void WriteObject(NetWriter writer, GameObject object)
	{
		let identity = object.GetComponent<NetworkIdentity>();
		writer.Write<bool>(identity != null);
		writer.Write<uint32>(identity != null ? identity.NetId : object.Id);
	}

	static GameObject ReadObject(ref NetReader reader, NetworkManager network)
	{
		let viaIdentity = reader.Read<bool>();
		let id = reader.Read<uint32>();
		if (!reader.Ok)
			return null;
		if (!viaIdentity)
			return network.Scene.FindById(id);
		return network.FindIdentity(id)?.GameObject;
	}

	/// The object that names a component across machines: the nearest ancestor with a Network Identity, or the
	/// component's own object when there is none.
	static GameObject Anchor(Component component)
	{
		var transform = component.Transform;
		while (transform != null)
		{
			if (transform.GameObject.GetComponent<NetworkIdentity>() != null)
				return transform.GameObject;
			transform = transform.Parent;
		}
		return component.GameObject;
	}

	static void Collect<T>(GameObject root, List<T> found) where T : Component
	{
		for (let component in root.Components)
		{
			if (let typed = component as T)
				found.Add(typed);
		}
		for (let child in root.Transform.Children)
			Collect<T>(child.GameObject, found);
	}

	/// Writes where a component is: its anchor object and its position among components of that type below the anchor.
	static void WriteComponent<T>(NetWriter writer, T component) where T : Component
	{
		let anchor = Anchor(component);
		List<T> all = scope .();
		Collect<T>(anchor, all);
		WriteObject(writer, anchor);
		writer.Write<uint16>((uint16)Math.Max(all.IndexOf(component), 0));
	}

	static T ReadComponent<T>(ref NetReader reader, NetworkManager network) where T : Component
	{
		let anchor = ReadObject(ref reader, network);
		let index = (int)reader.Read<uint16>();
		if (anchor == null || !reader.Ok)
			return null;
		List<T> all = scope .();
		Collect<T>(anchor, all);
		return index < all.Count ? all[index] : null;
	}

	/// Server: sends to every client, and optionally keeps the message for players who join later.
	static void Broadcast(NetworkManager network, uint8 id, NetWriter payload, bool remember)
	{
		network.SendToAll(id, payload);
		if (remember)
			network.Remember(id, payload);
	}

	static bool Finite(Vector3 v) => v.x.IsFinite && v.y.IsFinite && v.z.IsFinite;

	// ---- voxels ----

	/// Returns true if the caller must not apply the brush now: on a client it has been sent to the server and
	/// will be applied when the server passes it back, so every machine edits in the same order.
	public static bool RouteBrush(VoxelTerrain terrain, Vector3 center, float radius, float strength, VoxelBrush mode, int32 paintLayer, float flattenHeight)
	{
		let network = Active(terrain.Scene);
		if (network == null || sApplying)
			return false;
		let payload = scope NetWriter();
		WriteObject(payload, terrain.GameObject);
		payload.Write(center);
		payload.Write(radius);
		payload.Write(strength);
		payload.Write<int32>((int32)mode);
		payload.Write(paintLayer);
		payload.Write(flattenHeight);
		if (network.IsServer)
		{
			Broadcast(network, MsgTerrainBrush, payload, true);
			return false;
		}
		network.SendToServer(MsgTerrainBrush, payload);
		return true;
	}

	static void OnTerrainBrush(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let target = ReadObject(ref reader, network);
		let center = reader.Read<Vector3>();
		let radius = reader.Read<float>();
		let strength = reader.Read<float>();
		let mode = reader.Read<int32>();
		let paintLayer = reader.Read<int32>();
		let flattenHeight = reader.Read<float>();
		let terrain = target?.GetComponent<VoxelTerrain>();
		if (!reader.Ok || terrain == null || !Finite(center) || !radius.IsFinite || !strength.IsFinite || !flattenHeight.IsFinite || mode < 0 || mode > (int32)VoxelBrush.Paint)
			return;
		// On the server this is a client's request: applying it here sends it on to everyone.
		let wasApplying = sApplying;
		sApplying = !network.IsServer;
		terrain.Brush(center, Mathf.Clamp(radius, 0, 64), strength, (VoxelBrush)mode, paintLayer, flattenHeight);
		sApplying = wasApplying;
	}

	/// As RouteBrush, for VoxelObject.Carve.
	public static bool RouteCarve(VoxelObject voxels, Vector3 point, float radius)
	{
		let network = Active(voxels.Scene);
		if (network == null || sApplying)
			return false;
		let payload = scope NetWriter();
		WriteObject(payload, voxels.GameObject);
		// In the object's own space: a boulder that has rolled is not in exactly the same place on every machine.
		payload.Write(voxels.Transform.InverseTransformPoint(point));
		payload.Write(radius);
		if (network.IsServer)
		{
			Broadcast(network, MsgVoxelCarve, payload, true);
			return false;
		}
		network.SendToServer(MsgVoxelCarve, payload);
		return true;
	}

	static void OnVoxelCarve(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let target = ReadObject(ref reader, network);
		let point = reader.Read<Vector3>();
		let radius = reader.Read<float>();
		let voxels = target?.GetComponent<VoxelObject>();
		if (!reader.Ok || voxels == null || !Finite(point) || !radius.IsFinite)
			return;
		// On the server this is a client's request: carving here sends it on to everyone. A client applies the
		// point exactly as it came, in the object's own space, so that it does not depend on where the object is.
		let wasApplying = sApplying;
		sApplying = !network.IsServer;
		if (network.IsServer)
			voxels.Carve(voxels.Transform.TransformPoint(point), Mathf.Clamp(radius, 0, 64));
		else
			voxels.CarveLocal(point, Mathf.Clamp(radius, 0, 64));
		sApplying = wasApplying;
	}

	// ---- character controller shape ----

	static void WriteShape(NetWriter payload, CharacterController controller)
	{
		payload.Write<uint32>(controller.GetComponent<NetworkIdentity>().NetId);
		payload.Write<int32>((int32)controller.shape);
		payload.Write(controller.radius);
		payload.Write(controller.height);
		payload.Write(controller.boxSize);
		payload.Write(controller.edgeRadius);
		payload.Write(controller.center);
	}

	/// Called after a controller's shape changed locally. The server tells everyone; a client asks the server,
	/// having already changed its own copy so the player sees it at once.
	public static void ShapeChanged(CharacterController controller)
	{
		let network = Active(controller.Scene);
		if (network == null || sApplying || controller.GetComponent<NetworkIdentity>() == null)
			return;
		let payload = scope NetWriter();
		WriteShape(payload, controller);
		if (network.IsServer)
			network.SendToAll(MsgCharacterShape, payload);
		else
			network.SendToServer(MsgCharacterShape, payload);
	}

	static void OnCharacterShape(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let netId = reader.Read<uint32>();
		let shape = reader.Read<int32>();
		let radius = reader.Read<float>();
		let height = reader.Read<float>();
		let boxSize = reader.Read<Vector3>();
		let edgeRadius = reader.Read<float>();
		let center = reader.Read<Vector3>();
		if (!reader.Ok || shape < 0 || shape > (int32)CharacterShape.Box || !radius.IsFinite || !height.IsFinite || !Finite(boxSize) || !edgeRadius.IsFinite || !Finite(center))
			return;
		let identity = network.FindIdentity(netId);
		let controller = identity?.GetComponent<CharacterController>();
		if (controller == null)
			return;
		if (!network.IsServer)
		{
			sApplying = true;
			controller.ApplyRemoteShape((CharacterShape)shape, radius, height, boxSize, edgeRadius, center);
			sApplying = false;
			return;
		}
		// Only the player who controls a character may ask to change it, and only into something that fits.
		if (identity.ownerId == sender)
		{
			let old = (controller.shape, controller.radius, controller.height, controller.boxSize, controller.edgeRadius, controller.center);
			controller.shape = (CharacterShape)shape;
			controller.radius = radius;
			controller.height = height;
			controller.boxSize = boxSize;
			controller.edgeRadius = edgeRadius;
			controller.center = center;
			if (controller.ApplyShape())
				return; // which told everyone
			(controller.shape, controller.radius, controller.height, controller.boxSize, controller.edgeRadius, controller.center) = old;
		}
		// Refused: put the asker back to what the server has.
		let payload = scope NetWriter();
		WriteShape(payload, controller);
		network.SendToClient(sender, MsgCharacterShape, payload);
	}

	// ---- animation ----

	static void WriteAnimation(NetWriter payload, Component player, StringView clip, float fade)
	{
		let skinned = player as SkinnedMeshRenderer;
		payload.Write<bool>(skinned != null);
		if (skinned != null)
			WriteComponent<SkinnedMeshRenderer>(payload, skinned);
		else
			WriteComponent<Animator>(payload, (Animator)player);
		payload.WriteString(clip);
		payload.Write(fade);
	}

	/// Called when an Animator or Skinned Mesh Renderer starts a different clip. The server tells everyone. A
	/// client tells the server only about objects it controls, such as its own player.
	public static void AnimationPlayed(Component player, StringView clip, float fade)
	{
		let network = Active(player.Scene);
		if (network == null || sApplying)
			return;
		if (!network.IsServer)
		{
			let owner = Anchor(player).GetComponent<NetworkIdentity>();
			if (owner == null || !owner.IsOwner)
				return;
		}
		let payload = scope NetWriter();
		WriteAnimation(payload, player, clip, fade);
		if (network.IsServer)
			network.SendToAll(MsgAnimation, payload);
		else
			network.SendToServer(MsgAnimation, payload);
	}

	/// Called when an Animator with a controller has a parameter set (kind 0) or enters a state (kind 1). The same
	/// rule as clips: from the server, or from the player who owns the object, everyone follows.
	public static void AnimatorChanged(Animator animator, int32 kind, int32 index, float value)
	{
		let network = Active(animator.Scene);
		if (network == null || sApplying || !IsMine(animator))
			return;
		let payload = scope NetWriter();
		WriteComponent<Animator>(payload, animator);
		payload.Write((uint8)kind);
		payload.Write((int16)index);
		payload.Write(value);
		if (network.IsServer)
			network.SendToAll(MsgAnimator, payload);
		else
			network.SendToServer(MsgAnimator, payload);
	}

	/// Called when a Mesh Renderer is given another material (kind 0, name is its path) or has a value of its own
	/// material set (kind 1). The same rule as animation: from the server, or from the player who owns the
	/// object, everyone follows; the server remembers it for players who join later.
	public static void MaterialChanged(MeshRenderer renderer, int32 kind, StringView name, Vector4 value)
	{
		let network = Active(renderer.Scene);
		if (network == null || sApplying || !IsMine(renderer) || name.Length > 200)
			return;
		let payload = scope NetWriter();
		WriteComponent<MeshRenderer>(payload, renderer);
		payload.Write((uint8)kind);
		payload.WriteString(name);
		payload.Write(value);
		if (network.IsServer)
			Broadcast(network, MsgMaterial, payload, true);
		else
			network.SendToServer(MsgMaterial, payload);
	}

	static void OnMaterial(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let renderer = ReadComponent<MeshRenderer>(ref reader, network);
		let kind = (int32)reader.Read<uint8>();
		let name = scope String();
		reader.ReadString(name);
		let value = reader.Read<Vector4>();
		// kind 0: the renderer's material; 1: one of its material's values; 2: a skinned model's part's material
		// (value.x is the part).
		if (!reader.Ok || renderer == null || kind > 2 || name.Length > 200 || !value.x.IsFinite || !value.y.IsFinite || !value.z.IsFinite || !value.w.IsFinite)
			return;
		if (network.IsServer)
		{
			let owner = Anchor(renderer).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender || owner.ownerId == 0)
				return;
			let payload = scope NetWriter();
			WriteComponent<MeshRenderer>(payload, renderer);
			payload.Write((uint8)kind);
			payload.WriteString(name);
			payload.Write(value);
			Broadcast(network, MsgMaterial, payload, true);
		}
		let wasApplying = sApplying;
		sApplying = true;
		if (kind == 0)
			renderer.SetMaterial(name);
		else if (kind == 1)
			renderer.SetMaterialValue(name, value);
		else
			renderer.GameObject.GetComponent<SkinnedMeshRenderer>()?.SetPartMaterial((int)value.x, name);
		sApplying = wasApplying;
	}

	static void OnAnimator(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let animator = ReadComponent<Animator>(ref reader, network);
		let kind = (int32)reader.Read<uint8>();
		let index = (int32)reader.Read<int16>();
		let value = reader.Read<float>();
		if (!reader.Ok || animator == null || !value.IsFinite || kind > 1)
			return;
		if (network.IsServer)
		{
			let owner = Anchor(animator).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender || owner.ownerId == 0)
				return;
			// Passed on to the other players as it is applied here.
			let payload = scope NetWriter();
			WriteComponent<Animator>(payload, animator);
			payload.Write((uint8)kind);
			payload.Write((int16)index);
			payload.Write(value);
			network.SendToAll(MsgAnimator, payload);
		}
		let wasApplying = sApplying;
		sApplying = true;
		animator.ApplyRemote(kind, index, value);
		sApplying = wasApplying;
	}

	static void OnAnimation(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let isSkinned = reader.Read<bool>();
		SkinnedMeshRenderer skinned = null;
		Animator animator = null;
		if (isSkinned)
			skinned = ReadComponent<SkinnedMeshRenderer>(ref reader, network);
		else
			animator = ReadComponent<Animator>(ref reader, network);
		let clip = scope String();
		reader.ReadString(clip);
		let fade = reader.Read<float>();
		if (!reader.Ok || (skinned == null && animator == null) || !fade.IsFinite)
			return;
		if (network.IsServer)
		{
			// From the client that controls the object: play it here, which passes it on to the others.
			let owner = Anchor(skinned != null ? (Component)skinned : animator).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender)
				return;
		}
		let wasApplying = sApplying;
		sApplying = !network.IsServer;
		if (skinned != null)
			skinned.Play(clip, fade);
		else
			animator.Play(clip, fade);
		sApplying = wasApplying;
	}

	// ---- audio ----

	/// Called when an Audio Source plays (0), stops (1) or plays a one-off sound (2). As with animation: from the
	/// server it reaches everyone, from the player who controls the object it goes via the server.
	public static void AudioPlayed(AudioSource source, int32 action, StringView clip, float volume)
	{
		let network = Active(source.Scene);
		if (network == null || sApplying)
			return;
		if (!network.IsServer)
		{
			let owner = Anchor(source).GetComponent<NetworkIdentity>();
			if (owner == null || !owner.IsOwner)
				return;
		}
		let payload = scope NetWriter();
		WriteComponent<AudioSource>(payload, source);
		payload.Write(action);
		payload.WriteString(action == 0 ? (StringView)source.audioClip : clip);
		payload.Write(volume);
		if (network.IsServer)
			network.SendToAll(MsgAudio, payload);
		else
			network.SendToServer(MsgAudio, payload);
	}

	/// True when this machine is the one in charge of a component's object: always with no session, the server
	/// for objects nobody owns, and the owning client otherwise.
	public static bool IsMine(Component component)
	{
		let network = Active(component.Scene);
		if (network == null)
			return true;
		let identity = Anchor(component).GetComponent<NetworkIdentity>();
		if (identity == null)
			return network.IsServer;
		return identity.ownerId == network.LocalClientId || (network.IsServer && identity.ownerId == 0);
	}

	/// A client asks the server to move a shared conversation on: 0 advance, 1 choose index, 2 start at node,
	/// 3 stop. serial is the conversation step it saw, so a request about a line already gone is dropped.
	public static void DialogueRequest(DialogueRunner runner, int32 action, int32 serial, StringView node, int32 index = 0)
	{
		let network = Active(runner.Scene);
		if (network == null || network.IsServer || node.Length > 64)
			return;
		let payload = scope NetWriter();
		WriteComponent<DialogueRunner>(payload, runner);
		payload.Write(action);
		payload.Write(serial);
		payload.Write(index);
		payload.WriteString(node);
		network.SendToServer(MsgDialogue, payload);
	}

	static void OnDialogue(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null || !network.IsServer)
			return;
		let runner = ReadComponent<DialogueRunner>(ref reader, network);
		let action = reader.Read<int32>();
		let serial = reader.Read<int32>();
		let index = reader.Read<int32>();
		let node = scope String();
		reader.ReadString(node);
		if (!reader.Ok || runner == null || !runner.shared || action < 0 || action > 3 || node.Length > 64)
			return;
		if (runner.onlyOwnerChooses)
		{
			let owner = Anchor(runner).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender)
				return;
		}
		runner.ApplyRequest(action, serial, node, index);
	}

	/// Runs OnNetworkEvent(name, value) on a component on every machine. From the server it goes to everyone; from
	/// a client it goes through the server, which accepts it only for an object that client owns.
	public static void SendEvent(Component component, StringView name, float value = 0)
	{
		let network = Active(component.Scene);
		if (network == null)
		{
			component.OnNetworkEvent(name, value);
			return;
		}
		if (name.Length > 64 || !value.IsFinite)
			return;
		let payload = scope NetWriter();
		WriteComponent<Component>(payload, component);
		payload.WriteString(name);
		payload.Write(value);
		if (network.IsServer)
		{
			component.OnNetworkEvent(name, value);
			Broadcast(network, MsgEvent, payload, false);
		}
		else
			network.SendToServer(MsgEvent, payload);
	}

	static void OnEvent(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let component = ReadComponent<Component>(ref reader, network);
		let name = scope String();
		reader.ReadString(name);
		let value = reader.Read<float>();
		if (!reader.Ok || component == null || name.Length > 64 || !value.IsFinite)
			return;
		if (network.IsServer)
		{
			let owner = Anchor(component).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender)
				return;
			component.OnNetworkEvent(name, value);
			let payload = scope NetWriter();
			WriteComponent<Component>(payload, component);
			payload.WriteString(name);
			payload.Write(value);
			Broadcast(network, MsgEvent, payload, false);
		}
		else
			component.OnNetworkEvent(name, value);
	}

	static void OnAudio(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null)
			return;
		let source = ReadComponent<AudioSource>(ref reader, network);
		let action = reader.Read<int32>();
		let clip = scope String();
		reader.ReadString(clip);
		let volume = reader.Read<float>();
		if (!reader.Ok || source == null || !volume.IsFinite || action < 0 || action > 2)
			return;
		if (network.IsServer)
		{
			let owner = Anchor(source).GetComponent<NetworkIdentity>();
			if (owner == null || owner.ownerId != sender)
				return;
		}
		// On the server, doing it here passes it on to the other players.
		let wasApplying = sApplying;
		sApplying = !network.IsServer;
		switch (action)
		{
		case 0:
			if (!clip.IsEmpty)
				source.audioClip.Set(clip);
			source.Play();
		case 1: source.Stop();
		default: source.PlayOneShot(clip, volume);
		}
		sApplying = wasApplying;
	}

	// ---- [Sync] fields ----

	class Slot
	{
		public void* ptr;
		public int32 size;
		public bool isString;
		public List<uint8> last = new .() ~ delete _;
	}

	/// The [Sync] fields of an identity's object, in a fixed order that is the same on every machine.
	class SlotList
	{
		public List<Slot> slots = new .() ~ DeleteContainerAndItems!(_);
		/// Changes when components are added, removed or replaced by a script reload.
		public int signature;
	}

	static Dictionary<NetworkIdentity, SlotList> sSlots = new .() ~ DeleteDictionaryAndValues!(_);

	static int32 SizeOf(FieldRef field)
	{
		switch (field.kind)
		{
		case .Float: return 4;
		case .Double: return 8;
		case .Bool: return 1;
		case .Vector2: return 8;
		case .Vector3,.Int3: return 12;
		case .Vector4,.Quaternion,.Color: return 16;
		case .Matrix4: return 64;
		case .Int,.Enum,.Char: return (int32)field.type.Size;
		default: return 0;
		}
	}

	static SlotList Slots(NetworkIdentity identity)
	{
		int signature = identity.GameObject.Components.Count;
		for (let component in identity.GameObject.Components)
			signature = signature * 31 + (int)(void*)Internal.UnsafeCastToPtr(component);
		if (sSlots.TryGetValue(identity, let existing))
		{
			if (existing.signature == signature)
				return existing;
			sSlots.Remove(identity);
			delete existing;
		}
		let list = new SlotList();
		list.signature = signature;
		List<FieldRef> fields = scope .();
		for (let component in identity.GameObject.Components)
		{
			fields.Clear();
			ComponentRegistry.GetFields(component, fields);
			for (let field in fields)
			{
				if (!field.sync)
					continue;
				let size = SizeOf(field);
				if (size == 0 && field.kind != .String)
					continue;
				let slot = new Slot();
				slot.ptr = field.ptr;
				slot.size = size;
				slot.isString = field.kind == .String;
				list.slots.Add(slot);
			}
		}
		sSlots[identity] = list;
		return list;
	}

	public static void Forget(NetworkIdentity identity)
	{
		if (sSlots.GetAndRemove(identity) case .Ok(let pair))
			delete pair.value;
	}

	static Span<uint8> Bytes(Slot slot)
	{
		if (!slot.isString)
			return .((uint8*)slot.ptr, slot.size);
		let text = *(String*)slot.ptr;
		return text != null ? Span<uint8>((uint8*)text.Ptr, text.Length) : default;
	}

	static void WriteField(NetWriter payload, NetworkIdentity identity, int index, Slot slot)
	{
		let bytes = Bytes(slot);
		NetworkManager.WriteNetId(payload, identity.NetId);
		payload.WriteVarUInt((uint32)index);
		payload.WriteVarUInt((uint32)Math.Min(bytes.Length, 60000));
		payload.Data.AddRange(Span<uint8>(bytes.Ptr, Math.Min(bytes.Length, 60000)));
	}

	/// Server, once per snapshot: sends every [Sync] field whose value changed since it was last sent.
	public static void ServerTick(NetworkManager network)
	{
		let payload = scope NetWriter();
		for (let identity in network.Identities)
		{
			let list = Slots(identity);
			for (int i < list.slots.Count)
			{
				let slot = list.slots[i];
				let bytes = Bytes(slot);
				if (slot.last.Count == bytes.Length && (bytes.Length == 0 || Internal.MemCmp(slot.last.Ptr, bytes.Ptr, bytes.Length) == 0))
					continue;
				slot.last.Clear();
				slot.last.AddRange(bytes);
				payload.Clear();
				WriteField(payload, identity, i, slot);
				network.SendToAll(MsgField, payload);
			}
		}
	}

	static void OnField(int32 sender, ref NetReader reader)
	{
		let network = Active(Scene.Active);
		if (network == null || network.IsServer)
			return; // only the server's values are shared
		let netId = NetworkManager.ReadNetId(ref reader);
		let index = (int)reader.ReadVarUInt();
		let length = (int)reader.ReadVarUInt();
		if (!reader.Ok || length > 60000)
			return;
		uint8[] data = scope .[Math.Max(length, 1)];
		for (int i < length)
			data[i] = reader.Read<uint8>();
		if (!reader.Ok)
			return;
		let identity = network.FindIdentity(netId);
		if (identity == null)
			return;
		let list = Slots(identity);
		if (index >= list.slots.Count)
			return;
		let slot = list.slots[index];
		if (slot.isString)
		{
			let text = *(String*)slot.ptr;
			if (text != null)
				text..Clear().Append(StringView((char8*)&data[0], length));
		}
		else if (length == slot.size)
			Internal.MemCpy(slot.ptr, &data[0], length);
	}

	// ---- late joiners ----

	/// Server: brings a player who has just connected up to date with everything above.
	public static void ClientJoined(NetworkManager network, int32 clientId)
	{
		network.Replay(clientId);
		let payload = scope NetWriter();
		for (let identity in network.Identities)
		{
			let controller = identity.GetComponent<CharacterController>();
			if (controller != null)
			{
				payload.Clear();
				WriteShape(payload, controller);
				network.SendToClient(clientId, MsgCharacterShape, payload);
			}
			let list = Slots(identity);
			for (int i < list.slots.Count)
			{
				payload.Clear();
				WriteField(payload, identity, i, list.slots[i]);
				network.SendToClient(clientId, MsgField, payload);
			}
		}
		for (let component in network.Scene.Components)
		{
			StringView clip = "";
			if (let skinned = component as SkinnedMeshRenderer)
				clip = skinned.CurrentClip;
			else if (let animator = component as Animator)
				clip = animator.CurrentClip;
			if (clip.IsEmpty)
				continue;
			payload.Clear();
			WriteAnimation(payload, component, clip, 0);
			network.SendToClient(clientId, MsgAnimation, payload);
		}
	}
}
