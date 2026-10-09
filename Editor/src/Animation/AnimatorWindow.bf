using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// The Animator window: the state machine of an Animator Controller (.tcontroller), laid out the way Unity's is.
///   Parameters are on the left. States are boxes on the canvas: the orange one is the default, entered from Entry;
///   Any State stands for "whatever state is current". Right-click the canvas to create a state; right-click a
///   state to make a transition from it (then click the state it goes to), make it the default, or delete it.
///   Click a state or a transition arrow to edit it on the left. Delete removes the selection. Middle-drag pans,
///   the wheel zooms.
/// While the game plays, the selected object's Animator is shown live: its current state is highlighted with a
/// progress bar, and the parameters show (and set) its values.
extension EditorApp
{
	const float cStateWidth = 170;
	const float cStateHeight = 38;
	static Vector2 cAnyStatePosition = .(60, 40);
	static Vector2 cEntryPosition = .(60, 140);

	bool mShowAnimator;
	bool mDockAnimator;
	bool mAnimFocus;
	AnimatorController mAnimController;
	String mAnimControllerPath = new .() ~ delete _;
	Vector2 mAnimPan = .(40, 30);
	float mAnimZoom = 1;
	/// The selected state (-1 for Any State, -2 for none) and transition (-1 for none).
	int32 mAnimState = -2;
	int32 mAnimTransition = -1;
	/// The state a transition is being drawn from (-1 Any State), or -3 when none is.
	int32 mAnimLinkFrom = -3;
	int32 mAnimDragState = -2;
	bool mAnimDirty;
	int32 mAnimMenuState = -2;
	Vector2 mAnimMenuPosition;
	List<String> mAnimClipChoices = new .() ~ DeleteContainerAndItems!(_);
	int mAnimClipChoicesFrame = -1000;

	/// Opens a controller in the Animator window. The path is a file on disk.
	public void OpenAnimator(StringView fullPath)
	{
		let relative = scope String();
		Assets.MakeRelative(fullPath, relative);
		let controller = AnimatorController.Load(relative);
		if (controller == null)
			return;
		mAnimController = controller;
		mAnimControllerPath.Set(relative);
		mAnimState = -2;
		mAnimTransition = -1;
		mAnimLinkFrom = -3;
		mShowAnimator = true;
		mDockAnimator = true;
		mAnimFocus = true;
	}

	void CreateAnimatorAsset(StringView name)
	{
		if (!ProjectGenerator.IsValidName(name))
		{
			Log.Error("Animator controller names use letters, digits and underscores, and start with a letter.");
			return;
		}
		let path = scope $"{mBrowsePath}/{name}.tcontroller";
		if (File.Exists(path))
		{
			Log.Error(scope $"{path} already exists.");
			return;
		}
		// Something to start from: one state, entered by default.
		let controller = scope AnimatorController();
		controller.AddState("Idle", "", .(260, 130));
		controller.Save(path);
		OpenAnimator(path);
	}

	/// The Animator, in play or edit mode, on the selected object or the nearest object above it.
	Animator SelectedAnimator()
	{
		var object = Selected;
		while (object != null)
		{
			let animator = object.GetComponent<Animator>();
			if (animator != null)
				return animator;
			object = object.Transform.Parent?.GameObject;
		}
		return null;
	}

	void SaveAnimator()
	{
		if (mAnimController == null || mAnimControllerPath.IsEmpty)
			return;
		let full = scope String();
		Assets.ResolvePath(mAnimControllerPath, full);
		mAnimController.Save(full);
		mAnimDirty = false;
	}

	/// Every .tanim file in the project, for the clip picker. Refreshed now and then rather than every frame.
	void RefreshClipChoices()
	{
		if (Time.FrameCount - mAnimClipChoicesFrame < 240)
			return;
		mAnimClipChoicesFrame = Time.FrameCount;
		ClearAndDeleteItems!(mAnimClipChoices);
		void Scan(StringView folder, int depth)
		{
			if (depth > 8 || !Directory.Exists(folder))
				return;
			for (let entry in Directory.EnumerateFiles(folder))
			{
				let name = scope String();
				entry.GetFileName(name);
				if (!name.EndsWith(".tanim"))
					continue;
				let relative = new String();
				Assets.MakeRelative(scope $"{folder}/{name}", relative);
				mAnimClipChoices.Add(relative);
			}
			for (let entry in Directory.EnumerateDirectories(folder))
			{
				let name = scope String();
				entry.GetFileName(name);
				if (!name.StartsWith('.') && name != "build")
					Scan(scope $"{folder}/{name}", depth + 1);
			}
		}
		Scan(Assets.ProjectPath, 0);
		mAnimClipChoices.Sort(scope (a, b) => a.CompareTo(b));
	}

	static StringView ConditionLabel(AnimatorConditionMode mode)
	{
		switch (mode)
		{
		case .If: return "is true";
		case .IfNot: return "is false";
		case .Greater: return "greater than";
		case .Less: return "less than";
		case .Equals: return "equals";
		case .NotEqual: return "not equal to";
		}
	}

	Vector2 AnimStatePosition(int32 index) => index == -1 ? cAnyStatePosition : mAnimController.states[index].position;

	void DrawAnimator()
	{
		if (!mShowAnimator)
			return;
		// Follow the selection: an object whose Animator uses another controller switches the window to it.
		let selectedAnimator = SelectedAnimator();
		if (selectedAnimator != null && !selectedAnimator.controller.IsEmpty && selectedAnimator.controller != mAnimControllerPath)
		{
			let controller = AnimatorController.Load(selectedAnimator.controller);
			if (controller != null)
			{
				if (mAnimDirty)
					SaveAnimator();
				mAnimController = controller;
				mAnimControllerPath.Set(selectedAnimator.controller);
				mAnimState = -2;
				mAnimTransition = -1;
			}
		}
		if (mDockAnimator && mAssetCenterDock != 0) { ImGui.SetNextWindowDockID(mAssetCenterDock); mDockAnimator = false; }
		// Brought to the front when a controller is opened (once the layout exists, at start-up).
		if (mAnimFocus && Time.FrameCount > 30)
		{
			ImGui.SetNextWindowFocus();
			mAnimFocus = false;
		}
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(0, 0));
		let visible = ImGui.Begin("Animator", &mShowAnimator, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse);
		ImGui.PopStyleVar();
		if (!visible)
		{
			ImGui.End();
			return;
		}
		if (mAnimController == null)
		{
			ImGui.SetCursorPosX(16);
			ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 14);
			ImGui.TextDisabled("Create a controller with Project > + > Animator Controller, double-click a .tcontroller file,\nor select an object whose Animator has a controller.");
			ImGui.End();
			return;
		}
		let controller = mAnimController;
		// The running Animator to watch: the selected one, if it uses this controller.
		Animator live = (mPlay != .Edit && selectedAnimator != null && selectedAnimator.Controller == controller) ? selectedAnimator : null;
		mAnimState = Math.Min(mAnimState, (int32)controller.states.Count - 1);
		if (mAnimTransition >= controller.transitions.Count)
			mAnimTransition = -1;

		// ---- left: parameters and the selection ----
		ImGui.BeginChild("animleft", .(270, 0), ImGui.ChildBorders);
		ImGui.SetCursorPosX(8);
		ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 6);
		ImGui.Text("Parameters");
		ImGui.SameLine();
		if (ImGui.SmallButton("+##param"))
			ImGui.OpenPopup("AddParameter");
		if (ImGui.BeginPopup("AddParameter"))
		{
			for (let type in AnimatorParameterType[?](.Float, .Int, .Bool, .Trigger))
			{
				let label = scope String();
				type.ToString(label);
				if (ImGui.MenuItem(label.CStr()))
				{
					// A name that is not taken yet.
					let name = scope String();
					for (int n = 0; ; n++)
					{
						name.Clear();
						name.AppendF(n == 0 ? "New {0}" : "New {0} {1}", label, n);
						if (controller.FindParameter(name) < 0)
							break;
					}
					controller.AddParameter(name, type);
					mAnimDirty = true;
				}
			}
			ImGui.EndPopup();
		}
		int32 removeParameter = -1;
		for (int32 i = 0; i < (int32)controller.parameters.Count; i++)
		{
			let parameter = controller.parameters[i];
			ImGui.PushID(i);
			ImGui.SetCursorPosX(8);
			ImGui.SetNextItemWidth(118);
			if (ImGui.InputText("##name", parameter.name))
			{
				controller.Revision++;
				mAnimDirty = true;
			}
			ImGui.SameLine();
			// In play mode the value shown is the running Animator's, and editing it sets it there.
			var value = live != null ? live.GetParameter(i) : parameter.defaultValue;
			bool changed = false;
			ImGui.SetNextItemWidth(72);
			switch (parameter.type)
			{
			case .Float:
				changed = ImGui.DragFloat("##value", ref value, 0.05f);
			case .Int:
				int32 whole = (int32)Math.Round(value);
				changed = ImGui.InputInt("##value", ref whole);
				value = whole;
			case .Bool:
				bool flag = value != 0;
				changed = ImGui.Checkbox("##value", ref flag);
				value = flag ? 1 : 0;
			case .Trigger:
				if (ImGui.SmallButton(value != 0 ? "(set)" : "fire"))
				{
					value = 1;
					changed = live != null;
				}
			}
			if (changed)
			{
				if (live != null)
				{
					switch (parameter.type)
					{
					case .Float: live.SetFloat(parameter.name, value);
					case .Int: live.SetInteger(parameter.name, (int32)value);
					case .Bool: live.SetBool(parameter.name, value != 0);
					case .Trigger: live.SetTrigger(parameter.name);
					}
				}
				else if (parameter.type != .Trigger)
				{
					parameter.defaultValue = value;
					controller.Revision++;
					mAnimDirty = true;
				}
			}
			ImGui.SameLine();
			if (ImGui.SmallButton("x"))
				removeParameter = i;
			ImGui.PopID();
		}
		if (removeParameter >= 0)
		{
			controller.RemoveParameter(removeParameter);
			mAnimDirty = true;
		}
		if (controller.parameters.Count == 0)
		{
			ImGui.SetCursorPosX(8);
			ImGui.TextDisabled("None yet. Scripts set these;\ntransitions test them.");
		}

		ImGui.Dummy(.(0, 8));
		ImGui.Separator();
		ImGui.Dummy(.(0, 4));
		if (mAnimTransition >= 0)
			DrawAnimatorTransition(controller, controller.transitions[mAnimTransition]);
		else if (mAnimState >= 0)
			DrawAnimatorState(controller, controller.states[mAnimState], selectedAnimator);
		else
		{
			ImGui.SetCursorPosX(8);
			ImGui.TextDisabled(mAnimState == -1 ? "Any State: transitions from here\ncan fire from every state." : "Select a state or a transition.");
		}
		ImGui.EndChild();
		ImGui.SameLine(0, 0);

		// ---- right: the state machine ----
		ImGui.BeginChild("animcanvas", .(0, 0), 0, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse | ImGui.WindowFlags.NoMove);
		let origin = ImGui.GetCursorScreenPos();
		let size = ImGui.GetContentRegionAvail();
		ImGui.InvisibleButton("##animcanvas", .(Math.Max(size.x, 1), Math.Max(size.y, 1)));
		let hovered = ImGui.IsItemHovered();
		let mouse = ImGui.GetMousePos();
		NodeCanvas.UpdateView(ref mAnimPan, ref mAnimZoom, origin, mouse, hovered);
		let zoom = mAnimZoom;
		ImGui.Vec2 ToScreen(Vector2 p) => .(origin.x + mAnimPan.x + p.x * zoom, origin.y + mAnimPan.y + p.y * zoom);
		Vector2 ToGraph(ImGui.Vec2 p) => .((p.x - origin.x - mAnimPan.x) / zoom, (p.y - origin.y - mAnimPan.y) / zoom);
		NodeCanvas.DrawGrid(origin, size, mAnimPan, zoom);
		NodeCanvas.BeginFont(zoom);
		let graphMouse = ToGraph(mouse);
		Vector2 Center(int32 state) => AnimStatePosition(state) + Vector2(cStateWidth * 0.5f, cStateHeight * 0.5f);

		// Which state is under the mouse (-2 none).
		int32 hoverState = -2;
		if (hovered)
		{
			for (int32 i = (int32)controller.states.Count - 1; i >= -1; i--)
			{
				let p = AnimStatePosition(i);
				if (graphMouse.x >= p.x && graphMouse.x <= p.x + cStateWidth && graphMouse.y >= p.y && graphMouse.y <= p.y + cStateHeight)
				{
					hoverState = i;
					break;
				}
			}
		}

		// ---- transitions ----
		int32 hoverTransition = -1;
		void Arrow(Vector2 from, Vector2 to, Color color, float thickness)
		{
			let a = ToScreen(from), b = ToScreen(to);
			ImGui.DrawLine(a, b, color, thickness);
			// An arrowhead in the middle, pointing the way the transition goes.
			let direction = (to - from).Normalized;
			let side = Vector2(-direction.y, direction.x);
			let middle = (from + to) * 0.5f;
			let tip = ToScreen(middle + direction * 8);
			ImGui.DrawLine(tip, ToScreen(middle - direction * 6 + side * 7), color, thickness);
			ImGui.DrawLine(tip, ToScreen(middle - direction * 6 - side * 7), color, thickness);
		}
		for (int32 i = 0; i < (int32)controller.transitions.Count; i++)
		{
			let transition = controller.transitions[i];
			var from = Center(transition.from), to = Center(transition.to);
			if (from == to)
				continue;
			// Two transitions between the same pair run side by side instead of on top of each other.
			let direction = (to - from).Normalized;
			let offset = Vector2(-direction.y, direction.x) * 9;
			from += offset;
			to += offset;
			// Distance from the mouse to the line, for picking.
			let along = Mathf.Clamp(Vector2.Dot(graphMouse - from, direction), 0, (to - from).Length);
			let nearest = from + direction * along;
			if (hovered && hoverState == -2 && (graphMouse - nearest).Length < 7 / Math.Max(zoom, 0.3f))
				hoverTransition = i;
			let selected = i == mAnimTransition;
			Arrow(from, to, selected ? Color(0.45f, 0.70f, 1, 1) : (hoverTransition == i ? Color(1, 1, 1, 1) : Color(0.75f, 0.75f, 0.78f, 0.9f)), (selected ? 2.4f : 1.5f) * zoom);
		}
		if (controller.states.Count > 0)
			Arrow(cEntryPosition + Vector2(cStateWidth * 0.5f, cStateHeight * 0.5f), Center(Math.Clamp(controller.defaultState, 0, (int32)controller.states.Count - 1)), .(0.90f, 0.62f, 0.20f, 0.9f), 1.5f * zoom);
		if (mAnimLinkFrom != -3)
			Arrow(Center(mAnimLinkFrom), graphMouse, .(1, 1, 1, 0.9f), 1.5f * zoom);

		// ---- states ----
		void Box(Vector2 position, StringView label, Color color, bool selected, float progress)
		{
			let min = ToScreen(position), max = ToScreen(position + Vector2(cStateWidth, cStateHeight));
			ImGui.DrawRectFilled(min, max, color, 5 * zoom);
			if (progress >= 0)
				ImGui.DrawRectFilled(.(min.x, max.y - 5 * zoom), .(min.x + (max.x - min.x) * Mathf.Clamp01(progress), max.y), .(0.35f, 0.65f, 1, 1), 2 * zoom);
			ImGui.DrawRect(min, max, selected ? Color(0.45f, 0.70f, 1, 1) : Color(0, 0, 0, 0.8f), 5 * zoom, selected ? 2.5f : 1);
			let text = scope String(label);
			let textSize = ImGui.CalcTextSize(text.CStr());
			ImGui.DrawText(.((min.x + max.x - textSize.x) * 0.5f, (min.y + max.y - textSize.y) * 0.5f), .(1, 1, 1, 1), text.CStr());
		}
		Box(cAnyStatePosition, "Any State", .(0.20f, 0.52f, 0.52f, 1), mAnimState == -1 && mAnimTransition < 0, -1);
		Box(cEntryPosition, "Entry", .(0.20f, 0.50f, 0.25f, 1), false, -1);
		for (int32 i = 0; i < (int32)controller.states.Count; i++)
		{
			let state = controller.states[i];
			let isLive = live != null && live.CurrentStateIndex == i;
			var color = i == controller.defaultState ? Color(0.78f, 0.48f, 0.14f, 1) : Color(0.32f, 0.32f, 0.35f, 1);
			if (isLive)
				color = .(0.22f, 0.40f, 0.68f, 1);
			let progress = isLive ? (state.loop ? live.NormalizedTime % 1.0f : live.NormalizedTime) : -1;
			Box(state.position, state.name, color, mAnimState == i && mAnimTransition < 0, progress);
		}
		NodeCanvas.EndFont();

		// ---- mouse ----
		if (hovered && ImGui.IsMouseClicked(0))
		{
			if (mAnimLinkFrom != -3)
			{
				// Finishing a transition: it goes to the state clicked. Nothing goes to Any State.
				if (hoverState >= 0 && hoverState != mAnimLinkFrom)
				{
					let transition = controller.AddTransition(mAnimLinkFrom, hoverState);
					// From Any State a transition needs a condition to mean anything; from a state, waiting for
					// the clip to end is the usual default.
					transition.hasExitTime = mAnimLinkFrom >= 0;
					mAnimTransition = (int32)controller.transitions.Count - 1;
					mAnimDirty = true;
				}
				mAnimLinkFrom = -3;
			}
			else if (hoverState != -2)
			{
				mAnimState = hoverState;
				mAnimTransition = -1;
				mAnimDragState = hoverState >= 0 ? hoverState : -2;
			}
			else if (hoverTransition >= 0)
				mAnimTransition = hoverTransition;
			else
			{
				mAnimState = -2;
				mAnimTransition = -1;
			}
		}
		if (mAnimDragState >= 0 && mAnimDragState < controller.states.Count && ImGui.IsMouseDown(0))
		{
			if (ImGui.IsMouseDragging(0, 2))
			{
				controller.states[mAnimDragState].position += Input.MouseDelta / zoom;
				mAnimDirty = true;
			}
		}
		else
			mAnimDragState = -2;
		if (hovered && ImGui.IsMouseClicked(1))
		{
			mAnimLinkFrom = -3;
			mAnimMenuState = hoverState;
			mAnimMenuPosition = graphMouse;
			ImGui.OpenPopup("AnimatorMenu");
		}
		if (ImGui.BeginPopup("AnimatorMenu"))
		{
			if (mAnimMenuState == -2)
			{
				if (ImGui.MenuItem("Create State"))
				{
					let name = scope String();
					for (int n = 0; ; n++)
					{
						name.Clear();
						name.AppendF(n == 0 ? "New State" : "New State {0}", n);
						if (controller.FindState(name) < 0)
							break;
					}
					controller.AddState(name, "", mAnimMenuPosition);
					mAnimState = (int32)controller.states.Count - 1;
					mAnimTransition = -1;
					mAnimDirty = true;
				}
			}
			else
			{
				if (ImGui.MenuItem("Make Transition"))
					mAnimLinkFrom = mAnimMenuState;
				if (mAnimMenuState >= 0)
				{
					if (ImGui.MenuItem("Set as Default State"))
					{
						controller.defaultState = mAnimMenuState;
						controller.Revision++;
						mAnimDirty = true;
					}
					if (ImGui.MenuItem("Delete"))
					{
						controller.RemoveState(mAnimMenuState);
						mAnimState = -2;
						mAnimTransition = -1;
						mAnimDirty = true;
					}
				}
			}
			ImGui.EndPopup();
		}
		if (hovered && ImGui.IsKeyPressed(ImGui.Key.Delete))
		{
			if (mAnimTransition >= 0)
			{
				delete controller.transitions[mAnimTransition];
				controller.transitions.RemoveAt(mAnimTransition);
				controller.Revision++;
				mAnimTransition = -1;
				mAnimDirty = true;
			}
			else if (mAnimState >= 0)
			{
				controller.RemoveState(mAnimState);
				mAnimState = -2;
				mAnimDirty = true;
			}
		}
		if (ImGui.IsKeyPressed(ImGui.Key.Escape))
			mAnimLinkFrom = -3;

		// Status line, top left of the canvas.
		let status = scope String();
		status.Append(mAnimControllerPath);
		if (live != null)
			status.AppendF("   Watching: {}  ({})", live.GameObject.Name, live.CurrentState);
		else if (mAnimLinkFrom != -3)
			status.Append("   Click the state this transition goes to (Esc cancels).");
		ImGui.DrawText(.(origin.x + 8, origin.y + 6), .(1, 1, 1, 0.55f), status.CStr());
		ImGui.EndChild();
		ImGui.End();

		// Changes are written as soon as the mouse is let go, so there is no separate save step to forget.
		if (mAnimDirty && !ImGui.IsMouseDown(0))
			SaveAnimator();
	}

	void DrawAnimatorState(AnimatorController controller, AnimatorController.State state, Animator selectedAnimator)
	{
		ImGui.SetCursorPosX(8);
		ImGui.Text("State");
		ImGui.SetCursorPosX(8);
		ImGui.SetNextItemWidth(170);
		if (ImGui.InputText("Name##state", state.name))
		{
			controller.Revision++;
			mAnimDirty = true;
		}
		ImGui.SetCursorPosX(8);
		ImGui.SetNextItemWidth(170);
		if (ImGui.BeginCombo("Clip##state", state.clip.IsEmpty ? (char8*)"(none)" : state.clip.CStr()))
		{
			RefreshClipChoices();
			if (ImGui.Selectable("(none)", state.clip.IsEmpty))
			{
				state.clip.Clear();
				mAnimDirty = true;
			}
			for (let choice in mAnimClipChoices)
			{
				if (ImGui.Selectable(choice.CStr(), choice == state.clip))
				{
					state.clip.Set(choice);
					mAnimDirty = true;
				}
			}
			// Clips inside the selected object's skinned model are named, not files.
			let skinned = selectedAnimator != null ? FindSkinned(selectedAnimator) : null;
			if (skinned != null && skinned.Model != null)
			{
				for (let clip in skinned.Model.Clips)
				{
					let label = scope String();
					label.AppendF("{}  (model)", clip.name);
					if (ImGui.Selectable(label.CStr(), clip.name == state.clip))
					{
						state.clip.Set(clip.name);
						mAnimDirty = true;
					}
				}
			}
			ImGui.EndCombo();
		}
		ImGui.SetCursorPosX(8);
		ImGui.SetNextItemWidth(170);
		if (ImGui.DragFloat("Speed##state", ref state.speed, 0.02f))
			mAnimDirty = true;
		ImGui.SetCursorPosX(8);
		if (ImGui.Checkbox("Loop##state", ref state.loop))
			mAnimDirty = true;
		if (mAnimDirty)
			controller.Revision++;
	}

	static SkinnedMeshRenderer FindSkinned(Animator animator)
	{
		let own = animator.GetComponent<SkinnedMeshRenderer>();
		if (own != null)
			return own;
		for (let child in animator.Transform.Children)
		{
			let found = child.GameObject.GetComponent<SkinnedMeshRenderer>();
			if (found != null)
				return found;
		}
		return null;
	}

	void DrawAnimatorTransition(AnimatorController controller, AnimatorController.Transition transition)
	{
		ImGui.SetCursorPosX(8);
		let title = scope String();
		title.AppendF("{}  ->  {}", transition.from < 0 ? (StringView)"Any State" : controller.states[transition.from].name, controller.states[transition.to].name);
		ImGui.Text(title);
		ImGui.SetCursorPosX(8);
		if (ImGui.Checkbox("Has Exit Time", ref transition.hasExitTime))
			mAnimDirty = true;
		if (transition.hasExitTime)
		{
			ImGui.SetCursorPosX(8);
			ImGui.SetNextItemWidth(120);
			if (ImGui.DragFloat("Exit Time", ref transition.exitTime, 0.01f, 0, 100))
				mAnimDirty = true;
		}
		ImGui.SetCursorPosX(8);
		ImGui.SetNextItemWidth(120);
		if (ImGui.DragFloat("Duration (s)", ref transition.duration, 0.01f, 0, 10))
			mAnimDirty = true;
		ImGui.Dummy(.(0, 4));
		ImGui.SetCursorPosX(8);
		ImGui.Text("Conditions");
		ImGui.SameLine();
		ImGui.BeginDisabled(controller.parameters.Count == 0);
		if (ImGui.SmallButton("+##condition"))
		{
			AnimatorController.Condition condition;
			condition.parameter = 0;
			condition.threshold = 0;
			condition.mode = controller.parameters[0].type == .Float || controller.parameters[0].type == .Int ? .Greater : .If;
			transition.conditions.Add(condition);
			mAnimDirty = true;
		}
		ImGui.EndDisabled();
		int remove = -1;
		for (int i < transition.conditions.Count)
		{
			var condition = ref transition.conditions[i];
			condition.parameter = Math.Clamp(condition.parameter, 0, (int32)controller.parameters.Count - 1);
			if (condition.parameter < 0)
				continue;
			let parameter = controller.parameters[condition.parameter];
			ImGui.PushID((int32)i + 1000);
			ImGui.SetCursorPosX(8);
			ImGui.SetNextItemWidth(92);
			if (ImGui.BeginCombo("##parameter", parameter.name.CStr()))
			{
				for (int32 p = 0; p < (int32)controller.parameters.Count; p++)
				{
					if (ImGui.Selectable(controller.parameters[p].name.CStr(), p == condition.parameter))
					{
						condition.parameter = p;
						let numeric = controller.parameters[p].type == .Float || controller.parameters[p].type == .Int;
						condition.mode = numeric ? .Greater : .If;
						mAnimDirty = true;
					}
				}
				ImGui.EndCombo();
			}
			let numeric = parameter.type == .Float || parameter.type == .Int;
			if (parameter.type != .Trigger)
			{
				ImGui.SameLine();
				ImGui.SetNextItemWidth(92);
				if (ImGui.BeginCombo("##mode", scope String(ConditionLabel(condition.mode)).CStr()))
				{
					for (let mode in AnimatorConditionMode[?](.If, .IfNot, .Greater, .Less, .Equals, .NotEqual))
					{
						// Numbers are compared; booleans are simply true or false.
						if ((mode == .If || mode == .IfNot) == numeric)
							continue;
						if (parameter.type == .Float && (mode == .Equals || mode == .NotEqual))
							continue;
						if (ImGui.Selectable(scope String(ConditionLabel(mode)).CStr(), mode == condition.mode))
						{
							condition.mode = mode;
							mAnimDirty = true;
						}
					}
					ImGui.EndCombo();
				}
			}
			if (numeric)
			{
				ImGui.SameLine();
				ImGui.SetNextItemWidth(46);
				if (ImGui.DragFloat("##threshold", ref condition.threshold, parameter.type == .Int ? 1 : 0.05f))
					mAnimDirty = true;
			}
			ImGui.SameLine();
			if (ImGui.SmallButton("x"))
				remove = i;
			ImGui.PopID();
		}
		if (remove >= 0)
		{
			transition.conditions.RemoveAt(remove);
			mAnimDirty = true;
		}
		if (transition.conditions.Count == 0 && !transition.hasExitTime)
		{
			ImGui.SetCursorPosX(8);
			ImGui.TextDisabled("With no condition and no exit\ntime, this never fires.");
		}
		if (mAnimDirty)
			controller.Revision++;
	}
}
