using System;
using System.Collections;
using System.Reflection;

namespace Tessera;

enum FieldKind
{
	Float,
    Double,
    Char,
    Vector4,
    Int3,
    Matrix4,
	Int,
	Bool,
	Vector2,
	Vector3,
	Quaternion,
	Color,
	String,
	Enum,
	ObjectReference
}

/// One serializable field of a live component.
struct FieldRef
{
	public StringView name;
	public FieldKind kind;
	public void* ptr;
	public Type type;
	public bool hidden;
	/// Marked [Sync]: shared from the server to clients.
	public bool sync;
	public bool hasRange;
	public float rangeMin;
	public float rangeMax;
	/// Marked [Layer]: an integer that is one of the project's layers, or -1 for none.
	public bool isLayer;
}

/// Component type registry and field reflection shared by the scene serializer and the Inspector.
static class ComponentRegistry
{
	public class Info
	{
		public String fullName = new .() ~ delete _;
		public String name = new .() ~ delete _;
		public Type type;
	}

	static List<Info> sInfos ~ DeleteContainerAndItems!(_);

	/// All concrete component types in the program, engine and game alike, sorted by name.
	public static List<Info> Types
	{
		get
		{
			if (sInfos == null)
				Build();
			return sInfos;
		}
	}

	static void Build()
	{
		sInfos = new .();
		for (let type in ScriptReload.ReflectedTypes)
		{
			if (type == null) continue;
			if (!type.IsObject || type.IsAbstract || type.IsBoxed || type.IsArray)
				continue;
			if (type == typeof(Component) || !type.IsSubtypeOf(typeof(Component)))
				continue;
			let info = new Info();
			type.GetFullName(info.fullName);
			type.GetName(info.name);
			info.type = type;
			sInfos.Add(info);
		}
		sInfos.Sort(scope (a, b) => a.name.CompareTo(b.name));
	}

	public static void Refresh()
	{
		if (sInfos != null) { DeleteContainerAndItems!(sInfos); sInfos = null; }
		// Scripts were reloaded: loaded data assets are of the old classes.
		DataAsset.ClearCache();
		Build();
	}

	public static Info Find(StringView fullName)
	{
		for (let info in Types)
		{
			if (info.fullName == fullName)
				return info;
		}
		return null;
	}

	public static Info Find(Type type)
	{
		for (let info in Types)
		{
			if (info.type == type)
				return info;
		}
		return null;
	}

	public static Component Create(Type type)
	{
		if (type.CreateObject() case .Ok(let obj))
		{
			if (let component = obj as Component)
				return component;
			delete obj;
		}
		return null;
	}

	/// Scene references are non-owning. Components match by their reflected type.
	public static GameObject ReferenceOwner(FieldRef field)
	{
		let value = *(Object*)field.ptr;
		if (let go = value as GameObject) return go;
		if (let transform = value as Transform) return transform.GameObject;
		if (let component = value as Component) return component.GameObject;
		return null;
	}

	public static bool AssignReference(FieldRef field, GameObject go, int index = -1)
	{
		if (go == null) { *(Object*)field.ptr = null; return true; }
		Object value = null;
		if (field.type == typeof(GameObject)) value = go;
		else if (field.type == typeof(Transform)) value = go.Transform;
		else
		{
			for (int i < go.Components.Count)
			{
				if (index >= 0 && i != index) continue;
				let component = go.Components[i];
				if (component.GetType() == field.type || component.GetType().IsSubtypeOf(field.type))
				{ value = component; break; }
			}
		}
		if (value == null) return false;
		*(Object*)field.ptr = value;
		return true;
	}

	/// Collects the serializable fields of a component, base class fields first.
	public static void GetFields(Component component, List<FieldRef> fields, bool forReload = false) => GetFields(component, typeof(Component), fields, forReload);

	/// The same for any object (a data asset), with the fields of the classes from stopAt down.
	public static void GetFields(Object target, Type stopAt, List<FieldRef> fields, bool forReload = false)
	{
		List<TypeInstance> chain = scope .();
		var type = target.GetType() as TypeInstance;
		while (type != null && type != stopAt)
		{
			chain.Add(type);
			type = type.BaseType;
		}
		let basePtr = (uint8*)Internal.UnsafeCastToPtr(target);
		for (int i = chain.Count - 1; i >= 0; i--)
		{
			for (let field in chain[i].GetFields(.Instance | .Public | .NonPublic | .DeclaredOnly))
			{
				if (!field.IsInstanceField)
					continue;
				if (!forReload && !field.IsPublic && !(field.GetCustomAttribute<ShowInInspectorAttribute>() case .Ok))
					continue;
				if (field.GetCustomAttribute<NonSerializedAttribute>() case .Ok)
					continue;

				FieldRef fieldRef = default;
				let fieldType = field.FieldType;
				let storage=FieldNumbers.Storage(fieldType);
                if (storage == typeof(float)) fieldRef.kind = .Float;
                else if(storage==typeof(double)) fieldRef.kind=.Double;
                else if(fieldType.IsEnum && storage.IsInteger && fieldType.Size<=8) fieldRef.kind=.Enum;
                else if(storage.IsInteger) fieldRef.kind=.Int;
                else if(storage==typeof(char8) || storage==typeof(char16) || storage==typeof(char32)) fieldRef.kind=.Char;
                else if(fieldType==typeof(Vector4)) fieldRef.kind=.Vector4;
                else if(fieldType==typeof(Int3)) fieldRef.kind=.Int3;
                else if(fieldType==typeof(Matrix4)) fieldRef.kind=.Matrix4;
				else if (fieldType == typeof(bool)) fieldRef.kind = .Bool;
				else if (fieldType == typeof(Vector2)) fieldRef.kind = .Vector2;
				else if (fieldType == typeof(Vector3)) fieldRef.kind = .Vector3;
				else if (fieldType == typeof(Quaternion)) fieldRef.kind = .Quaternion;
				else if (fieldType == typeof(Color)) fieldRef.kind = .Color;
				else if (fieldType == typeof(String)) fieldRef.kind = .String;
				else if (fieldType == typeof(GameObject) || fieldType == typeof(Transform) || fieldType == typeof(Component) || fieldType.IsSubtypeOf(typeof(Component))) fieldRef.kind = .ObjectReference;
				else continue;

				fieldRef.name = field.Name;
				fieldRef.type = fieldType;
				fieldRef.ptr = basePtr + field.MemberOffset;
				fieldRef.hidden = field.GetCustomAttribute<HideInInspectorAttribute>() case .Ok;
				fieldRef.sync = field.GetCustomAttribute<SyncAttribute>() case .Ok;
				fieldRef.isLayer = field.GetCustomAttribute<LayerAttribute>() case .Ok;
				if (field.GetCustomAttribute<RangeAttribute>() case .Ok(let range))
				{
					fieldRef.hasRange = true;
					fieldRef.rangeMin = range.min;
					fieldRef.rangeMax = range.max;
				}
				fields.Add(fieldRef);
			}
		}
	}
}
