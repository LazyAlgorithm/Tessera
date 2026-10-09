using System;
using System.Collections;
using System.Threading;

namespace Tessera;

enum LogLevel
{
	Info,
	Warning,
	Error
}

/// Engine log. Entries are kept for the editor console and mirrored to stdout.
static class Log
{
	public struct Entry
	{
		public LogLevel level;
		public String text;
	}

	public const int MaxEntries = 2000;
	public static List<Entry> Entries = new .() ~ { for (let e in _) delete e.text; delete _; };
	public static int Version;
	static Monitor sMonitor = new .() ~ delete _;
	static System.IO.FileStream sFile ~ delete _;

	/// Also writes the log to a file from now on, replacing what was in it. Built games do this (log.txt beside
	/// the game, or in the temporary folder if that cannot be written), since they have no console to print to.
	public static bool OpenFile(StringView path)
	{
		using (sMonitor.Enter())
		{
			delete sFile;
			sFile = new .();
			if (sFile.Create(path, .Write, .Read) case .Err)
			{
				delete sFile;
				sFile = null;
				return false;
			}
			return true;
		}
	}

	/// Writes a line to the log file only, straight away. Safe from any thread.
	public static void ToFile(StringView text)
	{
		using (sMonitor.Enter())
		{
			if (sFile == null)
				return;
			sFile.Write(Span<uint8>((uint8*)text.Ptr, text.Length)).IgnoreError();
			sFile.Write(Span<uint8>((uint8*)"\r\n", 2)).IgnoreError();
			sFile.Flush().IgnoreError();
		}
	}

	public static void Info(StringView text) => Add(.Info, text);
	public static void Warning(StringView text) => Add(.Warning, text);
	public static void Error(StringView text) => Add(.Error, text);

	public static void Add(LogLevel level, StringView text)
	{
		using (sMonitor.Enter())
		{
			if (Entries.Count >= MaxEntries)
			{
				delete Entries[0].text;
				Entries.RemoveAt(0);
			}
			Entry entry;
			entry.level = level;
			entry.text = new String(text);
			Entries.Add(entry);
			Version++;
		}
		switch (level)
		{
		case .Info: ToFile(text);
		case .Warning: ToFile(scope $"[warning] {text}");
		case .Error: ToFile(scope $"[error] {text}");
		}
		switch (level)
		{
		case .Info: Console.WriteLine(text);
		case .Warning: Console.WriteLine("[warning] {}", text);
		case .Error: Console.WriteLine("[error] {}", text);
		}
	}

	public static void Clear()
	{
		using (sMonitor.Enter())
		{
			for (let e in Entries)
				delete e.text;
			Entries.Clear();
			Version++;
		}
	}
}
