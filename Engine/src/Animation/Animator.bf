using System;
using System.Collections;
using System.IO;

namespace Tessera;

/// Plays animation clips on the bones (child objects) below this object, blending smoothly when the clip changes.
/// A bone is any descendant GameObject; clips refer to bones by name.
[Component]
class Animator : Component
{
	/// Clip files separated by semicolons, e.g. "Animations/idle.tanim;Animations/walk.tanim".
	public String clips = new .() ~ delete _;
	/// Name of the clip to start with.
	public String defaultClip = new .("Idle") ~ delete _;
	public float speed = 1.0f;
	/// An Animator Controller (.tcontroller) made in the Animator window. With one set, the Animator runs its
	/// state machine: scripts set parameters, and transitions pick the clip. Without one, scripts call Play.
	public String controller = new .() ~ delete _;

	struct Bone
	{
		public Transform transform;
		public Vector3 restPosition;
		public Quaternion restRotation;
		public Vector3 restScale;
	}

	// ---- controller state ----
	AnimatorController mController;
	int32 mControllerRevision = -1;
	List<float> mParameters = new .() ~ delete _;
	int32 mState = -1;
	float mStateTime;
	SkinnedMeshRenderer mSkinned;

	public AnimatorController Controller => mController;
	/// The state the controller is in, or "" without a controller.
	public StringView CurrentState => (mController != null && mState >= 0 && mState < mController.states.Count) ? (StringView)mController.states[mState].name : "";
	public int32 CurrentStateIndex => mState;
	/// Seconds spent in the current state, scaled by the state's speed.
	public float StateTime => mStateTime;
	/// How far through its clip the current state is: 0 at the start, 1 at the end, more than 1 once it has looped.
	public float NormalizedTime => mStateTime / Math.Max(StateLength(mState), 0.0001f);
	/// True while one state's clip is still fading into the next.
	public bool IsInTransition => mPrevious != null && mFade < mFadeDuration;

	float StateLength(int32 index)
	{
		if (mController == null || index < 0 || index >= mController.states.Count)
			return 1;
		let state = mController.states[index];
		let clip = FindClip(state.clip);
		if (clip != null)
			return clip.duration;
		if (mSkinned != null && mSkinned.Model != null)
		{
			let modelClip = mSkinned.Model.FindClip(state.clip);
			if (modelClip != null)
				return modelClip.duration;
		}
		return 1;
	}

	AnimationClip FindClip(StringView nameOrPath)
	{
		for (let clip in mClips)
			if (clip.name == nameOrPath)
				return clip;
		if (nameOrPath.EndsWith(".tanim"))
		{
			let clip = AnimationClip.Load(nameOrPath);
			if (clip != null && !mClips.Contains(clip))
				mClips.Add(clip);
			return clip;
		}
		return null;
	}

	void SyncController()
	{
		if (mController == null || mControllerRevision == mController.Revision)
			return;
		// The controller was edited (or has just been loaded): keep the values of parameters that still exist.
		mControllerRevision = mController.Revision;
		while (mParameters.Count < mController.parameters.Count)
			mParameters.Add(mController.parameters[mParameters.Count].defaultValue);
		while (mParameters.Count > mController.parameters.Count)
			mParameters.PopBack();
		if (mState >= mController.states.Count)
			mState = -1;
	}

	int32 Parameter(StringView name)
	{
		SyncController();
		return mController != null ? mController.FindParameter(name) : -1;
	}

	void SetParameter(int32 index, float value)
	{
		if (index < 0 || index >= mParameters.Count || mParameters[index] == value)
			return;
		mParameters[index] = value;
		NetworkSync.AnimatorChanged(this, 0, index, value);
	}

	/// Sets a number parameter of the controller. Unknown names are ignored. In a network session the value is
	/// shared with everyone when set on the server or by the player who owns the object.
	public void SetFloat(StringView name, float value) => SetParameter(Parameter(name), value);
	public void SetInteger(StringView name, int32 value) => SetParameter(Parameter(name), (float)value);
	public void SetBool(StringView name, bool value) => SetParameter(Parameter(name), value ? 1 : 0);
	/// Sets a trigger: it stays set until a transition uses it, then clears itself.
	public void SetTrigger(StringView name) => SetParameter(Parameter(name), 1);
	public void ResetTrigger(StringView name) => SetParameter(Parameter(name), 0);

	public float GetFloat(StringView name)
	{
		let index = Parameter(name);
		return index >= 0 && index < mParameters.Count ? mParameters[index] : 0;
	}
	public int32 GetInteger(StringView name) => (int32)Math.Round(GetFloat(name));
	public bool GetBool(StringView name) => GetFloat(name) != 0;
	/// A parameter's value by its position in the controller, for showing live values.
	public float GetParameter(int32 index) => index >= 0 && index < mParameters.Count ? mParameters[index] : 0;

	/// Applies a change that arrived from the network. kind 0: a parameter value. kind 1: enter a state.
	public void ApplyRemote(int32 kind, int32 index, float value)
	{
		SyncController();
		if (kind == 0 && index >= 0 && index < mParameters.Count)
			mParameters[index] = value;
		else if (kind == 1 && mController != null && index >= 0 && index < mController.states.Count)
			EnterState(index, Math.Clamp(value, 0, 10));
	}

	bool Holds(AnimatorController.Condition condition)
	{
		if (condition.parameter < 0 || condition.parameter >= mParameters.Count)
			return false;
		let value = mParameters[condition.parameter];
		switch (condition.mode)
		{
		case .If: return value != 0;
		case .IfNot: return value == 0;
		case .Greater: return value > condition.threshold;
		case .Less: return value < condition.threshold;
		case .Equals: return Math.Abs(value - condition.threshold) < 0.0001f;
		case .NotEqual: return Math.Abs(value - condition.threshold) >= 0.0001f;
		}
	}

	void EnterState(int32 index, float fade)
	{
		let state = mController.states[index];
		mState = index;
		mStateTime = 0;
		let clip = FindClip(state.clip);
		if (clip != null)
			StartClip(clip, fade);
		else if (mSkinned != null && mSkinned.HasClip(state.clip))
		{
			mSkinned.loop = state.loop;
			mSkinned.Play(state.clip, fade);
		}
		NetworkSync.AnimatorChanged(this, 1, index, fade);
	}

	/// Jumps to a state of the controller by name, cross-fading over the given time.
	public void CrossFade(StringView stateName, float fadeSeconds = 0.15f)
	{
		SyncController();
		let index = mController != null ? mController.FindState(stateName) : -1;
		if (index >= 0)
			EnterState(index, fadeSeconds);
	}

	void UpdateController()
	{
		SyncController();
		if (mController.states.Count == 0)
			return;
		// The machine in charge of the object decides; the others are told which state was entered.
		let decides = NetworkSync.IsMine(this);
		if (mState < 0)
		{
			if (!decides)
				return;
			EnterState(Math.Clamp(mController.defaultState, 0, (int32)mController.states.Count - 1), 0);
		}
		let state = mController.states[mState];
		mStateTime += Time.DeltaTime * speed * state.speed;
		if (mSkinned != null)
			mSkinned.speed = speed * state.speed;
		if (!decides || IsInTransition)
			return;
		let normalized = NormalizedTime;
		for (let transition in mController.transitions)
		{
			if ((transition.from != mState && transition.from != -1) || (transition.to == mState && transition.from == -1))
				continue;
			if (transition.hasExitTime && normalized < transition.exitTime)
				continue;
			// With neither a condition nor an exit time there is nothing to wait for; Unity ignores such a
			// transition, and so does this.
			if (transition.conditions.Count == 0 && !transition.hasExitTime)
				continue;
			bool all = true;
			for (let condition in transition.conditions)
				all &= Holds(condition);
			if (!all)
				continue;
			// Triggers that let the transition through are used up.
			for (let condition in transition.conditions)
			{
				if (condition.parameter < mController.parameters.Count && mController.parameters[condition.parameter].type == .Trigger)
					SetParameter(condition.parameter, 0);
			}
			EnterState(transition.to, transition.duration);
			break;
		}
	}

	List<AnimationClip> mClips = new .() ~ delete _;
	List<Bone> mBones = new .() ~ delete _;
	AnimationClip mCurrent;
	AnimationClip mPrevious;
	float mTime;
	float mPreviousTime;
	float mFade;
	float mFadeDuration;

	public StringView CurrentClip => mCurrent != null ? (StringView)mCurrent.name : "";
	/// True once a non-looping clip has reached its end.
	public bool IsFinished => mCurrent != null && !mCurrent.loop && mTime >= mCurrent.duration;

	public override void Start()
	{
		Bind();
		if (mController == null)
			Play(defaultClip, 0);
	}

	/// Collects the bones and remembers their rest pose. Call again after changing the hierarchy.
	public void Bind()
	{
		mClips.Clear();
		for (var path in clips.Split(';'))
		{
			path.Trim();
			if (path.IsEmpty)
				continue;
			let clip = AnimationClip.Load(path);
			if (clip != null)
				mClips.Add(clip);
		}
		mBones.Clear();
		Collect(Transform);
		mSkinned = GetComponent<SkinnedMeshRenderer>();
		if (mSkinned == null)
		{
			for (let child in Transform.Children)
			{
				mSkinned = child.GameObject.GetComponent<SkinnedMeshRenderer>();
				if (mSkinned != null)
					break;
			}
		}
		mController = AnimatorController.Load(controller);
		mControllerRevision = -1;
		mParameters.Clear();
		mState = -1;
		SyncController();
	}

	void Collect(Transform parent)
	{
		for (let child in parent.Children)
		{
			Bone bone;
			bone.transform = child;
			bone.restPosition = child.LocalPosition;
			bone.restRotation = child.LocalRotation;
			bone.restScale = child.LocalScale;
			mBones.Add(bone);
			Collect(child);
		}
	}

	public bool HasClip(StringView name)
	{
		for (let clip in mClips)
		{
			if (clip.name == name)
				return true;
		}
		return false;
	}

	/// Switches to a clip, cross-fading from the current pose over fadeSeconds. Does nothing if it is already playing.
	public void Play(StringView name, float fadeSeconds = 0.15f)
	{
		// With a controller, the name is a state's.
		if (mController != null)
		{
			if (CurrentState != name)
				CrossFade(name, fadeSeconds);
			return;
		}
		if (mCurrent != null && mCurrent.name == name)
			return;
		for (let clip in mClips)
		{
			if (clip.name != name)
				continue;
			StartClip(clip, fadeSeconds);
			// In multiplayer a clip started by the server, or by the player who controls this object, plays everywhere.
			NetworkSync.AnimationPlayed(this, name, fadeSeconds);
			return;
		}
	}

	void StartClip(AnimationClip clip, float fadeSeconds)
	{
		if (mCurrent == clip)
		{
			mTime = 0;
			return;
		}
		mPrevious = mCurrent;
		mPreviousTime = mTime;
		mCurrent = clip;
		mTime = 0;
		mFadeDuration = mPrevious != null ? fadeSeconds : 0;
		mFade = 0;
	}

	/// Poses the object from a clip at a time, without playing. The Animation window uses it to scrub.
	public void SampleClip(AnimationClip clip, float time)
	{
		if (mBones.Count == 0)
			Collect(Transform);
		for (let bone in mBones)
		{
			if (bone.transform.GameObject.IsDestroyed)
				continue;
			let track = clip.FindTrack(bone.transform.GameObject.Name);
			Vector3 position = .Zero, scale = .(1, 1, 1);
			Quaternion rotation = .Identity;
			if (track != null)
				track.Sample(time, out position, out rotation, out scale);
			bone.transform.LocalPosition = bone.restPosition + position;
			bone.transform.LocalRotation = (bone.restRotation * rotation).Normalized;
			bone.transform.LocalScale = .(bone.restScale.x * scale.x, bone.restScale.y * scale.y, bone.restScale.z * scale.z);
		}
	}

	/// The pose a child had before any animation moved it, which keys are measured from.
	public bool RestPose(Transform child, out Vector3 position, out Quaternion rotation, out Vector3 scale)
	{
		position = .Zero; rotation = .Identity; scale = .(1, 1, 1);
		if (mBones.Count == 0)
			Collect(Transform);
		for (let bone in mBones)
		{
			if (bone.transform == child)
			{
				position = bone.restPosition; rotation = bone.restRotation; scale = bone.restScale;
				return true;
			}
		}
		return false;
	}

	float Wrap(AnimationClip clip, float time)
	{
		// A controller's state says whether its clip loops; otherwise the clip does.
		let loops = (mController != null && clip == mCurrent && mState >= 0 && mState < mController.states.Count) ? mController.states[mState].loop : clip.loop;
		if (loops)
			return time % clip.duration;
		return Math.Min(time, clip.duration);
	}

	public override void Update()
	{
		if (mController != null)
			UpdateController();
		if (mCurrent == null)
			return;
		let step = Time.DeltaTime * speed * ((mController != null && mState >= 0 && mState < mController.states.Count) ? mController.states[mState].speed : 1);
		mTime += step;
		mPreviousTime += step;
		mFade += Time.DeltaTime;
		let blending = mPrevious != null && mFade < mFadeDuration;
		let weight = blending ? Mathf.SmoothStep(0, 1, mFade / mFadeDuration) : 1.0f;
		let time = Wrap(mCurrent, mTime);
		let previousTime = blending ? Wrap(mPrevious, mPreviousTime) : 0;

		for (let bone in mBones)
		{
			if (bone.transform.GameObject.IsDestroyed)
				continue;
			let name = bone.transform.GameObject.Name;
			Vector3 position = .Zero, scale = .(1, 1, 1);
			Quaternion rotation = .Identity;
			let track = mCurrent.FindTrack(name);
			if (track != null)
				track.Sample(time, out position, out rotation, out scale);
			if (blending)
			{
				Vector3 fromPosition = .Zero, fromScale = .(1, 1, 1);
				Quaternion fromRotation = .Identity;
				let fromTrack = mPrevious.FindTrack(name);
				if (fromTrack != null)
					fromTrack.Sample(previousTime, out fromPosition, out fromRotation, out fromScale);
				scale = Vector3.Lerp(fromScale, scale, weight);
				position = Vector3.Lerp(fromPosition, position, weight);
				rotation = Quaternion.Slerp(fromRotation, rotation, weight);
			}
			else if (track == null)
			{
				// Bones this clip does not animate stay in (and return to) their rest pose.
				if (bone.transform.LocalRotation.x == bone.restRotation.x && bone.transform.LocalRotation.w == bone.restRotation.w && bone.transform.LocalPosition == bone.restPosition)
					continue;
			}
			bone.transform.LocalPosition = bone.restPosition + position;
			bone.transform.LocalRotation = (bone.restRotation * rotation).Normalized;
			if (track != null)
				bone.transform.LocalScale = .(bone.restScale.x * scale.x, bone.restScale.y * scale.y, bone.restScale.z * scale.z);
		}
	}
}
