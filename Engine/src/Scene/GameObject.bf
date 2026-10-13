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
