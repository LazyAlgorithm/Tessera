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
	/// The Set Up Tools window: open at start when a tool Tessera needs is missing.
	bool mSetupOpen;
	bool mSetupWasInstalling;
	bool mLicence;
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
		Toolchain.Apply();
		Toolchain.Check();
		mSetupOpen = Toolchain.AnyMissing && !File.Exists(SkipFile(.. scope .()));
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

	/// Written when the user closes the Set Up Tools window with tools still missing, so it does not open by itself
	/// every time (the Tools button still opens it).
	static void SkipFile(String path)
	{
		RecentProjects.GetConfigFolder(path);
		path.Append("toolchain-skipped");
	}

	void RequestOpen(StringView path)
	{
		if (Toolchain.AnyMissing)
		{
			// Compiling would only fail: say what is missing first.
			mSetupOpen = true;
			SetMessage("Some tools Tessera needs to compile projects are missing: see Set Up Tools.", true);
			return;
		}
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
		ImGui.SameLine(ImGui.GetContentRegionAvail().x - 110);
		if (ImGui.Button(Toolchain.AnyMissing ? "Set Up Tools (!)" : "Set Up Tools", .(130, 0)))
		{
			Toolchain.Check();
			mSetupOpen = true;
		}
		ImGui.Separator();
		ImGui.Spacing();
		if (mSetupOpen)
		{
			DrawSetup();
			ImGui.End();
			ImGui.tn_imgui_render(250);
			return;
		}

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

	/// Lists the tools, found or missing, and installs what is missing once the user says so.
	void DrawSetup()
	{
		let installing = Toolchain.Installing;
		if (mSetupWasInstalling && !installing)
			Toolchain.Check();
		mSetupWasInstalling = installing;

		ImGui.Text("Set up the tools Tessera compiles projects with");
		ImGui.Spacing();
		let folder = scope String(Toolchain.Folder);
		ImGui.TextWrapped(scope $"What is missing can be downloaded and set up for you. Tessera's own copies of its tools go in {folder} and are used by Tessera only.");
#if !BF_PLATFORM_WINDOWS
		ImGui.TextWrapped("The compiler and development files come from your system's package manager, which asks for your password.");
#endif
		ImGui.Spacing();
		bool needsLicence = false, anyMissing = false;
		for (let item in Toolchain.Items)
		{
			ImGui.PushID(item.name.CStr());
			if (item.found)
				ImGui.TextColored(.(0.45f, 0.9f, 0.5f, 1), "Found");
			else
				ImGui.TextColored(.(1.0f, 0.55f, 0.4f, 1), "Missing");
			ImGui.SameLine(90);
			ImGui.Text(item.name);
			ImGui.Indent(90);
			ImGui.PushStyleColor(ImGui.Col.Text, .(0.6f, 0.6f, 0.6f, 1));
			ImGui.TextWrapped(item.detail.CStr());
			ImGui.PopStyleColor();
			ImGui.Unindent(90);
			ImGui.Spacing();
			needsLicence |= !item.found && item.licence;
			anyMissing |= !item.found;
			ImGui.PopID();
		}

		if (needsLicence)
		{
			ImGui.Spacing();
			ImGui.Checkbox("I accept the Microsoft Visual Studio Build Tools licence for Microsoft's libraries", ref mLicence);
			ImGui.SameLine();
			if (ImGui.SmallButton("Read it"))
				Terminal.Open("https://go.microsoft.com/fwlink/?LinkId=2086102");
		}
#if !BF_PLATFORM_WINDOWS
		let packages = scope String();
		Toolchain.SystemPackagesCommand(packages);
		bool systemMissing = false;
		for (let item in Toolchain.Items)
			systemMissing |= item.kind == .System && !item.found;
		if (systemMissing && !packages.IsEmpty && !Toolchain.CanInstallSystemPackages)
		{
			ImGui.TextWrapped(scope $"Run this in a terminal, then press Check Again:  sudo {packages}");
			if (ImGui.SmallButton("Copy command"))
				ImGui.SetClipboardText(scope $"sudo {packages}".CStr());
		}
#endif

		ImGui.Spacing();
		ImGui.Separator();
		ImGui.Spacing();
		if (installing)
		{
			let status = scope String();
			Toolchain.GetStatus(status, ?);
			ImGui.ProgressBar(-(float)ImGui.GetTime(), .(-1, 0), status.CStr());
			return;
		}
		let status = scope String();
		bool failed;
		Toolchain.GetStatus(status, out failed);
		if (!status.IsEmpty)
		{
			if (failed)
				ImGui.TextColored(.(1.0f, 0.45f, 0.4f, 1), status.CStr());
			else
				ImGui.TextColored(.(0.45f, 0.9f, 0.5f, 1), status.CStr());
			if (failed && ImGui.SmallButton("Open the log"))
				Terminal.Open(Toolchain.GetLogPath(.. scope .()));
		}
		ImGui.BeginDisabled(!anyMissing);
		if (ImGui.Button("Install What Is Missing", .(220, 32)))
			Toolchain.Install(mLicence);
		ImGui.EndDisabled();
		ImGui.SameLine();
		if (ImGui.Button("Check Again", .(140, 32)))
			Toolchain.Check();
		ImGui.SameLine();
		if (ImGui.Button(anyMissing ? "Not Now" : "Done", .(140, 32)))
		{
			mSetupOpen = false;
			let skip = scope String();
			SkipFile(skip);
			if (anyMissing)
				File.WriteAllText(skip, "").IgnoreError();
			else
				File.Delete(skip).IgnoreError();
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
