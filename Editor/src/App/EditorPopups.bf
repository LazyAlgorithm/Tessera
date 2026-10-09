using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// Popups and keyboard shortcuts.
extension EditorApp
{
	void DrawPopups()
	{
		if (mOpenNewScript)
		{
			ImGui.OpenPopup("New Script");
			mOpenNewScript = false;
		}
		if (ImGui.BeginPopupModal("New Script", null, ImGui.WindowFlags.AlwaysAutoResize))
		{
			ImGui.Text("Class name");
			ImGui.SetNextItemWidth(280);
			ImGui.InputText("##scriptname", mNewScriptName);
			ImGui.TextDisabled("Created in the folder shown in Project. Rebuild & Reload to use it.");
			if (ImGui.Button("Create", .(120, 0)))
			{
				CreateScript(mNewScriptName);
				ImGui.CloseCurrentPopup();
			}
			ImGui.SameLine();
			if (ImGui.Button("Cancel", .(120, 0)))
				ImGui.CloseCurrentPopup();
			ImGui.EndPopup();
		}

		if (mOpenSaveAs)
		{
			mSceneSaveName.Set(mScene.Name);
			ImGui.OpenPopup("Save Scene As");
			mOpenSaveAs = false;
		}
		if (ImGui.BeginPopupModal("Save Scene As", null, ImGui.WindowFlags.AlwaysAutoResize))
		{
			ImGui.Text("Scene name (saved in Assets/Scenes)");
			ImGui.SetNextItemWidth(320);
			ImGui.InputText("##scenename", mSceneSaveName);
			if (ImGui.Button("Save", .(120, 0)) && ProjectGenerator.IsValidName(mSceneSaveName))
			{
				mScene.Name.Set(mSceneSaveName);
				mScene.Path.Clear();
				Directory.CreateDirectory(scope $"{Assets.ProjectPath}/Scenes").IgnoreError();
				mScene.Path.AppendF("{}/Scenes/{}.tscene", Assets.ProjectPath, mSceneSaveName);
				SaveScene();
				ImGui.CloseCurrentPopup();
			}
			ImGui.SameLine();
			if (ImGui.Button("Cancel", .(120, 0)))
				ImGui.CloseCurrentPopup();
			ImGui.EndPopup();
		}
	}

	void HandleShortcuts()
	{
		// While the code editor has focus, keys belong to it; only saving is handled here.
		if (mScriptsFocused)
		{
			if (ImGui.IsKeyDown(ImGui.Key.LeftCtrl) && ImGui.IsKeyPressed(ImGui.Key.S) && mActiveScript != null)
				SaveScript(mActiveScript);
			return;
		}
		let typing = (ImGui.tn_imgui_capture_flags() & 4) != 0;
		if (typing)
			return;
		let ctrl = ImGui.IsKeyDown(ImGui.Key.LeftCtrl);
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.S)) SaveScene();
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.P)) TogglePlay();
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.R)) RequestRebuild();
		if (mPlay == .Playing && mGameFocused)
			return;
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.D)) DuplicateSelected();
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.Z))
		{
			if (ImGui.IsKeyDown(ImGui.Key.LeftShift)) Redo(); else Undo();
		}
		if (ctrl && ImGui.IsKeyPressed(ImGui.Key.Y)) Redo();
		if (ImGui.IsKeyPressed(ImGui.Key.Delete)) DeleteSelected();
		if (!mFlying && !ctrl)
		{
			if (ImGui.IsKeyPressed(ImGui.Key.W)) mGizmoOperation = 0;
			if (ImGui.IsKeyPressed(ImGui.Key.E)) mGizmoOperation = 1;
			if (ImGui.IsKeyPressed(ImGui.Key.R)) mGizmoOperation = 2;
			if (ImGui.IsKeyPressed(ImGui.Key.F)) FocusSelected();
		}
	}
}
