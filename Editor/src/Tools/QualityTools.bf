using System;

namespace Tessera.Editor;

/// Window > Graphics Quality: the presets and each setting, applied at once to the Scene and Game views, to see what a
/// player's Low or Ultra looks like (docs/quality.md). The editor's own choice is not saved as the player's.
extension EditorApp
{
	bool mShowQuality;

	protected override bool LoadsPlayerQuality => false;

	void DrawQualityWindow()
	{
		if (!mShowQuality)
			return;
		let viewport = ImGui.GetMainViewport();
		ImGui.SetNextWindowPos(.(viewport.workPos.x + viewport.workSize.x - 700, viewport.workPos.y + 80), 4);
		ImGui.SetNextWindowSize(.(330, 470), 4);
		if (ImGui.Begin("Graphics Quality", &mShowQuality))
		{
			for (int i < 4)
			{
				let level = (QualityLevel)i;
				if (i > 0)
					ImGui.SameLine();
				if (ImGui.Selectable(scope String(Quality.Names[i]).CStr(), Quality.Level == level, 0, .(70, 0)))
					Quality.Set(level);
			}
			ImGui.TextDisabled(scope String()..AppendF("In use: {}   Suggested here: {}", Quality.Names[(int)Quality.Level], Quality.Names[(int)Quality.Recommended]).CStr());
			ImGui.Separator();
			var v = Quality.Current;
			var changed = false;
			changed |= ImGui.SliderFloat("Render Scale", ref v.renderScale, 0.25f, 1, "%.2f");
			changed |= ImGui.Checkbox("Antialias", ref v.antialias);
			changed |= ImGui.Checkbox("Shadows", ref v.shadows);
			var sizeIndex = (float)Math.Round(Math.Log(v.shadowMapSize / 512.0) / Math.Log(2));
			if (ImGui.SliderFloat(scope String()..AppendF("Shadow Map ({})###shadowmap", v.shadowMapSize).CStr(), ref sizeIndex, 0, 4, ""))
			{
				v.shadowMapSize = (int32)(512 << (int32)Math.Round(sizeIndex));
				changed = true;
			}
			changed |= ImGui.SliderFloat("Shadow Distance", ref v.shadowDistance, 0.25f, 3, "x%.2f");
			changed |= ImGui.Checkbox("Ambient Occlusion", ref v.ambientOcclusion);
			changed |= ImGui.Checkbox("Depth of Field", ref v.depthOfField);
			changed |= ImGui.Checkbox("Motion Blur", ref v.motionBlur);
			changed |= ImGui.SliderFloat("Detail Distance", ref v.lodBias, 0.25f, 3, "x%.2f");
			changed |= ImGui.SliderFloat("Foliage Distance", ref v.foliageDistance, 0.25f, 3, "x%.2f");
			changed |= ImGui.Checkbox("GPU Skinning", ref v.gpuSkinning);
			changed |= ImGui.Checkbox("Vsync", ref v.vsync);
			if (changed)
			{
				Quality.Current = v;
				Quality.Apply();
			}
			ImGui.Separator();
			ImGui.TextWrapped("Applies to the Scene and Game views now. Games set it with Quality.Set, and the player's choice is saved with Quality.Save.");
			if (ImGui.Button("Back to High"))
				Quality.Set(.High);
		}
		ImGui.End();
	}
}
