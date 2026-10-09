# Behaviour trees

A behaviour tree decides what an AI character does: patrol, chase what it sees, go and look where it last saw it. Trees are drawn in the **Behavior** tab, saved as `.tbt` files, and run by a **Behavior Tree Runner** component. While the game plays, the tab shows the tree of the selected object live.

## Making a tree

1. In the Project panel click **+** and choose **Behavior Tree**. The new tree opens with a working example: chase an object named `Player` on sight, otherwise wander.
2. Add a **Behavior Tree Runner** (Add Component > AI) to the character and set **Tree** to the file, for example `AI/Guard.tbt`.
3. Movement nodes drive a **Navigation Agent** on the same object, so add one and bake a Navigation Surface.

The canvas works like the Graph tab: right-click to add a node (type to search), middle-drag to pan, wheel to zoom, Delete to remove the selected node. **Fit View** shows the whole tree. Flow runs downward:

- A node's parent connects to the dot on its top, its children to the dot on its bottom.
- Drag from a node's bottom dot onto another node to make that node its child. Dropping on empty canvas offers a new node already connected.
- Alt+click a dot to disconnect it.
- **Children run left to right.** The small numbers beside them show the order; drag a node sideways to change it.

Select a node to edit its settings in the box at the top left, which also says what the node does.

## How a tree runs

The runner ticks the tree from the Root once per frame (or every **Tick Interval** seconds). Each node answers **Success**, **Failure** or **Running**. An action that takes time, such as walking somewhere, answers Running until it is done, and is resumed on the next tick.

| Flow node | What it does |
|---|---|
| Sequence | Runs children left to right. Fails as soon as one fails; succeeds when all have. "Do this, then this." |
| Selector | Tries children left to right. Succeeds as soon as one does; fails when all have. "Do the first of these that works." |
| Reactive Sequence | A Sequence that rechecks from the left every tick. A condition that turns false interrupts the action after it. |
| Reactive Selector | A Selector that rechecks from the left every tick. A higher-priority branch interrupts a lower one. |
| Parallel | Runs all children together. |

The reactive versions are what make a character respond. A plain Sequence that has moved on to "walk to the target" will not look at "can I still see it?" again until the walk ends; a Reactive Sequence asks every tick and stops the walk the moment the answer is no. Put conditions first and use a Reactive Selector at the top with the most urgent branch on the left.

Decorators have one child: **Invert**, **Always Succeed**, **Repeat** (a number of times, or forever), **Repeat Until Failure**, **Cooldown** and **Timeout**.

## The nodes

**Navigation** (needs a Navigation Agent on the object):

| Node | What it does |
|---|---|
| Move To Position | Walks to a fixed point. |
| Move To Object | Walks to the object with a given name, following it. |
| Move To Target | Walks to something remembered on the blackboard, such as what Can See found. With Follow on it keeps up with a moving target. |
| Patrol | Walks to the next child of a named object, in order, wrapping around. Each run visits one waypoint, so pair it with a Wait in a Sequence. |
| Wander | Walks to a random point within a radius of where the character started. |
| Stop Moving, Face Target | Stop the agent; turn toward a remembered object or position. |

**Detection:**

| Node | What it does |
|---|---|
| Can See | Succeeds if an object with a given name is within Range, inside the Field Of View cone in front of the character, and not hidden behind anything with a collider. End the name with `*` to match a prefix (`Enemy*`). |
| Is Near | Succeeds if such an object is within a distance, in any direction and through walls. Use it for hearing or touch. |
| Target Within | Succeeds while a remembered object or position is within a distance. |

Can See and Is Near remember what they found under **Store As** (default `target`), and where it was under that name plus `.position`. The object keeps updating as it moves; the position is where it was last detected, which is what a guard should go and check after losing sight.

**Blackboard:** the tree's memory, shared by all its nodes and kept while the game runs. **Has Value**, **Forget**, **Set Flag** and **Is Flag Set** read and write it.

**Actions:** **Wait** (a fixed time, or random between two), **Log**, and **Call Method**.

## Watching a tree while the game runs

Open the tree, press Play, and select an object that runs it. The toolbar names the object being watched; with nothing selected, the first object using the tree is shown.

| Colour | Meaning |
|---|---|
| Amber, pulsing | Running now. |
| Green | Succeeded. |
| Red | Failed. |
| Grey | Stopped part-way by a branch with higher priority. |

Results from the latest tick are bright and older ones fade over about a second, so the path the tree is taking stands out and what it did a moment ago is still visible. Links are coloured the same way. The box at the bottom left lists the watched object's blackboard.

Saving a tree while the game is playing reloads it on every object that uses it, so you can adjust a range or a speed and see the result without stopping.

## Running your own code

**Call Method** calls a method by name on any component of the same object. The method takes no parameters. If it returns `bool`, true is Success and false is Failure; anything else counts as Success.

```beef
[Component]
class GuardActions : Component
{
    public int32 ammo = 3;

    public bool HasAmmo() => ammo > 0;      // use as a condition
    public void Shoot() { ammo--; }           // use as an action
}
```

For a node with its own settings, or one that runs over several ticks, derive from `BTNode` and register it at startup (in `GameSetup.Register`):

```beef
class HasAmmoAtLeast : BTNode
{
    protected override BTStatus OnTick(BTContext context)
    {
        let actions = context.Object.GetComponent<GuardActions>();
        return actions != null && actions.ammo >= (int)Number(0) ? .Success : .Failure;
    }
}

BehaviorLibrary.Add("game.ammo", "Game", "Has Ammo At Least", .Condition, new () => new HasAmmoAtLeast())
    .With("Count", .Number, "1")
    .Describe("Succeeds while the guard has this much ammunition.");
```

`Number(i)`, `Text(i)`, `Flag(i)` and `Vector(i)` read the node's settings in the order they were declared. Override `OnStart` and `OnEnd(context, aborted)` to set up and clean up; `aborted` is true when a higher-priority branch stopped the node. `context` gives the object, its scene, the blackboard, the time since the last tick and the object's Navigation Agent as `Mover`.

From any script, `GetComponent<BehaviorTreeRunner>().Blackboard` lets gameplay talk to the tree: `SetFlag("alert", true)`, `SetObject("target", player)`, `SetVector("noise", position)`.

## Limits

- Objects are found by name; there are no tags or layers yet.
- Can See tests one ray to the middle of the target, so a target mostly hidden behind cover is either seen or not.
- A tree is interpreted, not compiled, and every runner loads its own copy.
- There are no subtrees yet; a large tree is one file.

CPU tests cover link rules and child order, save and load, each flow node and decorator, interruption by a reactive selector, Call Method, a game-defined node, Move To Position, Patrol order, Can See against range, view cone and a wall, Is Near, and a full patrol, chase and return behaviour.
