using System;
using System.Collections;
using System.IO;
using System.Threading;
using Tessera;

namespace Tessera.Editor;

/// The tools Tessera needs to compile projects, found on this machine or installed by Tessera itself (with the
/// user's permission, from the launcher's Set Up Tools window):
///
///   - Beef's compiler;
///   - Python 3.11 or later, for the build scripts;
///   - on Windows, Microsoft's C runtime and Windows SDK libraries: Visual Studio's C++ tools if they are installed,
///     otherwise fetched with xwin once the user accepts Microsoft's licence;
///   - on Linux, a C compiler and the X11 and OpenGL development files, from the system's package manager.
///
/// Tessera's own copies go in a folder of the user's (Folder) and are downloaded from the engine's GitHub release
/// named in tools/toolchain.txt. Apply points the editor and the build scripts at them.
static class Toolchain
{
	public enum Kind { Beef, Python, Microsoft, System }

	public class Item
	{
		public Kind kind;
		public String name = new .() ~ delete _;
		/// Where it was found, or what installing it does.
		public String detail = new .() ~ delete _;
		public bool found;
		/// Needs the user to accept Microsoft's licence before it is installed.
		public bool licence;
	}

	public static List<Item> Items = new .() ~ DeleteContainerAndItems!(_);
	static String sFolder = new .() ~ delete _;
	static String sRelease = new .("toolchain-1") ~ delete _;
	static bool sChecked;

	const String ReleaseBase = "https://github.com/LazyAlgorithm/Tessera/releases/download/";

	// ---- installing (on a thread of its own) ----
	static Monitor sLock = new .() ~ delete _;
	static Thread sThread;
	static String sStatus = new .() ~ delete _;
	static String sLogPath = new .() ~ delete _;
	static bool sFailed;
	public static bool Installing => sThread != null && !sThread.Join(0);

	/// Where Tessera keeps the tools it installed itself.
	public static String Folder
	{
		get
		{
			if (sFolder.IsEmpty)
			{
				let base_ = scope String();
#if BF_PLATFORM_WINDOWS
				Environment.GetEnvironmentVariable("LOCALAPPDATA", base_).IgnoreError();
				base_.Replace('\\', '/');
#else
				if (!(Environment.GetEnvironmentVariable("XDG_DATA_HOME", base_) case .Ok) || base_.IsEmpty)
				{
					base_.Clear();
					Environment.GetEnvironmentVariable("HOME", base_).IgnoreError();
					base_.Append("/.local/share");
				}
#endif
				sFolder.AppendF("{}/Tessera/toolchain", base_);
			}
			return sFolder;
		}
	}

	/// What the installer is doing, for the window; true in failed when it stopped with an error.
	public static void GetStatus(String text, out bool failed)
	{
		using (sLock.Enter())
		{
			text.Set(sStatus);
			failed = sFailed;
		}
	}

	public static void GetLogPath(String path) => path.Set(sLogPath);

	static void SetStatus(StringView text, bool failed = false)
	{
		using (sLock.Enter())
		{
			sStatus.Set(text);
			sFailed = failed;
		}
	}

	// ---- paths of Tessera's own copies ----

	static void OwnBeef(String path)
	{
#if BF_PLATFORM_WINDOWS
		path.AppendF("{}/beef/bin/BeefBuild.exe", Folder);
#else
		path.AppendF("{}/beef/IDE/dist/BeefBuild.sh", Folder);
#endif
	}

	static void OwnPythonFolder(String path)
	{
#if BF_PLATFORM_WINDOWS
		path.AppendF("{}/python", Folder);
#else
		path.AppendF("{}/python/bin", Folder);
#endif
	}

	static void OwnPython(String path)
	{
		OwnPythonFolder(path);
#if BF_PLATFORM_WINDOWS
		path.Append("/python.exe");
#else
		path.Append("/python3");
#endif
	}

	static void OwnMicrosoft(String path) => path.AppendF("{}/msvc", Folder);

	// ---- the environment ----

#if BF_PLATFORM_WINDOWS
	[CLink] static extern int32 _putenv_s(char8* name, char8* value);
#else
	[CLink] static extern int32 setenv(char8* name, char8* value, int32 overwrite);
#endif

	/// Sets an environment variable for this program and every program it starts (the C library's copy too, which
	/// is the one system() passes on).
	static void SetEnv(StringView name, StringView value)
	{
#if BF_PLATFORM_WINDOWS
		_putenv_s(scope String(name).CStr(), scope String(value).CStr());
#else
		setenv(scope String(name).CStr(), scope String(value).CStr(), 1);
#endif
	}

	/// Points this program, and the compilers and scripts it starts, at the tools Tessera installed. Call once at
	/// start; tools the user installed themselves are left as they are.
	public static void Apply()
	{
		let python = scope String();
		OwnPython(python);
		if (File.Exists(python))
		{
			let folder = scope String();
			OwnPythonFolder(folder);
#if BF_PLATFORM_WINDOWS
			folder.Replace('/', '\\');
			let separator = ';';
#else
			let separator = ':';
#endif
			let path = scope String();
			Environment.GetEnvironmentVariable("PATH", path).IgnoreError();
			if (!path.Contains(folder))
				SetEnv("PATH", scope $"{folder}{separator}{path}");
		}
		let beef = scope String();
		OwnBeef(beef);
		let current = scope String();
		let userBeef = Environment.GetEnvironmentVariable("BEEFBUILD", current) case .Ok && !current.IsEmpty && File.Exists(current) && current != beef;
		var useOwn = File.Exists(beef) && !userBeef && !FindOnPath("BeefBuild", scope .());
#if BF_PLATFORM_WINDOWS
		// Microsoft's libraries fetched by xwin are set up for Tessera's own Beef.
		let msvc = scope String();
		OwnMicrosoft(msvc);
		useOwn |= File.Exists(beef) && File.Exists(scope $"{msvc}/crt/lib/x86_64/libcmt.lib");
#endif
		if (useOwn)
			SetEnv("BEEFBUILD", beef);
	}

	// ---- looking ----

	/// Runs a command quietly; true if it succeeded.
	static bool Succeeds(StringView command)
	{
		return Terminal.Run(scope $"{command} > {Terminal.Null} 2>&1") == 0;
	}

	/// Finds a program on PATH.
	static bool FindOnPath(StringView program, String outPath)
	{
		let path = scope String();
		Environment.GetEnvironmentVariable("PATH", path).IgnoreError();
#if BF_PLATFORM_WINDOWS
		for (let folder in path.Split(';'))
		{
			for (let extension in StringView[?](".exe", ".bat", ".cmd"))
			{
				let candidate = scope $"{folder}\\{program}{extension}";
				// The Microsoft Store's stand-in for Python only offers to install it.
				if (File.Exists(candidate) && !candidate.Contains("WindowsApps"))
				{
					outPath.Set(candidate);
					return true;
				}
			}
		}
#else
		for (let folder in path.Split(':'))
		{
			let candidate = scope $"{folder}/{program}";
			if (!folder.IsEmpty && File.Exists(candidate))
			{
				outPath.Set(candidate);
				return true;
			}
		}
#endif
		return false;
	}

	static bool PythonWorks(StringView python)
	{
		let command = scope String();
		Terminal.Quote(python, command);
		command.Append(" -c \"import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)\"");
		return Succeeds(command);
	}

	/// Looks for every tool. Fast enough to run as the launcher starts.
	public static void Check()
	{
		sChecked = true;
		ReadVersions();
		ClearAndDeleteItems!(Items);

		// Beef
		{
			let item = new Item() { kind = .Beef };
			item.name.Set("Beef compiler");
			let found = scope String();
			let own = scope String();
			OwnBeef(own);
			if (Environment.GetEnvironmentVariable("BEEFBUILD", found) case .Ok && !found.IsEmpty && File.Exists(found))
				item.found = true;
			else if (FindOnPath("BeefBuild", found))
				item.found = true;
			else if (File.Exists(own))
			{
				found.Set(own);
				item.found = true;
			}
#if BF_PLATFORM_WINDOWS
			else if (File.Exists("C:/Program Files/BeefLang/bin/BeefBuild.exe"))
			{
				found.Set("C:/Program Files/BeefLang/bin/BeefBuild.exe");
				SetEnv("BEEFBUILD", found);
				item.found = true;
			}
#endif
			if (item.found)
				item.detail.Set(found);
			else
				item.detail.Set("Will be downloaded (about 100 MB) into Tessera's tools folder.");
			Items.Add(item);
		}

		// Python
		{
			let item = new Item() { kind = .Python };
			item.name.Set("Python 3.11 or later");
			let own = scope String();
			OwnPython(own);
			let found = scope String();
			if (File.Exists(own) && PythonWorks(own))
			{
				found.Set(own);
				item.found = true;
			}
			else if (FindOnPath(Terminal.Python, found) && PythonWorks(found))
				item.found = true;
			if (item.found)
				item.detail.Set(found);
			else
				item.detail.Set(found.IsEmpty ? "Will be downloaded (about 30 MB): a copy only Tessera uses." : scope $"{found} is too old; a newer copy only Tessera uses will be downloaded (about 30 MB).");
			Items.Add(item);
		}

#if BF_PLATFORM_WINDOWS
		// Microsoft's libraries
		{
			let item = new Item() { kind = .Microsoft, licence = true };
			item.name.Set("Microsoft C runtime and Windows SDK libraries");
			let own = scope String();
			OwnMicrosoft(own);
			let visualStudio = scope String();
			if (File.Exists(scope $"{own}/crt/lib/x86_64/libcmt.lib"))
			{
				item.found = true;
				item.detail.Set(own);
			}
			else if (FindVisualStudio(visualStudio))
			{
				item.found = true;
				item.detail.AppendF("Visual Studio C++ tools: {}", visualStudio);
			}
			else
				item.detail.Set("Visual Studio's C++ tools are not installed. Microsoft's libraries will be downloaded (about 700 MB) with xwin, under the Visual Studio Build Tools licence.");
			Items.Add(item);
			// Without Visual Studio, Beef has to be told where Microsoft's libraries are: Tessera does that for its
			// own copy of Beef only.
			let beefItem = Items[0];
			let ownBeef = scope String();
			OwnBeef(ownBeef);
			if (!item.found && beefItem.found && !Path.Equals(beefItem.detail, ownBeef))
			{
				beefItem.found = false;
				beefItem.detail.Set("Without Visual Studio, Tessera uses a copy of Beef of its own that it can point at Microsoft's libraries. Will be downloaded (about 100 MB).");
			}
		}
#else
		// The system's compiler and development files
		{
			let item = new Item() { kind = .System };
			item.name.Set("C compiler, X11 and OpenGL development files");
			let missing = scope String();
			let compiler = scope String();
			if (!FindOnPath("cc", compiler) && !FindOnPath("gcc", compiler) && !FindOnPath("clang", compiler))
				missing.Append("a C compiler");
			bool HasLibrary(StringView name)
			{
				for (let folder in StringView[?]("/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/usr/lib", "/lib/x86_64-linux-gnu", "/usr/local/lib"))
				{
					if (File.Exists(scope $"{folder}/{name}"))
						return true;
				}
				return false;
			}
			if (!HasLibrary("libGL.so"))
				missing..Append(missing.IsEmpty ? "" : ", ").Append("OpenGL development files");
			if (!HasLibrary("libX11.so"))
				missing..Append(missing.IsEmpty ? "" : ", ").Append("X11 development files");
			item.found = missing.IsEmpty;
			if (item.found)
				item.detail.Set(compiler);
			else
			{
				let command = scope String();
				SystemPackagesCommand(command);
				item.detail.AppendF("Missing: {}. Installed with your package manager{}", missing, command.IsEmpty ? " (not recognised: install them yourself)." : scope $": {command}");
			}
			Items.Add(item);
		}
#endif
	}

	/// True once checked, when a tool is missing.
	public static bool AnyMissing
	{
		get
		{
			if (!sChecked)
				Check();
			for (let item in Items)
			{
				if (!item.found)
					return true;
			}
			return false;
		}
	}

	static void ReadVersions()
	{
		let root = scope String();
		if (!ProjectGenerator.FindEngineRoot(root))
			return;
		let text = scope String();
		if (File.ReadAllText(scope $"{root}/tools/toolchain.txt", text) case .Err)
			return;
		for (var line in text.Split('\n'))
		{
			line.Trim();
			if (line.StartsWith("release = "))
			{
				sRelease.Set(line.Substring(10));
				sRelease.Trim();
			}
		}
	}

#if BF_PLATFORM_WINDOWS
	/// Visual Studio (or its Build Tools) with the C++ compiler, as vswhere reports it.
	static bool FindVisualStudio(String outPath)
	{
		let programs = scope String();
		Environment.GetEnvironmentVariable("ProgramFiles(x86)", programs).IgnoreError();
		let vswhere = scope $"{programs}\\Microsoft Visual Studio\\Installer\\vswhere.exe";
		if (programs.IsEmpty || !File.Exists(vswhere))
			return false;
		let output = scope $"{Folder}/vswhere.txt";
		Directory.CreateDirectory(Folder).IgnoreError();
		let command = scope String();
		Terminal.Quote(vswhere, command);
		command.Append(" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > ");
		Terminal.Quote(output, command);
		Terminal.Run(command);
		let text = scope String();
		File.ReadAllText(output, text).IgnoreError();
		File.Delete(output).IgnoreError();
		text.Trim();
		outPath.Set(text);
		return !text.IsEmpty;
	}
#else
	/// The command that installs the compiler and development files with this system's package manager, or empty.
	public static void SystemPackagesCommand(String command)
	{
		let found = scope String();
		if (FindOnPath("apt-get", found))
			command.Append("apt-get install -y build-essential libgl-dev libx11-dev");
		else if (FindOnPath("dnf", found))
			command.Append("dnf install -y gcc gcc-c++ mesa-libGL-devel libX11-devel");
		else if (FindOnPath("pacman", found))
			command.Append("pacman -S --needed --noconfirm base-devel libglvnd libx11");
		else if (FindOnPath("zypper", found))
			command.Append("zypper install -y gcc gcc-c++ Mesa-libGL-devel libX11-devel");
	}

	/// True when packages can be installed from here: pkexec asks for the password in a window of its own.
	public static bool CanInstallSystemPackages => FindOnPath("pkexec", scope .()) && !SystemPackagesCommand(.. scope .()).IsEmpty;
#endif

	// ---- installing ----

	/// Installs everything missing, in the background. acceptedLicence: the user accepted Microsoft's licence (needed
	/// for Microsoft's libraries on Windows). Check Installing and GetStatus; Check runs again when it is done.
	public static void Install(bool acceptedLicence)
	{
		if (Installing)
			return;
		if (sThread != null)
			DeleteAndNullify!(sThread);
		sLogPath.Set(scope $"{Folder}/install.log");
		SetStatus("Starting...");
		List<Kind> wanted = new .();
		for (let item in Items)
		{
			if (!item.found && (!item.licence || acceptedLicence))
				wanted.Add(item.kind);
		}
		sThread = new Thread(new () =>
			{
				InstallAll(wanted);
				delete wanted;
			});
		sThread.Start(false);
	}

	static void InstallAll(List<Kind> wanted)
	{
		Directory.CreateDirectory(Folder).IgnoreError();
		File.WriteAllText(sLogPath, "Tessera tool setup\n").IgnoreError();
		for (let kind in wanted)
		{
			bool ok = true;
			switch (kind)
			{
			case .Beef: ok = InstallBeef();
			case .Python: ok = InstallPython();
			case .Microsoft: ok = InstallMicrosoft();
			case .System: ok = InstallSystemPackages();
			}
			if (!ok)
				return;
		}
		SetStatus("Done.");
	}

	/// Runs a command with its output added to the install log; on failure says what failed.
	static bool Step(StringView what, StringView command)
	{
		SetStatus(what);
		let line = scope String(command);
		line.Append(" >> ");
		Terminal.Quote(sLogPath, line);
		line.Append(" 2>&1");
		if (Terminal.Run(line) == 0)
			return true;
		SetStatus(scope $"{what} failed. See {sLogPath}.", true);
		return false;
	}

	/// Downloads one of the toolchain release's files into the tools folder.
	static bool Download(StringView asset, String outFile)
	{
		outFile.AppendF("{}/{}", Folder, asset);
		let url = scope $"{ReleaseBase}{sRelease}/{asset}";
		let command = scope String();
#if BF_PLATFORM_WINDOWS
		// curl.exe comes with Windows 10 and later.
		command.Append("curl.exe -fL --retry 3 -o ");
		Terminal.Quote(outFile, command);
		command.AppendF(" {}", url);
#else
		command.Append("{ curl -fL --retry 3 -o ");
		Terminal.Quote(outFile, command);
		command.AppendF(" {0} || wget -O ", url);
		Terminal.Quote(outFile, command);
		command.AppendF(" {0}; }}", url);
#endif
		return Step(scope $"Downloading {asset}...", command);
	}

	/// Unpacks an archive (zip or tar.gz) into the tools folder, replacing `folder` there, and deletes the archive.
	static bool Unpack(StringView archive, StringView folder)
	{
		let target = scope $"{Folder}/{folder}";
		if (Directory.Exists(target))
			Directory.DelTree(target).IgnoreError();
		let command = scope String();
#if BF_PLATFORM_WINDOWS
		// Windows' own tar reads zip files too.
		command.Append("tar -xf ");
#else
		command.Append("tar -xzf ");
#endif
		Terminal.Quote(archive, command);
		command.Append(" -C ");
		Terminal.Quote(Folder, command);
		let ok = Step(scope $"Unpacking {folder}...", command);
		File.Delete(archive).IgnoreError();
		return ok;
	}

	static bool InstallBeef()
	{
		let archive = scope String();
#if BF_PLATFORM_WINDOWS
		if (!Download("beef-windows-x64.zip", archive) || !Unpack(archive, "beef"))
			return false;
		// Beef links with Microsoft's libraries: those xwin fetched, if that is where they are.
		WriteBeefSettings();
#else
		if (!Download("beef-linux-x64.tar.gz", archive) || !Unpack(archive, "beef"))
			return false;
#endif
		let beef = scope String();
		OwnBeef(beef);
		if (!File.Exists(beef))
		{
			SetStatus("The Beef compiler was not where it should be after unpacking.", true);
			return false;
		}
		SetEnv("BEEFBUILD", beef);
		return true;
	}

	static bool InstallPython()
	{
		let archive = scope String();
#if BF_PLATFORM_WINDOWS
		if (!Download("python-windows-x64.zip", archive) || !Unpack(archive, "python"))
			return false;
#else
		if (!Download("python-linux-x64.tar.gz", archive) || !Unpack(archive, "python"))
			return false;
#endif
		let python = scope String();
		OwnPython(python);
		if (!PythonWorks(python))
		{
			SetStatus("The downloaded Python does not run.", true);
			return false;
		}
		Apply();
		return true;
	}

#if BF_PLATFORM_WINDOWS
	static bool InstallMicrosoft()
	{
		let archive = scope String();
		if (!Download("xwin-windows-x64.zip", archive))
			return false;
		let command = scope String("tar -xf ");
		Terminal.Quote(archive, command);
		command.Append(" -C ");
		Terminal.Quote(Folder, command);
		if (!Step("Unpacking xwin...", command))
			return false;
		File.Delete(archive).IgnoreError();
		// The user accepted Microsoft's licence in the window before this ran.
		let xwin = scope String();
		Terminal.Quote(scope $"{Folder}/xwin.exe", xwin);
		let run = scope $"{xwin} --accept-license --arch x86_64 --cache-dir ";
		Terminal.Quote(scope $"{Folder}/xwin-cache", run);
		run.Append(" splat --output ");
		Terminal.Quote(scope $"{Folder}/msvc", run);
		if (!Step("Downloading Microsoft's libraries (this takes a few minutes)...", run))
			return false;
		Directory.DelTree(scope $"{Folder}/xwin-cache").IgnoreError();
		WriteBeefSettings();
		return true;
	}

	/// Tells Tessera's Beef where xwin put Microsoft's libraries (Beef otherwise looks for Visual Studio).
	static void WriteBeefSettings()
	{
		let msvc = scope String();
		OwnMicrosoft(msvc);
		if (!File.Exists(scope $"{msvc}/crt/lib/x86_64/libcmt.lib") || !Directory.Exists(scope $"{Folder}/beef/bin"))
			return;
		let text = scope String("[VisualStudio]\nManuallySet = true\nBin32Path = \"\"\nBin64Path = \"\"\nLib32Paths = []\nLib64Paths = [");
		bool first = true;
		for (let folder in StringView[?]("crt/lib/x86_64", "sdk/lib/um/x86_64", "sdk/lib/ucrt/x86_64"))
		{
			let path = scope $"{msvc}/{folder}";
			path.Replace('/', '\\');
			path.Replace("\\", "\\\\");
			text.AppendF("{}\"{}\"", first ? "" : ", ", path);
			first = false;
		}
		text.Append("]\n");
		File.WriteAllText(scope $"{Folder}/beef/bin/BeefSettings.toml", text).IgnoreError();
	}
#else
	static bool InstallMicrosoft() => true;
#endif

#if BF_PLATFORM_WINDOWS
	static bool InstallSystemPackages() => true;
#else
	static bool InstallSystemPackages()
	{
		let packages = scope String();
		SystemPackagesCommand(packages);
		if (packages.IsEmpty || !CanInstallSystemPackages)
		{
			SetStatus("Install the compiler and development files with your package manager, then check again.", true);
			return false;
		}
		// pkexec asks for the administrator password in a window of its own.
		return Step("Installing the system's compiler and development files (enter your password when asked)...", scope $"pkexec sh -c \"{packages}\"");
	}
#endif
}
