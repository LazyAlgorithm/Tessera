using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// The Graph tab: a zoomable node canvas for visual scripts (.tgraph files).
///   Right-click the canvas to add a node (type to search), drag from a pin to another pin to connect them,
///   or drop a link on empty canvas to pick from the nodes that fit it,
///   Alt+click a pin to disconnect it, Delete removes the selected node, middle-drag pans, the wheel zooms.
/// Save also compiles the graph to a Beef component next to it; automatic script reload then picks it up like any script.
extension EditorApp
{
	[CLink] static extern void* igGetWindowDrawList();
	[CLink] static extern void ImDrawList_AddCircleFilled(void* list, ImGui.Vec2 center, float radius, uint32 color, int32 segments);
	[CLink] static extern void ImDrawList_AddBezierCubic(void* list, ImGui.Vec2 p1, ImGui.Vec2 p2, ImGui.Vec2 p3, ImGui.Vec2 p4, uint32 color, float thickness, int32 segments);
	[CLink] static extern void igPushFont(void* font, float size);

	const float cNodeWidth = 190;
	const float cHeaderHeight = 26;
	const float cRowHeight = 22;

	NodeGraph mGraph ~ delete _;
	String mGraphPath = new .() ~ delete _;
	String mGraphStatus = new .() ~ delete _;
	Vector2 mGraphPan = .(60, 60);
	float mGraphZoom = 1.0f;
	int32 mGraphSelected;
	int32 mGraphDragNode;
	bool mGraphFocus;
	// Link being dragged out of a pin.
	bool mLinking;
	int32 mLinkNode;
	int32 mLinkPin;
	bool mLinkFromOutput;
	Vector2 mNewNodePosition;

	bool mGraphShowVariables = true;
	// Name being typed in the Variables panel; it is applied when the field loses focus.
	String mVariableEdit = new .() ~ delete _;
	int mVariableEditing = -1;

	String mNodeSearch = new .() ~ delete _;
	bool mOpenNodeSearch;
	bool mNodeSearchFocus;
	bool mSearchForLink;

	void OpenNodeSearch(Vector2 position, bool forLink)
	{
		mNewNodePosition = position;
		mNodeSearch.Clear();
		mSearchForLink = forLink;
		mOpenNodeSearch = true;
	}

	/// For a search opened by dragging a link: the first pin of a node kind that the dragged pin can connect to.
	int32 FirstCompatiblePin(NodeDef def)
	{
		let source = mGraph.Find(mLinkNode);
		if (source == null)
			return -1;
		if (mLinkFromOutput)
		{
			if (mLinkPin >= source.def.outputs.Count)
				return -1;
			let from = source.def.outputs[mLinkPin];
			for (int32 i = 0; i < (int32)def.inputs.Count; i++)
			{
				if (mGraph.Links(from, def.inputs[i]))
					return i;
			}
			return -1;
		}
		if (mLinkPin >= source.def.inputs.Count)
			return -1;
		let wanted = source.def.inputs[mLinkPin];
		for (int32 i = 0; i < (int32)def.outputs.Count; i++)
		{
			if (mGraph.Links(def.outputs[i], wanted))
				return i;
		}
		return -1;
	}

	String mPendingGraph = new .() ~ delete _;

	void OpenGraph(StringView path)
	{
        mShowGraph=true; mDockGraph=true;
		NodeLibrary.RefreshSubgraphs(Assets.ProjectPath);
		delete mGraph;
		mGraph = new NodeGraph();
		mGraphPath.Set(path);
		mGraph.name.Clear();
		Path.GetFileNameWithoutExtension(path, mGraph.name);
		// A shader graph uses the same canvas with its own nodes, and compiles to a shader, not a script.
		mGraph.isShader = path.EndsWith(".tsgraph");
		mGraph.Load(path);
		mGraph.Validate();
		mGraphSelected = 0;
		mVariableEditing = -1;
		mGraphStatus.Clear();
		mGraphFocus = true;
	}

	void CreateGraphAsset(StringView name)
	{
		if (!ProjectGenerator.IsValidName(name))
		{
			Log.Error("Graph names use letters, digits and underscores, and start with a letter.");
			return;
		}
		let path = scope $"{mBrowsePath}/{name}.tgraph";
		if (File.Exists(path))
		{
			Log.Error(scope $"{path} already exists.");
			return;
		}
		// Start with something that runs: spin the object a little every frame.
		let graph = scope NodeGraph();
		graph.name.Set(name);
		let update = graph.AddNode(NodeLibrary.Find("event.update"), .(40, 60));
		let rotate = graph.AddNode(NodeLibrary.Find("transform.rotate"), .(560, 60));
		let vector = graph.AddNode(NodeLibrary.Find("math.vector"), .(320, 150));
		let multiply = graph.AddNode(NodeLibrary.Find("math.mul"), .(60, 190));
		multiply.values[1].Set("90");
		graph.Connect(update.id, 0, rotate.id, 0);
		graph.Connect(update.id, 1, multiply.id, 0);
		graph.Connect(multiply.id, 0, vector.id, 1);
		graph.Connect(vector.id, 0, rotate.id, 1);
		graph.Save(path);
		RefreshAssetList();
		OpenGraph(path);
	}

	/// A reusable graph: Sub Entry starts it, Parameter nodes are its inputs, an optional Return node its result.
	void CreateSubgraphAsset(StringView name)
	{
		if (!ProjectGenerator.IsValidName(name))
		{
			Log.Error("Subgraph names use letters, digits and underscores, and start with a letter.");
			return;
		}
		let path = scope $"{mBrowsePath}/{name}.tgraph";
		if (File.Exists(path))
		{
			Log.Error(scope $"{path} already exists.");
			return;
		}
		let graph = scope NodeGraph();
		graph.name.Set(name);
		let entry = graph.AddNode(NodeLibrary.Find("sub.entry"), .(40, 60));
		let amount = graph.AddNode(NodeLibrary.Find("sub.param.float"), .(40, 190));
		amount.values[0].Set("amount");
		let vector = graph.AddNode(NodeLibrary.Find("math.vector"), .(300, 170));
		let move = graph.AddNode(NodeLibrary.Find("transform.translate"), .(560, 60));
		graph.Connect(entry.id, 0, move.id, 0);
		graph.Connect(amount.id, 0, vector.id, 1);
		graph.Connect(vector.id, 0, move.id, 1);
		graph.Save(path);
		RefreshAssetList();
		OpenGraph(path);
	}

	void CompileGraph()
	{
		if (mGraph == null)
			return;
		mGraph.Save(mGraphPath);
		if (mGraph.isShader)
		{
			CompileShaderGraph();
			return;
		}
		NodeLibrary.RefreshSubgraphs(Assets.ProjectPath);
		mGraph.Validate();
		if (mGraph.IsSubgraph)
		{
			mGraphStatus.Set("Saved. A subgraph is compiled into each graph that uses it: save those to update them.");
			return;
		}
		let folder = scope String();
		Path.GetDirectoryPath(mGraphPath, folder).IgnoreError();
		let fileName = scope String();
		Path.GetFileName(mGraphPath, fileName);
		let code = scope String();
		mGraph.Compile(Project.Current.Name, mGraph.name, fileName, code);
		let target = scope $"{folder}/{mGraph.name}.bf";
		if (File.WriteAllText(target, code) case .Ok)
		{
			mGraphStatus.Set("Saved and compiled.");
			Log.Info(scope $"Graph compiled to {target}");
			RefreshAssetList();
			StartErrorCheck();
		}
		else
			mGraphStatus.Set("Could not write the generated script.");
	}

	/// Saves a shader graph as the .tshader file beside it and compiles that.
	void CompileShaderGraph()
	{
		let text = scope String();
		let problem = scope String();
		if (!mGraph.CompileShader(text, problem))
		{
			mGraphStatus.Set(problem);
			return;
		}
		let target = scope String(mGraphPath);
		target.RemoveFromEnd(".tsgraph".Length);
		target.Append(".tshader");
		if (File.WriteAllText(target, text) case .Err)
		{
			mGraphStatus.Set("Could not write the generated shader.");
			return;
		}
		let relative = scope String();
		Assets.MakeRelative(target, relative);
		mGraphStatus.Set(CompileShader(relative) ? "Saved and compiled. Pick it as a material's Shader." : "Saved, but the shader did not compile: see the Console.");
		AssetPreviews.Invalidate(mGraphPath);
		RefreshAssetList();
	}

	void CreateShaderGraphAsset(StringView name)
	{
		if (!ValidAssetName(name, "Shader graph"))
			return;
		let path = scope $"{mBrowsePath}/{name}.tsgraph";
		if (File.Exists(path) || File.Exists(scope $"{mBrowsePath}/{name}.tshader"))
		{
			Log.Error(scope $"A shader named {name} already exists in this folder.");
			return;
		}
		// Something that visibly works: a colour property for the surface, and a pulse of it as glow.
		let graph = scope NodeGraph();
		graph.isShader = true;
		graph.name.Set(name);
		let output = graph.AddNode(NodeLibrary.Find("shader.output"), .(620, 120));
		let tint = graph.AddNode(NodeLibrary.Find("shader.prop.color"), .(60, 80));
		let pulse = graph.AddNode(NodeLibrary.Find("shader.pulse"), .(60, 260));
		let rgb = graph.AddNode(NodeLibrary.Find("shader.rgb"), .(300, 80));
		let glow = graph.AddNode(NodeLibrary.Find("shader.vscale"), .(360, 240));
		graph.Validate();
		tint.values[0].Set("tint"); tint.values[1].Set("0.2 0.7 1 1");
		pulse.values[0].Set("2");
		graph.Connect(tint.id, 0, rgb.id, 0);
		graph.Connect(rgb.id, 0, output.id, 0);
		graph.Connect(rgb.id, 0, glow.id, 0);
		graph.Connect(pulse.id, 0, glow.id, 1);
		graph.Connect(glow.id, 0, output.id, 4);
		graph.Save(path);
		RefreshAssetList();
		OpenGraph(path);
		CompileGraph();
	}

	static Color PinColor(PinType type)
	{
		switch (type)
		{
		case .Flow: return .(0.92f, 0.92f, 0.92f, 1);
		case .Float: return .(0.45f, 0.80f, 0.45f, 1);
		case .Bool: return .(0.86f, 0.36f, 0.36f, 1);
		case .Vector3: return .(0.95f, 0.78f, 0.30f, 1);
		case .String: return .(0.80f, 0.50f, 0.85f, 1);
		case .Int: return .(0.35f, 0.75f, 0.70f, 1);
		case .Object: return .(0.40f, 0.62f, 0.95f, 1);
		case .Enum: return .(0.70f, 0.70f, 0.40f, 1);
		case .Vector2: return .(0.95f, 0.62f, 0.30f, 1);
		case .Quaternion: return .(0.62f, 0.55f, 0.95f, 1);
		case .Color: return .(0.95f, 0.50f, 0.70f, 1);
		}
	}

	static Color CategoryColor(StringView category)=>NodeCanvas.CategoryColor(category);

	static float NodeHeight(GraphNode node) => cHeaderHeight + Math.Max(node.def.inputs.Count, node.def.outputs.Count) * cRowHeight + 8;

	/// Pin centre in graph space.
	static Vector2 PinPosition(GraphNode node, int32 pin, bool output)
	{
		return .(node.position.x + (output ? cNodeWidth : 0), node.position.y + cHeaderHeight + pin * cRowHeight + cRowHeight * 0.5f);
	}

	void DrawGraph()
	{
        if (!mShowGraph && mPendingGraph.IsEmpty) return;
        if (mDockGraph && mAssetCenterDock!=0) { ImGui.SetNextWindowDockID(mAssetCenterDock); mDockGraph=false; }
		if (!mPendingGraph.IsEmpty)
		{
			if (mGraph != null)
				mGraph.Save(mGraphPath);
			OpenGraph(mPendingGraph);
			mPendingGraph.Clear();
		}
		if (mGraphFocus && Time.FrameCount > 5)
		{
			ImGui.SetNextWindowFocus();
			mGraphFocus = false;
		}
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(0, 0));
		let visible = ImGui.Begin("Graph", &mShowGraph, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse);
		ImGui.PopStyleVar();
		if (!visible)
		{
			ImGui.End();
			return;
		}
		if (mGraph == null)
		{
			ImGui.SetCursorPosX(16);
			ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 14);
			ImGui.TextDisabled("Create a visual script with Project > + > Graph, or double-click a .tgraph file.");
			ImGui.End();
			return;
		}

		// ---- toolbar ----
		ImGui.SetCursorPosX(6);
		ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 4);
		if (ImGui.SmallButton("Save")) CompileGraph();
		ImGui.SameLine();
		if (ImGui.SmallButton("Reset View")) { mGraphPan = .(60, 60); mGraphZoom = 1; }
		ImGui.SameLine();
		if (mGraph.isShader)
			mGraphShowVariables = false; // a shader keeps its values in Property nodes
		else if (ImGui.SmallButton(mGraphShowVariables ? "Hide Variables" : "Variables")) mGraphShowVariables = !mGraphShowVariables;
		ImGui.SameLine(0, 14);
		ImGui.TextDisabled(scope String()..AppendF("{}   {:0}%   {}", mGraph.name, mGraphZoom * 100, mGraphStatus).CStr());

		ImGui.BeginChild("canvas", .(0, 0), 0, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse | ImGui.WindowFlags.NoMove);
		let origin = ImGui.GetCursorScreenPos();
		let size = ImGui.GetContentRegionAvail();
		ImGui.InvisibleButton("##canvas", .(Math.Max(size.x, 1), Math.Max(size.y, 1)));
		let hovered = ImGui.IsItemHovered();
		let mouse = ImGui.GetMousePos();
		let list = igGetWindowDrawList();
		var zoom = mGraphZoom;

		ImGui.Vec2 ToScreen(Vector2 p) => .(origin.x + mGraphPan.x + p.x * zoom, origin.y + mGraphPan.y + p.y * zoom);
		Vector2 ToGraph(ImGui.Vec2 p) => .((p.x - origin.x - mGraphPan.x) / zoom, (p.y - origin.y - mGraphPan.y) / zoom);

        NodeCanvas.UpdateView(ref mGraphPan,ref mGraphZoom,origin,mouse,hovered);
        zoom=mGraphZoom;
        NodeCanvas.DrawGrid(origin,size,mGraphPan,zoom);
        NodeCanvas.BeginFont(zoom);
		let pinRadius = 5.5f * zoom;
		let graphMouse = ToGraph(mouse);

		// ---- links ----
        void DrawLink(ImGui.Vec2 a,ImGui.Vec2 b,Color color)=>NodeCanvas.DrawLink(a,b,color,zoom);

		for (let link in mGraph.links)
		{
			let from = mGraph.Find(link.fromNode);
			let to = mGraph.Find(link.toNode);
			if (from != null && to != null)
				DrawLink(ToScreen(PinPosition(from, link.fromPin, true)), ToScreen(PinPosition(to, link.toPin, false)), PinColor(from.def.outputs[link.fromPin].type));
		}

		// ---- nodes ----
		GraphNode hoverNode = null;
		int32 hoverPin = -1;
		bool hoverPinIsOutput = false;
		for (let node in mGraph.nodes)
		{
			let min = ToScreen(node.position);
			let max = ToScreen(.(node.position.x + cNodeWidth, node.position.y + NodeHeight(node)));
			let selected = node.id == mGraphSelected;
            NodeCanvas.DrawNode(min,max,CategoryColor(node.def.category),selected,zoom);
			if (zoom > 0.4f)
				ImGui.DrawText(.(min.x + 9 * zoom, min.y + 5 * zoom), .White, NodeGraph.Title(node, .. scope String()).CStr());
			if (hovered && mouse.x >= min.x && mouse.x <= max.x && mouse.y >= min.y && mouse.y <= max.y)
				hoverNode = node;

			for (int side < 2)
			{
				let pins = side == 0 ? node.def.inputs : node.def.outputs;
				for (int32 i = 0; i < (int32)pins.Count; i++)
				{
					let center = ToScreen(PinPosition(node, i, side == 1));
					let pin = pins[i];
					let over = hovered && Math.Abs(mouse.x - center.x) < pinRadius * 2 && Math.Abs(mouse.y - center.y) < pinRadius * 2;
					if (over)
					{
						hoverNode = node;
						hoverPin = i;
						hoverPinIsOutput = side == 1;
					}
					ImDrawList_AddCircleFilled(list, center, over ? pinRadius * 1.4f : pinRadius, PinColor(pin.type).ToABGR(), 12);
					if (zoom <= 0.4f)
						continue;
					// Label, plus the literal for an input with nothing plugged in.
					let label = scope String(pin.name);
					if (side == 0 && pin.type != .Flow)
					{
						bool connected = false;
						for (let link in mGraph.links)
							connected |= link.toNode == node.id && link.toPin == i;
						// An object pin with nothing plugged in uses this object's own, or nothing.
						if (!connected && pin.type == .Object)
							label.AppendF("{}{}", label.IsEmpty ? "" : ": ", NodeLibrary.IsSelf(pin) ? "self" : "none");
						else if (!connected)
							label.AppendF("{}{}", label.IsEmpty ? "" : ": ", node.values[i]);
					}
					if (label.IsEmpty)
						continue;
					let textX = side == 0 ? center.x + 10 * zoom : center.x - 10 * zoom - ImGui.CalcTextSize(label.CStr()).x;
					ImGui.DrawText(.(textX, center.y - 8 * zoom), .(0.85f, 0.85f, 0.85f, 1), label.CStr());
				}
			}
		}
		NodeCanvas.EndFont();

		// ---- mouse: connect, select, drag ----
		if (hovered && ImGui.IsMouseDoubleClicked(0) && hoverNode != null && hoverPin < 0 && hoverNode.def.key.StartsWith("sub:"))
		{
			// Step into the subgraph behind this node.
			Assets.ResolvePath(hoverNode.def.key.Substring(4), mPendingGraph);
		}
		if (hovered && ImGui.IsMouseClicked(0))
		{
			if (hoverPin >= 0 && ImGui.IsKeyDown(ImGui.Key.LeftCtrl) == false && Input.GetKey(.LeftAlt))
				mGraph.DisconnectPin(hoverNode.id, hoverPin, !hoverPinIsOutput);
			else if (hoverPin >= 0)
			{
				mLinking = true;
				mLinkNode = hoverNode.id;
				mLinkPin = hoverPin;
				mLinkFromOutput = hoverPinIsOutput;
			}
			else if (hoverNode != null)
			{
				mGraphSelected = hoverNode.id;
				mGraphDragNode = hoverNode.id;
			}
			else
				mGraphSelected = 0;
		}
		if (mLinking)
		{
			let source = mGraph.Find(mLinkNode);
			if (source != null)
			{
				let start = ToScreen(PinPosition(source, mLinkPin, mLinkFromOutput));
				if (mLinkFromOutput)
					DrawLink(start, mouse, .(1, 1, 1, 0.8f));
				else
					DrawLink(mouse, start, .(1, 1, 1, 0.8f));
			}
			if (!ImGui.IsMouseDown(0))
			{
				// Dropped on a pin of the opposite direction and the same type: connect.
				if (source != null && hoverPin >= 0 && hoverNode.id != mLinkNode && hoverPinIsOutput != mLinkFromOutput)
				{
					let output = mLinkFromOutput ? source : hoverNode;
					let outputPin = mLinkFromOutput ? mLinkPin : hoverPin;
					let input = mLinkFromOutput ? hoverNode : source;
					let inputPin = mLinkFromOutput ? hoverPin : mLinkPin;
					if (mGraph.Links(output.def.outputs[outputPin], input.def.inputs[inputPin]))
						mGraph.Connect(output.id, outputPin, input.id, inputPin);
					else
						mGraphStatus.Set("Those pins have different types.");
				}
				else if (source != null && hovered && hoverNode == null)
				{
					// Dropped on empty canvas: offer the nodes that can take this link.
					OpenNodeSearch(graphMouse, true);
				}
				mLinking = false;
			}
		}
		if (mGraphDragNode != 0)
		{
			let dragged = mGraph.Find(mGraphDragNode);
			if (dragged != null && ImGui.IsMouseDown(0))
				dragged.position = dragged.position + Input.MouseDelta / zoom;
			else
				mGraphDragNode = 0;
		}
		if (hovered && ImGui.IsKeyPressed(ImGui.Key.Delete) && (ImGui.tn_imgui_capture_flags() & 4) == 0)
		{
			let selected = mGraph.Find(mGraphSelected);
			if (selected != null)
				mGraph.RemoveNode(selected);
			mGraphSelected = 0;
		}

		// ---- add-node menu with search ----
		if (hovered && ImGui.IsMouseClicked(1))
		{
			// Pick up subgraphs created or changed since the list was last built.
			NodeLibrary.RefreshSubgraphs(Assets.ProjectPath);
			mGraph.Validate();
			OpenNodeSearch(graphMouse, false);
		}
		if (mOpenNodeSearch)
		{
			ImGui.OpenPopup("AddNode");
			mOpenNodeSearch = false;
			mNodeSearchFocus = true;
		}
		if (ImGui.BeginPopup("AddNode"))
		{
			if (mNodeSearchFocus)
			{
				ImGui.SetKeyboardFocusHere();
				mNodeSearchFocus = false;
			}
			ImGui.SetNextItemWidth(260);
			ImGui.InputText("##nodesearch", mNodeSearch, 0, mSearchForLink ? "Search nodes that fit this pin" : "Search nodes");
			let enter = ImGui.IsKeyPressed(ImGui.Key.Enter);
			NodeDef chosen = null;
			if (mNodeSearch.IsEmpty && !mSearchForLink)
			{
				// Nothing typed: browse by category.
				String category = null;
				bool open = false;
				// Hand-written nodes by category.
				for (let def in NodeLibrary.Defs)
				{
					if (def.fromApi || def.isShader != mGraph.isShader)
						continue;
					if (category == null || category != def.category)
					{
						if (open)
							ImGui.EndMenu();
						category = def.category;
						open = ImGui.BeginMenu(category.CStr());
					}
					if (open && ImGui.MenuItem(def.title.CStr()))
						chosen = def;
				}
				if (open)
					ImGui.EndMenu();
				ImGui.Separator();
				// Everything read from source: the engine by area and then class, the game's own scripts by class.
				void Classes(StringView group, bool game)
				{
					String current = null;
					bool inside = false;
					for (let def in NodeLibrary.Defs)
					{
						if (!def.fromApi || def.fromGame != game || (!game && def.group != group))
							continue;
						if (current == null || current != def.category)
						{
							if (inside)
								ImGui.EndMenu();
							current = def.category;
							inside = ImGui.BeginMenu(current.CStr());
						}
						// Inside a class's menu its name is not repeated on every entry.
						var title = (StringView)def.title;
						if (title.StartsWith(def.category) && title.Length > def.category.Length + 2)
							title = title.Substring(def.category.Length + 2);
						if (inside && ImGui.MenuItem(scope String(title).CStr()))
							chosen = def;
					}
					if (inside)
						ImGui.EndMenu();
				}
				if (!mGraph.isShader && ImGui.BeginMenu("Engine"))
				{
					List<String> groups = scope .();
					for (let def in NodeLibrary.Defs)
					{
						if (def.fromApi && !def.fromGame && !groups.Contains(def.group))
							groups.Add(def.group);
					}
					groups.Sort(scope (a, b) => a.CompareTo(b));
					for (let group in groups)
					{
						if (ImGui.BeginMenu(group.CStr()))
						{
							Classes(group, false);
							ImGui.EndMenu();
						}
					}
					ImGui.EndMenu();
				}
				if (!mGraph.isShader && ImGui.BeginMenu("Game"))
				{
					bool any = false;
					for (let def in NodeLibrary.Defs)
						any |= def.fromApi && def.fromGame;
					if (any)
						Classes("", true);
					else
						ImGui.TextDisabled("Public members of your scripts appear here.");
					ImGui.EndMenu();
				}
			}
			else
			{
				// Typed text narrows the list as you type; names that start with it come first, Enter takes the top one.
				ImGui.BeginChild("matches", .(260, 240));
				int shown = 0;
				for (int pass < 2)
				{
					for (let def in NodeLibrary.Defs)
					{
						if (def.isShader != mGraph.isShader || (mSearchForLink && FirstCompatiblePin(def) < 0))
							continue;
						let starts = mNodeSearch.IsEmpty || def.title.StartsWith(mNodeSearch, .OrdinalIgnoreCase);
						let contains = def.title.Contains(mNodeSearch, true) || def.category.Contains(mNodeSearch, true);
						if ((pass == 0 && !starts) || (pass == 1 && (starts || !contains)))
							continue;
						let label = scope String();
						label.AppendF("{}   ({})", def.title, def.category);
						if (ImGui.Selectable(label.CStr(), shown == 0) || (enter && shown == 0))
							chosen = def;
						shown++;
					}
				}
				if (shown == 0)
					ImGui.TextDisabled("No matching nodes.");
				ImGui.EndChild();
			}
			if (chosen != null)
			{
				let created = mGraph.AddNode(chosen, mNewNodePosition);
				mGraphSelected = created.id;
				if (mSearchForLink)
				{
					// Finish the link that was dragged out to open this search.
					let pin = FirstCompatiblePin(chosen);
					if (pin >= 0 && mLinkFromOutput)
						mGraph.Connect(mLinkNode, mLinkPin, created.id, pin);
					else if (pin >= 0)
						mGraph.Connect(created.id, pin, mLinkNode, mLinkPin);
				}
				ImGui.CloseCurrentPopup();
			}
			ImGui.EndPopup();
		}

		// ---- values of the selected node ----
		let selectedNode = mGraph.Find(mGraphSelected);
		if (selectedNode != null)
		{
			int editable = 0;
			for (let pin in selectedNode.def.inputs)
				editable += pin.type != .Flow ? 1 : 0;
			if (editable > 0)
			{
				ImGui.SetCursorScreenPos(.(origin.x + 10, origin.y + 10));
				ImGui.PushStyleColor(ImGui.Col.ChildBg, .(0.10f, 0.10f, 0.11f, 0.92f));
				ImGui.BeginChild("values", .(250, 34 + editable * 27), ImGui.ChildBorders);
				ImGui.Text(NodeGraph.Title(selectedNode, .. scope String()));
				for (int32 i = 0; i < (int32)selectedNode.def.inputs.Count; i++)
				{
					let pin = selectedNode.def.inputs[i];
					if (pin.type == .Flow)
						continue;
					ImGui.PushID(i);
					ImGui.SetNextItemWidth(150);
					if (pin.type == .Bool)
					{
						bool value = selectedNode.values[i] == "true";
						if (ImGui.Checkbox("##v", ref value))
							selectedNode.values[i].Set(value ? "true" : "false");
					}
					else if (pin.type == .Int)
					{
						int32 value = (int32)SceneSerializer.ParseFloat(selectedNode.values[i]);
						if (ImGui.InputInt("##v", ref value))
							selectedNode.values[i]..Clear().AppendF("{}", value);
					}
					else if (pin.type == .Enum)
					{
						let entry = pin.typeName != null ? ApiIndex.Find(pin.typeName) : null;
						if (selectedNode.values[i].IsEmpty && entry != null && entry.members.Count > 0)
							selectedNode.values[i].Set(entry.members[0]);
						if (ImGui.BeginCombo("##v", selectedNode.values[i].CStr()))
						{
							if (entry != null)
							{
								for (let name in entry.members)
								{
									if (ImGui.Selectable(name.CStr(), name == selectedNode.values[i]))
										selectedNode.values[i].Set(name);
								}
							}
							ImGui.EndCombo();
						}
					}
					else if (pin.type == .Color)
					{
						Color color = .(1, 1, 1, 1);
						var parts = selectedNode.values[i].Split(' ', .RemoveEmptyEntries);
						float* channels = &color.r;
						for (int k < 4)
						{
							if (parts.GetNext() case .Ok(let part))
								channels[k] = SceneSerializer.ParseFloat(part);
						}
						if (ImGui.ColorEdit4("##v", ref color))
							selectedNode.values[i]..Clear().AppendF("{} {} {} {}", color.r, color.g, color.b, color.a);
					}
					else if (pin.type == .Object)
						ImGui.TextDisabled(NodeLibrary.IsSelf(pin) ? "this object's own" : "connect a value");
					else
						ImGui.InputText("##v", selectedNode.values[i], 0, pin.type == .Vector3 || pin.type == .Quaternion ? (char8*)"x y z" : (pin.type == .Vector2 ? (char8*)"x y" : (char8*)""));
					ImGui.SameLine();
					ImGui.Text(pin.name.IsEmpty ? (StringView)"Value" : pin.name);
					ImGui.PopID();
				}
				ImGui.EndChild();
				ImGui.PopStyleColor();
			}
		}
		if (mGraphShowVariables)
			DrawGraphVariables(.(origin.x + size.x - 10, origin.y + 10), NodeCanvas.CenterNode(size, mGraphPan, mGraphZoom));
		ImGui.EndChild();
		ImGui.End();
	}

	/// The Variables panel: each variable becomes a public field of the compiled component, so its default set here
	/// can be changed per object in the Inspector. Get and Set place nodes that read and write it.
	void DrawGraphVariables(ImGui.Vec2 topRight, Vector2 nodePosition)
	{
		const float cWidth = 470;
		ImGui.SetCursorScreenPos(.(topRight.x - cWidth, topRight.y));
		ImGui.PushStyleColor(ImGui.Col.ChildBg, .(0.10f, 0.10f, 0.11f, 0.92f));
		ImGui.BeginChild("variables", .(cWidth, 62 + Math.Min(mGraph.variables.Count, 8) * 27), ImGui.ChildBorders);
		ImGui.Text("Variables");
		ImGui.SameLine();
		if (ImGui.SmallButton("+ Add"))
			mGraph.AddVariable("variable", .Float);
		GraphVariable removed = null;
		for (int i < mGraph.variables.Count)
		{
			let variable = mGraph.variables[i];
			ImGui.PushID((int32)i);
			let name = mVariableEditing == i ? mVariableEdit : scope String(variable.name);
			ImGui.SetNextItemWidth(110);
			if (ImGui.InputText("##name", name) && mVariableEditing != i)
			{
				mVariableEdit.Set(name);
				mVariableEditing = i;
			}
			if (mVariableEditing == i && ImGui.IsItemDeactivatedAfterEdit())
			{
				if (!mGraph.RenameVariable(variable, mVariableEdit))
					mGraphStatus.Set("That variable name is already in use.");
				mVariableEditing = -1;
			}
			ImGui.SameLine();
			ImGui.SetNextItemWidth(84);
			if (ImGui.BeginCombo("##type", TypeLabel(variable.type)))
			{
				for (let type in PinType[?](.Float, .Int, .Vector3, .Bool, .String))
				{
					if (ImGui.Selectable(TypeLabel(type), type == variable.type))
						mGraph.SetVariableType(variable, type);
				}
				ImGui.EndCombo();
			}
			ImGui.SameLine();
			if (variable.type == .Bool)
			{
				bool value = variable.value == "true";
				if (ImGui.Checkbox("##default", ref value))
					variable.value.Set(value ? "true" : "false");
				ImGui.SameLine(322);
			}
			else
			{
				ImGui.SetNextItemWidth(100);
				ImGui.InputText("##default", variable.value, 0, variable.type == .Vector3 ? (char8*)"x y z" : (char8*)"default");
				ImGui.SameLine();
			}
			ImGui.Checkbox("##net", ref variable.networked);
			if (ImGui.IsItemHovered())
				ImGui.SetTooltip("Networked: in multiplayer the server's value is copied to every client.");
			ImGui.SameLine();
			if (ImGui.SmallButton("Get"))
				mGraphSelected = mGraph.AddVariableNode(variable, false, nodePosition).id;
			ImGui.SameLine();
			if (ImGui.SmallButton("Set"))
				mGraphSelected = mGraph.AddVariableNode(variable, true, nodePosition).id;
			ImGui.SameLine();
			if (ImGui.SmallButton("x"))
				removed = variable;
			ImGui.PopID();
		}
		if (removed != null)
		{
			mGraph.RemoveVariable(removed);
			mVariableEditing = -1;
		}
		ImGui.TextDisabled(mGraph.variables.IsEmpty ? "Values you can set per object in the Inspector." : "Defaults; set per object in the Inspector.");
		ImGui.EndChild();
		ImGui.PopStyleColor();
	}

	static char8* TypeLabel(PinType type)
	{
		switch (type)
		{
		case .Bool: return "Boolean";
		case .Vector3: return "Vector";
		case .String: return "Text";
		case .Int: return "Whole";
		default: return "Number";
		}
	}
}
