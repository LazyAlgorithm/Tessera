using System;
using System.Collections;
using System.Reflection;

namespace Tessera;

// ---- flow control ----

class BTRoot : BTNode
{
	protected override BTStatus OnTick(BTContext context) => children.Count > 0 ? children[0].Tick(context) : .Failure;
}

/// Runs children left to right until one fails. A running child is resumed next tick.
class BTSequence : BTNode
{
	int mIndex;
	protected override void OnStart(BTContext context) { mIndex = 0; }
	protected override BTStatus OnTick(BTContext context)
	{
		while (mIndex < children.Count)
		{
			let result = children[mIndex].Tick(context);
			if (result != .Success)
				return result;
			mIndex++;
		}
		return .Success;
	}
}

/// Runs children left to right until one succeeds. A running child is resumed next tick.
class BTSelector : BTNode
{
	int mIndex;
	protected override void OnStart(BTContext context) { mIndex = 0; }
	protected override BTStatus OnTick(BTContext context)
	{
		while (mIndex < children.Count)
		{
			let result = children[mIndex].Tick(context);
			if (result != .Failure)
				return result;
			mIndex++;
		}
		return .Failure;
	}
}

/// Like Sequence, but starts from the first child every tick, so an earlier condition that turns false
/// interrupts whatever a later child was doing.
class BTReactiveSequence : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		for (int i < children.Count)
		{
			let result = children[i].Tick(context);
			if (result == .Success)
				continue;
			// Whatever was running further right no longer applies.
			for (int later = i + 1; later < children.Count; later++)
				children[later].Abort(context);
			return result;
		}
		return .Success;
	}
}

/// Like Selector, but starts from the first child every tick, so a higher-priority branch that becomes
/// possible interrupts a lower one.
class BTReactiveSelector : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		for (int i < children.Count)
		{
			let result = children[i].Tick(context);
			if (result == .Failure)
				continue;
			for (int later = i + 1; later < children.Count; later++)
				children[later].Abort(context);
			return result;
		}
		return .Failure;
	}
}

/// Runs every child each tick. Succeeds when all have (Require All) or when any has.
class BTParallel : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		let requireAll = Flag(0);
		int succeeded = 0, failed = 0;
		for (let child in children)
		{
			// A child that already finished this run keeps its result.
			let result = (child.status == .Success || child.status == .Failure) && child.lastTick >= mStarted ? child.status : child.Tick(context);
			if (result == .Success) succeeded++;
			else if (result == .Failure) failed++;
		}
		BTStatus outcome = .Running;
		if (requireAll)
			outcome = failed > 0 ? .Failure : (succeeded == children.Count ? .Success : .Running);
		else
			outcome = succeeded > 0 ? .Success : (failed == children.Count ? .Failure : .Running);
		if (outcome != .Running)
		{
			for (let child in children)
				child.Abort(context);
		}
		return outcome;
	}
	int32 mStarted;
	protected override void OnStart(BTContext context) { mStarted = context.tick; }
}

class BTInvert : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Failure;
		let result = children[0].Tick(context);
		return result == .Success ? .Failure : (result == .Failure ? .Success : .Running);
	}
}

class BTAlwaysSucceed : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Success;
		return children[0].Tick(context) == .Running ? .Running : .Success;
	}
}

/// Runs its child again each time it succeeds: a number of times, or forever when Times is 0.
class BTRepeat : BTNode
{
	int mDone;
	protected override void OnStart(BTContext context) { mDone = 0; }
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Failure;
		let result = children[0].Tick(context);
		if (result == .Running) return .Running;
		if (result == .Failure) return .Failure;
		mDone++;
		let times = (int)Number(0);
		// One run per tick, so a child that finishes at once cannot spin forever inside a single frame.
		return times > 0 && mDone >= times ? .Success : .Running;
	}
}

/// Runs its child over and over until it fails, then succeeds.
class BTUntilFail : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Failure;
		return children[0].Tick(context) == .Failure ? .Success : .Running;
	}
}

/// After its child finishes, fails for a number of seconds without running it.
class BTCooldown : BTNode
{
	float mReadyAt = float.MinValue;
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Failure;
		if (children[0].status != .Running && Time.Time < mReadyAt)
			return .Failure;
		let result = children[0].Tick(context);
		if (result != .Running)
			mReadyAt = Time.Time + Number(0);
		return result;
	}
}

/// Fails, stopping its child, if the child runs longer than a number of seconds.
class BTTimeout : BTNode
{
	float mElapsed;
	protected override void OnStart(BTContext context) { mElapsed = 0; }
	protected override BTStatus OnTick(BTContext context)
	{
		if (children.Count == 0) return .Failure;
		mElapsed += context.deltaTime;
		if (mElapsed > Number(0))
		{
			children[0].Abort(context);
			return .Failure;
		}
		return children[0].Tick(context);
	}
}

// ---- simple actions ----

class BTWait : BTNode
{
	float mLeft;
	protected override void OnStart(BTContext context)
	{
		let low = Number(0);
		let high = Math.Max(Number(1), low);
		mLeft = low + (high - low) * (float)context.random.NextDouble();
	}
	protected override BTStatus OnTick(BTContext context)
	{
		mLeft -= context.deltaTime;
		return mLeft <= 0 ? .Success : .Running;
	}
}

class BTLog : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		Log.Info(scope $"{context.Object.Name}: {Text(0)}");
		return .Success;
	}
}

/// Calls a method by name on any component of the object. A method that returns bool decides success or
/// failure; any other method counts as success. This is the way to run your own code from a tree.
class BTCallMethod : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		let name = Text(0);
		for (let component in context.Object.Components)
		{
			if (component == context.runner)
				continue;
			let type = component.GetType() as TypeInstance;
			if (type == null)
				continue;
			if (type.GetMethod(name, .Instance | .Public | .NonPublic) case .Ok(let method))
			{
				if (method.ParamCount != 0)
					continue;
				switch (method.Invoke(component))
				{
				case .Ok(var result):
					defer result.Dispose();
					if (method.ReturnType == typeof(bool))
						return result.Get<bool>() ? .Success : .Failure;
					return .Success;
				case .Err:
					return .Failure;
				}
			}
		}
		if (!mWarned)
		{
			mWarned = true;
			Log.Warning(scope $"Behaviour tree on '{context.Object.Name}': no component has a method '{name}' without parameters.");
		}
		return .Failure;
	}
	bool mWarned;
}

// ---- blackboard ----

class BTHasValue : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		// A remembered object that has since been destroyed no longer counts.
		Vector3 position;
		return context.blackboard.Has(Text(0)) && (context.blackboard.TryGetPosition(Text(0), context.Scene, out position) || context.blackboard.Values[scope String(Text(0))].kind != .Object) ? .Success : .Failure;
	}
}

class BTClearValue : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		context.blackboard.Clear(Text(0));
		return .Success;
	}
}

class BTSetFlag : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		context.blackboard.SetFlag(Text(0), Flag(1));
		return .Success;
	}
}

class BTIsFlagSet : BTNode
{
	protected override BTStatus OnTick(BTContext context) => context.blackboard.GetFlag(Text(0)) ? .Success : .Failure;
}

/// Succeeds while a remembered object or position is within a distance of this object.
class BTWithinDistance : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		Vector3 position;
		if (!context.blackboard.TryGetPosition(Text(0), context.Scene, out position))
			return .Failure;
		return (position - context.Transform.Position).Length <= Number(1) ? .Success : .Failure;
	}
}

// ---- detection ----

/// Shared search for the detection nodes.
static class BTSenses
{
	/// A name matches exactly, or as a prefix when the pattern ends in '*'.
	public static bool NameMatches(StringView name, StringView pattern)
	{
		if (pattern.EndsWith('*'))
			return name.StartsWith(pattern.Substring(0, pattern.Length - 1));
		return name == pattern;
	}

	static bool IsPartOf(GameObject object, GameObject root)
	{
		var transform = object?.Transform;
		while (transform != null)
		{
			if (transform.GameObject == root)
				return true;
			transform = transform.Parent;
		}
		return false;
	}

	/// True if nothing solid lies between the eye and the target. Colliders of the looker and of the target
	/// themselves do not block the view.
	public static bool HasLineOfSight(Scene scene, GameObject looker, Vector3 eye, GameObject target, Vector3 targetPoint)
	{
		var origin = eye;
		for (int attempt < 4)
		{
			let delta = targetPoint - origin;
			let distance = delta.Length;
			if (distance < 0.05f)
				return true;
			RaycastHit hit;
			if (!scene.Physics.Raycast(origin, delta, distance, out hit))
				return true;
			if (IsPartOf(hit.gameObject, target))
				return true;
			if (!IsPartOf(hit.gameObject, looker))
				return false;
			// The ray started inside, or grazed, the looker's own collider: carry on from just past it.
			origin = hit.point + delta / distance * 0.05f;
		}
		return false;
	}

	/// Nearest object whose name matches and that passes the range, view-cone and line-of-sight tests.
	/// fieldOfView is the full cone angle in degrees; 360 or more looks all around. needSight false skips the ray.
	public static GameObject Find(BTContext context, StringView pattern, float range, float fieldOfView, float eyeHeight, bool needSight)
	{
		let self = context.Object;
		let eye = context.Transform.Position + Vector3(0, eyeHeight, 0);
		var forward = context.Transform.Forward;
		forward.y = 0;
		forward = forward.LengthSquared > 0.0001f ? forward.Normalized : Vector3.Forward;
		let minimumDot = fieldOfView >= 360 ? -2.0f : Math.Cos(Mathf.Clamp(fieldOfView, 0, 360) * 0.5f * Mathf.Deg2Rad);
		GameObject best = null;
		float bestDistance = range;
		for (let candidate in context.Scene.Objects)
		{
			if (candidate == self || !candidate.ActiveInHierarchy || !NameMatches(candidate.Name, pattern) || IsPartOf(candidate, self))
				continue;
			let targetPoint = candidate.Transform.Position + Vector3(0, eyeHeight * 0.5f, 0);
			var flat = candidate.Transform.Position - context.Transform.Position;
			let distance = flat.Length;
			if (distance > bestDistance)
				continue;
			flat.y = 0;
			if (flat.LengthSquared > 0.0001f && Vector3.Dot(flat.Normalized, forward) < minimumDot)
				continue;
			if (needSight && !HasLineOfSight(context.Scene, self, eye, candidate, targetPoint))
				continue;
			best = candidate;
			bestDistance = distance;
		}
		return best;
	}
}

/// Succeeds when an object with a matching name is in range, inside the view cone and not hidden behind
/// anything solid. The object and where it was seen are remembered under Store As and Store As + ".position".
class BTCanSee : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		let found = BTSenses.Find(context, Text(0), Number(1), Number(2), Number(3), true);
		if (found == null)
			return .Failure;
		let key = Text(4);
		if (!key.IsEmpty)
		{
			context.blackboard.SetObject(key, found);
			context.blackboard.SetVector(scope $"{key}.position", found.Transform.Position);
		}
		return .Success;
	}
}

/// Succeeds when an object with a matching name is within a distance, in any direction and through walls.
class BTIsNear : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		let found = BTSenses.Find(context, Text(0), Number(1), 360, 0, false);
		if (found == null)
			return .Failure;
		let key = Text(2);
		if (!key.IsEmpty)
		{
			context.blackboard.SetObject(key, found);
			context.blackboard.SetVector(scope $"{key}.position", found.Transform.Position);
		}
		return .Success;
	}
}

// ---- navigation ----

/// Common part of the movement nodes: ask the object's Navigation Agent for a path and wait for the result.
abstract class BTMove : BTNode
{
	protected bool mAsked;

	/// Where to go this tick, or false if there is nowhere.
	protected abstract bool Destination(BTContext context, out Vector3 point);
	protected abstract float Speed { get; }
	protected abstract float StopDistance { get; }
	/// Keep asking for the destination, for targets that move.
	protected virtual bool Follow => false;

	protected override void OnStart(BTContext context) { mAsked = false; }

	protected override BTStatus OnTick(BTContext context)
	{
		let mover = context.Mover;
		if (mover == null)
			return .Failure;
		if (!mAsked || Follow)
		{
			Vector3 point;
			if (!Destination(context, out point))
			{
				if (mAsked) mover.StopMovement();
				return .Failure;
			}
			mover.SetDestination(point, Speed, StopDistance);
			mAsked = true;
		}
		if (mover.PathFailed)
			return .Failure;
		return mover.HasArrived ? .Success : .Running;
	}

	protected override void OnEnd(BTContext context, bool aborted)
	{
		// Finishing normally leaves the agent standing where it arrived; being interrupted must stop it.
		if (aborted)
			context.Mover?.StopMovement();
	}
}

class BTMoveToPosition : BTMove
{
	protected override float Speed => Number(1);
	protected override float StopDistance => Number(2);
	protected override bool Destination(BTContext context, out Vector3 point) { point = Vector(0); return true; }
}

class BTMoveToObject : BTMove
{
	protected override float Speed => Number(1);
	protected override float StopDistance => Number(2);
	protected override bool Follow => true;
	protected override bool Destination(BTContext context, out Vector3 point)
	{
		point = default;
		let target = context.Scene.Find(Text(0));
		if (target == null)
			return false;
		point = target.Transform.Position;
		return true;
	}
}

/// Goes to an object or position remembered on the blackboard, for example one stored by Can See.
class BTMoveToTarget : BTMove
{
	protected override float Speed => Number(1);
	protected override float StopDistance => Number(2);
	protected override bool Follow => Flag(3);
	protected override bool Destination(BTContext context, out Vector3 point) => context.blackboard.TryGetPosition(Text(0), context.Scene, out point);
}

/// Goes to the next child of a waypoint object, in order, wrapping around. Each run visits one waypoint.
class BTPatrol : BTMove
{
	int mIndex = -1;
	protected override float Speed => Number(1);
	protected override float StopDistance => Number(2);
	protected override void OnStart(BTContext context)
	{
		base.OnStart(context);
		mIndex++;
	}
	protected override bool Destination(BTContext context, out Vector3 point)
	{
		point = default;
		let route = context.Scene.Find(Text(0));
		if (route == null || route.Transform.Children.Count == 0)
			return false;
		point = route.Transform.Children[mIndex % route.Transform.Children.Count].Position;
		return true;
	}
	protected override void OnEnd(BTContext context, bool aborted)
	{
		base.OnEnd(context, aborted);
		// An interrupted leg is walked again, not skipped.
		if (aborted)
			mIndex--;
	}
}

/// Goes to a random point within a radius of where the object was when the tree started.
class BTWander : BTMove
{
	Vector3 mPoint;
	protected override float Speed => Number(1);
	protected override float StopDistance => 0.3f;
	protected override void OnStart(BTContext context)
	{
		base.OnStart(context);
		let angle = (float)(context.random.NextDouble() * Math.PI_d * 2);
		let distance = Number(0) * Math.Sqrt((float)context.random.NextDouble());
		mPoint = context.runner.Home + Vector3(Math.Cos(angle), 0, Math.Sin(angle)) * distance;
	}
	protected override bool Destination(BTContext context, out Vector3 point) { point = mPoint; return true; }
}

class BTStopMoving : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		context.Mover?.StopMovement();
		return .Success;
	}
}

/// Turns to face a remembered object or position. Succeeds once it is facing it.
class BTFaceTarget : BTNode
{
	protected override BTStatus OnTick(BTContext context)
	{
		Vector3 position;
		if (!context.blackboard.TryGetPosition(Text(0), context.Scene, out position))
			return .Failure;
		let delta = position - context.Transform.Position;
		if (delta.x * delta.x + delta.z * delta.z < 0.0001f)
			return .Success;
		let wanted = Math.Atan2(delta.x, delta.z) * Mathf.Rad2Deg;
		let forward = context.Transform.Forward;
		let current = Math.Atan2(forward.x, forward.z) * Mathf.Rad2Deg;
		let turn = Mathf.WrapAngle(wanted - current);
		let step = Math.Max(Number(1), 1) * context.deltaTime;
		context.Transform.Rotation = Quaternion.Euler(0, current + Mathf.Clamp(turn, -step, step), 0);
		return Math.Abs(turn) <= step ? .Success : .Running;
	}
}

/// Every node kind the editor offers and the runner can build.
static class BehaviorLibrary
{
	static List<BTNodeDef> sDefs ~ DeleteContainerAndItems!(_);

	public static List<BTNodeDef> Defs
	{
		get
		{
			if (sDefs == null)
				Build();
			return sDefs;
		}
	}

	public static BTNodeDef Find(StringView key)
	{
		for (let def in Defs)
		{
			if (def.key == key)
				return def;
		}
		return null;
	}

	/// Adds a node kind. Games can call this at startup to offer their own nodes: derive from BTNode and register it.
	public static BTNodeDef Add(StringView key, StringView category, StringView title, BTKind kind, BTNodeDef.Factory create)
	{
		if (sDefs == null)
			Build();
		let def = new BTNodeDef();
		def.key.Set(key);
		def.category.Set(category);
		def.title.Set(title);
		def.kind = kind;
		def.create = create;
		sDefs.Add(def);
		return def;
	}

	static void Build()
	{
		sDefs = new .();
		Add("root", "Flow", "Root", .Root, new () => new BTRoot()).Describe("Where the tree starts. Connect one node below it.");
		Add("sequence", "Flow", "Sequence", .Composite, new () => new BTSequence()).Describe("Runs children left to right. Stops and fails when one fails; succeeds when all have.");
		Add("selector", "Flow", "Selector", .Composite, new () => new BTSelector()).Describe("Tries children left to right. Stops and succeeds when one succeeds; fails when all have.");
		Add("reactive.sequence", "Flow", "Reactive Sequence", .Composite, new () => new BTReactiveSequence()).Describe("A Sequence that rechecks from the left every tick, so a condition turning false interrupts the action after it.");
		Add("reactive.selector", "Flow", "Reactive Selector", .Composite, new () => new BTReactiveSelector()).Describe("A Selector that rechecks from the left every tick, so a higher-priority branch interrupts a lower one.");
		Add("parallel", "Flow", "Parallel", .Composite, new () => new BTParallel()).With("Require All", .Bool, "true").Describe("Runs all children together. Succeeds when all have, or when any has if Require All is off.");

		Add("invert", "Decorators", "Invert", .Decorator, new () => new BTInvert()).Describe("Turns its child's success into failure and failure into success.");
		Add("succeed", "Decorators", "Always Succeed", .Decorator, new () => new BTAlwaysSucceed()).Describe("Reports success whatever its child returns.");
		Add("repeat", "Decorators", "Repeat", .Decorator, new () => new BTRepeat()).With("Times", .Number, "0").Describe("Runs its child again each time it succeeds. Times 0 repeats forever.");
		Add("until.fail", "Decorators", "Repeat Until Failure", .Decorator, new () => new BTUntilFail()).Describe("Runs its child over and over until it fails.");
		Add("cooldown", "Decorators", "Cooldown", .Decorator, new () => new BTCooldown()).With("Seconds", .Number, "2").Describe("After its child finishes, fails for this long without running it.");
		Add("timeout", "Decorators", "Timeout", .Decorator, new () => new BTTimeout()).With("Seconds", .Number, "5").Describe("Stops its child and fails if the child runs longer than this.");

		Add("wait", "Actions", "Wait", .Action, new () => new BTWait()).With("Seconds", .Number, "1").With("Up To", .Number, "0").Describe("Waits. With Up To above Seconds the time is random between the two.");
		Add("log", "Actions", "Log", .Action, new () => new BTLog()).With("Text", .Text, "Hello").Describe("Writes a line to the Console.");
		Add("call", "Actions", "Call Method", .Action, new () => new BTCallMethod()).With("Method", .Text, "DoSomething").Describe("Calls a method with no parameters on a component of this object. A bool result decides success.");

		Add("nav.position", "Navigation", "Move To Position", .Action, new () => new BTMoveToPosition()).With("Position", .Vector, "0 0 0").With("Speed", .Number, "3").With("Stop Distance", .Number, "0.3").Describe("Walks to a fixed point using the object's Navigation Agent.");
		Add("nav.object", "Navigation", "Move To Object", .Action, new () => new BTMoveToObject()).With("Object", .Text, "Player").With("Speed", .Number, "3").With("Stop Distance", .Number, "1").Describe("Walks to the object with this name, following it if it moves.");
		Add("nav.target", "Navigation", "Move To Target", .Action, new () => new BTMoveToTarget()).With("Key", .Text, "target").With("Speed", .Number, "4").With("Stop Distance", .Number, "1").With("Follow", .Bool, "true").Describe("Walks to an object or position remembered on the blackboard, for example by Can See.");
		Add("nav.patrol", "Navigation", "Patrol", .Action, new () => new BTPatrol()).With("Waypoints", .Text, "Waypoints").With("Speed", .Number, "2").With("Stop Distance", .Number, "0.3").Describe("Walks to the next child of the named object, in order. Each run visits one waypoint.");
		Add("nav.wander", "Navigation", "Wander", .Action, new () => new BTWander()).With("Radius", .Number, "6").With("Speed", .Number, "2").Describe("Walks to a random point within a radius of where the object started.");
		Add("nav.stop", "Navigation", "Stop Moving", .Action, new () => new BTStopMoving()).Describe("Stops the Navigation Agent.");
		Add("nav.face", "Navigation", "Face Target", .Action, new () => new BTFaceTarget()).With("Key", .Text, "target").With("Turn Speed", .Number, "360").Describe("Turns toward a remembered object or position.");

		Add("see", "Detection", "Can See", .Condition, new () => new BTCanSee()).With("Object", .Text, "Player").With("Range", .Number, "12").With("Field Of View", .Number, "110").With("Eye Height", .Number, "1.6").With("Store As", .Text, "target").Describe("Succeeds if an object with this name (end with * for a prefix) is in range, in the view cone and not behind anything solid.");
		Add("near", "Detection", "Is Near", .Condition, new () => new BTIsNear()).With("Object", .Text, "Player").With("Distance", .Number, "3").With("Store As", .Text, "target").Describe("Succeeds if an object with this name is within a distance, in any direction and through walls.");
		Add("within", "Detection", "Target Within", .Condition, new () => new BTWithinDistance()).With("Key", .Text, "target").With("Distance", .Number, "2").Describe("Succeeds while a remembered object or position is within a distance.");

		Add("bb.has", "Blackboard", "Has Value", .Condition, new () => new BTHasValue()).With("Key", .Text, "target").Describe("Succeeds if something is remembered under this key.");
		Add("bb.clear", "Blackboard", "Forget", .Action, new () => new BTClearValue()).With("Key", .Text, "target").Describe("Forgets what is remembered under this key.");
		Add("bb.set", "Blackboard", "Set Flag", .Action, new () => new BTSetFlag()).With("Key", .Text, "alert").With("Value", .Bool, "true").Describe("Remembers a true or false value.");
		Add("bb.flag", "Blackboard", "Is Flag Set", .Condition, new () => new BTIsFlagSet()).With("Key", .Text, "alert").Describe("Succeeds if the flag is true.");
	}
}
