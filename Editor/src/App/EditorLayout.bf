using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// Per-frame editor UI: dock layout, menu bar and toolbar.
extension EditorApp
{
	void DrawUI()
	{
		// Outside play mode the Scene view's camera is the listener, so sounds can be auditioned where you look from.
		Audio.EditorListening = mPlay == .Edit;
		if (Audio.EditorListening)
		{
			let look = Quaternion.Euler(mCamPitch, mCamYaw, 0);
			Audio.SetListener(mCamPosition, look * Vector3.Forward, look * Vector3.Up);
		}
		DrawMenuBar();
		DrawToolbar();

		let viewport = ImGui.GetMainViewport();
		let dockId = ImGui.GetID("TesseraDock");
		if (!mLayoutBuilt || mResetLayout)
		{
			BuildDefaultLayout(dockId, viewport.workSize);
			mLayoutBuilt = true;
			mResetLayout = false;
		}
		// Leave room for the toolbar strip under the menu bar.
		let toolbarHeight = ImGui.GetFrameHeight() + 10;
		ImGui.SetNextWindowPos(.(viewport.workPos.x, viewport.workPos.y + toolbarHeight));
		ImGui.SetNextWindowSize(.(viewport.workSize.x, viewport.workSize.y - toolbarHeight));
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(0, 0));
		ImGui.Begin("##DockHost", null, ImGui.WindowFlags.NoDecoration | ImGui.WindowFlags.NoMove | ImGui.WindowFlags.NoDocking
			| ImGui.WindowFlags.NoBringToFrontOnFocus | ImGui.WindowFlags.NoNavFocus | ImGui.WindowFlags.NoSavedSettings | ImGui.WindowFlags.NoBackground);
		ImGui.PopStyleVar();
		DockSpace(dockId);
		ImGui.End();

		DrawHierarchy();
		DrawInspector();
		DrawProject();
		DrawConsole();
		DrawGameView();
		DrawSceneView();
		DrawScripts();
		DrawGraph();
		DrawBehavior();
		DrawAnimator();
		DrawAnimation();
		DrawUIEditor();
		DrawPopups();
		DrawProjectSettings();
		DrawBuildWindow();
		DrawAchievements();
		DrawInputActions();
		CommitUndoWhenIdle();
		if (mShowScene)
		{
			ImGui.SetWindowFocus("Scene");
			mShowScene = false;
		}
		if (mFocusScene && Time.FrameCount > 4)
		{
			// Scene is the tab shown when the editor opens, whatever tab the saved layout had in
			// front. Repeated for a few frames because docking settles over the first frames.
			if (mScripts.Count == 0 && mGraph == null && mUiData == null)
				ImGui.SetWindowFocus("Scene");
			if (Time.FrameCount > 10)
				mFocusScene = false;
		}
		if (mFocusGame && Time.FrameCount > 3)
		{
			// Bring the Game tab forward once every panel exists this frame.
			ImGui.SetWindowFocus("Game");
			mFocusGame = false;
		}
		if (mShowDemo)
			ImGui.ShowDemoWindow(&mShowDemo);
		HandleShortcuts();
	}

	[CLink] static extern uint32 igDockSpace(uint32 id, ImGui.Vec2 size, int32 flags, void* windowClass);

	void DockSpace(uint32 id)
	{
		igDockSpace(id, .(0, 0), 0, null);
	}

	void BuildDefaultLayout(uint32 dockId, ImGui.Vec2 size)
	{
		ImGui.DockBuilderRemoveNode(dockId);
		ImGui.DockBuilderAddNode(dockId, ImGui.DockFlags.DockSpace);
		ImGui.DockBuilderSetNodeSize(dockId, size);
		uint32 left, right, bottom, center, rest;
		ImGui.DockBuilderSplitNode(dockId, ImGui.Dir.Left, 0.17f, out left, out rest);
		ImGui.DockBuilderSplitNode(rest, ImGui.Dir.Right, 0.26f, out right, out rest);
		ImGui.DockBuilderSplitNode(rest, ImGui.Dir.Down, 0.28f, out bottom, out center);
		mAssetCenterDock = center;
		mBottomDock = bottom;
        ImGui.DockBuilderDockWindow("Hierarchy", left);
		ImGui.DockBuilderDockWindow("Inspector", right);
		ImGui.DockBuilderDockWindow("Project", bottom);
		ImGui.DockBuilderDockWindow("Console", bottom);
		// Tab order follows docking order: Game, Scene, then Scripts on the far right.
		ImGui.DockBuilderDockWindow("Game", center);
		ImGui.DockBuilderDockWindow("Scene", center);
		mFocusScene = true;
		ImGui.DockBuilderFinish(dockId);
	}

	void DrawMenuBar()
	{
		if (!ImGui.BeginMainMenuBar())
			return;
		if (ImGui.BeginMenu("File"))
		{
			if (ImGui.MenuItem("New Scene")) NewScene();
			if (ImGui.MenuItem("Save Scene", "Ctrl+S")) SaveScene();
			if (ImGui.MenuItem("Save Scene As...")) mOpenSaveAs = true;
			ImGui.Separator();
			if (ImGui.MenuItem("Reload Scripts", "Ctrl+R")) RequestRebuild();
            if (ImGui.MenuItem("Full Rebuild & Restart")) { SaveAllScripts(); mWantFullRestart=true; mBusyFrames=3; }
			if (ImGui.MenuItem("Project Settings...")) mShowSettings = true;
			if (ImGui.MenuItem("Build...")) OpenBuildWindow();
			ImGui.Separator();
			if (ImGui.MenuItem("Open Project Folder"))
			{
				Terminal.Open(Project.Current.Path);
			}
			if (ImGui.MenuItem("Exit")) Running = false;
			ImGui.EndMenu();
		}
		if (ImGui.BeginMenu("Edit"))
		{
			if (ImGui.MenuItem("Undo", "Ctrl+Z", false, CanUndo)) Undo();
			if (ImGui.MenuItem("Redo", "Ctrl+Y", false, CanRedo)) Redo();
			ImGui.Separator();
			if (ImGui.MenuItem("Duplicate", "Ctrl+D", false, Selected != null)) DuplicateSelected();
			if (ImGui.MenuItem("Delete", "Del", false, Selected != null)) DeleteSelected();
			if (ImGui.MenuItem("Frame Selected", "F", false, Selected != null)) FocusSelected();
			ImGui.Separator();
			if (ImGui.MenuItem("Play / Stop", "Ctrl+P")) TogglePlay();
			ImGui.EndMenu();
		}
		if (ImGui.BeginMenu("GameObject"))
		{
			DrawCreateMenu();
			ImGui.EndMenu();
		}
		if (ImGui.BeginMenu("Window"))
		{
			if (ImGui.MenuItem("Achievements")) mShowAchievements = true;
			if (ImGui.MenuItem("Input Actions")) mShowInputActions = true;
			if (ImGui.MenuItem("Animator")) { mShowAnimator = true; mDockAnimator = true; }
			if (ImGui.MenuItem("Animation")) mShowAnimation = true;
			if (ImGui.MenuItem("Reset Layout")) mResetLayout = true;
			if (ImGui.MenuItem("Scene Grid", null, mShowGrid)) mShowGrid = !mShowGrid;
			if (ImGui.MenuItem("ImGui Demo")) mShowDemo = true;
			ImGui.EndMenu();
		}
		let label = scope String();
		label.AppendF("{}{}  |  {:0} fps", mScene.Name, mDirty ? "*" : "", Time.SmoothedFps);
		let width = ImGui.CalcTextSize(label.CStr()).x;
		ImGui.SetCursorPosX(ImGui.GetWindowWidth() - width - 16);
		ImGui.TextDisabled(label.CStr());
		ImGui.EndMainMenuBar();
	}

	void DrawCreateMenu()
	{
		if (ImGui.MenuItem("Create Empty")) CreateObject("GameObject");
		if (ImGui.MenuItem("Spawn Point"))
		{
			CreateObject("Spawn Point").AddComponent<SpawnPoint>();
			MarkDirty();
		}
		if (ImGui.MenuItem("Audio Source"))
		{
			CreateObject("Audio Source").AddComponent<AudioSource>();
			MarkDirty();
		}
		if (ImGui.MenuItem("Folder"))
		{
			// Folders sit at the origin with an identity transform so they never move their contents.
			let parent = Selected;
			let folder = mScene.CreateGameObject("New Folder", (parent != null && parent.IsFolder) ? parent.Transform : null);
			folder.IsFolder = true;
			mSelectedId = folder.Id;
			MarkDirty();
		}
		if (ImGui.BeginMenu("3D Object"))
		{
			if (ImGui.MenuItem("Cube")) CreateObject("Cube", "builtin:cube");
			if (ImGui.MenuItem("Sphere")) CreateObject("Sphere", "builtin:sphere");
			if (ImGui.MenuItem("Capsule")) CreateObject("Capsule", "builtin:capsule");
			if (ImGui.MenuItem("Cylinder")) CreateObject("Cylinder", "builtin:cylinder");
			if (ImGui.MenuItem("Cone")) CreateObject("Cone", "builtin:cone");
			if (ImGui.MenuItem("Plane")) CreateObject("Plane", "builtin:plane");
			if (ImGui.MenuItem("Quad")) CreateObject("Quad", "builtin:quad");
			ImGui.EndMenu();
		}
		if (ImGui.BeginMenu("Light"))
		{
			if (ImGui.MenuItem("Directional Light"))
			{
				let o = CreateObject("Directional Light");
				o.AddComponent<Light>();
				o.Transform.EulerAngles = .(50, -30, 0);
			}
			if (ImGui.MenuItem("Point Light"))
			{
				let light = CreateObject("Point Light").AddComponent<Light>();
				light.type = .Point;
				light.intensity = 5;
			}
			if (ImGui.MenuItem("Spot Light"))
			{
				let o = CreateObject("Spot Light");
				let light = o.AddComponent<Light>();
				light.type = .Spot;
				light.intensity = 8;
				o.Transform.EulerAngles = .(90, 0, 0);
			}
			ImGui.EndMenu();
		}
		if (ImGui.MenuItem("Camera")) CreateObject("Camera").AddComponent<Camera>();
		if (ImGui.MenuItem("Particle System")) CreateObject("Particles").AddComponent<ParticleSystem>();
		if (ImGui.MenuItem("Destructible Voxel Object"))
		{
			let o = CreateObject("Voxel Object");
			o.AddComponent<VoxelObject>();
			o.AddComponent<MeshCollider>();
		}
		if (ImGui.MenuItem("Voxel Terrain"))
		{
			mSelectedId = 0;
			let o = CreateObject("Terrain");
			// A flat area to shape, centred on the origin.
			let terrain = o.AddComponent<VoxelTerrain>();
			let area = terrain.AreaSize;
			o.Transform.Position = .(-area.x * 0.5f, 0, -area.y * 0.5f);
		}
		if (ImGui.MenuItem("Network Session"))
		{
			mSelectedId = 0;
			CreateObject("Network Session").AddComponent<NetworkSession>();
		}
	}

	void RequestRebuild()
	{
		mWantRebuild = true;
		mBusyFrames = 3;
		mStatus.Set("Compiling scripts...");
	}

	void TogglePlay()
	{
		if (mPlay == .Edit) StartPlay(); else StopPlay();
	}

	void DuplicateSelected()
	{
		let selected = Selected;
		if (selected == null)
			return;
		let copy = Duplicate(selected, selected.Transform.Parent);
		mSelectedId = copy.Id;
		MarkDirty();
	}

	bool ToolButton(char8* label, bool active, float width = 0)
	{
		if (active)
			ImGui.PushStyleColor(ImGui.Col.Button, .(0.24f, 0.44f, 0.66f, 1));
		let pressed = ImGui.Button(label, .(width, 0));
		if (active)
			ImGui.PopStyleColor();
		return pressed;
	}

	void DrawToolbar()
	{
		let viewport = ImGui.GetMainViewport();
		let height = ImGui.GetFrameHeight() + 10;
		ImGui.SetNextWindowPos(viewport.workPos);
		ImGui.SetNextWindowSize(.(viewport.workSize.x, height));
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(8, 5));
		ImGui.PushStyleVar(ImGui.StyleVar.WindowBorderSize, 0.0f);
		ImGui.Begin("##Toolbar", null, ImGui.WindowFlags.NoDecoration | ImGui.WindowFlags.NoMove | ImGui.WindowFlags.NoDocking
			| ImGui.WindowFlags.NoSavedSettings | ImGui.WindowFlags.NoBringToFrontOnFocus | ImGui.WindowFlags.NoScrollWithMouse);
		ImGui.PopStyleVar(2);

		if (ToolButton("Move", mGizmoOperation == 0)) mGizmoOperation = 0;
		ImGui.SameLine();
		if (ToolButton("Rotate", mGizmoOperation == 1)) mGizmoOperation = 1;
		ImGui.SameLine();
		if (ToolButton("Scale", mGizmoOperation == 2)) mGizmoOperation = 2;
		ImGui.SameLine(0, 16);
		if (ImGui.Button(mGizmoLocal ? "Local" : "Global", .(64, 0))) mGizmoLocal = !mGizmoLocal;

		// Play controls sit in the middle like Unity's.
		let buttonWidth = 64.0f;
		ImGui.SameLine(viewport.workSize.x * 0.5f - buttonWidth * 1.5f - 6);
		// Capture the state first: pressing the button changes it before the matching pop.
		let wasPlaying = mPlay != .Edit;
		if (wasPlaying)
			ImGui.PushStyleColor(ImGui.Col.Button, .(0.20f, 0.46f, 0.72f, 1));
		if (ImGui.Button(wasPlaying ? Icons.StopLabel : Icons.PlayLabel, .(buttonWidth, 0)))
			TogglePlay();
		if (wasPlaying)
			ImGui.PopStyleColor();
		ImGui.SameLine();
		ImGui.BeginDisabled(mPlay == .Edit);
		if (ToolButton(Icons.PauseLabel, mPlay == .Paused, buttonWidth))
			mPlay = mPlay == .Paused ? .Playing : .Paused;
		ImGui.SameLine();
		if (ImGui.Button(Icons.StepLabel, .(buttonWidth, 0)) && mPlay == .Paused)
		{
			mScene.FixedUpdate();
			mScene.Update();
		}
		ImGui.EndDisabled();
		ImGui.SameLine(0, 16);
		if (ToolButton("Lock Mouse", mLockMouse))
			mLockMouse = !mLockMouse;
		if (ImGui.IsItemHovered())
			ImGui.SetTooltip("Let the game keep the mouse inside the Game view while you play (games ask with Input.LockCursor). Esc frees it.");

		if (!mStatus.IsEmpty)
		{
			ImGui.SameLine(0, 24);
			ImGui.TextColored(.(1, 0.82f, 0.35f, 1), mStatus.CStr());
		}
		else if (mScene.Network != null && mScene.Network.Mode != .Offline)
		{
			let network = mScene.Network;
			let text = scope String();
			if (network.IsServer)
				text.AppendF("{}: {} client(s), tick {}, {:0.0} kB/s out, {:0.0} in", network.Mode, network.ClientCount, network.Tick, network.BytesSentPerSecond / 1000.0f, network.BytesReceivedPerSecond / 1000.0f);
			else
				text.AppendF("Client {}: {} corrections, {} ticks ahead, {:0.0} kB/s out, {:0.0} in", network.LocalClientId, network.Rollbacks, network.PendingInputs, network.BytesSentPerSecond / 1000.0f, network.BytesReceivedPerSecond / 1000.0f);
			ImGui.SameLine(0, 24);
			ImGui.TextDisabled(text.CStr());
		}
		ImGui.End();
	}
}
