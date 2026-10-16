using System;
using System.Collections;

namespace Tessera;

[Reflect(.All)]
enum NetworkMode : int32
{
	Offline,
	Server,
	Host,
	Client
}

/// Server-authoritative networking with client-side prediction and reconciliation.
///
/// The server simulates every tick from the players' controls and sends snapshots: for each player their own
/// objects in full, and of everything else only what has changed, packed small.
///
/// A client runs the objects it controls ahead of the server, from its own controls. When a snapshot disagrees
/// with what it predicted for that tick, it goes back to the server's state and runs its unacknowledged controls
/// again. Everything it does not control it cannot predict, so it shows those a moment in the past, moving
/// evenly between two things the server has said about them. Its tick clock runs very slightly fast or slow to
/// keep a couple of ticks of controls waiting on the server, which absorbs an uneven connection.
class NetworkManager
{
	public delegate GameObject PrefabFactory(Scene scene);
	/// Handler for a game-defined message. sender is the client id (0 when it came from the server or host).
	public delegate void MessageHandler(int32 sender, ref NetReader reader);
	public delegate void ClientJoinedHandler(int32 clientId);

	static Dictionary<uint8, MessageHandler> sHandlers = new .() ~ DeleteDictionaryAndValues!(_);

	/// Server only: called after a client has connected and received every spawned object.
	public ClientJoinedHandler OnClientJoined ~ delete _;

	/// Give scene objects that move on their own (physics bodies, AI, character controllers) a Network Identity
	/// when the session starts, if they do not have one. Set by Network Session.
	public bool AutoReplicate = true;
	/// Game scene selection, delivered before spawned objects in the welcome packet.
	public String SessionContext = new .() ~ delete _;
	public delegate void SessionContextHandler(StringView context);
	public SessionContextHandler OnSessionContext ~ delete _;
	/// True while ticks are being run again after a correction from the server.
	public bool Replaying;
	public Scene Scene => mScene;

	// Engine-level changes (voxel edits) kept so players who join later can be brought up to date.
	List<(uint8 id, List<uint8> data)> mRemembered = new .() ~ { for (let entry in _) delete entry.data; delete _; };
	// Scene objects the server has destroyed; a newcomer loads the scene with them still in it.
	List<uint32> mDestroyedSceneIds = new .() ~ delete _;
	bool mApplyingDespawn;
	// Ids for objects that every machine creates itself at the same point in the shared order of events (voxel
	// fragments): each machine counts them the same way, so they agree without the server naming each one.
	const uint32 FragmentIdBase = 0x20000000;
	uint32 mNextFragmentId = FragmentIdBase;

	public void AdoptFragment(NetworkIdentity identity)
	{
		Unregister(identity);
		identity.NetId = mNextFragmentId++;
		Register(identity);
	}
	const int cMaxRemembered = 100000;

	public void Remember(uint8 id, NetWriter payload)
	{
		if (mRemembered.Count >= cMaxRemembered)
		{
			if (mRemembered.Count == cMaxRemembered)
				Log.Warning("Too many world edits to replay; players who join from now on will miss the oldest ones.");
			delete mRemembered[0].data;
			mRemembered.RemoveAt(0);
		}
		let copy = new List<uint8>();
		copy.AddRange(payload.Data);
		mRemembered.Add((id, copy));
	}

	/// Server: sends a newcomer the remembered edits and the scene objects that no longer exist.
	public void Replay(int32 clientId)
	{
		for (let client in mClients)
		{
			if (client.id != clientId)
				continue;
			// Edits first: they recreate fragments, some of which the list below then removes again.
			for (let entry in mRemembered)
			{
				mWriter.Clear();
				mWriter.Write(MsgCustom);
				mWriter.Write(entry.id);
				mWriter.Data.AddRange(entry.data);
				Send(client.peer, true);
			}
			for (let netId in mDestroyedSceneIds)
			{
				mWriter.Clear();
				mWriter.Write(MsgDespawn);
				mWriter.Write(netId);
				Send(client.peer, true);
			}
		}
	}

	/// Called by Scene.Destroy. On the server, destroying a networked object removes it everywhere. On a client the
	/// server decides, so the request is refused unless it is the server's own instruction being carried out.
	public bool AllowDestroy(GameObject gameObject)
	{
		if (mMode == .Offline)
			return true;
		let identity = gameObject.GetComponent<NetworkIdentity>();
		if (identity == null || !mByNetId.ContainsKey(identity.NetId))
			return true;
		if (!IsServer)
			return mApplyingDespawn;
		mWriter.Clear();
		mWriter.Write(MsgDespawn);
		mWriter.Write(identity.NetId);
		for (let client in mClients)
			Send(client.peer, true);
		if (identity.NetId < SpawnedIdBase)
			mDestroyedSceneIds.Add(identity.NetId);
		Unregister(identity);
		return true;
	}

	/// Server: makes an object that was just created from a prefab file exist on every machine.
	public void Adopt(GameObject root, StringView prefabPath)
	{
		if (!IsServer)
			return;
		var identity = root.GetComponent<NetworkIdentity>();
		if (identity == null)
			return;
		Unregister(identity);
		identity.NetId = mNextSpawnId++;
		identity.ownerId = 0;
		identity.PrefabName.Set(prefabPath);
		Register(identity);
		for (let client in mClients)
			SendSpawn(client, identity);
	}

	/// Registers a handler for a game message id. Call once at startup on every machine.
	public static void RegisterMessage(uint8 id, MessageHandler handler)
	{
		if (sHandlers.TryGetValue(id, let old))
			delete old;
		sHandlers[id] = handler;
	}

	void Dispatch(uint8 id, int32 sender, ref NetReader reader)
	{
		if (sHandlers.TryGetValue(id, let handler))
			handler(sender, ref reader);
	}

	void WriteCustom(uint8 id, NetWriter payload)
	{
		mWriter.Clear();
		mWriter.Write(MsgCustom);
		mWriter.Write(id);
		mWriter.Data.AddRange(payload.Data);
	}

	/// Sends a game message to the server. On the server or host it is handled immediately. Reliable messages
	/// always arrive, in order; pass false for things that are useless late, like speech.
	public void SendToServer(uint8 id, NetWriter payload, bool reliable = true)
	{
		if (IsServer)
		{
			var reader = NetReader(payload.Data.Ptr, payload.Data.Count);
			Dispatch(id, Math.Max(LocalClientId, 0), ref reader);
		}
		else if (mServerPeer != null)
		{
			WriteCustom(id, payload);
			Send(mServerPeer, reliable);
		}
	}

	/// Server only: sends a reliable game message to every connected client.
	public void SendToAll(uint8 id, NetWriter payload)
	{
		if (!IsServer)
			return;
		WriteCustom(id, payload);
		for (let client in mClients)
			Send(client.peer, true);
	}

	/// Server only: sends a game message to one client.
	public void SendToClient(int32 clientId, uint8 id, NetWriter payload, bool reliable = true)
	{
		if (!IsServer)
			return;
		WriteCustom(id, payload);
		for (let client in mClients)
		{
			if (client.id == clientId)
				Send(client.peer, reliable);
		}
	}

	/// Server only: the ids of the connected clients. The host's own player is 0 and is not in the list.
	public void GetClientIds(List<int32> ids)
	{
		for (let client in mClients)
			ids.Add(client.id);
	}

	/// The character spawned for a player (0 is the host's own), or null if they have none.
	public GameObject PlayerObject(int32 clientId)
	{
		GameObject fallback = null;
		for (let identity in mIdentities)
		{
			if (identity.ownerId != clientId || identity.PrefabName.IsEmpty)
				continue;
			if (identity.PrefabName == PlayerPrefab)
				return identity.GameObject;
			if (fallback == null && clientId != 0)
				fallback = identity.GameObject;
		}
		return fallback;
	}

	VoiceChat.VoiceSession mVoice ~ delete _;
	/// This session's voice chat state. See VoiceChat.
	public VoiceChat.VoiceSession Voice
	{
		get
		{
			if (mVoice == null)
				mVoice = new .(this);
			return mVoice;
		}
	}

	/// Server only: hands control of an object to a client (or back to the server with 0).
	public void SetOwner(NetworkIdentity identity, int32 ownerId)
	{
		if (!IsServer || identity == null)
			return;
		identity.ownerId = ownerId;
		mWriter.Clear();
		mWriter.Write(MsgOwner);
		mWriter.Write(identity.NetId);
		mWriter.Write(ownerId);
		for (let client in mClients)
			Send(client.peer, true);
	}

	struct SnapshotDelivery
    {
        public uint32 tick, change;
        public int32 repeats;
        public bool dormant;
    }

    class ClientInfo
	{
		public int32 id;
		public void* peer;
		public List<(uint32 tick, NetInput input, double view)> queue = new .() ~ delete _;
		/// The server tick this player's machine was showing them when they gave the controls now in use.
		public double view;
		public NetInput lastInput;
		public uint32 lastProcessedTick;
		public uint32 lastReceivedTick;
		public int32 snapshotsSent;
        public int cursor;
        public Dictionary<uint32, SnapshotDelivery> delivered = new .() ~ delete _;
		/// Ticks since the last snapshot for which no controls had arrived.
		public int32 starved;
	}

	const uint8 MsgWelcome = 1;
	const uint8 MsgSpawn = 2;
	const uint8 MsgDespawn = 3;
	const uint8 MsgInput = 4;
	const uint8 MsgSnapshot = 5;
	const uint8 MsgCustom = 6;
	const uint8 MsgOwner = 7;
    const uint8 MsgSnapshotPart = 8;
	// Each packet of controls repeats the ticks before it, so that a lost packet costs nothing.
	const int InputRedundancy = 3;
	// More controls than this waiting on the server means the client has run ahead; the oldest are dropped.
	const int MaxQueuedInputs = 8;
	// An object that has stopped changing is still sent this many more times, in case the last word was lost,
	// and everything is sent again once in every RefreshEvery snapshots regardless.
	const uint32 SnapshotRepeats = 3;
	const uint32 RefreshEvery = 40;
	const int InputHistory = 256;
	const uint32 SpawnedIdBase = 0x40000000;

	Scene mScene;
	NetTransport mTransport ~ delete _;
	void* mServerPeer;
	/// How this session reaches other machines. Set before StartServer or StartClient.
	public NetworkTransportKind Transport = .Direct;
	NetworkMode mMode = .Offline;
	List<ClientInfo> mClients = new .() ~ DeleteContainerAndItems!(_);
	List<NetworkIdentity> mIdentities = new .() ~ delete _;
	Dictionary<uint32, NetworkIdentity> mByNetId = new .() ~ delete _;
	static Dictionary<String, PrefabFactory> mPrefabs = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	NetWriter mWriter = new .() ~ delete _;
    NetCompression mCompression ~ delete _;
    List<uint8> mCompressed=new .() ~ delete _;
    List<uint8> mDecompressed=new .() ~ delete _;
    int32 mStatTransportSent;
    /// Encoded application bytes offered to the transport before simulated loss (not physical wire bytes).
    public int32 TransportBytesSentPerSecond;
	int32 mNextClientId = 1;
	uint32 mNextSpawnId = SpawnedIdBase;
	uint32 mTick;
	NetInput[InputHistory] mInputs;
	NetInput mHostInput;
	bool mConnected;

	/// Prefab spawned for every player that joins (and for the host).
	public String PlayerPrefab = new .() ~ delete _;
	/// Server ticks between snapshots: 3 gives 20 snapshots per second at 60 ticks.
	public int32 SnapshotInterval = 3;
    /// Optional packet batching, remote formats, rates, dormancy and relevance. Legacy behaviour by default.
    public bool OptimizeSnapshots;
    /// Optional CPU timing of snapshot encoding and decoding, independent of frame pacing.
    public bool ProfileSnapshots;
    public uint64 SnapshotBuildNanoseconds,SnapshotReadNanoseconds,SnapshotBuildWorstNs,SnapshotReadWorstNs;
    public int64 SnapshotBuildCalls,SnapshotReadCalls;
    /// Remote snapshot payload limit; clamped to 256..1200. Owned corrections stay together and may exceed it.
    public int32 SnapshotPacketBytes = 1100;
    /// Per-client snapshot payload budget in bytes/second; zero means unlimited. Own prediction is reserved first.
    public int32 SnapshotBytesPerSecond;
    /// World-unit radius around each client's player, for distanceFiltered identities. Zero disables.
    public float SnapshotRelevanceRadius;
    /// Lossless compression: native ENet coder for Direct; independent message frames for Steam/WebRTC.
    public bool LosslessCompression;
    /// Force transport-independent lossless frames (also useful for testing Steam's message path over Direct).
    public bool MessageCompression;
    /// ENet UDP payload totals, including transport headers, retransmissions and compression.
    public uint32 WireBytesSent => mTransport?.WireSent ?? 0;
    public uint32 WireBytesReceived => mTransport?.WireReceived ?? 0;
	/// Position error in world units that triggers a rollback.
	public float CorrectionThreshold = 0.03f;
	/// How far in the past, in ticks, a client shows the objects it does not control. 0 picks two snapshots'
	/// worth, which rides out one lost snapshot; less is more up to date and less forgiving.
	public int32 InterpolationTicks = 0;
	public int32 LocalClientId = 0;
	/// The anti-cheat's notes on this session; see AntiCheat.
	public AntiCheat.Session AntiCheatState ~ delete _;
	/// The session whose messages are being handled right now, for message handlers; null between.
	public static NetworkManager Dispatching;
	/// Replace local controls with scripted movement.
	public bool BotInput;

	// Statistics for the editor's network panel.
	public int32 Rollbacks;
	public int32 SnapshotsReceived;
	public int32 PendingInputs;
	public float LastCorrection;

	/// Print a line of network figures once a second (--netstats), for finding out why a connection feels rough.
	public static bool LogStats;
	int32 mStatRollbacks, mStatReplayed, mStatSnapshots, mStatStarved, mStatDropped, mStatTicks;
	int32 mStatSent, mStatReceived, mStatPacketsSent, mStatHeld;
	float mStatOwnWorst;
	/// Bytes sent and received in the last full second, for the editor's network panel and --netstats.
	public int32 BytesSentPerSecond, BytesReceivedPerSecond;

	// Client: keeping in step with the server.
	uint32 mLastSnapshotTick;
	bool mHaveSnapshot;
	int32 mServerInterval = 3;
	/// Server tick minus this machine's tick, as snapshots arrive; smoothed.
	double mServerOffset;
	bool mClockSet;
	float mDepth = 2, mTargetDepth = cCalmDepth;
	int32 mCalmSnapshots;
	uint32 mSnapshotNumber;
	// How many ticks of controls the client aims to have waiting on the server when all is calm.
	const float cCalmDepth = 1.5f;
	/// Client: how many ticks of controls the server has waiting (smoothed), and how many this machine aims for.
	/// The server's tick as near as this machine knows it: exact on the server, estimated from snapshots on a
	/// client. Anything worked out from it alone (the swell on some water, a day and night cycle) comes out the
	/// same on every machine without being sent.
	public double ServerTick => IsServer || !mClockSet ? (double)mTick : (double)mTick + mServerOffset;
	public float InputsWaiting => mDepth;
	public float InputsWanted => mTargetDepth;

	void ReportStats()
	{
		if (++mStatTicks < Time.TickRate)
			return;
		BytesSentPerSecond = mStatSent;
        TransportBytesSentPerSecond=mStatTransportSent;mStatTransportSent=0;
		BytesReceivedPerSecond = mStatReceived;
		if (LogStats && IsServer)
		{
			let text = scope String();
			for (let client in mClients)
				text.AppendF(" [client {}: {} inputs waiting]", client.id, client.queue.Count);
			Log.Info(scope $"netstats server: sent {mStatSent} bytes in {mStatPacketsSent} packets, received {mStatReceived}, {mIdentities.Count} objects, {mStatStarved} ticks without input, {mStatDropped} inputs dropped{text}");
		}
		else if (LogStats)
			Log.Info(scope $"netstats client: sent {mStatSent} bytes, received {mStatReceived}, {mStatSnapshots} snapshots, {mStatRollbacks} rollbacks replaying {mStatReplayed} ticks, {PendingInputs} ticks ahead, own error {mStatOwnWorst:0.000}, {mDepth:0.0} of {mTargetDepth:0.0} inputs waiting, tick rate {Time.TickScale:0.000}, {mStatHeld} waits for news");
		mStatRollbacks = mStatReplayed = mStatSnapshots = mStatStarved = mStatDropped = mStatTicks = 0;
		mStatSent = mStatReceived = mStatPacketsSent = mStatHeld = 0;
		mStatOwnWorst = 0;
	}

	public NetworkMode Mode => mMode;
	public bool IsServer => mMode == .Server || mMode == .Host;
	public bool IsClient => mMode == .Client;
	public bool IsConnected => mConnected;
	public int32 ClientCount => (int32)mClients.Count;
	public uint32 Tick => mTick;
	public List<NetworkIdentity> Identities => mIdentities;

	public this(Scene scene)
	{
		mScene = scene;
	}

	public ~this()
	{
		Stop();
	}

	/// Registers a function that builds a networked object. Call once at startup (before any
	/// session starts) with the same names on the server and on clients.
	public static void RegisterPrefab(StringView name, PrefabFactory factory)
	{
		if (mPrefabs.TryGetValueAlt(name, let existing))
		{
			delete existing;
			mPrefabs[scope String(name)] = factory;
			return;
		}
		mPrefabs[new String(name)] = factory;
	}

	/// Registers a prefab file (made with "Save as Prefab" in the editor) under a name.
	/// Whether a network prefab of that name has been registered.
	public static bool IsRegistered(StringView name) => mPrefabs.ContainsKeyAlt(name);

	/// Makes one of a registered network prefab on this machine only, as the factory makes it (SaveSystem uses this
	/// to bring back saved objects when there is no session).
	public static GameObject CreateRegistered(Scene scene, StringView name)
	{
		if (!mPrefabs.TryGetValueAlt(name, let factory))
			return null;
		let gameObject = factory(scene);
		if (gameObject != null)
			String.NewOrSet!(gameObject.SpawnedFrom, name);
		return gameObject;
	}

	public static void RegisterPrefabFile(StringView name, StringView projectRelativePath)
	{
		let path = new String(projectRelativePath);
		RegisterPrefab(name, new [=path] (scene) => Prefab.Instantiate(scene, path) ~ delete path);
	}

	public bool StartServer(uint16 port, bool hostAlsoPlays)
	{
		Stop();
		mTransport = NetTransport.Create(Transport);
        if (let direct=mTransport as ENetTransport)direct.LosslessCompression=LosslessCompression;
		if (!mTransport.Host(port))
		{
			Stop();
			return false;
		}
		mMode = hostAlsoPlays ? .Host : .Server;
		mConnected = true;
		LocalClientId = hostAlsoPlays ? 0 : -1;
		NetworkSync.Prepare(this);
		RegisterSceneIdentities();
		if (hostAlsoPlays && !PlayerPrefab.IsEmpty)
			SpawnPlayer(0);
		Log.Info(scope $"Server listening on port {port}.");
		return true;
	}

	public bool StartClient(StringView address, uint16 port)
	{
		Stop();
		mTransport = NetTransport.Create(Transport);
        if (let direct=mTransport as ENetTransport)direct.LosslessCompression=LosslessCompression;
		if (!mTransport.Connect(address, port, out mServerPeer))
		{
			Stop();
			return false;
		}
		mMode = .Client;
		LocalClientId = -1;
		NetworkSync.Prepare(this);
		RegisterSceneIdentities();
		Log.Info(scope $"Connecting to {address}:{port}...");
		return true;
	}

	public void Stop()
	{
		if (mTransport != null)
		{
			if (mServerPeer != null)
				mTransport.Disconnect(mServerPeer);
			for (let client in mClients)
				mTransport.Disconnect(client.peer);
			mTransport.Close();
			delete mTransport;
		}
		mTransport = null;
		mServerPeer = null;
		ClearAndDeleteItems!(mDelayed);
		ClearAndDeleteItems!(mClients);
		if (mMode == .Client)
			Time.TickScale = 1;
		mMode = .Offline;
		mConnected = false;
	}

	void RegisterSceneIdentities()
	{
		for (let component in mScene.Components)
		{
			if (let identity = component as NetworkIdentity)
			{
				if (identity.NetId == 0)
					identity.NetId = identity.GameObject.Id;
				Register(identity);
			}
		}
	}

	void Register(NetworkIdentity identity)
	{
		if (identity.NetId == 0 || mByNetId.ContainsKey(identity.NetId))
			return;
		mIdentities.Add(identity);
		mByNetId[identity.NetId] = identity;
	}

	void Unregister(NetworkIdentity identity)
	{
        for(let client in mClients)client.delivered.Remove(identity.NetId);
		if (mIdentities.Remove(identity))
			mByNetId.Remove(identity.NetId);
	}

	/// Number of teams players are shared out among as they join, each going to the smallest. 0 for no teams.
	public int32 TeamCount;
	public delegate int32 TeamChooser(int32 clientId);
	/// Decides a joining player's team instead of TeamCount. Server only.
	public TeamChooser ChooseTeam ~ delete _;

	int32 TeamFor(int32 clientId)
	{
		if (ChooseTeam != null)
			return ChooseTeam(clientId);
		if (TeamCount <= 0)
			return 0;
		// Join the team with the fewest players; the lowest number wins a tie.
		int32 best = 1;
		int bestSize = int.MaxValue;
		for (int32 team = 1; team <= TeamCount; team++)
		{
			int size = 0;
			for (let identity in mIdentities)
			{
				if (identity.team == team && identity.PrefabName == PlayerPrefab)
					size++;
			}
			if (size < bestSize)
			{
				bestSize = size;
				best = team;
			}
		}
		return best;
	}

	/// Creates a player's object at a spawn point: the scene's Spawn Points if it has any (the next one for the
	/// player's team), otherwise beside an object named "SpawnPoint".
	GameObject SpawnPlayer(int32 clientId)
	{
		let team = TeamFor(clientId);
		Vector3 position;
		Quaternion rotation;
		if (!SpawnPoints.TryGet(mScene, team, false, out position, out rotation))
		{
			let marker = mScene.Find("SpawnPoint");
			let origin = marker != null ? marker.Transform.Position : Vector3(0, 2, 0);
			position = origin + Vector3((clientId % 4) * 2.0f, 0, (clientId / 4) * 2.0f);
			rotation = .Identity;
		}
		let player = Spawn(PlayerPrefab, position, rotation, clientId);
		let identity = player?.GetComponent<NetworkIdentity>();
		if (identity != null)
			identity.team = team;
		return player;
	}

	/// Server only: creates a prefab instance everywhere.
	public GameObject Spawn(StringView prefab, Vector3 position, Quaternion rotation, int32 ownerId)
	{
		if (!IsServer)
			return null;
		let netId = mNextSpawnId++;
		let gameObject = CreateFromPrefab(prefab, netId, ownerId, position, rotation);
		if (gameObject == null)
			return null;
		for (let client in mClients)
			SendSpawn(client, gameObject.GetComponent<NetworkIdentity>());
		return gameObject;
	}

	GameObject CreateFromPrefab(StringView prefab, uint32 netId, int32 ownerId, Vector3 position, Quaternion rotation)
	{
		GameObject gameObject = null;
		if (mPrefabs.TryGetValueAlt(prefab, let factory))
			gameObject = factory(mScene);
		else if (prefab.EndsWith(".tprefab"))
			gameObject = Prefab.Create(mScene, prefab); // a prefab file the server instantiated directly
		else
		{
			Log.Error(scope $"Network prefab '{prefab}' is not registered.");
			return null;
		}
		if (gameObject == null)
			return null;
		String.NewOrSet!(gameObject.SpawnedFrom, prefab);
		gameObject.Transform.SetPositionAndRotation(position, rotation);
		var identity = gameObject.GetComponent<NetworkIdentity>();
		if (identity == null)
			identity = gameObject.AddComponent<NetworkIdentity>();
		Unregister(identity);
		identity.NetId = netId;
		identity.ownerId = ownerId;
		identity.PrefabName.Set(prefab);
		Register(identity);
		return gameObject;
	}

	void SendSpawn(ClientInfo client, NetworkIdentity identity)
	{
		let state = identity.CaptureState();
		mWriter.Clear();
		mWriter.Write(MsgSpawn);
		mWriter.Write(identity.NetId);
		mWriter.Write(identity.ownerId);
		mWriter.WriteString(identity.PrefabName);
		mWriter.Write(state.position);
		mWriter.Write(state.rotation);
		Send(client.peer, true);
	}

	class DelayedPacket
	{
		public void* peer;
		public bool reliable;
		public uint64 dueTime;
		public List<uint8> data = new .() ~ delete _;
	}

	List<DelayedPacket> mDelayed = new .() ~ DeleteContainerAndItems!(_);
	uint32 mLossRandom = 0x2545f491;

	/// Network condition simulator for testing on one machine: every packet this machine sends is
	/// held back this many milliseconds. Run both sides with the same value; round-trip is twice it.
	public static int32 SimulatedLagMs;
	/// Percentage (0-100) of unreliable packets (inputs, snapshots) this machine throws away.
	public static float SimulatedLossPercent;
	/// Up to this many more milliseconds, different for every packet of controls or snapshots, on top of
	/// SimulatedLagMs: an uneven connection, on which packets bunch up and overtake one another.
	public static int32 SimulatedJitterMs;

	uint32 NextRandom()
	{
		mLossRandom ^= mLossRandom << 13;
		mLossRandom ^= mLossRandom >> 17;
		mLossRandom ^= mLossRandom << 5;
		return mLossRandom;
	}

	void Send(void* peer, bool reliable)
	{
		mStatSent += (int32)mWriter.Data.Count;
		mStatPacketsSent++;
        Span<uint8> payload=mWriter.Data;
        if(MessageCompression || LosslessCompression && Transport!=.Direct)
        {
            if(mCompression==null)mCompression=new .();
            if(mCompression.Encode(payload,mCompressed))payload=mCompressed;
        }
        mStatTransportSent+=(int32)payload.Length;
		if (SimulatedLossPercent > 0 && !reliable)
		{
			if ((NextRandom() % 10000) < (uint32)(SimulatedLossPercent * 100))
				return;
		}
		if (SimulatedLagMs > 0 || SimulatedJitterMs > 0)
		{
			let delayed = new DelayedPacket();
			delayed.peer = peer;
			delayed.reliable = reliable;
			// Reliable packets keep the plain delay, so that they stay in order.
			let extra = reliable || SimulatedJitterMs <= 0 ? 0 : NextRandom() % (uint32)(SimulatedJitterMs * 1000);
			delayed.dueTime = SDL.SDL_GetTicksNS() + (uint64)SimulatedLagMs * 1000000 + (uint64)extra * 1000;
			delayed.data.AddRange(payload);
			mDelayed.Add(delayed);
			return;
		}
		mTransport?.Send(peer, payload, reliable);
	}

	/// Sends the simulated-lag packets whose delay has passed.
	void ReleaseDelayed()
	{
		if (mDelayed.Count == 0)
			return;
		let now = SDL.SDL_GetTicksNS();
		int kept = 0;
		for (int i < mDelayed.Count)
		{
			let delayed = mDelayed[i];
			if (delayed.dueTime > now)
			{
				mDelayed[kept++] = delayed;
				continue;
			}
			mTransport?.Send(delayed.peer, delayed.data, delayed.reliable);
			delete delayed;
		}
		if (kept < mDelayed.Count)
			mDelayed.RemoveRange(kept, mDelayed.Count - kept);
	}

	void DropDelayedFor(void* peer)
	{
		for (int i = mDelayed.Count - 1; i >= 0; i--)
		{
			if (mDelayed[i].peer == peer)
			{
				delete mDelayed[i];
				mDelayed.RemoveAt(i);
			}
		}
	}

	ClientInfo FindClient(void* peer)
	{
		for (let client in mClients)
		{
			if (client.peer == peer)
				return client;
		}
		return null;
	}

	void Poll()
	{
		if (mTransport == null)
			return;
		ReleaseDelayed();
		NetEvent event;
		Dispatching = this;
		defer { Dispatching = null; }
		while (mTransport != null && mTransport.Poll(out event))
		{
			switch (event.kind)
			{
			case .Connected:
				if (IsServer)
					OnClientConnected(event.peer);
			case .Disconnected:
				if (IsServer)
					OnClientDisconnected(event.peer);
				else
				{
					Log.Warning("Disconnected from server.");
					mConnected = false;
				}
			case .Data:
				mStatReceived += (int32)event.length;
				Span<uint8> payload=.(event.data,event.length);
                if(event.length>0 && event.data[0]==NetCompression.MessageType)
                {
                    if(mCompression==null)mCompression=new .();
                    if(!mCompression.Decode(payload,mDecompressed))continue;
                    payload=mDecompressed;
                }
                var reader = NetReader(payload.Ptr, payload.Length);
				let type = reader.Read<uint8>();
				if (IsServer)
				{
					let client = FindClient(event.peer);
					if (client != null && type == MsgInput)
						ReadInputs(client, ref reader);
					else if (client != null && type == MsgCustom)
					{
						let messageId = reader.Read<uint8>();
						AntiCheat.NoteMessage(this, client.id, messageId);
						Dispatch(messageId, client.id, ref reader);
					}
				}
				else
				{
					switch (type)
					{
					case MsgWelcome: ReadWelcome(ref reader);
					case MsgSpawn: ReadSpawn(ref reader);
					case MsgDespawn: ReadDespawn(ref reader);
					case MsgSnapshot: ReadSnapshot(ref reader);
                        case MsgSnapshotPart: ReadSnapshot(ref reader, true);
					case MsgCustom: Dispatch(reader.Read<uint8>(), 0, ref reader);
					case MsgOwner:
						let ownedId = reader.Read<uint32>();
						let newOwner = reader.Read<int32>();
						if (reader.Ok && mByNetId.TryGetValue(ownedId, let owned))
						{
							owned.ownerId = newOwner;
							owned.ClearKeys();
						}
					default:
					}
				}
			}
		}
	}

	// ---- server ----

	void OnClientConnected(void* peer)
	{
		let client = new ClientInfo();
		client.id = mNextClientId++;
		client.peer = peer;
		mClients.Add(client);
		mWriter.Clear();
		mWriter.Write(MsgWelcome);
		mWriter.Write(client.id);
		mWriter.Write(mTick);
		mWriter.WriteString(SessionContext);
		Send(peer, true);
		// Bring the newcomer up to date with everything spawned so far, then add their player.
		for (let identity in mIdentities)
		{
			if (identity.NetId >= SpawnedIdBase)
				SendSpawn(client, identity);
		}
		if (!PlayerPrefab.IsEmpty)
			SpawnPlayer(client.id);
		AntiCheat.ClientJoined(this, client.id);
		NetworkSync.ClientJoined(this, client.id);
		if (OnClientJoined != null)
			OnClientJoined(client.id);
		Log.Info(scope $"Client {client.id} connected.");
	}

	/// Server: removes a client from the session, for a game that decides who may play (a private match, a
	/// player being sent away). Their objects go as if they had left. False if there is no such client.
	/// Anything sent to them just before may not arrive: send a reason a moment ahead if they should see one.
	public bool Kick(int32 clientId)
	{
		if (!IsServer || mTransport == null)
			return false;
		for (let client in mClients)
		{
			if (client.id != clientId)
				continue;
			let peer = client.peer;
			mTransport.Flush();
			mTransport.Disconnect(peer);
			OnClientDisconnected(peer);
			return true;
		}
		return false;
	}

	void OnClientDisconnected(void* peer)
	{
		let client = FindClient(peer);
		if (client == null)
			return;
		DropDelayedFor(peer);
		for (int i = mIdentities.Count - 1; i >= 0; i--)
		{
			let identity = mIdentities[i];
			if (identity.ownerId == client.id && identity.NetId >= SpawnedIdBase)
				Despawn(identity.GameObject);
		}
		AntiCheat.ClientLeft(this, client.id);
		Log.Info(scope $"Client {client.id} disconnected.");
		mClients.Remove(client);
		delete client;
	}

	/// Server only: removes a spawned object everywhere.
	public void Despawn(GameObject gameObject)
	{
		if (!IsServer || gameObject.GetComponent<NetworkIdentity>() == null)
			return;
		// Scene.Destroy asks AllowDestroy, which tells the clients.
		mScene.Destroy(gameObject);
	}

	void ReadInputs(ClientInfo client, ref NetReader reader)
	{
		let newest = reader.Read<uint32>();
		let count = (int)reader.Read<uint8>();
		if (!reader.Ok || count > 32)
			return;
		AntiCheat.NoteInputs(this, client.id, newest);
		// With the controls comes the server tick the player was being shown everyone else at, in quarter ticks;
		// only the low bits are sent, the rest being close to the tick the server is on.
		let viewLow = (int64)reader.Read<uint16>();
		let now4 = (int64)mTick * 4;
		var view4 = (now4 & ~(int64)0xFFFF) | viewLow;
		if (view4 > now4 + 0x8000)
			view4 -= 0x10000;
		else if (view4 < now4 - 0x8000)
			view4 += 0x10000;
		NetInput previous = default;
		for (int i < count)
		{
			let input = NetPack.ReadInput(ref reader, previous);
			if (!reader.Ok)
				return;
			previous = input;
			uint32 tick = newest - (uint32)(count - 1 - i);
			// Controls arrive several times over; only ticks not seen before count.
			if (tick <= client.lastReceivedTick)
				continue;
			client.lastReceivedTick = tick;
			AntiCheat.CheckInput(this, client.id, input);
			NetInput clean = input;
			clean.moveX = Mathf.Clamp(clean.moveX, -1, 1);
			clean.moveZ = Mathf.Clamp(clean.moveZ, -1, 1);
			if (tick > client.lastProcessedTick)
				client.queue.Add((tick, clean, (double)view4 / 4 - (double)(count - 1 - i)));
			else
				client.lastInput = clean; // too late for its own tick, but still the freshest word on what the player wants
		}
		// A client that runs ahead builds a backlog; drop the oldest to bound latency.
		while (client.queue.Count > MaxQueuedInputs)
		{
			client.queue.RemoveAt(0);
			mStatDropped++;
		}
	}

	void SimulateOwned(int32 ownerId, NetInput input)
	{
		for (int i = 0; i < mIdentities.Count; i++)
		{
			let identity = mIdentities[i];
			if (identity.ownerId != ownerId || !identity.IsActiveAndEnabled)
				continue;
			for (let component in identity.GameObject.Components)
			{
				if (let behaviour = component as NetworkBehaviour)
				{
					if (behaviour.IsActiveAndEnabled)
						behaviour.Simulate(input, Time.FixedDeltaTime);
				}
			}
		}
	}

	NetInput GatherLocalInput()
	{
		NetInput input = default;
		if (BotInput)
		{
			// Deterministic wandering used by automated tests and for filling a server with movement.
			input.moveZ = 1.0f;
			input.yaw = Math.Sin(mTick * 0.02f) * 120.0f;
			input.SetButton(0, mTick % 90 == 0);
			return input;
		}
		for (let identity in mIdentities)
		{
			if (identity.ownerId != LocalClientId || !identity.IsActiveAndEnabled)
				continue;
			for (let component in identity.GameObject.Components)
			{
				if (let behaviour = component as NetworkBehaviour)
					behaviour.GatherInput(ref input);
			}
		}
		return input;
	}

	/// Called by the scene before gameplay and physics run for a tick.
	public void PreTick()
	{
		Poll();
		if (mMode == .Offline)
			return;
		AntiCheat.Tick(this);
		if (IsServer)
		{
			if (mMode == .Host)
			{
				mHostInput = GatherLocalInput();
				SimulateOwned(0, mHostInput);
			}
			for (let client in mClients)
			{
				if (client.queue.Count > 0)
				{
					let entry = client.queue[0];
					client.queue.RemoveAt(0);
					client.lastInput = entry.input;
					client.lastProcessedTick = entry.tick;
					client.view = entry.view;
				}
				else if (client.lastProcessedTick > 0)
				{
					// Nothing has arrived for this tick. Carry on with the last controls and count the tick as done:
					// the player's own machine guessed the same unless the controls changed that very tick, and if
					// the real ones turn up late they are no longer wanted. Stalling instead would leave this player
					// a tick behind their own prediction for good.
					client.lastProcessedTick++;
					client.view += 1;
					client.starved++;
					mStatStarved++;
				}
				mSimulatingClient = client.id;
				mSimulatingView = client.view;
				SimulateOwned(client.id, client.lastInput);
				EndLagCompensation();
				mSimulatingClient = -1;
			}
		}
		else if (mConnected && LocalClientId > 0)
		{
			mTick++;
			ApplyRemoteStates();
			// Rounded to what the server will receive, so that both sides simulate from the same numbers.
			let input = NetPack.Quantize(GatherLocalInput());
			mInputs[mTick % InputHistory] = input;
			SendInputs();
			SimulateOwned(LocalClientId, input);
		}
	}

	/// Called by the scene after physics ran for a tick.
	public void PostTick()
	{
		if (mMode == .Offline)
			return;
		if (IsServer)
		{
			mTick++;
			if (mTick % (uint32)Math.Max(SnapshotInterval, 1) == 0)
			{
				SendSnapshots();
				NetworkSync.ServerTick(this);
			}
		}
		else if (mConnected && LocalClientId > 0)
		{
			for (let identity in mIdentities)
			{
				if (identity.ownerId == LocalClientId)
					identity.History[mTick % NetworkIdentity.HistorySize] = identity.CaptureState();
			}
		}
		// Objects this machine does not move itself change once a tick; they are drawn gliding between ticks.
		for (let identity in mIdentities)
		{
			identity.NoteTick(identity.ownerId != LocalClientId && !(IsServer && identity.ownerId == 0));
			// The server remembers where everything has been lately, for lag compensation.
			if (IsServer && mClients.Count > 0)
				identity.PushKey(mTick, identity.Transform.Position, identity.Transform.Rotation);
		}
		mTransport?.Flush();
		ReportStats();
	}

	/// Object ids are large numbers with the kind in the top bits; on the wire the kind goes in the low two bits,
	/// so that the usual small ones take a byte or two.
	static uint32 PackId(uint32 netId)
	{
		if (netId >= SpawnedIdBase && netId - SpawnedIdBase < 0x3FFFFFFF)
			return ((netId - SpawnedIdBase) << 2) | 1;
		if (netId >= FragmentIdBase && netId - FragmentIdBase < 0x1FFFFFFF)
			return ((netId - FragmentIdBase) << 2) | 2;
		if (netId < 0x20000000)
			return netId << 2;
		return 3;
	}

	void WriteId(uint32 netId) => WriteNetId(mWriter, netId);

	/// Writes an object's network id in as few bytes as it takes, usually one or two.
	public static void WriteNetId(NetWriter writer, uint32 netId)
	{
		let packed = PackId(netId);
		writer.WriteVarUInt(packed);
		if (packed == 3)
			writer.Write(netId);
	}

	public static uint32 ReadNetId(ref NetReader reader) => ReadId(ref reader);

	static uint32 ReadId(ref NetReader reader)
	{
		let packed = reader.ReadVarUInt();
		switch (packed & 3)
		{
		case 0: return packed >> 2;
		case 1: return SpawnedIdBase + (packed >> 2);
		case 2: return FragmentIdBase + (packed >> 2);
		default: return reader.Read<uint32>();
		}
	}

    void BeginSnapshotPacket(ClientInfo client)
    {
        mWriter.Clear();mWriter.Write(MsgSnapshotPart);mWriter.Write(mTick);mWriter.Write(client.lastProcessedTick);
        mWriter.Write((uint8)Math.Clamp(SnapshotInterval,1,255));
        mWriter.Write((int8)(client.starved>0 ? -Math.Min(client.starved,100) : Math.Min(client.queue.Count,100)));
        mWriter.Write((uint16)0);
    }

    void FlushSnapshotPacket(ClientInfo client, int count, bool reliable)
    {
        if(count==0)return;
        var written=(uint16)count;Internal.MemCpy(mWriter.Data.Ptr+11,&written,2);
        Send(client.peer,reliable);
    }

    void WriteSnapshotRecord(NetWriter writer, NetworkIdentity identity, int32 clientId)
    {
        WriteNetId(writer,identity.NetId);
        let flagsAt=writer.Data.Count;
        if(identity.ownerId==clientId || identity.remoteFormat==.Legacy && identity.fullPrecision)
        { writer.Write(NetPack.FlagFull);writer.Write(identity.CaptureState()); }
        else if(identity.remoteFormat!=.Legacy)
            NetPack.WriteTransform(writer,identity.Transform.Position,identity.Transform.Rotation,identity.remoteFormat==.QuantizedTransform);
        else NetPack.Write(writer,identity.Sent);
        if(identity.ownerId!=clientId && identity.SnapshotSleeping)writer.Data[flagsAt]|=NetPack.FlagSleeping;
    }

    void SendOptimizedSnapshots()
    {
        mSnapshotNumber++;
        for(let identity in mIdentities)identity.NoteSnapshot(mSnapshotNumber,true);
        let record=scope NetWriter();
        let candidates=scope List<NetworkIdentity>();
        for(let client in mClients)
        {
            let player=PlayerObject(client.id);
            candidates.Clear();
            for(let identity in mIdentities)
            {
                let own=identity.ownerId==client.id;
                if(!own && identity.distanceFiltered && SnapshotRelevanceRadius>0 && player!=null &&
                    (identity.Transform.Position-player.Transform.Position).LengthSquared>SnapshotRelevanceRadius*SnapshotRelevanceRadius)
                { client.delivered.Remove(identity.NetId);continue; }
                SnapshotDelivery sent=default;let known=client.delivered.TryGetValue(identity.NetId,out sent);
                if(own) { candidates.Add(identity);continue; }
                if(known && mTick-sent.tick<(uint32)Math.Max(identity.remoteIntervalTicks,SnapshotInterval))continue;
                let changed=!known || sent.change!=identity.ChangedAt || sent.dormant!=identity.SnapshotSleeping;
                let refresh=!identity.SnapshotSleeping && mTick-sent.tick>=(uint32)(Math.Max(SnapshotInterval,1)*(int32)RefreshEvery);
                if(changed || sent.repeats<(int32)SnapshotRepeats || refresh)candidates.Add(identity);
            }
            // Ownership, explicit priority, then age. Stable id breaks ties so every client is deterministic.
            candidates.Sort(scope (a,b) =>
            {
                if((a.ownerId==client.id)!=(b.ownerId==client.id))return a.ownerId==client.id ? -1 : 1;
                if(a.snapshotPriority!=b.snapshotPriority)return b.snapshotPriority<=>a.snapshotPriority;
                SnapshotDelivery sa=default,sb=default;client.delivered.TryGetValue(a.NetId,out sa);client.delivered.TryGetValue(b.NetId,out sb);
                return sa.tick!=sb.tick ? sa.tick<=>sb.tick : a.NetId<=>b.NetId;
            });
            BeginSnapshotPacket(client);int count=0,spent=0;bool reliable=false,containsOwned=false;
            let limit=Math.Clamp(SnapshotPacketBytes,256,1200);
            let budget=SnapshotBytesPerSecond>0 ? Math.Max(128,(int)((int64)SnapshotBytesPerSecond*Math.Max(SnapshotInterval,1)/Math.Max(Time.TickRate,1))) : int.MaxValue;
            for(let identity in candidates)
            {
                record.Clear();WriteSnapshotRecord(record,identity,client.id);
                let dormant=identity.ownerId!=client.id && identity.SnapshotSleeping;
                let own=identity.ownerId==client.id;
                // One coherent correction for all owned objects: replay must not advance them once per chunk.
                // Exceptional large ownership groups retain legacy fragmentation rather than replaying twice.
                let flush=count>0 && (!own && (containsOwned || mWriter.Data.Count+record.Data.Count>limit) || reliable!=dormant);
                let cost=record.Data.Count+((count==0 || flush) ? 13 : 0);
                if(identity.ownerId!=client.id && spent+cost>budget)continue;
                if(flush) { FlushSnapshotPacket(client,count,reliable);BeginSnapshotPacket(client);count=0;containsOwned=false; }
                reliable=dormant;containsOwned |= own;mWriter.Data.AddRange(record.Data);count++;spent+=cost;
                SnapshotDelivery sent=default;client.delivered.TryGetValue(identity.NetId,out sent);
                let same=sent.change==identity.ChangedAt && sent.dormant==dormant;
                sent.repeats=dormant ? (int32)SnapshotRepeats : (same ? sent.repeats+1 : 1);
                sent.tick=mTick;sent.change=identity.ChangedAt;sent.dormant=dormant;
                client.delivered[identity.NetId]=sent;
            }
            FlushSnapshotPacket(client,count,reliable);
            if(count==0 && spent==0) { BeginSnapshotPacket(client);Send(client.peer,false); }
            client.snapshotsSent++;client.starved=0;
        }
    }

	void SendSnapshots()
    {
        let began=ProfileSnapshots ? SDL.SDL_GetTicksNS() : 0;
        defer { if(ProfileSnapshots) { let ns=SDL.SDL_GetTicksNS()-began;SnapshotBuildNanoseconds+=ns;SnapshotBuildWorstNs=Math.Max(SnapshotBuildWorstNs,ns);SnapshotBuildCalls++; } }
        if (OptimizeSnapshots) { SendOptimizedSnapshots();return; }
		mSnapshotNumber++;
		for (let identity in mIdentities)
			identity.NoteSnapshot(mSnapshotNumber);
		for (let client in mClients)
		{
			mWriter.Clear();
			mWriter.Write(MsgSnapshot);
			mWriter.Write(mTick);
			mWriter.Write(client.lastProcessedTick);
			mWriter.Write((uint8)Math.Clamp(SnapshotInterval, 1, 255));
			// How well supplied with this player's controls the server is: their machine steers its clock by it.
			mWriter.Write((int8)(client.starved > 0 ? -Math.Min(client.starved, 100) : Math.Min(client.queue.Count, 100)));
			let countAt = mWriter.Data.Count;
			mWriter.Write((uint16)0);
			int count = 0;
			// A newcomer is told about everything, a few times over in case a snapshot is lost.
			let everything = client.snapshotsSent < (int32)SnapshotRepeats;
			for (let identity in mIdentities)
			{
				// Nothing is said about an object that has not changed for a few snapshots.
				if (!everything && mSnapshotNumber - identity.ChangedAt >= SnapshotRepeats && (mSnapshotNumber + identity.NetId) % RefreshEvery != 0)
					continue;
				WriteId(identity.NetId);
				if (identity.ownerId == client.id || identity.fullPrecision)
				{
					// Their own objects go exactly, velocity and all: this is what their prediction is checked against.
					mWriter.Write(NetPack.FlagFull);
					mWriter.Write(identity.CaptureState());
				}
				else
					NetPack.Write(mWriter, identity.Sent);
				count++;
			}
			var written = (uint16)Math.Min(count, 65535);
			Internal.MemCpy(mWriter.Data.Ptr + countAt, &written, 2);
			client.snapshotsSent++;
			client.starved = 0;
			Send(client.peer, false);
		}
	}

	// ---- client ----

	void SendInputs()
	{
		let count = (int)Math.Min((uint32)InputRedundancy, mTick);
		mWriter.Clear();
		mWriter.Write(MsgInput);
		mWriter.Write(mTick);
		mWriter.Write((uint8)count);
		mWriter.Write((uint16)((int64)Math.Round(mViewTick * 4) & 0xFFFF));
		NetInput previous = default;
		for (int i = count - 1; i >= 0; i--)
		{
			let input = mInputs[(mTick - (uint32)i) % InputHistory];
			NetPack.WriteInput(mWriter, input, previous, i != count - 1);
			previous = input;
		}
		Send(mServerPeer, false);
	}

	void ReadWelcome(ref NetReader reader)
	{
		LocalClientId = reader.Read<int32>();
		reader.Read<uint32>();
		let context=scope String();reader.ReadString(context);
		if(reader.Ok && OnSessionContext!=null) OnSessionContext(context);
		mConnected = reader.Ok;
		mTick = 0;
		mHaveSnapshot = false;
		mClockSet = false;
		mDepth = 2;
		mTargetDepth = cCalmDepth;
		Log.Info(scope $"Connected as client {LocalClientId}.");
	}

	void ReadSpawn(ref NetReader reader)
	{
		let netId = reader.Read<uint32>();
		let ownerId = reader.Read<int32>();
		let name = scope String();
		reader.ReadString(name);
		let position = reader.Read<Vector3>();
		let rotation = reader.Read<Quaternion>();
		if (!reader.Ok || mByNetId.ContainsKey(netId))
			return;
		CreateFromPrefab(name, netId, ownerId, position, rotation);
	}

	void ReadDespawn(ref NetReader reader)
	{
		let netId = reader.Read<uint32>();
		if (reader.Ok && mByNetId.TryGetValue(netId, let identity))
		{
			mApplyingDespawn = true;
			mScene.Destroy(identity.GameObject);
			mApplyingDespawn = false;
			Unregister(identity);
		}
	}

	void ReadSnapshot(ref NetReader reader, bool part = false)
    {
        let began=ProfileSnapshots ? SDL.SDL_GetTicksNS() : 0;
        defer { if(ProfileSnapshots) { let ns=SDL.SDL_GetTicksNS()-began;SnapshotReadNanoseconds+=ns;SnapshotReadWorstNs=Math.Max(SnapshotReadWorstNs,ns);SnapshotReadCalls++; } }
		let serverTick = reader.Read<uint32>();
		let ackTick = reader.Read<uint32>();
		uint32 interval = (uint32)Math.Max((int32)reader.Read<uint8>(), 1);
		let depth = (int32)reader.Read<int8>();
		let count = (int)reader.Read<uint16>();
		if (!reader.Ok || LocalClientId <= 0)
			return;
		SnapshotsReceived++;
		mStatSnapshots++;
		// Snapshots can overtake one another on the way; one older than the last has nothing to add.
		let fresh = !mHaveSnapshot || (int32)(serverTick-mLastSnapshotTick)>0;
        if (!part && !fresh)return;
		// With the snapshot before this one in hand, an object it left out is known to have been still then.
		let sawPrevious = mHaveSnapshot && serverTick - mLastSnapshotTick == interval;

		List<(NetworkIdentity identity, BodyState state)> owned = scope .();
		for (int i < count)
		{
			let netId = ReadId(ref reader);
			let flags = reader.Read<uint8>();
			BodyState state = default;
			if ((flags & NetPack.FlagFull) != 0)
				state = reader.Read<BodyState>();
			else if ((flags & (NetPack.FlagExactTransform | NetPack.FlagFineTransform))!=0)
                NetPack.ReadTransform(ref reader,flags,out state.position,out state.rotation);
            else
				NetPack.Unpack(NetPack.Read(ref reader, flags), out state.position, out state.rotation);
			if (!reader.Ok)
				return;
			if (!mByNetId.TryGetValue(netId, let identity))
				continue;
			if (identity.ownerId == LocalClientId)
			{
				if ((flags & NetPack.FlagFull) != 0 && (!part || fresh || serverTick==mLastSnapshotTick))
					owned.Add((identity, state));
				continue;
			}
			if (!part && sawPrevious && identity.HasKeys && serverTick - identity.NewestKeyTick > interval)
				identity.HoldKey((uint32)(serverTick - interval));
            if ((flags & NetPack.FlagFull) != 0) identity.PushBodyKey(serverTick,state,(flags & NetPack.FlagSleeping)!=0);
            else identity.PushKey(serverTick, state.position, state.rotation, (flags & NetPack.FlagSleeping)!=0);
		}
		if (fresh)
        {
            mLastSnapshotTick=serverTick;mHaveSnapshot=true;mServerInterval=(int32)interval;
            FollowServerClock(serverTick,depth);
        }
        if (owned.Count>0)Reconcile(ackTick,owned);
	}

	/// Client: keeps track of what tick the server is on, and runs this machine's ticks a little faster or slower
	/// so that the server always has a tick or two of its controls in hand: enough to cover an uneven connection,
	/// and no more, because every tick waiting there is a tick of delay on everything this player does.
	void FollowServerClock(uint32 serverTick, int32 depth)
	{
		let sample = (double)serverTick - (double)mTick;
		if (!mClockSet || Math.Abs(sample - mServerOffset) > 30)
			mServerOffset = sample;
		else
			mServerOffset += (sample - mServerOffset) * 0.1;
		mClockSet = true;

		if (depth < 0)
		{
			// The server ran dry: the connection is less even than was allowed for.
			mTargetDepth = Math.Min(mTargetDepth + 0.5f, MaxQueuedInputs - 2);
			mCalmSnapshots = 0;
		}
		else if (++mCalmSnapshots >= 200)
		{
			mTargetDepth = Math.Max(mTargetDepth - 0.5f, cCalmDepth);
			mCalmSnapshots = 0;
		}
		mDepth += ((float)depth - mDepth) * 0.2f;
		Time.TickScale = 1 + Math.Clamp((mTargetDepth - mDepth) * 0.02f, -0.05f, 0.05f);
	}

	// ---- lag compensation ----

	/// The furthest back, in ticks, that lag compensation will go: 24 is 0.4 seconds.
	public int32 MaxRewindTicks = 24;
	// Server: whose controls are being run right now, and the server tick their machine was showing them.
	int32 mSimulatingClient = -1;
	double mSimulatingView;
	bool mRewound;
	List<(NetworkIdentity identity, BodyState state)> mRewoundStates = new .() ~ delete _;
	// Client: the server tick everything else is being shown at this tick.
	double mViewTick;

	/// Server, while a player's tick is being run (in OnTick or Simulate): puts every other networked object back
	/// where that player's machine was showing it when they gave these controls, until EndLagCompensation. A
	/// player aims at what they see, which is the past: the time their controls took to arrive, plus the moment's
	/// delay everything they do not control is shown with. Do the ray cast or overlap test for a shot or a swing
	/// between the two calls, and the server judges it against what the player was looking at.
	///
	/// Returns false, having done nothing, anywhere it does not apply: with no session, on a client, and for the
	/// host's own player and the server's objects, who see things as they are. Keep what happens in between
	/// short and free of side effects: find out what was hit, end, then deal the damage.
	public bool BeginLagCompensation(NetworkIdentity forObject)
	{
		if (!IsServer || mRewound || forObject == null || forObject.ownerId <= 0 || forObject.ownerId != mSimulatingClient)
			return false;
		let view = Math.Max(mSimulatingView, (double)mTick - Math.Max(MaxRewindTicks, 0));
		if (view >= (double)mTick)
			return false;
		for (let identity in mIdentities)
		{
			if (identity.ownerId == forObject.ownerId || !identity.IsActiveAndEnabled)
				continue;
			BodyState then;
			if (!identity.Sample(view, 0, out then))
				continue;
			let now = identity.CaptureState();
			if ((now.position - then.position).LengthSquared < 1.0e-6f)
				continue;
			mRewoundStates.Add((identity, now));
			var moved = now;
			moved.position = then.position;
			moved.rotation = then.rotation;
			identity.ApplyState(moved);
		}
		mRewound = true;
		return true;
	}

	/// Puts everything back where it really is. Safe to call when nothing was moved.
	public void EndLagCompensation()
	{
		if (!mRewound)
			return;
		for (let entry in mRewoundStates)
		{
			if (!entry.identity.GameObject.IsDestroyed)
				entry.identity.ApplyState(entry.state);
		}
		mRewoundStates.Clear();
		mRewound = false;
	}

	/// Client, every tick: puts everything this machine does not control where the server had it a moment ago.
	void ApplyRemoteStates()
	{
		if (!mClockSet)
			return;
		let delay = InterpolationTicks > 0 ? InterpolationTicks : mServerInterval * 2;
		let at = (double)mTick + mServerOffset - delay;
		mViewTick = at;
		for (let identity in mIdentities)
		{
			if (identity.ownerId == LocalClientId || !identity.HasKeys)
				continue;
			BodyState state;
			if (!identity.Sample(at, mServerInterval, out state))
				continue;
			if (at > (double)identity.NewestKeyTick && state.linearVelocity != .Zero)
				mStatHeld++;
			// Something lying still needs nothing done; leaving it alone also lets a physics body go to sleep.
			let transform = identity.Transform;
			if ((transform.Position - state.position).LengthSquared < 1.0e-8f && Mathf.Abs(Quaternion.Dot(transform.Rotation, state.rotation)) > 0.999999f)
				continue;
			identity.ApplyState(state);
		}
	}

	/// Client: checks what the server says about this machine's own objects against what was predicted for the
	/// same tick, and if they differ, goes back to the server's state and runs the ticks since again.
	void Reconcile(uint32 ackTick, List<(NetworkIdentity identity, BodyState state)> owned)
	{
		if (owned.IsEmpty)
			return;
		// Remember where things were drawn so that a correction can be eased in visually.
		List<Vector3> before = scope .();
		for (let entry in owned)
			before.Add(entry.identity.Transform.Position + entry.identity.SmoothOffset);
		defer
		{
			for (int i < owned.Count)
			{
				let identity = owned[i].identity;
				if (before.Count > i)
					identity.SmoothOffset = before[i] - identity.Transform.Position;
			}
		}

		if (ackTick > mTick)
		{
			// The server has got ahead of this machine, which must have stopped for a moment. Take its state and
			// jump the clock forward to where it should be, rather than limp along behind.
			let lead = (uint32)Math.Clamp(PendingInputs, 1, 30);
			let last = mInputs[mTick % InputHistory];
			for (let entry in owned)
			{
				entry.identity.ApplyState(entry.state);
				for (int i < NetworkIdentity.HistorySize)
					entry.identity.History[i] = entry.state;
			}
			uint32 target = ackTick + lead;
			uint32 first = target >= (uint32)InputHistory ? target - (uint32)InputHistory + 1 : 1;
			for (uint32 tick = Math.Max(mTick + 1, first); tick <= target; tick++)
				mInputs[tick % InputHistory] = last;
			mServerOffset -= (double)(target - mTick);
			mTick = target;
			Rollbacks++;
			mStatRollbacks++;
			return;
		}

		// Until the server has consumed one of our inputs there is nothing to compare against: adopt its state.
		let comparable = ackTick > 0 && mTick - ackTick < NetworkIdentity.HistorySize;
		float worst = 0;
		if (comparable)
		{
			for (let entry in owned)
			{
				let predicted = entry.identity.History[ackTick % NetworkIdentity.HistorySize];
                if(predicted.prediction0.w != entry.state.prediction0.w) worst=Math.Max(worst,1);
				worst = Math.Max(worst, (predicted.position - entry.state.position).Length);
				worst = Math.Max(worst, (1.0f - Mathf.Abs(Quaternion.Dot(predicted.rotation, entry.state.rotation))) * 2.0f);
			}
			mStatOwnWorst = Math.Max(mStatOwnWorst, worst);
			PendingInputs = (int32)(mTick - ackTick);
			if (worst <= CorrectionThreshold)
			{
				before.Clear(); // nothing moved: leave any easing already under way alone
				return;
			}
		}

		LastCorrection = worst;
		Rollbacks++;
		mStatRollbacks++;
		for (let entry in owned)
			entry.identity.ApplyState(entry.state);
		if (!comparable)
			return;
		for (let entry in owned)
			entry.identity.History[ackTick % NetworkIdentity.HistorySize] = entry.state;
		mStatReplayed += (int32)(mTick - ackTick);

		// Objects moved by the physics engine need it stepped as well. That moves every other body too, so those
		// are put back afterwards: where they are is the server's business.
		bool stepPhysics = false;
		for (let entry in owned)
		{
			let body = entry.identity.GetComponent<Rigidbody>();
			if (body != null && body.HasBody)
				stepPhysics = true;
		}
		List<(NetworkIdentity identity, BodyState state)> others = scope .();
		if (stepPhysics)
		{
			for (let identity in mIdentities)
			{
				let body = identity.ownerId != LocalClientId ? identity.GetComponent<Rigidbody>() : null;
				if (body != null && body.HasBody)
					others.Add((identity, identity.CaptureState()));
			}
		}

		// Replay every input the server has not acknowledged yet on top of the corrected state.
		Replaying = true;
		defer { Replaying = false; }
		for (uint32 tick = ackTick + 1; tick <= mTick; tick++)
		{
			SimulateOwned(LocalClientId, mInputs[tick % InputHistory]);
            // A replayed contact can hand a transform motor to a body during this tick.
            if(!stepPhysics)
            {
                for(let entry in owned)
                    if(entry.identity.GetComponent<Rigidbody>()?.HasBody == true) stepPhysics=true;
                if(stepPhysics)
                    for(let identity in mIdentities)
                        if(identity.ownerId != LocalClientId && identity.GetComponent<Rigidbody>()?.HasBody == true)
                            others.Add((identity,identity.CaptureState()));
            }
			if (stepPhysics)
				mScene.Physics.Step(Time.FixedDeltaTime);
			for (let entry in owned)
				entry.identity.History[tick % NetworkIdentity.HistorySize] = entry.identity.CaptureState();
		}
		for (let entry in others)
			entry.identity.ApplyState(entry.state);
	}
}
