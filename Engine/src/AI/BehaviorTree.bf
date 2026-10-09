using System;
using System.Collections;
using System.IO;

namespace Tessera;

enum BTStatus : int32
{
	/// Not run yet, or stopped before it finished.
	Idle,
	Running,
	Success,
	Failure
}

enum BTKind
{
	/// Where the tree starts; one child.
	Root,
	/// Runs several children in an order it decides.
	Composite,
	/// Changes the result or timing of one child.
	Decorator,
	/// Does something; may take many ticks.
	Action,
	/// Answers a question at once.
	Condition
}

enum BTParamType { Number, Bool, Text, Vector }

struct BTParam
{
	public String name;
	public BTParamType type;
	public String fallback;
}

/// A kind of behaviour tree node: what it is called, the settings it takes and how to make one.
class BTNodeDef
{
	public delegate BTNode Factory();

	public String key = new .() ~ delete _;
	public String title = new .() ~ delete _;
	public String category = new .() ~ delete _;
	public String description = new .() ~ delete _;
	public BTKind kind;
	public List<BTParam> parameters = new .() ~ { for (let p in _) { delete p.name; delete p.fallback; } delete _; };
	public Factory create ~ delete _;

	/// How many children a node of this kind may have.
	public int MaxChildren => kind == .Composite ? int.MaxValue : ((kind == .Decorator || kind == .Root) ? 1 : 0);

	public BTNodeDef With(StringView name, BTParamType type, StringView fallback)
	{
		BTParam p;
		p.name = new String(name);
		p.type = type;
		p.fallback = new String(fallback);
		parameters.Add(p);
		return this;
	}

	public BTNodeDef Describe(StringView text)
	{
		description.Set(text);
		return this;
	}
}

/// One node as stored in a .tbt file and shown in the editor.
class BTNodeData
{
	public int32 id;
	public BTNodeDef def;
	public Vector2 position;
	/// One value per parameter of the definition, written the way the editor shows it.
	public List<String> values = new .() ~ DeleteContainerAndItems!(_);
}

struct BTLink
{
	public int32 parent;
	public int32 child;
}

/// A behaviour tree asset (.tbt): nodes and the parent-to-child links between them. Children run left to right,
/// in the order they are laid out on the canvas.
class BehaviorTreeData
{
	public String name = new .("NewTree") ~ delete _;
	public List<BTNodeData> nodes = new .() ~ DeleteContainerAndItems!(_);
	public List<BTLink> links = new .() ~ delete _;
	int32 mNextId = 1;

	public BTNodeData Find(int32 id)
	{
		for (let node in nodes)
		{
			if (node.id == id)
				return node;
		}
		return null;
	}

	public BTNodeData Root
	{
		get
		{
			for (let node in nodes)
			{
				if (node.def.kind == .Root)
					return node;
			}
			return null;
		}
	}

	public BTNodeData AddNode(BTNodeDef def, Vector2 position, int32 id = 0)
	{
		let node = new BTNodeData();
		node.id = id > 0 ? id : mNextId;
		mNextId = Math.Max(mNextId, node.id) + 1;
		node.def = def;
		node.position = position;
		for (let p in def.parameters)
			node.values.Add(new String(p.fallback));
		nodes.Add(node);
		return node;
	}

	public void RemoveNode(BTNodeData node)
	{
		for (int i = links.Count - 1; i >= 0; i--)
		{
			if (links[i].parent == node.id || links[i].child == node.id)
				links.RemoveAt(i);
		}
		nodes.Remove(node);
		delete node;
	}

	public int32 ParentOf(int32 child)
	{
		for (let link in links)
		{
			if (link.child == child)
				return link.parent;
		}
		return 0;
	}

	/// Ids of a node's children from left to right.
	public void ChildrenOf(int32 parent, List<int32> result)
	{
		result.Clear();
		for (let link in links)
		{
			if (link.parent == parent && Find(link.child) != null)
				result.Add(link.child);
		}
		result.Sort(scope (a, b) => Find(a).position.x <=> Find(b).position.x);
	}

	bool IsAncestor(int32 node, int32 of)
	{
		var cursor = of;
		for (int guard < 4096)
		{
			if (cursor == node)
				return true;
			cursor = ParentOf(cursor);
			if (cursor == 0)
				return false;
		}
		return true;
	}

	/// Makes child a child of parent. A node has one parent, a decorator one child and an action none; a link that
	/// would break those rules replaces the link in its way, and a link that would form a loop is refused.
	public bool Connect(int32 parent, int32 child, String error = null)
	{
		let from = Find(parent);
		let to = Find(child);
		if (from == null || to == null || parent == child)
			return false;
		if (from.def.MaxChildren == 0) { error?.Set(scope $"{from.def.title} cannot have children."); return false; }
		if (to.def.kind == .Root) { error?.Set("Root cannot be a child."); return false; }
		if (IsAncestor(child, parent)) { error?.Set("That link would make a loop."); return false; }
		for (int i = links.Count - 1; i >= 0; i--)
		{
			if (links[i].child == child || (from.def.MaxChildren == 1 && links[i].parent == parent))
				links.RemoveAt(i);
		}
		BTLink link;
		link.parent = parent;
		link.child = child;
		links.Add(link);
		return true;
	}

	public void Disconnect(int32 node, bool asChild)
	{
		for (int i = links.Count - 1; i >= 0; i--)
		{
			if (asChild ? links[i].child == node : links[i].parent == node)
				links.RemoveAt(i);
		}
	}

	public void Save(StringView path)
	{
		let text = scope String();
		text.AppendF("tree {}\n", SceneSerializer.Quote(name, .. scope .()));
		for (let node in nodes)
		{
			text.AppendF("node {} {} {} {}", node.id, node.def.key, node.position.x, node.position.y);
			for (let value in node.values)
				text.AppendF(" {}", SceneSerializer.Quote(value, .. scope .()));
			text.Append('\n');
		}
		for (let link in links)
			text.AppendF("link {} {}\n", link.parent, link.child);
		File.WriteAllText(path, text).IgnoreError();
	}

	public bool Load(StringView path)
	{
		let text = scope String();
		if (AssetPack.ReadAllText(path, text) case .Err)
			return false;
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer { for (let s in storage) delete s; }
		for (let line in text.Split('\n'))
		{
			tokens.Clear();
			SceneSerializer.Tokenize(line, tokens, storage);
			if (tokens.Count >= 2 && tokens[0] == "tree")
				name.Set(tokens[1]);
			else if (tokens.Count >= 5 && tokens[0] == "node")
			{
				let def = BehaviorLibrary.Find(tokens[2]);
				if (def == null)
				{
					Log.Warning(scope $"Behaviour tree uses unknown node '{tokens[2]}'; it was dropped.");
					continue;
				}
				let node = AddNode(def, .(SceneSerializer.ParseFloat(tokens[3]), SceneSerializer.ParseFloat(tokens[4])), SceneSerializer.ParseInt(tokens[1]));
				for (int i = 0; i < node.values.Count && 5 + i < tokens.Count; i++)
					node.values[i].Set(tokens[5 + i]);
			}
			else if (tokens.Count >= 3 && tokens[0] == "link")
				Connect(SceneSerializer.ParseInt(tokens[1]), SceneSerializer.ParseInt(tokens[2]));
		}
		return true;
	}
}

/// What a tree remembers between ticks, shared by all of its nodes: a target that was seen, a flag, a position.
class Blackboard
{
	public enum Kind { Number, Flag, Vector, Object }
	public struct Value
	{
		public Kind kind;
		public Vector3 vector;
		public float number;
		public uint32 objectId;
	}

	public Dictionary<String, Value> Values = new .() ~ DeleteDictionaryAndKeys!(_);

	void Store(StringView key, Value value)
	{
		if (Values.TryGetAlt(key, let existing, let unused))
			Values[existing] = value;
		else
			Values[new String(key)] = value;
	}

	public bool Has(StringView key) => Values.ContainsKeyAlt(key);

	public void Clear(StringView key)
	{
		if (Values.GetAndRemoveAlt(key) case .Ok(let pair))
			delete pair.key;
	}

	public void SetNumber(StringView key, float number) { Value v = default; v.kind = .Number; v.number = number; Store(key, v); }
	public void SetFlag(StringView key, bool flag) { Value v = default; v.kind = .Flag; v.number = flag ? 1 : 0; Store(key, v); }
	public void SetVector(StringView key, Vector3 vector) { Value v = default; v.kind = .Vector; v.vector = vector; Store(key, v); }
	public void SetObject(StringView key, GameObject object) { Value v = default; v.kind = .Object; v.objectId = object != null ? object.Id : 0; Store(key, v); }

	public float GetNumber(StringView key, float fallback = 0) => Values.TryGetValueAlt(key, let v) ? v.number : fallback;
	public bool GetFlag(StringView key) => Values.TryGetValueAlt(key, let v) && v.number != 0;

	/// The object stored under a key, or null if there is none or it no longer exists.
	public GameObject GetObject(StringView key, Scene scene)
	{
		if (!Values.TryGetValueAlt(key, let v) || v.kind != .Object || v.objectId == 0)
			return null;
		return scene.FindById(v.objectId);
	}

	/// A place to go: a stored position, or where a stored object is now.
	public bool TryGetPosition(StringView key, Scene scene, out Vector3 position)
	{
		position = default;
		if (!Values.TryGetValueAlt(key, let v))
			return false;
		if (v.kind == .Vector)
		{
			position = v.vector;
			return true;
		}
		let object = GetObject(key, scene);
		if (object == null)
			return false;
		position = object.Transform.Position;
		return true;
	}

	/// The value under a key as text, for the editor's debug view.
	public void Describe(StringView key, Scene scene, String text)
	{
		if (!Values.TryGetValueAlt(key, let v))
			return;
		switch (v.kind)
		{
		case .Number: text.AppendF("{:0.##}", v.number);
		case .Flag: text.Append(v.number != 0 ? "true" : "false");
		case .Vector: text.AppendF("({:0.#}, {:0.#}, {:0.#})", v.vector.x, v.vector.y, v.vector.z);
		case .Object:
			let object = scene.FindById(v.objectId);
			text.Append(object != null ? (StringView)object.Name : "(gone)");
		}
	}
}

/// What a node can reach while it runs.
class BTContext
{
	public BehaviorTreeRunner runner;
	public Blackboard blackboard;
	/// Seconds since the tree last ticked.
	public float deltaTime;
	public int32 tick;
	public Random random = new .() ~ delete _;

	public GameObject Object => runner.GameObject;
	public Scene Scene => runner.Scene;
	public Transform Transform => runner.Transform;
	/// The object's movement component, or null with a one-time warning if it has none.
	public AIMovementDriver Mover
	{
		get
		{
			let mover = runner.GetComponent<AIMovementDriver>();
			if (mover == null && !mWarned)
			{
				mWarned = true;
				Log.Warning(scope $"Behaviour tree on '{Object.Name}' uses a movement node, but the object has no Navigation Agent.");
			}
			return mover;
		}
	}
	bool mWarned;
}

/// A node of a running tree. Each kind overrides OnTick; OnStart and OnEnd bracket one run of it.
abstract class BTNode
{
	public BTNodeData data;
	public List<BTNode> children = new .() ~ DeleteContainerAndItems!(_);
	/// Result of the latest run; Running while it is in progress.
	public BTStatus status;
	/// The tree tick on which this node last ran, for the editor's highlighting.
	public int32 lastTick = -1;

	protected StringView Text(int index) => index < data.values.Count ? (StringView)data.values[index] : "";
	protected float Number(int index) => SceneSerializer.ParseFloat(Text(index));
	protected bool Flag(int index) => Text(index) == "true" || Text(index) == "1";
	protected Vector3 Vector(int index)
	{
		var parts = Text(index).Split(' ', .RemoveEmptyEntries);
		float[3] v = default;
		for (int i < 3)
		{
			if (parts.GetNext() case .Ok(let part))
				v[i] = SceneSerializer.ParseFloat(part);
		}
		return .(v[0], v[1], v[2]);
	}

	public BTStatus Tick(BTContext context)
	{
		if (status != .Running)
			OnStart(context);
		status = OnTick(context);
		lastTick = context.tick;
		if (status != .Running)
			OnEnd(context, false);
		return status;
	}

	/// Stops a node that is part-way through, along with whatever it was running.
	public void Abort(BTContext context)
	{
		if (status != .Running)
			return;
		for (let child in children)
			child.Abort(context);
		OnEnd(context, true);
		status = .Idle;
	}

	protected virtual void OnStart(BTContext context) { }
	protected abstract BTStatus OnTick(BTContext context);
	/// aborted is true when something above stopped this node before it finished.
	protected virtual void OnEnd(BTContext context, bool aborted) { }
}
