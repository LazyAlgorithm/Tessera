using System;
using System.Collections;

namespace Tessera;

/// Environment settings saved with a scene: ambient light, sky and fog.
class SceneEnvironment
{
	public Color skyZenith = .(0.16f, 0.36f, 0.72f);
	public Color skyHorizon = .(0.62f, 0.76f, 0.90f);
	public Color skyGround = .(0.28f, 0.27f, 0.26f);
	public Color ambientSky = .(0.42f, 0.50f, 0.62f);
	public Color ambientGround = .(0.22f, 0.20f, 0.18f);
	public float ambientIntensity = 0.55f;
	public Color fogColor = .(0.62f, 0.76f, 0.90f);
	public float fogDensity = 0.004f;
	public float exposure = 1.0f;
	/// Glow around bright things (lights, emissive surfaces, the sun on pale walls). 0 is off; 0.3 to 0.6 is
	/// gentle; above 1 is heavy.
	public float bloom = 0.0f;
	/// How bright something must be before it glows. 1 is the brightest a surface gets from light alone, so at 1
	/// only emissive and over-bright things bloom.
	public float bloomThreshold = 1.0f;
	public float shadowDistance = 120.0f;

	// ---- Screen effects (docs/post-processing.md). All off by default; colour grading's defaults leave the picture
	// as it always was. ----

	/// Ambient occlusion: darkens creases, corners and where things meet the ground. 0 is off; 1 is normal; up to 2.
	public float ambientOcclusion = 0;
	/// How far around each point, in metres, is looked at for what hides it from the open air.
	public float occlusionRadius = 0.6f;

	/// Depth of field: blurs what is nearer or further than the focus. 0 is off; 1 is the largest blur, a circle 3% of
	/// the screen's height across (its radius is DepthOfFieldReach); up to 2.
	public float depthOfField = 0;
	/// The distance, in metres from the camera, that is sharp.
	public float focusDistance = 10;
	/// How deep the sharp band around the focus is, in metres: sharp within half of it either side, fully blurred a
	/// whole range beyond that.
	public float focusRange = 8;
	/// Focus on whatever is in the middle of the screen instead of Focus Distance.
	public bool autoFocus;

	/// Camera motion blur: a smear along the way the picture moves when the camera turns or moves. 0 is off; 0.5 is
	/// like a film camera; 1 is the whole movement of a frame. The viewmodel is never blurred.
	public float motionBlur = 0;

	/// Colour grading, applied with the tonemapping. Contrast and saturation: 1 leaves the picture alone.
	public float contrast = 1;
	public float saturation = 1.05f;
	/// White balance: above 0 warmer (more orange), below 0 cooler (more blue). -1 to 1.
	public float temperature = 0;
	/// Above 0 towards magenta, below 0 towards green. -1 to 1.
	public float tint = 0;
	/// Multiplies the light of the whole picture: a coloured filter on the lens.
	public Color colorFilter = .(1, 1, 1);
	/// Darkening towards the corners.
	public float vignette = 0.35f;
	/// A colour lookup table image (a strip of squares, made with the editor's Make Neutral Lookup Table and
	/// recoloured in any image editor), or empty for none.
	public String colorLookup = new .() ~ delete _;
	/// How much of the lookup table is used: 0 none, 1 all of it.
	public float colorLookupStrength = 1;

	/// The radius of the depth of field's largest blur as a share of the screen's height, at Depth Of Field 1.
	public const float DepthOfFieldReach = 0.015f;

	/// Whether the scene needs the depth pass (ambient occlusion, depth of field or motion blur).
	public bool UsesDepthEffects => ambientOcclusion > 0.001f || depthOfField > 0.001f || motionBlur > 0.001f;

	/// How blurred something at `depth` metres is, 0 (sharp) to 1, with the focus at `focus` metres: the shader's sum.
	public float BlurAmount(float depth, float focus)
	{
		if (depth < 0)
			return 0;
		let range = Math.Max(focusRange, 0.01f);
		return Math.Clamp((Math.Abs(depth - focus) - range * 0.5f) / range, 0.0f, 1.0f);
	}

	/// Puts every setting back to how a new scene has it.
	public void Reset()
	{
		let fresh = scope SceneEnvironment();
		CopyFrom(fresh);
	}

	public void CopyFrom(SceneEnvironment other)
	{
		skyZenith = other.skyZenith; skyHorizon = other.skyHorizon; skyGround = other.skyGround;
		ambientSky = other.ambientSky; ambientGround = other.ambientGround; ambientIntensity = other.ambientIntensity;
		fogColor = other.fogColor; fogDensity = other.fogDensity; exposure = other.exposure;
		bloom = other.bloom; bloomThreshold = other.bloomThreshold; shadowDistance = other.shadowDistance;
		ambientOcclusion = other.ambientOcclusion; occlusionRadius = other.occlusionRadius;
		depthOfField = other.depthOfField; focusDistance = other.focusDistance; focusRange = other.focusRange; autoFocus = other.autoFocus;
		motionBlur = other.motionBlur;
		contrast = other.contrast; saturation = other.saturation; temperature = other.temperature; tint = other.tint;
		colorFilter = other.colorFilter; vignette = other.vignette;
		colorLookup.Set(other.colorLookup); colorLookupStrength = other.colorLookupStrength;
	}
}

/// A hierarchy of GameObjects plus the per-scene systems (rendering lists, physics).
class Scene
{
	public String Name = new .("Untitled") ~ delete _;
	public String Path = new .() ~ delete _;
	public SceneEnvironment Environment = new .() ~ delete _;

	List<GameObject> mRoots = new .() ~ delete _;
	List<GameObject> mObjects = new .() ~ delete _;
	Dictionary<uint32, GameObject> mById = new .() ~ delete _;
	List<Component> mComponents = new .() ~ delete _;
	List<Component> mPendingStart = new .() ~ delete _;
	List<GameObject> mDestroyQueue = new .() ~ delete _;
	uint32 mNextId = 1;
	bool mPlaying;

	// Non-owning lists maintained by the components themselves in OnRegister / OnUnregister.
	public List<MeshRenderer> Renderers = new .() ~ delete _;
	public List<Light> Lights = new .() ~ delete _;
	public List<Camera> Cameras = new .() ~ delete _;
	public List<ParticleSystem> Particles = new .() ~ delete _;

	public PhysicsWorld Physics ~ delete _;
	/// Set while a multiplayer session is running (see NetworkManager).
	public NetworkManager Network ~ delete _;

	/// The scene gameplay code is running in.
	public static Scene Active;
	/// Seconds since the current spawn start phase began, and whether it was closed early. See SpawnPoints.
	public float SpawnPhaseTime;
	public bool SpawnStartOver;

	Dictionary<String, List<GameObject>> mTagged = new .() ~ { for (let entry in _) { delete entry.key; delete entry.value; } delete _; };
	int32 mWorldState;

	/// Called when the active world state changes, with the state before and the state now.
	public Event<delegate void(int32 from, int32 to)> WorldStateChanged ~ _.Dispose();

	/// The active world state (an index into ProjectConfig.WorldStates). Objects that are not part of it are not
	/// drawn, do not collide, are not heard and are not walked on. Setting it switches all of that in one go.
	public int32 WorldState
	{
		get => mWorldState;
		set
		{
			let state = Math.Clamp(value, 0, ProjectConfig.MaxWorldStates - 1);
			if (state == mWorldState)
				return;
			let previous = mWorldState;
			mWorldState = state;
			Physics.ApplyWorldState(this);
			WorldStateChanged(previous, state);
		}
	}

	/// The same by name; false when the project has no world state of that name.
	public bool SetWorldState(StringView name)
	{
		let state = ProjectConfig.WorldStateNamed(name);
		if (state < 0)
			return false;
		WorldState = state;
		return true;
	}

	void WorldMembershipChanged(GameObject gameObject)
	{
		Physics.ApplyWorldState(gameObject);
	}

	void IndexTag(GameObject gameObject, StringView tag, bool add)
	{
		if (add)
		{
			List<GameObject> list;
			if (!mTagged.TryGetValueAlt(tag, out list))
			{
				list = new .();
				mTagged[new String(tag)] = list;
			}
			list.Add(gameObject);
		}
		else if (mTagged.TryGetValueAlt(tag, let list))
			list.Remove(gameObject);
	}

	/// The first object with that tag that is active, or null. Fast: tagged objects are kept in lists by tag.
	public GameObject FindWithTag(StringView tag)
	{
		if (mTagged.TryGetValueAlt(tag, let list))
		{
			for (let gameObject in list)
			{
				if (!gameObject.IsDestroyed && gameObject.ActiveInHierarchy)
					return gameObject;
			}
		}
		return null;
	}

	/// Adds every object with that tag (active or not) to the list.
	public void FindAllWithTag(StringView tag, List<GameObject> found)
	{
		if (mTagged.TryGetValueAlt(tag, let list))
		{
			for (let gameObject in list)
			{
				if (!gameObject.IsDestroyed)
					found.Add(gameObject);
			}
		}
	}

	public List<GameObject> Roots => mRoots;
	public List<GameObject> Objects => mObjects;
	public List<Component> Components => mComponents;
	public bool IsPlaying => mPlaying;

	public this()
	{
		Physics = new PhysicsWorld();
	}

	public ~this()
	{
		if (Active == this)
			Active = null;
		Network?.Stop();
		Clear();
		if (Active == this)
			Active = null;
	}

	/// Removes every object. Components are unregistered without gameplay callbacks.
	public void Clear()
	{
		while (mRoots.Count > 0)
			DestroyImmediate(mRoots.Back);
		mDestroyQueue.Clear();
		mPendingStart.Clear();
		mNextId = 1;
	}

	public GameObject CreateGameObject(StringView name, Transform parent = null)
	{
		return CreateGameObjectWithId(name, 0, parent);
	}

	public GameObject CreateGameObjectWithId(StringView name, uint32 id, Transform parent = null)
	{
		let gameObject = new GameObject(name);
		var useId = id;
		if (useId == 0 || mById.ContainsKey(useId))
			useId = mNextId;
		mNextId = Math.Max(mNextId, useId + 1);
		gameObject.Id = useId;
		gameObject.[Friend]mScene = this;
		mObjects.Add(gameObject);
		mById[useId] = gameObject;
		mRoots.Add(gameObject);
		if (parent != null)
			gameObject.Transform.SetParent(parent, false);
		return gameObject;
	}

	public GameObject FindById(uint32 id)
	{
		if (mById.TryGetValue(id, let gameObject))
			return gameObject;
		return null;
	}

	public GameObject Find(StringView name)
	{
		for (let gameObject in mObjects)
		{
			if (gameObject.Name == name)
				return gameObject;
		}
		return null;
	}

	public T FindComponent<T>() where T : Component
	{
		for (let component in mComponents)
		{
			if (let typed = component as T)
				return typed;
		}
		return null;
	}

	/// Queues an object (and its children) for destruction at the end of the frame.
	public void Destroy(GameObject gameObject)
	{
		if (gameObject == null || gameObject.IsDestroyed)
			return;
		// In multiplayer the server decides what happens to shared objects, and tells the clients.
		if (Network != null && !Network.AllowDestroy(gameObject))
			return;
		gameObject.[Friend]mDestroyed = true;
		mDestroyQueue.Add(gameObject);
	}

	/// Destroys an object right now. Prefer Destroy from gameplay code.
	public void DestroyImmediate(GameObject gameObject)
	{
		// Clear non-owning references before freeing their targets.
		List<FieldRef> referenceFields = scope .();
		for (let component in mComponents)
		{
			referenceFields.Clear();
			ComponentRegistry.GetFields(component, referenceFields);
			for (let field in referenceFields)
				if (field.kind == .ObjectReference && ComponentRegistry.ReferenceOwner(field) == gameObject)
					ComponentRegistry.AssignReference(field, null);
		}
		let transform = gameObject.Transform;
		while (transform.Children.Count > 0)
			DestroyImmediate(transform.Children.Back.GameObject);

		for (int i = gameObject.Components.Count - 1; i >= 0; i--)
			UnregisterComponent(gameObject.Components[i]);

		if (transform.Parent != null)
			transform.Parent.Children.Remove(transform);
		else
			mRoots.Remove(gameObject);
		mObjects.Remove(gameObject);
		mById.Remove(gameObject.Id);
		mDestroyQueue.Remove(gameObject);
		for (int i < gameObject.TagCount)
			IndexTag(gameObject, gameObject.GetTag(i), false);
		delete gameObject;
	}

	void RegisterComponent(Component component)
	{
		if (component.[Friend]mRegistered)
			return;
		component.[Friend]mRegistered = true;
		mComponents.Add(component);
		component.OnRegister();
		if (mPlaying)
			WakeComponent(component);
	}

	void UnregisterComponent(Component component)
	{
		if (!component.[Friend]mRegistered)
			return;
		if (mPlaying && component.IsAwake)
		{
			if (component.Enabled)
				component.OnDisable();
			component.OnDestroy();
		}
		List<FieldRef> referenceFields = scope .();
		for (let owner in mComponents)
		{
			referenceFields.Clear(); ComponentRegistry.GetFields(owner, referenceFields);
			for (let field in referenceFields)
				if (field.kind == .ObjectReference && *(Object*)field.ptr == component)
					ComponentRegistry.AssignReference(field, null);
		}
		component.OnUnregister();
		component.[Friend]mRegistered = false;
		component.[Friend]mAwake = false;
		mComponents.Remove(component);
		mPendingStart.Remove(component);
	}

	void WakeComponent(Component component)
	{
		if (component.IsAwake)
			return;
		component.[Friend]mAwake = true;
		component.Awake();
		if (component.Enabled)
			component.OnEnable();
		mPendingStart.Add(component);
	}

	/// Enters play mode: every component receives Awake / OnEnable, then Start before its first update.
	public void StartPlay()
	{
		if (mPlaying)
			return;
		// A save to load at start that is still on its way holds the scene back (Update asks again).
		mStartHeld = SaveSystem.HoldStart(this);
		if (mStartHeld)
			return;
		SaveSystem.SceneStarting(this);
		mPlaying = true;
		Active = this;
		Time.Time = 0;
		Time.Tick = 0;
		for (int i = 0; i < mComponents.Count; i++)
			WakeComponent(mComponents[i]);
	}

	public void StopPlay()
	{
		mStartHeld = false;
		if (!mPlaying)
			return;
		// A game that locked the mouse does not keep it once it has stopped.
		Input.LockCursor = false;
		for (int i = mComponents.Count - 1; i >= 0; i--)
		{
			if (i >= mComponents.Count)
				continue;
			let component = mComponents[i];
			if (!component.IsAwake)
				continue;
			if (component.Enabled)
				component.OnDisable();
			component.OnDestroy();
			component.[Friend]mAwake = false;
			component.[Friend]mStarted = false;
		}
		mPendingStart.Clear();
		mPlaying = false;
	}

	void RunPendingStarts()
	{
		while (mPendingStart.Count > 0)
		{
			let component = mPendingStart[0];
			mPendingStart.RemoveAt(0);
			if (!component.[Friend]mStarted && component.IsActiveAndEnabled)
			{
				component.[Friend]mStarted = true;
				component.Start();
			}
			else if (!component.[Friend]mStarted)
			{
				// Still disabled: retry next frame without spinning here.
				mDeferredStart.Add(component);
			}
		}
		for (let component in mDeferredStart)
			mPendingStart.Add(component);
		mDeferredStart.Clear();
	}

	List<Component> mDeferredStart = new .() ~ delete _;

	/// One fixed simulation tick: gameplay FixedUpdate, then physics.
	public void FixedUpdate()
	{
		if (!mPlaying)
			return;
		Active = this;
		SpawnPhaseTime += Time.FixedDeltaTime;
		RunPendingStarts();
		Network?.PreTick();
		for (int i = 0; i < mComponents.Count; i++)
		{
			let component = mComponents[i];
			if (component.[Friend]mStarted && component.IsActiveAndEnabled)
				{ Watchdog.Running = component; component.FixedUpdate(); Watchdog.Running = null; }
		}
		Physics.Step(Time.FixedDeltaTime);
		Network?.PostTick();
		Time.Tick++;
	}

	/// Per-frame update. In edit mode only the destroy queue is processed.
	bool mStartHeld;
	/// Waiting for a save before play starts (SaveSystem.LoadAtStart with a storage that answers later).
	public bool StartHeld => mStartHeld;

	public void Update()
	{
		Active = this;
		if (mStartHeld)
			StartPlay();
		for (int i = 0; i < mComponents.Count; i++)
		{
			let component = mComponents[i];
			if (component.IsActiveAndEnabled)
				{ Watchdog.Running = component; component.OnFrame(); Watchdog.Running = null; }
		}
		VoiceChat.Update(this);
		Audio.Update(this);
		if (mPlaying)
		{
			RunPendingStarts();
			for (int i = 0; i < mComponents.Count; i++)
			{
				let component = mComponents[i];
				if (component.[Friend]mStarted && component.IsActiveAndEnabled)
					{ Watchdog.Running = component; component.Update(); Watchdog.Running = null; }
			}
			for (int i = 0; i < mComponents.Count; i++)
			{
				let component = mComponents[i];
				if (component.[Friend]mStarted && component.IsActiveAndEnabled)
					{ Watchdog.Running = component; component.LateUpdate(); Watchdog.Running = null; }
			}
		}
		while (mDestroyQueue.Count > 0)
		{
			let gameObject = mDestroyQueue.PopBack();
			DestroyImmediate(gameObject);
		}
	}
}
