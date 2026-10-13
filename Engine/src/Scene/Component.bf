using System;
using System.Collections;
using System.Reflection;

namespace Tessera;

/// Put [Component] on every component class. It keeps the type, its constructor and its fields
/// in the reflection data so the class can be created by name when a scene loads, listed in
/// the Add Component menu, and edited in the Inspector. Beef does not inherit attributes, so
/// each subclass needs its own.
[AttributeUsage(.Class, .AlwaysIncludeTarget | .ReflectAttribute, ReflectUser = .All, AlwaysIncludeUser = .AssumeInstantiated | .IncludeAllMethods)]
struct ComponentAttribute : Attribute
{
}

/// Save a supported private field and expose it in the Inspector.
[AttributeUsage(.Field, .ReflectAttribute)]
struct ShowInInspectorAttribute : Attribute {}

/// Keep a public field out of the Inspector (it is still saved).
[AttributeUsage(.Field, .ReflectAttribute)]
struct HideInInspectorAttribute : Attribute
{
}

/// Keep a public field out of scene files and the Inspector.
[AttributeUsage(.Field, .ReflectAttribute)]
struct NonSerializedAttribute : Attribute
{
}

/// Show a numeric field as a slider.
[AttributeUsage(.Field, .ReflectAttribute)]
struct RangeAttribute : Attribute
{
	public float min;
	public float max;

	public this(float min, float max)
	{
		this.min = min;
		this.max = max;
	}
}

/// Base class for everything attached to a GameObject.
///
/// Lifecycle while the scene is playing: Awake, OnEnable, Start (before the first Update),
/// then FixedUpdate at Time.TickRate, Update and LateUpdate per frame, and OnDisable / OnDestroy.
/// Public fields of supported types are saved with the scene and shown in the Inspector.
[Component]
abstract class Component
{
	GameObject mGameObject;
	bool mEnabled = true;
	bool mAwake;
	bool mStarted;
	bool mRegistered;

	public GameObject GameObject => mGameObject;
	public Transform Transform => mGameObject.Transform;
	public Scene Scene => mGameObject.Scene;
	public bool IsAwake => mAwake;

	public bool Enabled
	{
		get => mEnabled;
		set
		{
			if (mEnabled == value)
				return;
			mEnabled = value;
			if (mAwake && mGameObject.Scene.IsPlaying)
			{
				if (value) OnEnable(); else OnDisable();
			}
		}
	}

	/// True when this component is enabled and its object is active in the hierarchy.
	public bool IsActiveAndEnabled => mEnabled && mGameObject.ActiveInHierarchy;

	public T GetComponent<T>() where T : Component => mGameObject.GetComponent<T>();

	// ---- gameplay callbacks (play mode only) ----
	public virtual void Awake() { }
	public virtual void OnEnable() { }
	public virtual void Start() { }
	public virtual void FixedUpdate() { }
	public virtual void Update() { }
	public virtual void LateUpdate() { }
	public virtual void OnDisable() { }
	public virtual void OnDestroy() { }

	// ---- engine callbacks (edit and play mode) ----
	/// Called when the component joins a scene, including in the editor. Engine components
	/// use it to add themselves to the scene's render / physics lists.
	public virtual void OnRegister() { }
	public virtual void OnUnregister() { }
	/// Called every frame in edit and play mode (streaming, procedural generation).
	public virtual void OnFrame() { }
	/// Draw in-game interface with the GUI class. Called every frame while playing.
	public virtual void OnGUI() { }
	/// Called on every machine when SendNetworkEvent is used on this component (and at once, with no session).
	public virtual void OnNetworkEvent(StringView name, float value) { }
	/// Tells this component on every machine that something happened. Allowed from the server, or from the
	/// client that owns the object. Without a session it simply calls OnNetworkEvent here.
	public void SendNetworkEvent(StringView name, float value = 0) => NetworkSync.SendEvent(this, name, value);
	/// Called just before the scene is written to disk; save side files here.
	public virtual void OnBeforeSave() { }
	/// Writes or reads this component's [Saved] fields (SaveSystem). The compiler writes this for every component
	/// with a [Saved] field; override it, calling base, only to keep extra values by hand.
	public virtual void SaveFields(SaveIO io) { }
	/// Whether the component has [Saved] fields: written by the compiler with SaveFields.
	public virtual bool HasSavedFields => false;
	/// SaveSystem.Save is about to read this component's [Saved] fields: bring them up to date here.
	public virtual void OnSaving() { }
	/// SaveSystem.Load has just put this component's [Saved] fields back: rebuild anything made from them here.
	public virtual void OnLoaded() { }
	/// Called after a field was changed by the Inspector or the scene loader.
	public virtual void OnValidate() { }
	/// Draw editor-only helpers with DebugDraw.
	public virtual void OnDrawGizmos(bool selected) { }
}
