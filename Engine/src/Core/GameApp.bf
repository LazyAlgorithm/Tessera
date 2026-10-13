using System;
using System.IO;
namespace Tessera;

/// Runs a project as a game: the start scene in play mode, rendered straight to the window.
class GameApp : Application
{
	public String GameName = new .("Tessera") ~ delete _;
    public String StartScene = new .("Scenes/Main.tscene") ~ delete _;
    Scene mScene ~ delete _;
	RenderView mView ~ delete _;
	bool mGui;

	protected override void OnEvent(ref SDL.Event event)
	{
		if (mGui && !Input.HiddenFromInterface(event.type))
			ImGui.tn_imgui_event(&event);
	}

	protected override bool OnInit()
	{
		Title.Set(GameName);
		if (Window != null)
			SDL.SDL_SetWindowTitle(Window, Title.CStr());
		mScene = new Scene();
		let sceneArg = scope String();
		GetArg("--scene", sceneArg);
		if (!LoadScene(mScene, sceneArg)) return false;
		if (!Headless)
		{
			mView = new RenderView(10);
			mView.ToBackbuffer = true;
			mGui = ImGui.tn_imgui_init(Window, null, 1.0f);
		}
		mScene.StartPlay();
		return true;
	}

    protected virtual bool LoadScene(Scene scene, StringView overridePath)
    {
        let path = scope String();
        Assets.ResolvePath(overridePath.IsEmpty ? (StringView)StartScene : overridePath, path);
        if (!AssetPack.Exists(path)) { Log.Error(scope $"Start scene missing: {path}"); return false; }
        SceneSerializer.LoadFromFile(scene, path);
        return true;
    }

	protected override void OnFixedUpdate()
	{
		mScene.FixedUpdate();
		if (HasArg("--trace") && Time.Tick % 20 == 0 && mScene.Network != null)
		{
			for (let identity in mScene.Network.Identities)
			{
				if (identity.GameObject.Name == "Player")
					Log.Info(scope $"tick {Time.Tick} player {identity.NetId & 0xff} owner {identity.ownerId} at {identity.Transform.Position}");
			}
		}
		if (Headless && Time.Tick % 300 == 0 && mScene.Network != null)
			Log.Info(scope $"tick {Time.Tick}: {mScene.Network.ClientCount} client(s), {mScene.Network.Identities.Count} networked objects");
	}

	protected override void OnUpdate()
	{
		SceneManager.ApplyPending(mScene);
		let camera = FindCamera();
		if (camera != null)
			VoxelTerrain.ViewerPosition = camera.Transform.Position;
		else if (mScene.Network != null && mScene.Network.Identities.Count > 0)
			VoxelTerrain.ViewerPosition = mScene.Network.Identities.Back.Transform.Position;
		mScene.Update();
#if !BF_PLATFORM_WASM
		// (A web page is closed with the browser; there, Escape only gives the mouse back.)
		if (Input.GetKeyDown(.Escape))
			Running = false;
#endif
	}

	Camera FindCamera()
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
		let camera = FindCamera();
		if (camera == null)
			return;
		mView.Resize(Width, Height);
		mView.Render(mScene, camera.GetCameraData((float)Width / Math.Max(Height, 1)));
		if (mGui)
		{
			// Components draw their interface into one invisible window covering the screen.
			ImGui.tn_imgui_new_frame();
			ImGui.SetNextWindowPos(.(0, 0));
			ImGui.SetNextWindowSize(.(Width, Height));
			ImGui.Begin("##GameGUI", null, ImGui.WindowFlags.NoDecoration | ImGui.WindowFlags.NoBackground | ImGui.WindowFlags.NoSavedSettings
				| ImGui.WindowFlags.NoMove | ImGui.WindowFlags.NoBringToFrontOnFocus | ImGui.WindowFlags.NoScrollWithMouse);
			GUI.Run(mScene, .(0, 0), .(Width, Height));
			// On a touch screen, the game's on-screen controls go over everything else.
			TouchControls.Draw();
			ImGui.End();
			ImGui.tn_imgui_render(250);
		}
	}

	protected override void OnShutdown()
	{
		if (mScene != null)
			mScene.StopPlay();
		if (mGui && Gfx.Initialized)
			ImGui.tn_imgui_shutdown();
	}
}

