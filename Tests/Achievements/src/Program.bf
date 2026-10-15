using System;
using System.IO;
using Tessera;
namespace AchievementTests;
/// Achievements without Steam: the project has no App ID here, so nothing in this test touches a Steam account.
class Program
{
    static bool Check(bool pass, StringView label) { Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}"); return pass; }
    public static int Main(String[] args)
    {
        if (args.Count == 2 && args[0] == "--steam-library-check")
        {
            // This mode is used only with a local fake API, never a real Steam account.
            Assets.ProjectPath.Set(args[1]);
            let initialized = Steam.Init(0);
            let loaded = !initialized && Steam.Library != null && Steam.Error.Contains("library lookup fixture");
            return Check(loaded, "Steam loads the project Libraries runtime from the editor asset path") ? 0 : 1;
        }
        let folder = "/tmp/tessera-achievement-test";
        Directory.CreateDirectory(folder).IgnoreError();
        Assets.ProjectPath.Set(folder);
        File.Delete(scope $"{folder}/{Achievements.FileName}").IgnoreError(); // left behind if an earlier run was interrupted
        Achievements.SaveName.Set("TesseraAchievementTest");
        Steam.AppId = 0;
        bool ok = Check(!Achievements.OnSteam && !Steam.IsReady, "with no App ID, Steam is never started");
        Achievements.ClearAll();

        let first = new AchievementInfo(); first.id.Set("FIRST_WIN"); first.name.Set("First \"Win\""); first.description.Set("Win a round.");
        let secret = new AchievementInfo(); secret.id.Set("SECRET"); secret.name.Set("Secret"); secret.hidden = true;
        Achievements.Definitions.Add(first); Achievements.Definitions.Add(secret);
        ok &= Check(Achievements.SaveDefinitions(), "the list saves to the project");
        Achievements.Reload();
        ok &= Check(Achievements.Definitions.Count == 2 && Achievements.Find("FIRST_WIN")?.name == "First \"Win\"" && Achievements.Find("SECRET").hidden && !Achievements.Find("FIRST_WIN").hidden, "and loads back with names, descriptions and the hidden flag");

        int heard = 0;
        Achievements.OnUnlocked.Add(new [&] (id) => { if (id == "FIRST_WIN") heard++; });
        ok &= Check(!Achievements.IsUnlocked("FIRST_WIN") && Achievements.Unlock("FIRST_WIN") && Achievements.IsUnlocked("FIRST_WIN") && heard == 1, "unlocking works once and tells listeners");
        ok &= Check(!Achievements.Unlock("FIRST_WIN") && heard == 1, "unlocking again changes nothing");
        Achievements.SetProgress("SECRET", 3, 5);
        let partway = Achievements.IsUnlocked("SECRET");
        Achievements.SetProgress("SECRET", 5, 5);
        ok &= Check(!partway && Achievements.IsUnlocked("SECRET"), "progress unlocks when it reaches the goal");
        ok &= Check(Achievements.AddStat("kills") == 1 && Achievements.AddStat("kills", 4) == 5 && Achievements.GetStat("kills") == 5 && Achievements.GetStat("never") == 0, "counters add up");

        // A fresh start reads the same progress back from the player's machine.
        Achievements.[Friend]sStateLoaded = false;
        ClearAndDeleteItems!(Achievements.[Friend]sUnlocked);
        for (let key in Achievements.[Friend]sStats.Keys) delete key;
        Achievements.[Friend]sStats.Clear();
        ok &= Check(Achievements.IsUnlocked("FIRST_WIN") && Achievements.IsUnlocked("SECRET") && Achievements.GetStat("kills") == 5, "progress is kept between runs");
        Achievements.Clear("FIRST_WIN");
        ok &= Check(!Achievements.IsUnlocked("FIRST_WIN") && Achievements.IsUnlocked("SECRET"), "one achievement can be locked again for testing");
        ok &= Check(Achievements.Unlock("NOT_LISTED") && Achievements.IsUnlocked("NOT_LISTED"), "an id missing from the list still unlocks, with a warning");
        Achievements.ClearAll();
        ok &= Check(!Achievements.IsUnlocked("SECRET") && Achievements.GetStat("kills") == 0, "everything can be cleared");

        // Mods and Workshop items: a mounted folder's files are found by their path inside it, ahead of the project's.
        let mod = "/tmp/tessera-achievement-test-mod";
        Directory.CreateDirectory(scope $"{mod}/Scenes").IgnoreError(); Directory.CreateDirectory(scope $"{folder}/Scenes").IgnoreError();
        File.WriteAllText(scope $"{folder}/Scenes/Main.tscene", "project").IgnoreError(); File.WriteAllText(scope $"{folder}/Scenes/Only.tscene", "project").IgnoreError();
        File.WriteAllText(scope $"{mod}/Scenes/Main.tscene", "mod").IgnoreError(); File.WriteAllText(scope $"{mod}/Scenes/Arena.tscene", "mod").IgnoreError();
        bool Is(StringView path, StringView expected) { let resolved = scope String(); Assets.ResolvePath(path, resolved); return resolved == expected; }
        let before = Is("Scenes/Main.tscene", scope $"{folder}/Scenes/Main.tscene");
        Assets.AddSearchPath(mod); Assets.AddSearchPath(mod);
        ok &= Check(before && Assets.SearchPaths.Count == 1 && Is("Scenes/Main.tscene", scope $"{mod}/Scenes/Main.tscene") && Is("Scenes/Arena.tscene", scope $"{mod}/Scenes/Arena.tscene"), "a mounted folder adds files and replaces the project's file of the same path");
        ok &= Check(Is("Scenes/Only.tscene", scope $"{folder}/Scenes/Only.tscene") && Is("Missing.png", scope $"{folder}/Missing.png") && Is("/abs/x.png", "/abs/x.png"), "anything the mod lacks still comes from the project");
        Assets.RemoveSearchPath(mod);
        ok &= Check(Assets.SearchPaths.Count == 0 && Is("Scenes/Main.tscene", scope $"{folder}/Scenes/Main.tscene"), "unmounting restores the project's file");
        ok &= Check(!Workshop.Available && Workshop.MountInstalled() == 0, "with no App ID the Workshop reports unavailable and mounts nothing");
        bool told = false;
        Workshop.Browse(.Popular, 1, "", new [&] (items, ok) => { told = !ok && items.Count == 0; });
        ok &= Check(told, "and a browse request is answered at once as failed");
        for (let f in StringView[?]("Scenes/Main.tscene", "Scenes/Arena.tscene")) File.Delete(scope $"{mod}/{f}").IgnoreError();
        for (let f in StringView[?]("Scenes/Main.tscene", "Scenes/Only.tscene")) File.Delete(scope $"{folder}/{f}").IgnoreError();
        Directory.Delete(scope $"{mod}/Scenes").IgnoreError(); Directory.Delete(mod).IgnoreError(); Directory.Delete(scope $"{folder}/Scenes").IgnoreError();
        File.Delete(scope $"{folder}/{Achievements.FileName}").IgnoreError(); Directory.Delete(folder).IgnoreError();
        return ok ? 0 : 1;
    }
}
