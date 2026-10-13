using System;
using System.IO;

namespace Tessera;

/// Where a game keeps the player's own files: settings, saves, maps they made. One folder per game per player, in
/// the place each system expects:
///
///   Windows   %APPDATA%\Tessera\<Game>\
///   Linux     ~/.local/share/Tessera/<Game>/      (or $XDG_DATA_HOME)
///   macOS     ~/Library/Application Support/Tessera/<Game>/
///   Web       the browser's storage for the page (kept between visits)
///
///   let path = scope $"{GamePaths.PlayerData}notes.txt";
///
/// The game folder itself (beside the executable, or inside the asset pack) is for reading only; write here.
static class GamePaths
{
	static String sPlayerData ~ delete _;

	/// The publisher's part of the path. Changing it moves where everything is kept, so set it once, early.
	public static String Company = new .("Tessera") ~ delete _;
	/// The game's part of the path: its name, from the build's manifest.
	public static String Game = new .("Game") ~ delete _;

	/// The player's folder for this game, ending in a slash. Made the first time it is asked for.
	public static StringView PlayerData
	{
		get
		{
			if (sPlayerData == null)
			{
				sPlayerData = new String();
				let pref = SDL.SDL_GetPrefPath(Company.CStr(), Game.CStr());
				if (pref != null)
				{
					sPlayerData.Append(StringView(pref));
					SDL.SDL_free(pref);
				}
				else
				{
					// No system folder (a sandbox that refuses one): beside the working folder.
					Directory.GetCurrentDirectory(sPlayerData);
					sPlayerData.Append("/player-data/");
					Directory.CreateDirectory(sPlayerData).IgnoreError();
				}
				sPlayerData.Replace('\\', '/');
				if (!sPlayerData.EndsWith('/'))
					sPlayerData.Append('/');
			}
			return sPlayerData;
		}
	}

	/// Where SaveSystem's file storage keeps saves: PlayerData + "saves/".
	public static void Saves(String path) => path.AppendF("{}saves/", PlayerData);

	/// Call after changing Company or Game, so that the folder is looked up again.
	public static void Refresh() => DeleteAndNullify!(sPlayerData);
}
