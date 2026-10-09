---
title: Your own graph nodes and reusable subgraphs
summary: Turn Beef methods into nodes for the visual scripting editor, and package a group of nodes as a subgraph you can drop into any graph.
difficulty: Intermediate
minutes: 15
order: 4
---
The graph editor comes with nodes for transforms, math, input and time. When you need something else there are two ways to add it: write a method in code, or build a subgraph out of existing nodes.

## Part 1: nodes written in code

Any public static method can be a node. Create a script named `GameNodes`:

```beef
using System;
using Tessera;

namespace MyGame;

[GraphLibrary]
static class GameNodes
{
    /// A value node: parameters are inputs, the return value is the output.
    [GraphNode]
    public static float Pulse(float time, float speed) => Math.Sin(time * speed) * 0.5f + 0.5f;

    /// An action node: a method that returns nothing gets flow pins.
    [GraphNode]
    public static void Shout(String text) => Log.Info(text);

    /// A first parameter of type Component receives the graph's own component and makes no pin.
    [GraphNode]
    public static void Bob(Component owner, float height, float speed)
    {
        var position = owner.Transform.LocalPosition;
        position.y = Math.Sin(Time.Time * speed) * height;
        owner.Transform.LocalPosition = position;
    }
}
```

The rules:

- The class needs `[GraphLibrary]` and each method `[GraphNode]`.
- Parameters and return values can be `float`, `int32`, `bool`, `Vector3` and `String`. A method using any other type is left out.
- A method that returns a value becomes a **value node**. A method that returns nothing becomes an **action node** with white flow pins, and runs when flow reaches it.
- An optional first parameter of type `Component` is filled in with the component the graph compiles to. Use it to reach `Transform`, `GameObject` or other components.

Save the script. After the script library reloads, right-click the graph canvas: the nodes are under **Code**, named `GameNodes.Pulse`, `GameNodes.Shout` and `GameNodes.Bob`. If they are missing, look in the Console for a compile error.

### Use them

1. Create a graph (**+** > **Graph (visual script)**) and delete its example nodes except **On Update**.
2. Add **GameNodes.Bob** and connect **On Update** to it. Select it and set **height** to `0.5` and **speed** to `2`.
3. Save, add the graph's component to an object and press Play. The object bobs up and down.

## Part 2: subgraphs

A subgraph is a graph that appears as a single node in other graphs. Use one when the same few nodes keep turning up.

1. In the Project panel click **+** and choose **Subgraph (reusable node)**. Name it `Nudge`.
2. It opens with a working example: **Sub Entry** runs **Translate**, moving the object by a **Vector** whose Y comes from a **Parameter (Number)** named `amount`.

The building blocks are under **Subgraph** in the add-node menu:

| Node | Purpose |
|---|---|
| Sub Entry | Where the subgraph starts when it is called. |
| Parameter (Number, Vector, Boolean, Text) | An input pin on the subgraph's node. Select it and type the pin's name in **Name**. |
| Return (Number, Vector, Boolean) | Ends the subgraph and gives it an output. A subgraph with a Return is a value node; without one it is an action node. |

3. Save the subgraph. The status reads that a subgraph is compiled into each graph that uses it.

### Use it

1. Open another graph, right-click the canvas and look under **Subgraphs**. Add **Sub: Nudge**.
2. It has a flow pin and an `amount` pin, like any action node. Connect **On Update** to it and feed `amount` from **Delta Time**.
3. Save the graph that uses it.
4. Double-click the **Sub: Nudge** node to step into the subgraph and edit it.

After changing a subgraph, save every graph that uses it again. A subgraph becomes a private method of each of those components, so they pick up the change when they are compiled.

## Which to use

| Use a code node when | Use a subgraph when |
|---|---|
| The logic is easier to write than to wire: loops, strings, anything using engine calls that have no node. | The logic is a handful of existing nodes you want to reuse. |
| You want it available in every graph in the project. | You want to open it and adjust it visually. |

Variables declared in a subgraph live on the component of the graph that uses it; see [A visual script with variables](tutorials.php?t=graph-variables).
