using System;
using System.Collections;

namespace Tessera;

/// The client's side: sending inputs, and reading the welcome, spawns, despawns and snapshots the server sends.
extension NetworkManager
{
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
		let context = scope String();
		reader.ReadString(context);
		if (reader.Ok && OnSessionContext != null)
			OnSessionContext(context);
		mConnected = reader.Ok;
		mTick = 0;
		mHaveSnapshot = false;
		mClockSet = false;
		mDepth = 2;
		mTargetDepth = CalmDepth;
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
		let began = ProfileSnapshots ? SDL.SDL_GetTicksNS() : 0;
		defer
		{
			if (ProfileSnapshots)
			{
				let ns = SDL.SDL_GetTicksNS() - began;
				SnapshotReadNanoseconds += ns;
				SnapshotReadWorstNs = Math.Max(SnapshotReadWorstNs, ns);
				SnapshotReadCalls++;
			}
		}
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
		let fresh = !mHaveSnapshot || (int32)(serverTick - mLastSnapshotTick) > 0;
		if (!part && !fresh) return;
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
			else if ((flags & (NetPack.FlagExactTransform | NetPack.FlagFineTransform)) != 0)
				NetPack.ReadTransform(ref reader, flags, out state.position, out state.rotation);
			else
				NetPack.Unpack(NetPack.Read(ref reader, flags), out state.position, out state.rotation);
			if (!reader.Ok)
				return;
			if (!mByNetId.TryGetValue(netId, let identity))
				continue;
			if (identity.ownerId == LocalClientId)
			{
				if ((flags & NetPack.FlagFull) != 0 && (!part || fresh || serverTick == mLastSnapshotTick))
					owned.Add((identity, state));
				continue;
			}
			if (!part && sawPrevious && identity.HasKeys && serverTick - identity.NewestKeyTick > interval)
				identity.HoldKey((uint32)(serverTick - interval));
			// Character motors may use velocity slots for prediction metadata. Only
			// rigidbodies carry physical spin that is safe to extrapolate.
			if ((flags & NetPack.FlagFull) != 0 && identity.GetComponent<Rigidbody>() != null)
				identity.PushBodyKey(serverTick, state, (flags & NetPack.FlagSleeping) != 0);
			else
				identity.PushKey(serverTick, state.position, state.rotation, (flags & NetPack.FlagSleeping) != 0);
		}
		if (fresh)
		{
			mLastSnapshotTick = serverTick;
			mHaveSnapshot = true;
			mServerInterval = (int32)interval;
			FollowServerClock(serverTick, depth);
		}
		if (owned.Count > 0)
			Reconcile(ackTick, owned);
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
			mTargetDepth = Math.Max(mTargetDepth - 0.5f, CalmDepth);
			mCalmSnapshots = 0;
		}
		mDepth += ((float)depth - mDepth) * 0.2f;
		Time.TickScale = 1 + Math.Clamp((mTargetDepth - mDepth) * 0.02f, -0.05f, 0.05f);
	}
}
