using System;
using System.Collections;
using System.IO;

namespace Tessera;

/// Reads and writes scenes as line-based text (.tscene), which diffs and merges cleanly.
///
///   scene "Main"
///   env skyZenith 0.16 0.36 0.72 1
///   object 3 parent 0 active 1 name "Crate"
///   transform 0 1 0  0 0 0 1  1 1 1
///   component Tessera.MeshRenderer enabled 1
///   field mesh "builtin:cube"
static class SceneSerializer
{
	public static void Save(Scene scene, String text)
	{
		text.AppendF("scene {}\n", Quote(scene.Name, .. scope .()));
		let env = scene.Environment;
		WriteColor(text, "skyZenith", env.skyZenith);
		WriteColor(text, "skyHorizon", env.skyHorizon);
		WriteColor(text, "skyGround", env.skyGround);
		WriteColor(text, "ambientSky", env.ambientSky);
		WriteColor(text, "ambientGround", env.ambientGround);
		WriteColor(text, "fogColor", env.fogColor);
		text.AppendF("env ambientIntensity {}\n", env.ambientIntensity);
		text.AppendF("env fogDensity {}\n", env.fogDensity);
		text.AppendF("env exposure {}\n", env.exposure);
		text.AppendF("env bloom {}\n", env.bloom);
		text.AppendF("env bloomThreshold {}\n", env.bloomThreshold);
		text.AppendF("env shadowDistance {}\n", env.shadowDistance);
		for (let root in scene.Roots)
			SaveObject(root, text);
	}

	static void WriteColor(String text, StringView name, Color c)
	{
		text.AppendF("env {} {} {} {} {}\n", name, c.r, c.g, c.b, c.a);
	}

	/// Writes one object and its children; the text can be loaded with Instantiate or LoadObjects.
	public static void SaveObjectTree(GameObject gameObject, String text) => SaveObject(gameObject, text);

	static void SaveObject(GameObject gameObject, String text)
	{
		if (gameObject.Transient)
			return;
		let transform = gameObject.Transform;
		let parentId = transform.Parent != null ? transform.Parent.GameObject.Id : 0;
		text.AppendF("object {} parent {} active {} name {}\n", gameObject.Id, parentId, gameObject.ActiveSelf ? 1 : 0, Quote(gameObject.Name, .. scope .()));
		if (gameObject.IsFolder)
			text.Append("folder\n");
		let p = transform.LocalPosition;
		let q = transform.LocalRotation;
		let s = transform.LocalScale;
		text.AppendF("transform {} {} {} {} {} {} {} {} {} {}\n", p.x, p.y, p.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z);
		// Written only when set, so scenes that use none of them read as they always did.
		if (gameObject.Layer != 0)
			text.AppendF("layer {}\n", gameObject.Layer);
		if (gameObject.TagCount > 0)
		{
			text.Append("tags");
			for (int i < gameObject.TagCount)
			{
				text.Append(' ');
				Quote(gameObject.GetTag(i), text);
			}
			text.Append('\n');
		}
		if (gameObject.WorldStates != uint32.MaxValue)
			text.AppendF("worlds {:X8}\n", gameObject.WorldStates);

		List<FieldRef> fields = scope .();
		for (let component in gameObject.Components)
		{
			let info = ComponentRegistry.Find(component.GetType());
			if (info == null)
				continue;
			text.AppendF("component {} enabled {}\n", info.fullName, component.Enabled ? 1 : 0);
			fields.Clear();
			ComponentRegistry.GetFields(component, fields);
			for (let field in fields)
			{
				text.AppendF("field {} ", field.name);
				WriteValue(field, text);
				text.Append('\n');
			}
		}
		for (let child in transform.Children)
			SaveObject(child.GameObject, text);
	}

	public static void WriteValue(FieldRef field, String text)
	{
		switch (field.kind)
		{
		case .Float: text.AppendF("{}", *(float*)field.ptr);
		case .Double: (*(double*)field.ptr).ToString(text,"R",null);
        case .Int,.Char:
            if(FieldNumbers.Signed(field)) text.AppendF("{}",FieldNumbers.ReadSigned(field));
            else text.AppendF("{}",FieldNumbers.ReadUnsigned(field));
        case .Vector4:
            let v=*(Vector4*)field.ptr;text.AppendF("{} {} {} {}",v.x,v.y,v.z,v.w);
        case .Int3:
            let v=*(Int3*)field.ptr;text.AppendF("{} {} {}",v.x,v.y,v.z);
        case .Matrix4:
            let matrix=(Matrix4*)field.ptr;for(int i<16) {if(i>0) text.Append(' ');text.AppendF("{}",matrix.m[i]);}
		case .Bool: text.Append(*(bool*)field.ptr ? "1" : "0");
		case .Vector2:
			let v = *(Vector2*)field.ptr;
			text.AppendF("{} {}", v.x, v.y);
		case .Vector3:
			let v = *(Vector3*)field.ptr;
			text.AppendF("{} {} {}", v.x, v.y, v.z);
		case .Quaternion:
			let v = *(Quaternion*)field.ptr;
			text.AppendF("{} {} {} {}", v.x, v.y, v.z, v.w);
		case .Color:
			let v = *(Color*)field.ptr;
			text.AppendF("{} {} {} {}", v.r, v.g, v.b, v.a);
		case .String:
			let str = *(String*)field.ptr;
			Quote(str != null ? (StringView)str : "", text);
		case .ObjectReference:
			let go = ComponentRegistry.ReferenceOwner(field);
			int index = -1;
			if (let component = (*(Object*)field.ptr) as Component)
				index = go.Components.IndexOf(component);
			text.AppendF("{} {}", go != null ? go.Id : 0, index);
        case .Enum:
            let name=scope String();Enum.EnumToString(field.type,name,FieldNumbers.EnumValue(field));
            if(!FieldNumbers.Signed(field) && (name.IsEmpty || name[0].IsDigit || name[0]=='-')) text.AppendF("{}",FieldNumbers.ReadUnsigned(field));
            else text.Append(name);
		}
	}

	public static void ReadValue(FieldRef field, Span<StringView> tokens)
	{
		if (tokens.Length == 0)
			return;
		switch (field.kind)
		{
		case .Float: *(float*)field.ptr = ParseFloat(tokens[0]);
		case .Double: if(double.Parse(tokens[0]) case .Ok(let value)) *(double*)field.ptr=value;
        case .Int,.Char: FieldNumbers.ReadText(field,tokens[0]);
        case .Vector4:if(tokens.Length>=4) *(Vector4*)field.ptr=.(ParseFloat(tokens[0]),ParseFloat(tokens[1]),ParseFloat(tokens[2]),ParseFloat(tokens[3]));
        case .Int3:if(tokens.Length>=3) *(Int3*)field.ptr=.(ParseInt(tokens[0]),ParseInt(tokens[1]),ParseInt(tokens[2]));
        case .Matrix4:if(tokens.Length>=16) {let matrix=(Matrix4*)field.ptr;for(int i<16) matrix.m[i]=ParseFloat(tokens[i]);}
		case .Bool: *(bool*)field.ptr = tokens[0] == "1" || tokens[0] == "true";
		case .Vector2:
			if (tokens.Length >= 2)
				*(Vector2*)field.ptr = .(ParseFloat(tokens[0]), ParseFloat(tokens[1]));
		case .Vector3:
			if (tokens.Length >= 3)
				*(Vector3*)field.ptr = .(ParseFloat(tokens[0]), ParseFloat(tokens[1]), ParseFloat(tokens[2]));
		case .Quaternion:
			if (tokens.Length >= 4)
				*(Quaternion*)field.ptr = .(ParseFloat(tokens[0]), ParseFloat(tokens[1]), ParseFloat(tokens[2]), ParseFloat(tokens[3]));
		case .Color:
			if (tokens.Length >= 4)
				*(Color*)field.ptr = .(ParseFloat(tokens[0]), ParseFloat(tokens[1]), ParseFloat(tokens[2]), ParseFloat(tokens[3]));
		case .String:
			let str = *(String*)field.ptr;
			if(str!=null) str.Set(tokens[0]);
            else *(String*)field.ptr=new String(tokens[0]);
		case .ObjectReference:
			let id = (uint32)ParseInt(tokens[0]);
			ComponentRegistry.AssignReference(field, id == 0 ? null : Scene.Active?.FindById(id), tokens.Length > 1 ? ParseInt(tokens[1]) : -1);
        case .Enum:
            if(Enum.Parse(field.type,tokens[0]) case .Ok(let value))
            {if(FieldNumbers.Signed(field)) FieldNumbers.WriteSigned(field,value);else FieldNumbers.WriteUnsigned(field,(uint64)value);}
            else FieldNumbers.ReadText(field,tokens[0]);
		}
	}

	public static bool SaveToFile(Scene scene, StringView path)
	{
		for (let component in scene.Components)
			component.OnBeforeSave();
		let text = scope String();
		Save(scene, text);
		if (File.WriteAllText(path, text) case .Err)
		{
			Log.Error(scope $"Could not write scene {path}");
			return false;
		}
		scene.Path.Set(path);
		return true;
	}

	public static bool LoadFromFile(Scene scene, StringView path)
	{
		let text = scope String();
		if (AssetPack.ReadAllText(path, text) case .Err)
		{
			Log.Error(scope $"Could not read scene {path}");
			return false;
		}
		Load(scene, text);
		scene.Path.Set(path);
		return true;
	}

	/// Replaces the contents of the scene with the serialized text.
	public static void Load(Scene scene, StringView text) => LoadInternal(scene, text, true, false);

	/// Adds the objects in the text to the scene, keeping their saved ids (the editor's undo uses this).
	public static void LoadObjects(Scene scene, StringView text) => LoadInternal(scene, text, false, false);

	/// Adds a copy of saved objects with fresh ids and returns the first (root) object.
	public static GameObject Instantiate(Scene scene, StringView text) => LoadInternal(scene, text, false, true);

	/// Reads the environment lines of a serialized scene into the scene's settings.
	public static void LoadEnvironment(Scene scene, StringView text)
	{
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer { for (let s in storage) delete s; }
		for (let line in text.Split('\n'))
		{
			if (!line.StartsWith("env "))
				continue;
			tokens.Clear();
			Tokenize(line, tokens, storage);
			if (tokens.Count >= 3)
				ReadEnvironment(scene.Environment, tokens);
		}
	}

	static GameObject LoadInternal(Scene scene, StringView text, bool clear, bool remap)
	{
		if (clear)
			scene.Clear();
		GameObject first = null;
		Dictionary<uint32, GameObject> created = scope .();
		GameObject current = null;
		Component component = null;
		List<FieldRef> fields = scope .();
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer { for (let s in storage) delete s; }
		List<(GameObject object, uint32 parent)> parents = scope .();
		List<Component> loaded = scope .();
		List<(FieldRef field, uint32 id, int index)> references = scope .();

		for (let rawLine in text.Split('\n'))
		{
			tokens.Clear();
			Tokenize(rawLine, tokens, storage);
			if (tokens.Count == 0)
				continue;
			let key = tokens[0];
			if (key == "scene" && tokens.Count >= 2 && clear)
			{
				scene.Name.Set(tokens[1]);
			}
			else if (key == "env" && tokens.Count >= 3 && clear)
			{
				ReadEnvironment(scene.Environment, tokens);
			}
			else if (key == "object" && tokens.Count >= 8)
			{
				let id = (uint32)ParseInt(tokens[1]);
				current = scene.CreateGameObjectWithId(tokens[7], remap ? 0 : id);
				created[id] = current;
				if (first == null)
					first = current;
				current.SetActive(tokens[5] == "1");
				parents.Add((current, (uint32)ParseInt(tokens[3])));
				component = null;
			}
			else if (key == "folder" && current != null)
			{
				current.IsFolder = true;
			}
			else if (key == "layer" && current != null && tokens.Count >= 2)
				current.Layer = ParseInt(tokens[1]);
			else if (key == "tags" && current != null)
			{
				for (int i = 1; i < tokens.Count; i++)
					current.AddTag(tokens[i]);
			}
			else if (key == "worlds" && current != null && tokens.Count >= 2)
			{
				if (uint32.Parse(tokens[1], .HexNumber) case .Ok(let mask))
					current.WorldStates = mask;
			}
			else if (key == "transform" && current != null && tokens.Count >= 11)
			{
				let t = current.Transform;
				t.LocalPosition = .(ParseFloat(tokens[1]), ParseFloat(tokens[2]), ParseFloat(tokens[3]));
				t.LocalRotation = .(ParseFloat(tokens[4]), ParseFloat(tokens[5]), ParseFloat(tokens[6]), ParseFloat(tokens[7]));
				t.LocalScale = .(ParseFloat(tokens[8]), ParseFloat(tokens[9]), ParseFloat(tokens[10]));
			}
			else if (key == "component" && current != null && tokens.Count >= 4)
			{
				component = null;
				let info = ComponentRegistry.Find(tokens[1]);
				if (info == null)
				{
					Log.Warning(scope $"Scene references unknown component type {tokens[1]}; it was skipped.");
					continue;
				}
				component = current.AddComponent(info.type);
				// Terrain saved before it had a mode was endless; a scene that says nothing keeps that. Scenes saved
				// since always state the mode on the lines that follow.
				if (let terrain = component as VoxelTerrain)
					terrain.mode = .Endless;
				if (component != null)
				{
					component.[Friend]mEnabled = tokens[3] == "1";
					fields.Clear();
					ComponentRegistry.GetFields(component, fields);
					loaded.Add(component);
				}
			}
			else if (key == "field" && component != null && tokens.Count >= 2)
			{
				for (let field in fields)
				{
					if (field.name == tokens[1])
					{
						if (field.kind == .ObjectReference && tokens.Count >= 3)
							references.Add((field, (uint32)ParseInt(tokens[2]), (tokens.Count > 3 ? ParseInt(tokens[3]) : -1)));
						else ReadValue(field, Span<StringView>(tokens.Ptr + 2, tokens.Count - 2));
						break;
					}
				}
			}
		}

		for (let entry in parents)
		{
			if (entry.parent == 0)
				continue;
			GameObject parent = null;
			if (!created.TryGetValue(entry.parent, out parent) && !remap)
				parent = scene.FindById(entry.parent);
			if (parent != null)
				entry.object.Transform.SetParent(parent.Transform, false);
		}
		for (let reference in references)
		{
			GameObject target = null;
			if (reference.id != 0 && !created.TryGetValue(reference.id, out target) )
				target = scene.FindById(reference.id);
			ComponentRegistry.AssignReference(reference.field, target, reference.index);
		}
		for (let c in loaded)
			c.OnValidate();
		return first;
	}

	static void ReadEnvironment(SceneEnvironment env, List<StringView> tokens)
	{
		let name = tokens[1];
		Color color = default;
		if (tokens.Count >= 6)
			color = .(ParseFloat(tokens[2]), ParseFloat(tokens[3]), ParseFloat(tokens[4]), ParseFloat(tokens[5]));
		let value = ParseFloat(tokens[2]);
		switch (name)
		{
		case "skyZenith": env.skyZenith = color;
		case "skyHorizon": env.skyHorizon = color;
		case "skyGround": env.skyGround = color;
		case "ambientSky": env.ambientSky = color;
		case "ambientGround": env.ambientGround = color;
		case "fogColor": env.fogColor = color;
		case "ambientIntensity": env.ambientIntensity = value;
		case "fogDensity": env.fogDensity = value;
		case "exposure": env.exposure = value;
		case "bloom": env.bloom = value;
		case "bloomThreshold": env.bloomThreshold = value;
		case "shadowDistance": env.shadowDistance = value;
		}
	}

	public static float ParseFloat(StringView token)
	{
		if (float.Parse(token) case .Ok(let value))
			return value;
		return 0;
	}

	public static int32 ParseInt(StringView token)
	{
		if (int32.Parse(token) case .Ok(let value))
			return value;
		return 0;
	}

	/// Appends the text as a double-quoted token with \" \\ and \n escapes.
	public static void Quote(StringView value, String text)
	{
		text.Append('"');
		for (let c in value.RawChars)
		{
			if (c == '"' || c == '\\')
			{
				text.Append('\\');
				text.Append(c);
			}
			else if (c == '\n')
				text.Append("\\n");
			else if (c != '\r')
				text.Append(c);
		}
		text.Append('"');
	}

	/// Splits a line on whitespace. Quoted tokens are unescaped into storage, which owns them.
	public static void Tokenize(StringView line, List<StringView> tokens, List<String> storage)
	{
		int i = 0;
		let n = line.Length;
		while (i < n)
		{
			let c = line[i];
			if (c == ' ' || c == '\t' || c == '\r')
			{
				i++;
				continue;
			}
			if (c == '"')
			{
				let unescaped = new String();
				storage.Add(unescaped);
				i++;
				while (i < n && line[i] != '"')
				{
					if (line[i] == '\\' && i + 1 < n)
					{
						i++;
						unescaped.Append(line[i] == 'n' ? '\n' : line[i]);
					}
					else
						unescaped.Append(line[i]);
					i++;
				}
				i++;
				tokens.Add(unescaped);
			}
			else
			{
				let start = i;
				while (i < n && line[i] != ' ' && line[i] != '\t' && line[i] != '\r')
					i++;
				tokens.Add(line.Substring(start, i - start));
			}
		}
	}
}
