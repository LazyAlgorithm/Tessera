using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// File > Export Scene as Map...: writes the open scene as a .tmap file (MapFiles) into the project's Maps folder,
/// where the game finds it when it runs from the editor, and into the Maps folder of each built copy of the game
/// under Builds, so it can be tried in the built game straight away.
extension EditorApp
{
	bool mOpenExportMap;
	String mMapName = new .() ~ delete _;
	String mMapAuthor = new .() ~ delete _;
	String mMapDescription = new .() ~ delete _;
	String mMapFolder = new .() ~ delete _;
	bool mMapCopyToBuilds = true;
	/// What the last export did, shown in the window.
	String mMapExportReport = new .() ~ delete _;

	void DrawExportMapPopup()
	{
		if (mOpenExportMap)
		{
			mOpenExportMap = false;
			if (mMapName.IsEmpty || mMapName != mScene.Name)
				mMapName.Set(mScene.Name);
			if (mMapFolder.IsEmpty)
				MapFiles.Folder(mMapFolder);
			mMapExportReport.Clear();
			ImGui.OpenPopup("Export Scene as Map");
		}
		if (!ImGui.BeginPopupModal("Export Scene as Map", null, ImGui.WindowFlags.AlwaysAutoResize))
			return;
		ImGui.TextDisabled("The scene is saved first. A map uses the game's models, prefabs and scripts, and carries its own terrain.");
		ImGui.SetNextItemWidth(420);
		ImGui.InputText("Name", mMapName);
		ImGui.SetNextItemWidth(420);
		ImGui.InputText("Author", mMapAuthor);
		ImGui.SetNextItemWidth(420);
		ImGui.InputText("Description", mMapDescription);
		ImGui.SetNextItemWidth(420);
		ImGui.InputText("Folder", mMapFolder);
		ImGui.Checkbox("Also put it in each build of the game (Builds/*/Maps)", ref mMapCopyToBuilds);
		if (!mMapExportReport.IsEmpty)
			ImGui.TextWrapped(mMapExportReport);
		ImGui.BeginDisabled(mMapName.IsEmpty || mPlay != .Edit);
		if (ImGui.Button("Export", .(120, 0)))
			ExportMap();
		ImGui.EndDisabled();
		ImGui.SameLine();
		if (ImGui.Button("Close", .(120, 0)))
			ImGui.CloseCurrentPopup();
		ImGui.EndPopup();
	}

	/// Saves the scene, writes it as a map and copies it into the builds. Fills mMapExportReport.
	bool ExportMap()
	{
		mMapExportReport.Clear();
		if (mScene.Path.IsEmpty)
		{
			mMapExportReport.Set("Save the scene first (File > Save Scene As...).");
			return false;
		}
		SaveScene();
		let fileName = scope String();
		for (let c in mMapName.RawChars)
			fileName.Append((c.IsLetterOrDigit || c == ' ' || c == '-' || c == '_') ? c : '_');
		fileName.Trim();
		let file = scope $"{mMapFolder}/{fileName}{MapFiles.Extension}";
		let problems = scope List<String>();
		defer
		{
			ClearAndDeleteItems!(problems);
		}
		if (MapFiles.Export(mScene, file, mMapName, mMapAuthor, mMapDescription, problems) case .Err)
		{
			mMapExportReport.AppendF("Could not write {}.", file);
			Log.Error(mMapExportReport);
			return false;
		}
		mMapExportReport.AppendF("Exported {}.", file);
		if (mMapCopyToBuilds)
		{
			let copies = scope List<String>();
			defer
			{
				ClearAndDeleteItems!(copies);
			}
			CopyMapToBuilds(file, scope $"{fileName}{MapFiles.Extension}" , copies);
			for (let copy in copies)
				mMapExportReport.AppendF("\nCopied to {}.", copy);
		}
		for (let problem in problems)
			mMapExportReport.AppendF("\nWarning: {} The map will not load in a game that lacks it.", problem);
		Log.Info(mMapExportReport);
		return true;
	}

	/// Copies the map into the Maps folder of every built game under the project's Builds folder: any folder there
	/// (or one level further down) with a game.tessera or game.tpak in it.
	void CopyMapToBuilds(StringView file, StringView fileName, List<String> copies)
	{
		let builds = scope $"{Project.Current.Path}/Builds";
		if (!Directory.Exists(builds))
			return;
		let games = scope List<String>();
		defer
		{
			ClearAndDeleteItems!(games);
		}
		for (let entry in Directory.EnumerateDirectories(builds))
		{
			let folder = entry.GetFilePath(.. scope .());
			if (IsBuiltGame(folder))
				games.Add(new String(folder));
			else
			{
				for (let inner in Directory.EnumerateDirectories(folder))
				{
					let innerFolder = inner.GetFilePath(.. scope .());
					if (IsBuiltGame(innerFolder))
						games.Add(new String(innerFolder));
				}
			}
		}
		for (let game in games)
		{
			let maps = scope $"{game}/Maps";
			Directory.CreateDirectory(maps).IgnoreError();
			let target = scope $"{maps}/{fileName}";
			if (File.Copy(file, target, true) case .Ok)
				copies.Add(new String(target));
			else
				Log.Warning(scope $"Could not copy the map to {target}.");
		}
	}

	static bool IsBuiltGame(StringView folder) => File.Exists(scope $"{folder}/game.tessera") || File.Exists(scope $"{folder}/game.tpak");

	/// Test switch --export-map [name]: exports the opened scene (as the window would, copying into the builds)
	/// and logs MAP-EXPORT PASS or FAIL.
	void RunExportMapSwitch()
	{
		let name = scope String();
		if (!GetArg("--export-map", name) || name.StartsWith("--"))
			name.Set(mScene.Name);
		mMapName.Set(name);
		mMapFolder.Clear();
		MapFiles.Folder(mMapFolder);
		let ok = ExportMap();
		Log.Info(scope $"MAP-EXPORT {ok ? "PASS" : "FAIL"}: {mMapExportReport}");
	}
}
