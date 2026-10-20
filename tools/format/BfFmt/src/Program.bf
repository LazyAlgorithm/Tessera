using System;
using System.IO;

namespace BfFmt;

/// Formats Beef source files in place with the Beef IDE's own formatter (Format Document). Used by
/// tools/format/format_code.py, which also restores string literals and checks that only whitespace changed.
///   BfFmt [--defines=A,B] file.bf...   (--defines applies to the files after it)
class Program
{
	[CLink] static extern void* BfSystem_Create();
	[CLink] static extern void* BfSystem_CreateProject(void* system, char8* name, char8* dir);
	[CLink] static extern void* BfSystem_CreateParser(void* system, void* project);
	[CLink] static extern void BfProject_SetOptions(void* project, int32 targetType, char8* startupObject, char8* macros, int32 optLevel, int32 ltoType, int32 relocType, int32 picLevel, int32 flags);
	[CLink] static extern void* BfSystem_CreatePassInstance(void* system);
	[CLink] static extern void BfParser_SetSource(void* parser, char8* data, int32 length, char8* fileName, int32 textVersion);
	[CLink] static extern bool BfParser_Parse(void* parser, void* passInstance, bool compatMode);
	[CLink] static extern bool BfParser_Reduce(void* parser, void* passInstance);
	[CLink] static extern char8* BfParser_Format(void* parser, int32 start, int32 end, int32** charMapping, int32 maxCol, int32 tabSize, bool tabsAsSpaces, bool indentCaseLabels);
	[CLink] static extern void BfSystem_DeleteParser(void* system, void* parser);
	[CLink] static extern void BfPassInstance_Delete(void* passInstance);
	[CLink] static extern int32 BfPassInstance_GetErrorCount(void* passInstance);

	public static int Main(String[] args)
	{
		let system = BfSystem_Create();
		let project = BfSystem_CreateProject(system, "Fmt", "/tmp");
		int failures = 0;
		for (let path in args)
		{
			// --defines=A,B: preprocessor symbols, so that code under #if A is formatted too.
			if (path.StartsWith("--defines="))
			{
				let macros = scope String(path.Substring(10));
				macros.Replace(',', '\n');
				BfProject_SetOptions(project, 0, "", macros, 0, 0, 0, 0, 0);
				continue;
			}
			let text = scope String();
			if (File.ReadAllText(path, text, true) case .Err)
			{
				Console.WriteLine($"cannot read {path}");
				failures++;
				continue;
			}
			let parser = BfSystem_CreateParser(system, project);
			let pass = BfSystem_CreatePassInstance(system);
			BfParser_SetSource(parser, text.CStr(), (int32)text.Length, scope String(path).CStr(), -1);
			BfParser_Parse(parser, pass, false);
			BfParser_Reduce(parser, pass);
			if (BfPassInstance_GetErrorCount(pass) > 0)
			{
				Console.WriteLine($"parse errors, skipped: {path}");
				failures++;
			}
			else
			{
				int32* mapping = null;
				let formatted = scope String(BfParser_Format(parser, 0, (int32)text.Length, &mapping, 0, 4, false, false));
				if (formatted != text)
				{
					File.WriteAllText(path, formatted);
					Console.WriteLine($"formatted {path}");
				}
			}
			BfPassInstance_Delete(pass);
			BfSystem_DeleteParser(system, parser);
		}
		return failures;
	}
}
