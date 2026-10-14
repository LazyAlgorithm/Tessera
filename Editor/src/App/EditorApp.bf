using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// The Tessera editor: Hierarchy, Scene, Game, Inspector, Project and Console panels around
/// a dockable workspace, with Play / Pause / Stop running the scene in place.
class EditorApp : Application
{
	enum PlayState { Edit, Playing, Paused }

	const uint16 ImGuiView = 250;
	static readonly Color cAccent = .(0.36f, 0.62f, 0.92f, 1);

	Scene mScene ~ delete _;
	RenderView mSceneView ~ delete _;
	RenderView mGameView ~ delete _;
	PlayState mPlay = .Edit;
	String mSnapshot = new .() ~ delete _;
    uint32 mPrePlaySelection;
    bool mPrePlayDirty;
	String mIniPath = new .() ~ delete _;
	String mBrowsePath = new .() ~ delete _;
	String mComponentSearch = new .() ~ delete _;
    ComponentClipboard mComponentClipboard = new .() ~ delete _;
    bool mFocusComponentSearch;
	String mHierarchySearch = new .() ~ delete _;
	String mNewScriptName = new .("NewScript") ~ delete _;
	String mSceneSaveName = new .() ~ delete _;
	String mStatus = new .() ~ delete _;
	uint32 mSelectedId;
	bool mDirty;
	bool mLayoutBuilt;
	bool mResetLayout;
	bool mGameFocused;
	/// Toolbar button: games may lock the mouse to the Game view while it is being played in.
	bool mLockMouse = true;
	/// Escape was pressed while the mouse was locked: the lock stays off until the Game view is clicked again.
	bool mLockHeldOff;
	bool mSceneHovered;
	bool mFlying;
	bool mWantRebuild;
	bool mWantBuildGame;
	int32 mBusyFrames;
	bool mOpenNewScript;
	bool mOpenSaveAs;
	bool mFocusGame;
	bool mShowDemo;
	bool mFocusScene = true;
	/// Bring the Scene view to the front now, whatever else is open (set when a prefab is opened).
	bool mShowScene;
    uint32 mAssetCenterDock;
    uint32 mBottomDock;
    bool mShowScripts; bool mShowGraph; bool mShowUI;
    bool mDockScripts; bool mDockGraph; bool mDockUI;
	int32 mLogVersion;

	// Scene view camera and tools.
	Vector3 mCamPosition = .(9, 7, -12);
	float mCamYaw = -35;
	float mCamPitch = 24;
	int32 mGizmoOperation = 0;
	bool mGizmoLocal = true;
	bool mShowGrid = true;
	CameraData mSceneCamera;
	ImGui.Vec2 mSceneSize = .(640, 360);
	ImGui.Vec2 mGameSize = .(640, 360);

	public this()
	{
		// The window is the editor's; a game played in it cannot take the whole screen.
		GameWindow.Allowed = false;
		StartMaximized = true;
		Title.Set("Tessera");
	}

	GameObject Selected => mSelectedId != 0 ? mScene.FindById(mSelectedId) : null;

	// ------------------------------------------------------------------ lifecycle

	protected override bool OnInit()
	{
		let project = Project.Current;
		Title.Set(scope $"Tessera - {project.Name}");
		SDL.SDL_SetWindowTitle(Window, Title.CStr());
		if (!project.EngineRoot.IsEmpty)
			SetWindowIcon(scope $"{project.EngineRoot}/icon.png");
		RecentProjects.Load();
		RecentProjects.Add(project.Path);

		RecentProjects.GetConfigFolder(mIniPath);
		mIniPath.AppendF("layout5_{}.ini", project.Name);
		mLayoutBuilt = File.Exists(mIniPath);
		if (!ImGui.tn_imgui_init(Window, mIniPath.CStr(), 1.0f))
			return false;

		mBrowsePath.Set(Assets.ProjectPath);
        InitializeScriptReload();
		mSceneView = new RenderView(10);
		mSceneView.DrawGizmos = true;
		// Depth of field and motion blur get in the way of editing (Scene Settings > Screen Effects can show them).
		mSceneView.ShowDepthOfField = false;
		mSceneView.ShowMotionBlur = false;
		mGameView = new RenderView(30);
		ProjectConfig.Load();
		mScene = new Scene();
		let sceneArg = scope String();
		GetArg("--scene", sceneArg);
		EditorMain.LoadStartScene(mScene, sceneArg);
		Log.Info(scope $"Opened project {project.Name} ({project.Path})");
		ResetUndo();
		AlignSceneCameraToGameCamera();
		// Shaders edited outside the editor, or never compiled on this machine, are built before anything draws.
		CompileStaleShaders();
		let browse = scope String();
		if (GetArg("--browse", browse))
		{
			let full = scope String();
			Assets.ResolvePath(browse, full);
			if (Directory.Exists(full))
				mBrowsePath.Set(full);
		}
		let openPrefab = scope String();
		if (GetArg("--prefab", openPrefab))
		{
			let full = scope String();
			Assets.ResolvePath(openPrefab, full);
			if (File.Exists(full))
				OpenPrefab(full);
		}
		let openMaterial = scope String();
		if (GetArg("--material", openMaterial))
		{
			let full = scope String();
			Assets.ResolvePath(openMaterial, full);
			if (File.Exists(full))
				OpenMaterial(full);
		}
		let openUi = scope String();
		if (GetArg("--ui", openUi))
		{
			let full = scope String();
			Assets.ResolvePath(openUi, full);
			OpenUI(full);
			let pick = scope String();
			if (GetArg("--ui-select", pick) && mUiData != null && mUiData.root != null)
				mUiSelected = mUiData.root.Find(pick);
		}
		if (HasArg("--achievements"))
			mShowAchievements = true;
		if (HasArg("--input-actions"))
			mShowInputActions = true;
		if (HasArg("--build-window"))
		{
			OpenBuildWindow();
			if (HasArg("--build-windows"))
				mBuildTarget = .Windows;
			if (HasArg("--build-web"))
				mBuildTarget = .Web;
			if (HasArg("--build-editor"))
				mBuildEditor = true;
			// For automated checks: build straight away into the given folder.
			let folder = scope String();
			if (GetArg("--build-now", folder))
			{
				mBuildFolder.Set(folder);
				mWantBuildGame = true;
				mBusyFrames = 3;
			}
		}
		let openController = scope String();
		if (GetArg("--animator", openController))
		{
			let full = scope String();
			Assets.ResolvePath(openController, full);
			if (File.Exists(full))
				OpenAnimator(full);
			else
				mShowAnimator = true;
		}
		let openClip = scope String();
		if (GetArg("--animation", openClip))
		{
			let full = scope String();
			Assets.ResolvePath(openClip, full);
			if (File.Exists(full))
				OpenAnimationClip(full);
			else
				mShowAnimation = true;
		}
		let openTree = scope String();
		if (GetArg("--behavior", openTree))
		{
			let full = scope String();
			Assets.ResolvePath(openTree, full);
			if (File.Exists(full))
			{
				OpenBehavior(full);
				mTreeFocusAfter = 30;
			}
		}
		let openGraph = scope String();
		if (GetArg("--graph", openGraph))
		{
			let full = scope String();
			Assets.ResolvePath(openGraph, full);
			if (!File.Exists(full))
			{
				let saved = scope String(mBrowsePath);
				Path.GetDirectoryPath(full, mBrowsePath..Clear()).IgnoreError();
				let graphName = scope String();
				Path.GetFileNameWithoutExtension(full, graphName);
				CreateGraphAsset(graphName);
				mBrowsePath.Set(saved);
			}
			else
				OpenGraph(full);
			if (HasArg("--compile-graph"))
				CompileGraph();
		}
		let openScript = scope String();
		if (GetArg("--script", openScript))
		{
			let full = scope String();
			Assets.ResolvePath(openScript, full);
			OpenScript(full);
		}
		// Test switches for the terrain brush: --brush <0-4> picks a tool, --brush-preview "x,z" or "x,z,size" shows its preview there.
		let brushArg = scope String();
		if (GetArg("--brush", brushArg) && (int32.Parse(brushArg) case .Ok(let tool)))
			mBrushTool = Math.Clamp(tool, 0, 4);
		if (GetArg("--brush-preview", brushArg))
		{
			var parts = brushArg.Split(',');
			if ((parts.GetNext() case .Ok(let xText)) && (parts.GetNext() case .Ok(let zText)) && (float.Parse(xText) case .Ok(let x)) && (float.Parse(zText) case .Ok(let z)))
			{
				mBrushTestPoint = .(x, 0, z);
				mBrushTest = true;
				if ((parts.GetNext() case .Ok(let sizeText)) && (float.Parse(sizeText) case .Ok(let brushSize)))
					mBrushSize = Math.Clamp(brushSize, 1, 40);
			}
		}
		let selectName = scope String();
		if (GetArg("--select", selectName))
		{
			let found = mScene.Find(selectName);
			if (found != null)
			{
				mSelectedId = found.Id;
				FocusSelected();
			}
		}
		if (HasArg("--play"))
			StartPlay();
		return true;
	}

	protected override void OnShutdown()
	{
		AssetPreviews.Shutdown();
		if (mCheckThread != null)
			mCheckThread.Join();
		if (mScene != null && mPlay != .Edit)
			mScene.StopPlay();
		if (Gfx.Initialized)
			ImGui.tn_imgui_shutdown();
	}

	protected override void OnEvent(ref SDL.Event event)
	{
		// While a game has the mouse locked, the editor's own panels must not see it move or click.
		if (!Input.HiddenFromInterface(event.type))
			ImGui.tn_imgui_event(&event);
		// Files dragged in from the desktop file manager are copied into the folder shown in Project.
		if (event.type == 0x1000)
		{
			let file = *(char8**)((uint8*)&event + 40);
			if (file != null)
				ImportExternalFile(StringView(file));
		}
	}

	protected override void OnFixedUpdate()
	{
		if (mPlay == .Playing)
		{
			Input.Enabled = mGameFocused;
			mScene.FixedUpdate();
			Input.Enabled = true;
		}
	}

	protected override void OnUpdate()
	{
        PollScriptReload();
        PollProjectFolders();
		// A game changing scene: only while playing, so that the scene being edited is never replaced.
		if (mPlay == .Playing)
			SaveSystem.Update();
			SceneManager.ApplyPending(mScene);
		let gameCamera = FindGameCamera();
		VoxelTerrain.ViewerPosition = (mPlay != .Edit && gameCamera != null) ? gameCamera.Transform.Position : mCamPosition;
		if (mPlay != .Paused)
		{
			Input.Enabled = mPlay == .Playing && mGameFocused;
			mScene.Update();
			Input.Enabled = true;
		}
		// A game may lock the mouse only while its view is being played in. Escape always gives the pointer back.
		if (Input.CursorLocked && Input.GetKeyDown(.Escape))
			mLockHeldOff = true;
		if (mPlay != .Playing)
			mLockHeldOff = false;
		Input.LockAllowed = mPlay == .Playing && mGameFocused && mLockMouse && !mLockHeldOff;
	}

	/// Starts the Scene view near the game camera so a freshly opened scene shows its content.
	void AlignSceneCameraToGameCamera()
	{
		let camera = FindGameCamera();
		if (camera == null)
			return;
		let euler = camera.Transform.EulerAngles;
		mCamPitch = Mathf.Clamp(euler.x + 8, -89, 89);
		mCamYaw = euler.y;
		let rotation = Quaternion.Euler(mCamPitch, mCamYaw, 0);
		mCamPosition = camera.Transform.Position - rotation * Vector3.Forward * 6.0f + Vector3(0, 2, 0);
	}

	Camera FindGameCamera()
	{
		for (let camera in mScene.Cameras)
		{
			if (camera.IsActiveAndEnabled)
				return camera;
		}
		return null;
	}

	protected override void OnRender()
	{
		bgfx.set_view_clear(0, 0x0003, 0x1e1e1eff, 1.0f, 0);
		bgfx.touch(0);

		ImGui.tn_imgui_new_frame();
		DrawUI();
		BuildGizmos();

		AssetPreviews.Update();
		mSceneView.Resize((int32)mSceneSize.x, (int32)mSceneSize.y);
		mSceneView.Render(mScene, mSceneCamera);
		let gameCamera = FindGameCamera();
		if (gameCamera != null)
		{
			mGameView.Resize((int32)mGameSize.x, (int32)mGameSize.y);
			mGameView.Render(mScene, gameCamera.GetCameraData(mGameSize.x / Math.Max(mGameSize.y, 1)));
		}
		ImGui.tn_imgui_render(ImGuiView);

		// Long blocking jobs run after a frame that shows the "working" message has been presented.
		if (mBusyFrames > 0 && --mBusyFrames == 0)
		{
			if (mWantRebuild)
				RebuildAndReload();
			if (mWantBuildGame)
				BuildGame();
            if (mWantFullRestart) FullRebuildAndRestart();
            mWantFullRestart = false;
			mWantRebuild = false;
			mWantBuildGame = false;
			mStatus.Clear();
		}
	}
}
