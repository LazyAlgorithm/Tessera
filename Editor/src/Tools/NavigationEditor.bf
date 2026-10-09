using System;
using System.IO;
using Tessera;
namespace Tessera.Editor;
extension EditorApp
{
    Vector3 mNavigationDirtyCenter,mNavigationDirtySize=.(16,10,16);
    void DrawNavigationTools(NavigationSurface surface)
    {
        ImGui.TextWrapped("Position is the minimum corner of the bake bounds. Walking samples the highest floor; Flying samples free space in 3D. Cell size trades detail for memory and bake time.");
        if(ImGui.Button("Bake & Save Navigation"))
        {
            if(surface.bakedData.IsEmpty)
            {
                let name=scope String();for(let c in (StringView)surface.GameObject.Name) name.Append(c.IsLetterOrDigit ? c : '_');
                surface.bakedData.Set(scope $"{name}.tnav");MarkDirty();
            }
            if(surface.Bake() && surface.SaveData()) {Log.Info("Navigation baked and saved.");RefreshAssetList();}
        }
        ImGui.SameLine();if(ImGui.Button("Load Baked Data")) surface.LoadData();
        if(surface.Data!=null) ImGui.Text(scope $"{surface.Data.cells.Count} cells; revision {surface.Data.Revision}; chunk size {surface.Data.chunkSize}");
        if(ImGui.CollapsingHeader("Rebuild Changed Chunks"))
        {
            ImGui.DragFloat3("Changed bounds center",ref mNavigationDirtyCenter);
            ImGui.DragFloat3("Changed bounds size",ref mNavigationDirtySize,0.1f,0.1f,100000);
            if(ImGui.Button("Rebuild Chunks"))
            {
                let half=Vector3.Abs(mNavigationDirtySize)*0.5f;
                if(surface.Rebuild(.(mNavigationDirtyCenter-half,mNavigationDirtyCenter+half)))
                {surface.SaveData();Log.Info("Changed navigation chunks rebuilt.");}
            }
        }
    }
}
