using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// What the script editor knows about code: every type and its members, read straight from the engine's source
/// files and the project's scripts. Nothing here is a hand-kept list, so a new engine feature or a script the
/// game adds is coloured and completed the next time the index is built, with no editor change.
static class ApiIndex
{
	[CLink] static extern void tn_code_api_begin();
	[CLink] static extern void tn_code_api_type(char8* name, char8* baseType, char8* members);
	[CLink] static extern void tn_code_api_end();
	[CLink] static extern char8* tn_code_api_complete(char8* text);

	public enum MemberKind { Method, Field, Property }

	/// One declared member with enough of its signature to call it: used to offer it as a visual scripting node.
	public class Member
	{
		public String name = new .() ~ delete _;
		public MemberKind kind;
		public bool isStatic, isPublic, canSet, isGeneric, isMutating;
		/// The declared type, as written ("float", "GameObject", "void").
		public String type = new .() ~ delete _;
		/// Parameters as written: type, name, and whether it is an out parameter. Null type means the
		/// parameter list could not be read (it ran over several lines), so the member cannot be called from a node.
		public List<(String type, String name, bool isOut, bool hasDefault)> parameters = new .() ~ { for (let p in _) { delete p.type; delete p.name; } delete _; };
		public bool unreadable;
	}

	public class TypeEntry
	{
		public String name = new .() ~ delete _;
		public String baseType = new .() ~ delete _;
		/// The part of the engine it belongs to, from its source folder ("Audio", "Physics"); empty for the game's own.
		public String group = new .() ~ delete _;
		public List<String> members = new .() ~ DeleteContainerAndItems!(_);
		public List<Member> signatures = new .() ~ DeleteContainerAndItems!(_);
		public bool isEnum, isStruct, isNested, isStatic, isAbstract, fromProject, isDelegate;

		public bool Has(StringView member)
		{
			for (let m in members)
				if (m == member)
					return true;
			return false;
		}
	}

	static Dictionary<String, TypeEntry> sEngine = new .() ~ DeleteDictionaryAndValues!(_);
	static Dictionary<String, TypeEntry> sProject = new .() ~ DeleteDictionaryAndValues!(_);
	static String sEngineRoot = new .() ~ delete _;
	static String sProjectPath = new .() ~ delete _;
	/// Goes up each time the index is rebuilt, so open scripts know to recolour.
	public static int Revision;

	public static int TypeCount => sEngine.Count + sProject.Count;
	static bool sBuilt;
	// Nested types that lost their name to a top-level type; kept only so they can be freed.
	static List<TypeEntry> sDiscarded = new .() ~ DeleteContainerAndItems!(_);

	/// Remembers where the code is; the files are read the first time a script is opened.
	public static void SetRoots(StringView engineRoot, StringView projectPath)
	{
		sEngineRoot.Set(engineRoot);
		sProjectPath.Set(projectPath);
		sBuilt = false;
	}

	/// Builds the index if it has not been built, otherwise picks up changes to the project's scripts.
	public static void Ensure()
	{
		if (!sBuilt)
			Build(scope String(sEngineRoot), scope String(sProjectPath));
		else
			RefreshProject();
	}

	/// Reads the engine's source and the project's scripts. Call once when a project opens.
	public static void Build(StringView engineRoot, StringView projectPath)
	{
		sEngineRoot.Set(engineRoot);
		sProjectPath.Set(projectPath);
		sBuilt = true;
		Clear(sEngine);
		if (!engineRoot.IsEmpty)
			ScanFolder(scope $"{engineRoot}/Engine/src", sEngine, true, "");
		RefreshProject();
	}

	/// Reads the project's scripts again. Called when a script or graph is saved.
	public static void RefreshProject()
	{
		Clear(sProject);
		if (!sProjectPath.IsEmpty)
			ScanFolder(scope $"{sProjectPath}/src", sProject, false, "");
		Push();
	}

	static void Clear(Dictionary<String, TypeEntry> types)
	{
		for (let entry in types.Values)
			delete entry;
		types.Clear();
	}

	/// Every type, the engine's first and then the project's.
	public static void AllTypes(List<TypeEntry> output)
	{
		for (let entry in sEngine.Values)
			output.Add(entry);
		for (let entry in sProject.Values)
			output.Add(entry);
	}

	/// True when a type is, or is built on, another ("AudioSource" is a "Component").
	public static bool IsA(StringView type, StringView ancestor)
	{
		var current = scope String(type);
		for (int depth < 10)
		{
			if (current == ancestor)
				return true;
			let entry = Find(current);
			if (entry == null || entry.baseType.IsEmpty)
				return false;
			current.Set(entry.baseType);
		}
		return false;
	}

	/// A type the index knows, from the project first and then the engine, or null.
	public static TypeEntry Find(StringView name)
	{
		if (sProject.TryGetValueAlt(name, let mine))
			return mine;
		if (sEngine.TryGetValueAlt(name, let engine))
			return engine;
		return null;
	}

	/// What the editor would suggest with the cursor at the end of this script text, one per line.
	public static void Complete(StringView text, String output)
	{
		output.Append(tn_code_api_complete(scope String(text).CStr()));
	}

	static void Push()
	{
		tn_code_api_begin();
		let members = scope String();
		for (let types in Dictionary<String, TypeEntry>[?](sEngine, sProject))
		{
			for (let entry in types.Values)
			{
				members.Clear();
				for (let member in entry.members)
				{
					members.Append(member);
					members.Append('\n');
				}
				tn_code_api_type(entry.name.CStr(), entry.baseType.CStr(), members.CStr());
			}
		}
		tn_code_api_end();
		Revision++;
	}

	static void ScanFolder(StringView folder, Dictionary<String, TypeEntry> types, bool publicOnly, StringView group)
	{
		if (!Directory.Exists(folder))
			return;
		for (let entry in Directory.EnumerateFiles(folder))
		{
			let name = scope String();
			entry.GetFileName(name);
			if (!name.EndsWith(".bf"))
				continue;
			let text = scope String();
			if (File.ReadAllText(scope $"{folder}/{name}", text, true) case .Ok)
				ScanText(text, types, publicOnly, group);
		}
		for (let entry in Directory.EnumerateDirectories(folder))
		{
			let name = scope String();
			entry.GetFileName(name);
			if (name != "build" && !name.StartsWith("."))
				ScanFolder(scope $"{folder}/{name}", types, publicOnly, (publicOnly && group.IsEmpty) ? (StringView)name : group);
		}
	}

	static bool IsWord(char8 c) => c.IsLetterOrDigit || c == '_';

	/// Removes comments and the insides of strings, so that braces and names in them are not counted.
	static void Strip(StringView line, String output, ref bool inComment)
	{
		int i = 0;
		while (i < line.Length)
		{
			let c = line[i];
			let next = (i + 1 < line.Length) ? line[i + 1] : '\0';
			if (inComment)
			{
				if (c == '*' && next == '/')
				{
					inComment = false;
					i++;
				}
				i++;
				continue;
			}
			if (c == '/' && next == '/')
				break;
			if (c == '/' && next == '*')
			{
				inComment = true;
				i += 2;
				continue;
			}
			if (c == '"' || c == '\'')
			{
				// A lone apostrophe after a word is not a character literal (generic constraints do not use it,
				// but be safe): only skip when a closing quote exists on the line.
				int close = i + 1;
				while (close < line.Length && line[close] != c)
				{
					if (line[close] == '\\')
						close++;
					close++;
				}
				if (close < line.Length)
				{
					output.Append(c);
					output.Append(c);
					i = close + 1;
					continue;
				}
			}
			output.Append(c);
			i++;
		}
	}

	static void Words(StringView text, List<StringView> words)
	{
		int i = 0;
		while (i < text.Length)
		{
			if (IsWord(text[i]) && !text[i].IsDigit)
			{
				int start = i;
				while (i < text.Length && IsWord(text[i]))
					i++;
				words.Add(text.Substring(start, i - start));
			}
			else if (text[i].IsDigit)
			{
				while (i < text.Length && IsWord(text[i]))
					i++;
			}
			else
				i++;
		}
	}

	static bool IsModifier(StringView word)
	{
		switch (word)
		{
		case "public", "private", "protected", "internal", "static", "const", "readonly", "virtual", "override", "abstract",
			"extern", "new", "mut", "ref", "out", "in", "volatile", "sealed", "implicit", "explicit", "append", "scope", "var", "let":
			return true;
		}
		return false;
	}

	static TypeEntry Entry(Dictionary<String, TypeEntry> types, StringView name)
	{
		if (types.TryGetValueAlt(name, let existing))
			return existing;
		let entry = new TypeEntry();
		entry.name.Set(name);
		types[entry.name] = entry;
		return entry;
	}

	static void AddMember(TypeEntry type, StringView name)
	{
		if (name.IsEmpty || name.StartsWith("tn_") || name.StartsWith("ig") && name.Length > 2 && name[2].IsUpper || type.Has(name))
			return;
		type.members.Add(new String(name));
	}

	/// Records how a member is declared, from one line of source: `code` is the line, `cut` where the name ends
	/// (the first of "(", "=", ";" or "{"), `head` everything before that. Returns the member if it is a property.
	static Member AddSignature(TypeEntry type, StringView code, int cut, StringView head, StringView name, bool isPublic)
	{
		let member = new Member();
		member.name.Set(name);
		member.isPublic = isPublic;
		type.signatures.Add(member);
		// The declared type is what stands between the modifiers and the name.
		var rest = head;
		if (rest.EndsWith(name))
			rest = rest.Substring(0, rest.Length - name.Length);
		bool isConst = false;
		while (true)
		{
			rest.Trim();
			int end = 0;
			while (end < rest.Length && IsWord(rest[end]))
				end++;
			let word = rest.Substring(0, end);
			if (end == 0 || !IsModifier(word) || word == "var" || word == "let")
				break;
			if (word == "static" || word == "const")
				member.isStatic = true;
			if (word == "const" || word == "readonly")
				isConst = true;
			rest = rest.Substring(end);
		}
		member.type.Set(rest);
		member.isStatic |= type.isStatic;
		let cutChar = cut < code.Length ? code[cut] : '\0';
		if (cutChar == '(')
		{
			member.kind = .Method;
			var beforeBracket = code.Substring(0, cut);
			beforeBracket.Trim();
			member.isGeneric = beforeBracket.EndsWith('>');
			// Parameters: up to the bracket that closes the list, if it is on this line.
			int depth = 0, close = -1;
			for (int i = cut; i < code.Length; i++)
			{
				if (code[i] == '(')
					depth++;
				else if (code[i] == ')' && --depth == 0)
				{
					close = i;
					break;
				}
			}
			if (close < 0)
			{
				member.unreadable = true;
				return null;
			}
			List<StringView> afterList = scope .();
			Words(code.Substring(close + 1), afterList);
			member.isMutating = afterList.Contains("mut");
			let list = code.Substring(cut + 1, close - cut - 1);
			int start = 0, nest = 0;
			for (int i = 0; i <= list.Length; i++)
			{
				let c = i < list.Length ? list[i] : ',';
				if (c == '<' || c == '(' || c == '[')
					nest++;
				else if (c == '>' || c == ')' || c == ']')
					nest--;
				if (c == ',' && nest == 0)
				{
					var parameter = list.Substring(start, i - start);
					start = i + 1;
					parameter.Trim();
					if (parameter.IsEmpty)
						continue;
					bool hasDefault = false;
					let equals = parameter.IndexOf('=');
					if (equals > 0)
					{
						hasDefault = true;
						parameter = parameter.Substring(0, equals);
						parameter.Trim();
					}
					bool isOut = false;
					for (let prefix in StringView[?]("out ", "ref ", "params ", "mut ", "in "))
					{
						if (parameter.StartsWith(prefix))
						{
							if (prefix == "out ")
								isOut = true;
							else
								member.unreadable = true;
							parameter = parameter.Substring(prefix.Length);
							parameter.Trim();
						}
					}
					int nameStart = parameter.Length;
					while (nameStart > 0 && IsWord(parameter[nameStart - 1]))
						nameStart--;
					var parameterType = parameter.Substring(0, nameStart);
					parameterType.Trim();
					if (parameterType.IsEmpty)
						member.unreadable = true;
					member.parameters.Add((new String(parameterType), new String(parameter.Substring(nameStart)), isOut, hasDefault));
				}
			}
			return null;
		}
		// "X => ..." is a property that can only be read; "X { ... }" one that may have a setter; the rest are fields.
		let arrow = cutChar == '=' && cut + 1 < code.Length && code[cut + 1] == '>';
		if (arrow || cutChar == '{' || cutChar == '\0')
		{
			member.kind = .Property;
			if (cutChar == '{')
			{
				List<StringView> inside = scope .();
				Words(code.Substring(cut), inside);
				// "{ get; private set; }" can be read from outside but not written.
				let setAt = inside.IndexOf("set");
				member.canSet = setAt >= 0 && !(setAt > 0 && (inside[setAt - 1] == "private" || inside[setAt - 1] == "protected"));
			}
			return arrow ? null : member;
		}
		member.kind = .Field;
		member.canSet = !isConst;
		return null;
	}

	/// "A, B = 4, C" or "case A, B;": each name outside an initialiser.
	static void EnumNames(TypeEntry type, StringView code)
	{
		bool afterEquals = false;
		int i = 0;
		while (i < code.Length)
		{
			let c = code[i];
			if (c == '=')
				afterEquals = true;
			else if (c == ',')
				afterEquals = false;
			if (IsWord(c) && !c.IsDigit)
			{
				int start = i;
				while (i < code.Length && IsWord(code[i]))
					i++;
				let word = code.Substring(start, i - start);
				if (!afterEquals && word != "case" && !IsModifier(word))
					AddMember(type, word);
				continue;
			}
			i++;
		}
	}

	/// Reads type and member declarations out of Beef source. It follows braces rather than parsing the language:
	/// a line directly inside a type's braces is a member, anything deeper is code.
	public static void ScanText(StringView text, Dictionary<String, TypeEntry> types, bool publicOnly, StringView group = "")
	{
		List<(TypeEntry type, int depth)> stack = scope .();
		TypeEntry pending = null;
		Member lastProperty = null;
		int depth = 0;
		bool inComment = false;
		let line = scope String();
		List<StringView> words = scope .();
		for (let raw in text.Split('\n'))
		{
			line.Clear();
			Strip(raw, line, ref inComment);
			var code = (StringView)line;
			code.Trim();
			// Attributes in front of a declaration ("[Range(0, 1)] public float volume") are not part of it.
			while (code.StartsWith("["))
			{
				let close = code.IndexOf(']');
				if (close < 0)
					break;
				code = code.Substring(close + 1);
				code.Trim();
			}
			if (!code.IsEmpty && !code.StartsWith("#"))
			{
				words.Clear();
				Words(code, words);
				// A type declaration: "class Name : Base", possibly after modifiers.
				int keyword = -1;
				for (int i < words.Count)
				{
					let word = words[i];
					if (word == "class" || word == "struct" || word == "enum" || word == "interface" || word == "extension")
					{
						keyword = i;
						break;
					}
					if (!IsModifier(word))
						break;
				}
				let inType = stack.Count > 0 && depth == stack.Back.depth;
				if (keyword >= 0 && keyword + 1 < words.Count && (stack.Count == 0 || inType) && pending == null)
				{
					// A type declared inside another must not be confused with a top-level type of the same name
					// (a loader's private "Transform" is not the engine's Transform): the top-level one wins.
					let nested = stack.Count > 0;
					let declared = words[keyword + 1];
					if (types.TryGetValueAlt(declared, let existing) && existing.isNested != nested && words[keyword] != "extension")
					{
						if (nested)
						{
							pending = new TypeEntry();
							pending.name.Set(declared);
							sDiscarded.Add(pending);
						}
						else
						{
							ClearAndDeleteItems!(existing.members);
							ClearAndDeleteItems!(existing.signatures);
							existing.baseType.Clear();
							existing.isEnum = existing.isStruct = existing.isStatic = existing.isAbstract = false;
							existing.isNested = false;
							pending = existing;
						}
					}
					else
					{
						pending = Entry(types, declared);
						if (pending.members.IsEmpty && pending.signatures.IsEmpty)
							pending.isNested = nested;
					}
					pending.isEnum |= words[keyword] == "enum";
					if (pending.group.IsEmpty)
						pending.group.Set(group);
					pending.isStruct |= words[keyword] == "struct";
					pending.fromProject = !publicOnly;
					for (int i < keyword)
					{
						if (words[i] == "static")
							pending.isStatic = true;
						if (words[i] == "abstract")
							pending.isAbstract = true;
					}
					let colon = code.IndexOf(':');
					if (colon > 0 && keyword + 2 < words.Count && pending.baseType.IsEmpty && words[keyword] != "enum")
					{
						List<StringView> after = scope .();
						Words(code.Substring(colon + 1), after);
						if (after.Count > 0)
							pending.baseType.Set(after[0]);
					}
					// "enum Kind { A, B = 2 }" on one line.
					let open = code.IndexOf('{');
					let close = code.LastIndexOf('}');
					if (pending.isEnum && open > 0 && close > open)
						EnumNames(pending, code.Substring(open + 1, close - open - 1));
				}
				else if (stack.Count > 0 && depth == stack.Back.depth + 1 && words.Count > 0 && words[0] == "set" && lastProperty != null)
					lastProperty.canSet = true;
				else if (inType && words.Count > 0)
				{
					let type = stack.Back.type;
					if (type.isEnum && !code.Contains('('))
					{
						EnumNames(type, code);
					}
					else
					{
						bool isPublic = false, isDelegate = false, skip = false;
						for (let word in words)
						{
							if (word == "public")
								isPublic = true;
							if (word == "delegate" || word == "function")
								isDelegate = true;
							if (word == "operator" || word == "case" || word == "using" || word == "typealias" || word == "this")
								skip = true;
						}
						// "set" inside a property's braces makes the property written just before it settable.
						if (words[0] == "set" && lastProperty != null)
							lastProperty.canSet = true;
						if (!skip && (isPublic || !publicOnly))
						{
							// The name is the last word before the first of ( = ; { or =>.
							int cut = code.Length;
							for (int i < code.Length)
							{
								let c = code[i];
								if (c == '(' || c == '=' || c == ';' || c == '{')
								{
									cut = i;
									break;
								}
							}
							var head = code.Substring(0, cut);
							head.Trim();
							// "Name<T>(": drop the generic arguments.
							if (head.EndsWith('>'))
							{
								int open = head.LastIndexOf('<');
								if (open > 0)
									head = head.Substring(0, open);
							}
							List<StringView> headWords = scope .();
							Words(head, headWords);
							// A declaration has at least a type and a name; "get", "set" and the like are neither.
							int real = 0;
							for (let word in headWords)
								if (!IsModifier(word))
									real++;
							if (headWords.Count >= 2 && real >= 2 || isDelegate && real >= 2)
							{
								let name = headWords.Back;
								if (!IsModifier(name) && name != "get" && name != "set" && name != "where")
								{
									AddMember(type, name);
									if (!isDelegate)
										lastProperty = AddSignature(type, code, cut, head, name, isPublic);
									if (isDelegate)
										Entry(types, name).isDelegate = true;
								}
							}
						}
					}
				}
			}
			for (let c in code.RawChars)
			{
				if (c == '{')
				{
					depth++;
					if (pending != null)
					{
						stack.Add((pending, depth));
						pending = null;
					}
				}
				else if (c == '}')
				{
					if (stack.Count > 0 && stack.Back.depth == depth)
						stack.PopBack();
					depth--;
				}
				else if (c == ';' && pending != null && !code.Contains('{'))
					pending = null; // "struct Name;" with no body
			}
		}
	}
}
