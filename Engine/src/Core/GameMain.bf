using System;
using System.IO;
namespace Tessera;

/// Editor-free packaged game entry point. Distribution layout: game.tessera, Assets/, Engine/assets/.
static class GameMain
{
    public static int Run(String[] args)
    {
        let root = scope String();
        let basePath = SDL.SDL_GetBasePath();
        if (basePath != null) root.Set(StringView(basePath));
        for (int i = 0; i + 1 < args.Count; i++)
            if (args[i] == "--game") root.Set(args[i + 1]);
        // A packed game: its assets, the engine's shaders and its manifest are in game.tpak, as if beside it, with
        // each scene's own files in a pack of their own when the build split them.
        AssetPack.MountGame(root);
        let manifest = scope String();
        if (AssetPack.ReadAllText(scope $"{root}/game.tessera", manifest) case .Err)
        { Console.WriteLine("Missing game.tessera (or game.tpak). Use --game <package folder>."); return 1; }
#if BF_PLATFORM_WASM
        // In a browser this function is left for good once the game starts (see WebPlatform.RunMainLoop) while the game
        // keeps running, so the game must not live on its stack.
        let app = new GameApp();
#else
        let app = scope GameApp();
#endif
        // A built game has no console: keep a log beside it (or in the temporary folder if that is read-only),
        // and note in it what the game was doing if it ever stops moving.
        {
            let logPath = scope String();
            Environment.GetExecutableFilePath(logPath);
            let slash = Math.Max(logPath.LastIndexOf('/'), logPath.LastIndexOf('\\'));
            if (slash >= 0)
                logPath.RemoveToEnd(slash + 1);
            logPath.Append("log.txt");
            if (!Log.OpenFile(logPath))
            {
                logPath.Clear();
                System.IO.Path.GetTempPath(logPath);
                logPath.Append("/tessera-game-log.txt");
                Log.OpenFile(logPath);
            }
            Watchdog.Start();
        }
        for (let line in manifest.Split('\n'))
        {
            let eq = line.IndexOf('='); if (eq < 0) continue;
            var key = line.Substring(0, eq); var value = line.Substring(eq + 1); key.Trim(); value.Trim();
            if (key == "name") app.GameName.Set(value);
            if (key == "startScene") app.StartScene.Set(value);
            if (key == "audioHrtf") Audio.Hrtf = value == "1";
            if (key == "fullscreen") GameWindow.StartsFullscreen = value == "1";
            // With the anti-cheat on, a built game also closes its memory to other programs and watches itself.
            if (key == "antiCheat" && value == "1")
            {
                AntiCheat.Enabled = true;
                Log.Info(AntiCheat.Harden() ? "Anti-cheat on: this game's memory is closed to other programs." : "Anti-cheat on. (This system would not close the game's memory to other programs.)");
            }
            if (key == "voiceChat") VoiceChat.Enabled = value == "1";
            if (key == "voicePushToTalk") VoiceChat.PushToTalk = value == "1";
            if (key == "voiceProximity") VoiceChat.Proximity = value == "1";
            if (key == "voiceTeamOnly") VoiceChat.TeamOnly = value == "1";
            if (key == "voiceKey") { if (Enum.Parse<KeyCode>(value) case .Ok(let voiceKey)) VoiceChat.PushToTalkKey = voiceKey; }
            if (key == "steamAppId") Steam.AppId = (uint32)Math.Max(SceneSerializer.ParseInt(value), 0);
            if (key == "name") Achievements.SaveName.Set(value);
            if (key == "name") WebRtc.AppName.Set(value);
            if (key == "name") { GamePaths.Game.Set(value); GamePaths.Refresh(); }
            if (key == "company" && !value.IsEmpty) { GamePaths.Company.Set(value); GamePaths.Refresh(); }
            if (key == "loadSaveAtStart") SaveSystem.LoadAtStart = value == "1";
            if (key == "saveSlot" && !value.IsEmpty) SaveSystem.StartSlot.Set(value);
        }
        Assets.ProjectPath.Set(scope $"{root}/Assets");
        Environment.SetEnvironmentVariable("TESSERA_ROOT", root);
        for (int i = 0; i < args.Count; i++)
        {
            let arg = args[i];
            if (arg == "--server") { app.Headless = true; NetworkSession.ModeOverride = .Server; }
            else if (arg == "--host") NetworkSession.ModeOverride = .Host;
            else if (arg == "--bot") NetworkSession.BotOverride = true;
            else if (arg == "--connect" && i + 1 < args.Count)
            { NetworkSession.ModeOverride = .Client; NetworkSession.AddressOverride.Set(args[++i]); }
            else if (arg == "--port" && i + 1 < args.Count) NetworkSession.PortOverride = SceneSerializer.ParseInt(args[++i]);
            else if (arg == "--lag" && i + 1 < args.Count) NetworkManager.SimulatedLagMs = Math.Max(0, SceneSerializer.ParseInt(args[++i]));
            else if (arg == "--loss" && i + 1 < args.Count) NetworkManager.SimulatedLossPercent = Mathf.Clamp(SceneSerializer.ParseFloat(args[++i]), 0, 100);
            else if (arg == "--jitter" && i + 1 < args.Count) NetworkManager.SimulatedJitterMs = Math.Max(0, SceneSerializer.ParseInt(args[++i]));
            else if (arg == "--teststall") Watchdog.TestStall = true;
            else if (arg == "--netstats") NetworkManager.LogStats = true;
            else if (arg == "--editor") { Console.WriteLine("This game was built without the editor."); return 1; }
        }
        return app.Run(args);
    }
}
