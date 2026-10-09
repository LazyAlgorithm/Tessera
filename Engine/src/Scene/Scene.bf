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
		mPlaying = true;
		Active = this;
		Time.Time = 0;
		Time.Tick = 0;
		for (int i = 0; i < mComponents.Count; i++)
			WakeComponent(mComponents[i]);
	}

	public void StopPlay()
	{
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
	public void Update()
	{
		Active = this;
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
