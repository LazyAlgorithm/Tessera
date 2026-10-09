using System;
using System.Collections;

namespace Tessera;

/// Runs a behaviour tree asset (.tbt) for its object. Movement nodes drive a Navigation Agent on the same object.
/// The Behavior tab in the editor shows the tree of the selected object live while the game plays.
[Component]
class BehaviorTreeRunner : Component
{
	/// Tree file, relative to the project's asset folder.
	public String tree = new .() ~ delete _;
	/// Seconds between ticks. 0 ticks every frame; a little higher is cheaper for crowds.
	public float tickInterval = 0;
	/// Start over when the tree finishes. Off leaves it stopped.
	public bool restartWhenDone = true;

	BehaviorTreeData mData ~ delete _;
	BTNode mRoot ~ delete _;
	Dictionary<int32, BTNode> mById = new .() ~ delete _;
	BTContext mContext = new .() ~ delete _;
	Blackboard mBlackboard = new .() ~ delete _;
	String mLoaded = new .() ~ delete _;
	float mSinceTick;
	bool mFinished;

	public Blackboard Blackboard => mBlackboard;
	public BehaviorTreeData Data => mData;
	/// Number of ticks run so far; a node whose LastTick equals TickCount ran on the latest tick.
	public int32 TickCount => mContext.tick;
	/// Where the object was when the tree started.
	public Vector3 Home;

	public BTStatus StatusOf(int32 nodeId) => mById.TryGetValue(nodeId, let node) ? node.status : .Idle;
	public int32 LastTickOf(int32 nodeId) => mById.TryGetValue(nodeId, let node) ? node.lastTick : -1;

	public override void Start()
	{
		Home = Transform.Position;
		Reload();
	}

	/// Reads the tree file again and starts from the top. The blackboard is kept.
	public void Reload()
	{
		if (mRoot != null)
			mRoot.Abort(mContext);
		delete mRoot; mRoot = null;
		delete mData; mData = null;
		mById.Clear();
		mLoaded.Set(tree);
		mFinished = false;
		mContext.runner = this;
		mContext.blackboard = mBlackboard;
		if (tree.IsEmpty)
			return;
		let path = scope String();
		Assets.ResolvePath(tree, path);
		let data = new BehaviorTreeData();
		if (!data.Load(path))
		{
			Log.Warning(scope $"Behaviour tree not found: {tree}");
			delete data;
			return;
		}
		mData = data;
		let root = data.Root;
		if (root == null)
		{
			Log.Warning(scope $"Behaviour tree {tree} has no Root node.");
			return;
		}
		mRoot = Build(root);
	}

	BTNode Build(BTNodeData data)
	{
		let node = data.def.create();
		node.data = data;
		mById[data.id] = node;
		List<int32> children = scope .();
		mData.ChildrenOf(data.id, children);
		for (let child in children)
			node.children.Add(Build(mData.Find(child)));
		return node;
	}

	public override void Update()
	{
		if (mLoaded != tree)
			Reload();
		// In multiplayer the tree thinks on the server only; clients see what it does through the object's movement.
		if (mRoot == null || mFinished || NetworkSync.IsClientOf(Scene))
			return;
		mSinceTick += Time.DeltaTime;
		if (mSinceTick < tickInterval)
			return;
		Tick(mSinceTick);
		mSinceTick = 0;
	}

	/// Runs the tree once. deltaTime is how long it has been since the last tick.
	public BTStatus Tick(float deltaTime)
	{
		if (mRoot == null)
			return .Failure;
		mContext.deltaTime = deltaTime;
		mContext.tick++;
		let result = mRoot.Tick(mContext);
		if (result != .Running && !restartWhenDone)
			mFinished = true;
		return result;
	}

	public override void OnDisable()
	{
		if (mRoot != null)
			mRoot.Abort(mContext);
	}
}
