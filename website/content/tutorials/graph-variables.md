---
title: A visual script with variables
summary: Build a graph that spins its object, then give it a speed and an on/off switch you can set per object in the Inspector.
difficulty: Beginner
minutes: 15
order: 3
---
A graph is a visual script. Saving it compiles it into an ordinary Beef component with the graph's name, so everything a component can do, a graph can do.

![The finished graph with its Variables panel](assets/screenshots/graph.jpg)

## 1. Create the graph

1. In the **Project** panel click **+** and choose **Graph (visual script)**. Name it `Turntable`.
2. The **Graph** tab opens with a working example: **On Update** runs **Rotate**, and the angle is **Delta Time** multiplied by `90` and fed into the **Y** of a **Vector**.

Canvas controls: right-click adds a node (type to search), drag from one pin to another to connect, Alt+click a pin to disconnect, Delete removes the selected node, middle-drag pans and the wheel zooms.

## 2. Add a speed variable

The `90` is typed into the Multiply node, so every object that uses this graph turns at the same speed. A variable fixes that.

1. In the **Variables** panel at the top right of the canvas, click **+ Add**.
2. Rename the new variable to `speed`, leave its type as **Number** and set the default to `90`.
3. Click **Get** on that row. A **Get speed** node appears in the middle of the canvas.
4. Drag from the output pin of **Get speed** to the **B** pin of **Multiply**. The link replaces the typed `90`.

## 3. Add an on/off switch

1. Click **+ Add** again. Name the variable `spinning`, set its type to **Boolean** and tick its default.
2. Right-click the canvas and add **Branch** (under Flow).
3. Drag the white flow pin of **On Update** to the flow input of **Branch**. This replaces the link that went straight to Rotate.
4. Drag **True** on the Branch to the flow input of **Rotate**.
5. Click **Get** on the `spinning` row and connect the new node to the Branch's **Condition**.

## 4. Save and use it

1. Click **Save** in the Graph toolbar. Save also compiles the graph; the status next to the buttons reads "Saved and compiled."
2. Select an object, click **Add Component** in the Inspector and pick **Turntable**.
3. The component has two fields, **Speed** and **Spinning**. Give two objects different speeds, and untick Spinning on one of them.
4. Press **Play**.

The values in the Variables panel are only what a new component starts with. Each object keeps its own values, saved with the scene like any script field.

## Changing a variable from the graph

**Set** on a variable's row places a node that writes it. For example, connect **On Start** to **Set speed** to pick a starting speed at run time. Text variables are copied when set, so the component owns its own text.

## Good to know

- Renaming a variable renames its nodes. Scenes that already saved a value under the old name treat it as a new field.
- Changing a variable's type drops links that no longer fit.
- A subgraph's variables live on the component of the graph that uses it.
- Right-click a graph in the Project panel and choose **View Generated Code** to see the Beef it produced.
