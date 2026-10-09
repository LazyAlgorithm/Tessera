using System;
using System.Collections;
using System.IO;
using Tessera;
using Tessera.Editor;
using Bgfx;

namespace Tessera.Launcher;

/// The project hub: pick a recent project, add an existing one, or create a new one.
/// Opening a project compiles its scripts and starts its editor.
///
/// Command line: --create <folder> [--sample]   create a project without the window
///               --open <folder>                build and open a project's editor directly
class LauncherApp : Application
{
	String mName = new .("MyGame") ~ delete _;
	String mLocation = new .() ~ delete _;
	String mExisting = new .() ~ delete _;
	String mMessage = new .() ~ delete _;
	String mPendingOpen = new .() ~ delete _;
	String mEngineRoot = new .() ~ delete _;
	bool mSample = true;
	bool mScrap;
	bool mMessageIsError;
	int32 mOpenCountdown;
	int32 mSelected = -1;

	public this()
	{
		Width = 980;
		Height = 620;
		Title.Set("Tessera");
	}

	protected override bool OnInit()
	{
		let ini = new String();
		RecentProjects.GetConfigFolder(ini);
		ini.Append("launcher.ini");
		mIni = ini;
		if (!ImGui.tn_imgui_init(Window, mIni.CStr(), 1.0f))
			return false;
		ProjectGenerator.FindEngineRoot(mEngineRoot);
		if (!mEngineRoot.IsEmpty)
			SetWindowIcon(scope $"{mEngineRoot}/icon.png");
		RecentProjects.Load();
		let home = scope String();
#if BF_PLATFORM_WINDOWS
		Environment.GetEnvironmentVariable("USERPROFILE", home).IgnoreError();
		home.Replace('\\', '/');
#else
		Environment.GetEnvironmentVariable("HOME", home).IgnoreError();
#endif
		if (!home.IsEmpty)
			mLocation.AppendF("{}/TesseraProjects", home);
		else
			mLocation.Set("TesseraProjects");
		return true;
	}

	String mIni ~ delete _;

	protected override void OnShutdown()
	{
		if (Gfx.Initialized)
			ImGui.tn_imgui_shutdown();
	}

	protected override void OnEvent(ref SDL.Event event)
	{
		ImGui.tn_imgui_event(&event);
	}

	void SetMessage(StringView text, bool error)
	{
		mMessage.Set(text);
		mMessageIsError = error;
	}

	void RequestOpen(StringView path)
	{
		mPendingOpen.Set(path);
		mOpenCountdown = 3;
		SetMessage(scope $"Compiling {path} ...", false);
	}

	/// Builds the project and starts its editor. Returns false with the compiler output on failure.
	public static bool OpenProject(StringView path, String error)
	{
		let project = scope Project();
		if (!project.Load(path))
		{
			error.Set(scope $"{path} is not a Tessera project (no project.tessera).");
			return false;
		}
		if (!project.Build(false))
		{
			error.Set("The project did not compile:\n");
			project.ReadBuildLog(error);
			return false;
		}
		RecentProjects.Add(project.Path);
		let command = scope String();
		let exe = scope String();
		project.GetExecutablePath(exe, false);
		Terminal.Quote(exe, command);
		command.Append(" --editor --project ");
		Terminal.Quote(project.Path, command);
		Terminal.RunDetached(command);
		return true;
	}

	protected override void OnRender()
	{
		bgfx.set_view_clear(0, 0x0003, 0x262626ff, 1.0f, 0);
		bgfx.touch(0);
		ImGui.tn_imgui_new_frame();

		let viewport = ImGui.GetMainViewport();
		ImGui.SetNextWindowPos(viewport.workPos);
		ImGui.SetNextWindowSize(viewport.workSize);
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(22, 18));
		ImGui.Begin("Launcher", null, ImGui.WindowFlags.NoDecoration | ImGui.WindowFlags.NoMove | ImGui.WindowFlags.NoSavedSettings);
		ImGui.PopStyleVar();

		ImGui.Text("TESSERA");
		ImGui.SameLine();
		ImGui.TextDisabled("Projects");
		ImGui.Separator();
		ImGui.Spacing();

		let busy = mOpenCountdown > 0;
		ImGui.BeginDisabled(busy);
		let total = ImGui.GetContentRegionAvail();
		let footer = 64.0f;

		// Left: recent projects.
		ImGui.BeginChild("recent", .(total.x * 0.56f, total.y - footer), ImGui.ChildBorders);
		ImGui.TextDisabled("Recent projects");
		ImGui.Spacing();
		if (RecentProjects.Paths.Count == 0)
			ImGui.TextWrapped("No projects yet. Create one on the right.");
		for (int32 i = 0; i < (int32)RecentProjects.Paths.Count; i++)
		{
			let path = RecentProjects.Paths[i];
			let name = scope String();
			Path.GetFileName(path, name);
			ImGui.PushID(i);
			if (ImGui.Selectable("##row", mSelected == i, ImGui.SelectableFlags.AllowDoubleClick, .(0, 40)))
			{
				mSelected = i;
				if (ImGui.IsMouseDoubleClicked(0))
					RequestOpen(path);
			}
			let min = ImGui.GetCursorScreenPos();
			ImGui.DrawText(.(min.x + 8, min.y - 42), .(0.9f, 0.9f, 0.9f, 1), name.CStr());
			ImGui.DrawText(.(min.x + 8, min.y - 24), .(0.55f, 0.55f, 0.55f, 1), path.CStr());
			ImGui.PopID();
		}
		ImGui.EndChild();
		ImGui.SameLine();

		// Right: create or add.
		ImGui.BeginChild("create", .(0, total.y - footer), ImGui.ChildBorders);
		ImGui.TextDisabled("New project");
		ImGui.Spacing();
		ImGui.Text("Name");
		ImGui.SetNextItemWidth(-1);
		ImGui.InputText("##name", mName);
		ImGui.Text("Location");
		ImGui.SetNextItemWidth(-1);
		ImGui.InputText("##location", mLocation);
		ImGui.Checkbox("Include sample (voxel world, networked player)", ref mSample);
		ImGui.Checkbox("Vehicle building game (blocks, wheels, thrusters, seats)", ref mScrap);
		ImGui.Spacing();
		if (ImGui.Button("Create Project", .(-1, 32)))
			CreateFromForm();

		ImGui.Spacing();
		ImGui.Separator();
		ImGui.Spacing();
		ImGui.TextDisabled("Add existing project");
		ImGui.Spacing();
		ImGui.Text("Project folder");
		ImGui.SetNextItemWidth(-1);
		ImGui.InputText("##existing", mExisting);
		if (ImGui.Button("Add and Open", .(-1, 28)))
		{
			if (File.Exists(scope $"{mExisting}/project.tessera"))
				RequestOpen(mExisting);
			else
				SetMessage("That folder does not contain a project.tessera file.", true);
		}
		ImGui.EndChild();

		ImGui.Spacing();
		let hasSelection = mSelected >= 0 && mSelected < RecentProjects.Paths.Count;
		ImGui.BeginDisabled(!hasSelection);
		if (ImGui.Button("Open", .(140, 32)))
			RequestOpen(RecentProjects.Paths[mSelected]);
		ImGui.SameLine();
		if (ImGui.Button("Remove from list", .(160, 32)))
		{
			RecentProjects.Remove(scope String(RecentProjects.Paths[mSelected]));
			mSelected = -1;
		}
		ImGui.EndDisabled();
		ImGui.EndDisabled();

		if (!mMessage.IsEmpty)
		{
			ImGui.SameLine(0, 18);
			ImGui.BeginChild("message", .(0, 40));
			if (mMessageIsError)
				ImGui.TextColored(.(1.0f, 0.45f, 0.4f, 1), mMessage.CStr());
			else
				ImGui.TextColored(.(1.0f, 0.82f, 0.35f, 1), mMessage.CStr());
			ImGui.EndChild();
		}
		ImGui.End();
		ImGui.tn_imgui_render(250);

		// The build blocks, so start it a few frames after the "Compiling" message is on screen.
		if (mOpenCountdown > 0 && --mOpenCountdown == 0)
		{
			let error = scope String();
			if (OpenProject(mPendingOpen, error))
				Running = false;
			else
				SetMessage(error, true);
		}
	}

	void CreateFromForm()
	{
		if (mEngineRoot.IsEmpty)
		{
			SetMessage("The engine folder was not found. Set TESSERA_ROOT.", true);
			return;
		}
		let folder = scope $"{mLocation}/{mName}";
		Directory.CreateDirectory(mLocation).IgnoreError();
		let error = scope String();
		ProjectGenerator.ScrapTemplate = mScrap;
		if (!ProjectGenerator.Create(folder, mName, mEngineRoot, mSample, error))
		{
			SetMessage(error, true);
			return;
		}
		RecentProjects.Add(folder);
		RequestOpen(folder);
	}
}

class Program
{
	public static int Main(String[] args)
	{
		for (int i < args.Count)
		{
			if (args[i] == "--create" && i + 1 < args.Count)
				return CreateFromCommandLine(args[i + 1], args);
			if (args[i] == "--open" && i + 1 < args.Count)
			{
				let error = scope String();
				if (!LauncherApp.OpenProject(args[i + 1], error))
				{
					Console.WriteLine(error);
					return 1;
				}
				return 0;
			}
		}
		let app = scope LauncherApp();
		return app.Run(args);
	}

	static int CreateFromCommandLine(StringView folderIn, String[] args)
	{
		var folder = folderIn;
		while (folder.EndsWith('/') && folder.Length > 1)
			folder.RemoveFromEnd(1);
		let name = scope String();
		Path.GetFileName(folder, name);
		bool sample = false;
		for (let arg in args)
		{
			if (arg == "--sample")
				sample = true;
			if (arg == "--scrap")
				ProjectGenerator.ScrapTemplate = true;
		}
		let root = scope String();
		// No window here, so locate the engine relative to this executable.
		Gfx.LocateEngineAssets();
		if (!ProjectGenerator.FindEngineRoot(root))
		{
			Console.WriteLine("Engine folder not found. Set TESSERA_ROOT.");
			return 1;
		}
		let error = scope String();
		if (!ProjectGenerator.Create(folder, name, root, sample, error))
		{
			Console.WriteLine(error);
			return 1;
		}
		Console.WriteLine("Created {} at {}", name, folder);
		return 0;
	}
}
