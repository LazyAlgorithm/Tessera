using System;
using System.Collections;
using System.IO;
using System.Threading;
using Tessera;

namespace TerrainTests;

class Program
{
    static bool Check(bool pass, StringView label) { Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}"); return pass; }

    /// Runs frames until the terrain has stopped loading, or a time limit passes.
    static void Settle(Scene scene, VoxelTerrain terrain)
    {
        int stable = 0, last = -1;
        for (int i = 0; i < 3000 && stable < 40; i++)
        {
            Time.DeltaTime = 0.016f; Time.UnscaledDeltaTime = 0.016f;
            scene.Update();
            Thread.Sleep(2);
            let busy = terrain.[Friend]mBusy + terrain.[Friend]mJobs.Count + terrain.[Friend]mFinished.Count;
            if (terrain.ChunkCount == last && busy == 0) stable++; else stable = 0;
            last = terrain.ChunkCount;
        }
    }

    static void SaveScene(Scene scene, StringView path)
    {
        let text = scope String();
        SceneSerializer.Save(scene, text);
        File.WriteAllText(path, text).IgnoreError();
    }

    static bool LoadScene(Scene scene, StringView path)
    {
        let text = scope String();
        if (File.ReadAllText(path, text) case .Err)
            return false;
        SceneSerializer.Load(scene, text);
        return true;
    }

    /// The height of the ground under a point, or NaN where there is none.
    static float Ground(VoxelTerrain terrain, float x, float z)
    {
        Vector3 point;
        if (terrain.Raycast(Ray(.(x, 60, z), .(0, -1, 0)), 200, out point))
            return point.y;
        return float.NaN;
    }

    public static int Main(String[] args)
    {
        bool ok = true;
        let folder = "/tmp/tessera-terrain-test";
        Directory.CreateDirectory(folder).IgnoreError();
        {
            let scene = scope Scene();
            let terrain = scene.CreateGameObject("Terrain").AddComponent<VoxelTerrain>();
            terrain.generateColliders = false;
            ok &= Check(terrain.mode == .Fixed && terrain.sizeX == 4 && terrain.sizeZ == 4 && terrain.AreaSize.x == 128, "a new terrain is a fixed 4 x 4 chunk area (128 m), not an endless one");
            scene.StartPlay();
            VoxelTerrain.ViewerPosition = .(5000, 0, 5000);   // the camera far away: a fixed terrain does not care
            Settle(scene, terrain);
            ok &= Check(terrain.ChunkCount == 4 * 4 * 4, scope $"the whole area is loaded wherever the camera is ({terrain.ChunkCount} chunks)");
            let middle = Ground(terrain, 64, 64), corner = Ground(terrain, 3, 3), far = Ground(terrain, 120, 125);
            ok &= Check(Math.Abs(middle) < 0.6f && Math.Abs(corner) < 0.6f && Math.Abs(far) < 0.6f, scope $"it starts flat at height 0 (measured {middle:0.00}, {corner:0.00}, {far:0.00})");
            ok &= Check(Ground(terrain, -10, 64).IsNaN && Ground(terrain, 64, 140).IsNaN && Ground(terrain, 300, 300).IsNaN, "there is no ground beyond the edge of the area");
            terrain.ModifySphere(.(64, 0, 64), 8, 6);
            Settle(scene, terrain);
            let raised = Ground(terrain, 64, 64);
            terrain.ModifySphere(.(20, 0, 20), 6, -6);
            Settle(scene, terrain);
            let dug = Ground(terrain, 20, 20);
            ok &= Check(raised > 2 && dug < -2 && Math.Abs(Ground(terrain, 100, 30)) < 0.6f, scope $"it can be raised and dug by hand, and the rest stays flat (hill {raised:0.0}, pit {dug:0.0})");
            terrain.flatHeight = 10; terrain.sizeX = 2; terrain.OnValidate();
            Settle(scene, terrain);
            ok &= Check(terrain.ChunkCount == 2 * 4 * 4 && Math.Abs(Ground(terrain, 40, 100) - 10) < 0.6f && Ground(terrain, 100, 100).IsNaN, scope $"changing the size and the starting height rebuilds it ({terrain.ChunkCount} chunks, ground at {Ground(terrain, 40, 100):0.0})");

            // ---- a game's own generator ----
            terrain.flatHeight = 0; terrain.sizeX = 4;
            terrain.SetGenerator(new (x, y, z) => (x * 0.1f) - y);     // a ramp rising along X
            Settle(scene, terrain);
            let low = Ground(terrain, 20, 64), high = Ground(terrain, 100, 64);
            ok &= Check(Math.Abs(low - 2) < 0.7f && Math.Abs(high - 10) < 0.7f && Ground(terrain, 140, 64).IsNaN, scope $"a custom generator shapes the ground, still inside the area ({low:0.0} at x=20, {high:0.0} at x=100)");
            terrain.SetGenerator(null);
            Settle(scene, terrain);
            ok &= Check(Math.Abs(Ground(terrain, 100, 64)) < 0.6f, "and removing it brings the flat ground back");

            // ---- endless, by choice ----
            terrain.mode = .Endless; terrain.viewDistance = 2; terrain.OnValidate();
            VoxelTerrain.ViewerPosition = .(0, 0, 0);
            Settle(scene, terrain);
            let nearCount = terrain.ChunkCount;
            let hills = Ground(terrain, 10, 10), hills2 = Ground(terrain, -40, 25);
            ok &= Check(nearCount > 20 && !hills.IsNaN && !hills2.IsNaN && Math.Abs(hills - hills2) > 0.05f, scope $"Endless mode generates rolling ground around the camera, including where a fixed area has none ({hills:0.0} and {hills2:0.0})");
            VoxelTerrain.ViewerPosition = .(2000, 0, 0);
            Settle(scene, terrain);
            ok &= Check(!Ground(terrain, 2000, 5).IsNaN && Ground(terrain, 10, 10).IsNaN, "and follows the camera, dropping what is left behind");
            terrain.SetGenerator(new (x, y, z) => 5 - y);
            Settle(scene, terrain);
            ok &= Check(Math.Abs(Ground(terrain, 2010, -20) - 5) < 0.6f, "a custom generator works in Endless mode too");
            SaveScene(scene, scope $"{folder}/new.tscene");
        }
        // ---- scenes ----
        {
            let scene = scope Scene();
            ok &= Check(LoadScene(scene, scope $"{folder}/new.tscene") && scene.FindComponent<VoxelTerrain>().mode == .Endless, "a scene remembers a terrain's mode");
        }
        {
            let scene = scope Scene();
            scene.CreateGameObject("Terrain").AddComponent<VoxelTerrain>().sizeZ = 7;
            SaveScene(scene, scope $"{folder}/fixed.tscene");
            let loaded = scope Scene();
            let fine = LoadScene(loaded, scope $"{folder}/fixed.tscene");
            let terrain = fine ? loaded.FindComponent<VoxelTerrain>() : null;
            ok &= Check(terrain != null && terrain.mode == .Fixed && terrain.sizeZ == 7, "a fixed terrain saves and loads as fixed, with its size");
            // A scene from before terrains had a mode: strip the new lines, as an old file would lack them.
            let text = scope String();
            File.ReadAllText(scope $"{folder}/fixed.tscene", text).IgnoreError();
            let old = scope String();
            for (let line in text.Split('\n'))
                if (!line.StartsWith("field mode ") && !line.StartsWith("field sizeX ") && !line.StartsWith("field sizeZ ") && !line.StartsWith("field flatHeight "))
                    old..Append(line).Append('\n');
            File.WriteAllText(scope $"{folder}/old.tscene", old).IgnoreError();
            let legacy = scope Scene();
            ok &= Check(LoadScene(legacy, scope $"{folder}/old.tscene") && legacy.FindComponent<VoxelTerrain>().mode == .Endless, "a scene saved before this change keeps its endless terrain");
        }
        for (let name in StringView[?]("new.tscene", "fixed.tscene", "old.tscene")) File.Delete(scope $"{folder}/{name}").IgnoreError();
        Directory.Delete(folder).IgnoreError();
        Scene.Active = null;
        return ok ? 0 : 1;
    }
}
