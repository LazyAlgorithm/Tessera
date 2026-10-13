using System;
using System.Collections;

namespace Tessera;

/// An entity in a scene: a named Transform with a list of components.
class GameObject
{
	public String Name = new .() ~ delete _;
	public uint32 Id;
	public Transform Transform ~ delete _;
	public List<Component> Components = new .() ~ delete _;
	/// An organisational folder in the Hierarchy: it only groups objects. Its transform stays at
	/// identity so it never moves its children, and it carries no components.
	public bool IsFolder;
	/// Generated at runtime (voxel chunks, pooled effects): not saved with the scene and hidden in the Hierarchy.
	public bool Transient;
	/// What this object was made from while the game ran: a prefab file, or the name of a registered network prefab.
	/// Empty for objects that came with the scene. SaveSystem uses it to make the object again on loading.
	public String SpawnedFrom ~ delete _;

	Scene mScene;
	bool mActive = true;
	bool mDestroyed;
	int32 mLayer;
	List<String> mTags ~ DeleteContainerAndItems!(_);
	uint32 mWorldStates = uint32.MaxValue;

	/// The physics layer (named in Project Settings, 0 to 31): which other layers this object's colliders, rigid
	/// body and character controller collide with, and which ray and shape queries see it. 0 is "Default".
	public int32 Layer
	{
		get => mLayer;
		set
		{
			let layer = Math.Clamp(value, 0, ProjectConfig.MaxLayers - 1);
			if (layer == mLayer)
				return;
			mLayer = layer;
			mScene?.Physics.RefreshLayer(this);
		}
	}

	/// The world states this object is part of, one bit per state in Project Settings (all of them by default).
	/// Outside the scene's active world state it is not drawn, does not collide, is not heard and is not walked on.
	public uint32 WorldStates
	{
		get => mWorldStates;
		set
		{
			if (value == mWorldStates)
				return;
			mWorldStates = value;
			mScene?.[Friend]WorldMembershipChanged(this);
		}
	}

	/// True when the object is part of that world state.
	public bool InWorldState(int32 state) => state >= 0 && state < 32 && (mWorldStates & (1u << state)) != 0;

	/// Puts the object in or takes it out of one world state.
	public void SetInWorldState(int32 state, bool member)
	{
		if (state < 0 || state >= 32)
			return;
		WorldStates = member ? (mWorldStates | (1u << state)) : (mWorldStates & ~(1u << state));
	}

	/// The world states the object is really in: its own, less any that an object above it is left out of.
	public uint32 EffectiveWorldStates
	{
		get
		{
			var mask = mWorldStates;
			var transform = Transform?.Parent;
			while (transform != null && mask != 0)
			{
				mask &= transform.GameObject.mWorldStates;
				transform = transform.Parent;
			}
			return mask;
		}
	}

	/// True when the object, and every object above it, is part of the scene's active world state: a parent left
	/// out of a state takes its children out with it.
	public bool InActiveWorld => mScene == null || (EffectiveWorldStates & (1u << mScene.WorldState)) != 0;

	// ---- tags ----

	/// How many tags the object has, and each in turn.
	public int TagCount => mTags != null ? mTags.Count : 0;
	public StringView GetTag(int index) => mTags[index];

	public bool HasTag(StringView tag)
	{
		if (mTags == null)
			return false;
		for (let t in mTags)
		{
			if (t == tag)
				return true;
		}
		return false;
	}

	/// Gives the object a tag (any text; the editor offers the tags listed in Project Settings). Scene.FindWithTag
	/// and FindAllWithTag find tagged objects without looking at every object.
	public void AddTag(StringView tag)
	{
		if (tag.IsEmpty || HasTag(tag))
			return;
		if (mTags == null)
			mTags = new .();
		mTags.Add(new .(tag));
		mScene?.[Friend]IndexTag(this, tag, true);
	}

	public void RemoveTag(StringView tag)
	{
		if (mTags == null)
			return;
		for (int i < mTags.Count)
		{
			if (mTags[i] == tag)
			{
				mScene?.[Friend]IndexTag(this, tag, false);
				delete mTags[i];
				mTags.RemoveAt(i);
				return;
			}
		}
	}

	public this(StringView name)
	{
		Name.Set(name);
		Transform = new Transform(this);
	}

	public ~this()
	{
		for (let component in Components)
			delete component;
	}

	public Scene Scene => mScene;
	public bool ActiveSelf => mActive;
	public bool IsDestroyed => mDestroyed;

	public bool ActiveInHierarchy
	{
		get
		{
			var t = Transform;
			while (t != null)
			{
				if (!t.GameObject.mActive)
					return false;
				t = t.Parent;
			}
			return true;
		}
	}

	/// Activates or deactivates this object and everything under it. While playing, components
	/// receive OnDisable / OnEnable, so for example a deactivated Rigidbody leaves the simulation.
	public void SetActive(bool active)
	{
		if (mActive == active)
			return;
		let wasActive = ActiveInHierarchy;
		mActive = active;
		let isActive = ActiveInHierarchy;
		if (wasActive != isActive && mScene != null && mScene.IsPlaying)
			NotifyActiveChanged(isActive);
	}

	void NotifyActiveChanged(bool active)
	{
		for (int i = 0; i < Components.Count; i++)
		{
			let component = Components[i];
			if (!component.IsAwake || !component.Enabled)
				continue;
			if (active) component.OnEnable(); else component.OnDisable();
		}
		for (let child in Transform.Children)
		{
			// Children that are switched off themselves were already disabled.
			if (child.GameObject.mActive)
				child.GameObject.NotifyActiveChanged(active);
		}
	}

	public T AddComponent<T>() where T : Component
	{
		return (T)AddComponent(typeof(T));
	}

	public Component AddComponent(Type type)
	{
		let component = ComponentRegistry.Create(type);
		if (component == null)
		{
			Log.Error(scope $"Cannot create component {type}. Is the class marked with [Component]?");
			return null;
		}
		AttachComponent(component);
		return component;
	}

	void AttachComponent(Component component)
	{
		component.[Friend]mGameObject = this;
		Components.Add(component);
		if (mScene != null)
			mScene.[Friend]RegisterComponent(component);
	}

	public T GetComponent<T>() where T : Component
	{
		for (let component in Components)
		{
			if (let typed = component as T)
				return typed;
		}
		return null;
	}

	public T GetComponentInChildren<T>() where T : Component
	{
		let own = GetComponent<T>();
		if (own != null)
			return own;
		for (let child in Transform.Children)
		{
			let found = child.GameObject.GetComponentInChildren<T>();
			if (found != null)
				return found;
		}
		return null;
	}

	public void RemoveComponent(Component component)
	{
		if (!Components.Remove(component))
			return;
		if (mScene != null)
			mScene.[Friend]UnregisterComponent(component);
		delete component;
	}
}
