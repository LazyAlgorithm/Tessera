using System;
using System.Collections;

namespace Tessera;

/// Looking back in time: lag compensation for the server's hit checks, smoothing other players' objects between snapshots, and correcting this machine's own predictions.
extension NetworkManager
{
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
			JumpToServer(ackTick, owned);
			return;
		}

		// Until the server has consumed one of our inputs there is nothing to compare against: adopt its state.
		let comparable = ackTick > 0 && mTick - ackTick < NetworkIdentity.HistorySize;
		float worst = 0;
		if (comparable)
		{
			worst = PredictionError(ackTick, owned);
			mStatOwnWorst = Math.Max(mStatOwnWorst, worst);
			PendingInputs = (int32)(mTick - ackTick);
			if (worst <= CorrectionThreshold)
			{
				// Nothing moved: leave any easing already under way alone.
				before.Clear();
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
		ReplayInputs(ackTick, owned);
	}

	/// The server has got ahead of this machine, which must have stopped for a moment. Takes its state and jumps the
	/// clock forward to where it should be, rather than limp along behind.
	void JumpToServer(uint32 ackTick, List<(NetworkIdentity identity, BodyState state)> owned)
	{
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
	}

	/// How far the prediction for a tick was from what the server says: the largest of the position error, the
	/// rotation error and a changed prediction state, over every owned object.
	float PredictionError(uint32 ackTick, List<(NetworkIdentity identity, BodyState state)> owned)
	{
		float worst = 0;
		for (let entry in owned)
		{
			let predicted = entry.identity.History[ackTick % NetworkIdentity.HistorySize];
			if (predicted.prediction0.w != entry.state.prediction0.w)
				worst = Math.Max(worst, 1);
			worst = Math.Max(worst, (predicted.position - entry.state.position).Length);
			worst = Math.Max(worst, (1.0f - Mathf.Abs(Quaternion.Dot(predicted.rotation, entry.state.rotation))) * 2.0f);
		}
		return worst;
	}

	/// Replays every input the server has not acknowledged yet on top of the corrected state.
	void ReplayInputs(uint32 ackTick, List<(NetworkIdentity identity, BodyState state)> owned)
	{
		// Objects moved by the physics engine need it stepped as well. That moves every other body too, so those
		// are put back afterwards: where they are is the server's business.
		List<(NetworkIdentity identity, BodyState state)> others = scope .();
		bool stepPhysics = AnyHasBody(owned);
		if (stepPhysics)
			CaptureOtherBodies(others);

		Replaying = true;
		defer
		{
			Replaying = false;
		}
		for (uint32 tick = ackTick + 1; tick <= mTick; tick++)
		{
			SimulateOwned(LocalClientId, mInputs[tick % InputHistory]);
			// A replayed contact can hand a transform motor to a body during this tick.
			if (!stepPhysics && AnyHasBody(owned))
			{
				stepPhysics = true;
				CaptureOtherBodies(others);
			}
			if (stepPhysics)
				mScene.Physics.Step(Time.FixedDeltaTime);
			for (let entry in owned)
				entry.identity.History[tick % NetworkIdentity.HistorySize] = entry.identity.CaptureState();
		}
		for (let entry in others)
			entry.identity.ApplyState(entry.state);
	}

	static bool AnyHasBody(List<(NetworkIdentity identity, BodyState state)> owned)
	{
		for (let entry in owned)
		{
			if (entry.identity.GetComponent<Rigidbody>()?.HasBody == true)
				return true;
		}
		return false;
	}

	/// The state of every physics body this machine does not own, to put back after a replay.
	void CaptureOtherBodies(List<(NetworkIdentity identity, BodyState state)> others)
	{
		for (let identity in mIdentities)
		{
			if (identity.ownerId != LocalClientId && identity.GetComponent<Rigidbody>()?.HasBody == true)
				others.Add((identity, identity.CaptureState()));
		}
	}
}
