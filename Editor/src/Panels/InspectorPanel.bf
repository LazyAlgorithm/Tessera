using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// The Inspector panel.
extension EditorApp
{
	bool BeginProperty(char8* label)
	{
		ImGui.TableNextRow();
		ImGui.TableNextColumn();
		ImGui.AlignTextToFramePadding();
		ImGui.Text(StringView(label));
		ImGui.TableNextColumn();
		ImGui.SetNextItemWidth(-1);
		return true;
	}

	bool BeginPropertyTable(char8* id)
	{
		if (!ImGui.BeginTable(id, 2, ImGui.TableFlags.SizingStretchProp))
			return false;
		ImGui.TableSetupColumn("name", ImGui.ColumnFlags.WidthStretch, 0.38f);
		ImGui.TableSetupColumn("value", ImGui.ColumnFlags.WidthStretch, 0.62f);
		return true;
	}

	/// Turns "moveSpeed" into "Move Speed" for display.
	static void NiceName(StringView name, String outText)
	{
		for (int i < name.Length)
		{
			let c = name[i];
			if (i == 0)
				outText.Append(c.ToUpper);
			else
			{
				if (c.IsUpper && !name[i - 1].IsUpper)
					outText.Append(' ');
				outText.Append(c);
			}
		}
	}

	void DrawInspector()
	{
		if (ImGui.Begin("Inspector"))
		{
			let selected = Selected;
			// Selecting another object takes the Inspector back from an asset clicked in the Project panel.
			if (mSelectedId != mInspectedObject)
			{
				mInspectedObject = mSelectedId;
				if (mSelectedId != 0)
					mInspectAsset = false;
			}
			if (mInspectAsset && mSelectedAsset.EndsWith(".tmat"))
			{
				let relative = scope String();
				Assets.MakeRelative(mSelectedAsset, relative);
				let name = scope String();
				Path.GetFileNameWithoutExtension(mSelectedAsset, name);
				ImGui.Text(scope $"{name}  (Material)");
				ImGui.TextDisabled(relative.CStr());
				DrawMaterialInspector(relative);
			}
			else if (mInspectAsset && mSelectedAsset.EndsWith(".tdata"))
				DrawDataAssetInspector(mSelectedAsset);
			else if (selected == null)
				DrawSceneSettings();
			else
			{
				DrawObjectInspector(selected);
				// The material its Mesh Renderer uses, under the components, as in Unity.
				let renderer = selected.GetComponent<MeshRenderer>();
				if (renderer != null && !renderer.material.IsEmpty)
				{
					let name = scope String();
					Path.GetFileNameWithoutExtension(renderer.material, name);
					ImGui.Dummy(.(0, 6));
					if (ImGui.CollapsingHeader(scope $"{name}  (Material)###materialheader".CStr(), ImGui.TreeFlags.DefaultOpen))
						DrawMaterialInspector(renderer.material);
				}
				DrawInspectorScriptDrop(selected);
			}
		}
		ImGui.End();
	}

	void DrawSceneSettings()
	{
		ImGui.TextDisabled("Scene Settings");
		ImGui.Separator();
		let env = mScene.Environment;
		bool changed = false;
		if (ImGui.CollapsingHeader("Lighting", ImGui.TreeFlags.DefaultOpen) && BeginPropertyTable("lighting"))
		{
			BeginProperty("Ambient Sky"); changed |= ImGui.ColorEdit3("##as", ref env.ambientSky);
			BeginProperty("Ambient Ground"); changed |= ImGui.ColorEdit3("##ag", ref env.ambientGround);
			BeginProperty("Ambient Intensity"); changed |= ImGui.SliderFloat("##ai", ref env.ambientIntensity, 0, 2);
			BeginProperty("Exposure"); changed |= ImGui.SliderFloat("##ex", ref env.exposure, 0.1f, 4);
			BeginProperty("Bloom"); changed |= ImGui.SliderFloat("##bl", ref env.bloom, 0, 2);
			BeginProperty("Bloom Threshold"); changed |= ImGui.SliderFloat("##bt", ref env.bloomThreshold, 0, 4);
			BeginProperty("Shadow Distance"); changed |= ImGui.DragFloat("##sd", ref env.shadowDistance, 1, 10, 1000);
			ImGui.EndTable();
		}
		if (ImGui.CollapsingHeader("Sky and Fog", ImGui.TreeFlags.DefaultOpen) && BeginPropertyTable("sky"))
		{
			BeginProperty("Zenith"); changed |= ImGui.ColorEdit3("##sz", ref env.skyZenith);
			BeginProperty("Horizon"); changed |= ImGui.ColorEdit3("##sh", ref env.skyHorizon);
			BeginProperty("Ground"); changed |= ImGui.ColorEdit3("##sg", ref env.skyGround);
			BeginProperty("Fog Color"); changed |= ImGui.ColorEdit3("##fc", ref env.fogColor);
			BeginProperty("Fog Density"); changed |= ImGui.DragFloat("##fd", ref env.fogDensity, 0.0002f, 0, 0.2f, "%.4f");
			ImGui.EndTable();
		}
		if (changed)
			MarkDirty();
		ImGui.Spacing();
		ImGui.TextDisabled("Select an object to edit its components.");
	}

	void DrawObjectInspector(GameObject gameObject)
	{
		// ---- header: icon, active toggle, name ----
		ImGui.AlignTextToFramePadding();
		ImGui.TextColored(gameObject.IsFolder ? Icons.FolderColor : Icons.ObjectColor, ObjectIcon(gameObject));
		ImGui.SameLine();
		bool active = gameObject.ActiveSelf;
		if (ImGui.Checkbox("##active", ref active))
		{
			gameObject.SetActive(active);
			MarkDirty();
		}
		ImGui.SameLine();
		ImGui.SetNextItemWidth(-1);
		if (ImGui.InputText("##name", gameObject.Name))
			MarkDirty();
		ImGui.Spacing();

		if (gameObject.IsFolder)
		{
			ImGui.Separator();
			ImGui.Spacing();
			ImGui.TextWrapped("Folder. It only groups objects in the Hierarchy: it has no transform or components and does not affect its children.");
			ImGui.Spacing();
			if (ImGui.Button("Convert to GameObject"))
			{
				gameObject.IsFolder = false;
				MarkDirty();
			}
			return;
		}

		// ---- Transform ----
		ImGui.Separator();
		if (ImGui.CollapsingHeader(scope String()..AppendF("{}  Transform", StringView(Icons.Transform)).CStr(), ImGui.TreeFlags.DefaultOpen) && BeginPropertyTable("transform"))
		{
			let transform = gameObject.Transform;
			var position = transform.LocalPosition;
			var euler = transform.LocalEulerAngles;
			var scale = transform.LocalScale;
			BeginProperty("Position");
			if (DrawVector3("pos", ref position, 0.05f)) { transform.LocalPosition = position; MarkDirty(); }
			BeginProperty("Rotation");
			if (DrawVector3("rot", ref euler, 0.5f)) { transform.LocalEulerAngles = euler; MarkDirty(); }
			BeginProperty("Scale");
			if (DrawVector3("scl", ref scale, 0.02f)) { transform.LocalScale = scale; MarkDirty(); }
			ImGui.EndTable();
		}

		// ---- components ----
		Component remove = null;
		int move = 0;
		int moveIndex = -1;
		List<FieldRef> fields = scope .();
		for (int index = 0; index < gameObject.Components.Count; index++)
		{
			let component = gameObject.Components[index];
			let info = ComponentRegistry.Find(component.GetType());
			let title = scope String();
			NiceName(info != null ? (StringView)info.name : "Component", title);
			ImGui.PushID(Internal.UnsafeCastToPtr(component));
			ImGui.Separator();
			// The label leaves room for the enable checkbox and icon drawn over the header.
			let open = ImGui.CollapsingHeader(scope String()..AppendF("            {}###header", title).CStr(), ImGui.TreeFlags.DefaultOpen | ImGui.TreeFlags.AllowOverlap);
			if (ImGui.BeginPopupContextItem("ComponentMenu"))
			{
				if (ImGui.MenuItem("Reset")) { ResetComponent(component); MarkDirty(); }
                if (ImGui.MenuItem("Copy Component")) mComponentClipboard.Copy(component);
                if (ImGui.MenuItem("Paste Component Values", null, false, mComponentClipboard.CanPaste(component)))
                { mComponentClipboard.PasteValues(component); MarkDirty(); }
                if (ImGui.MenuItem("Paste Component As New", null, false, mComponentClipboard.HasData))
                { mComponentClipboard.PasteNew(gameObject); MarkDirty(); }
				if (ImGui.MenuItem("Move Up", null, false, index > 0)) { move = -1; moveIndex = index; }
				if (ImGui.MenuItem("Move Down", null, false, index < gameObject.Components.Count - 1)) { move = 1; moveIndex = index; }
				ImGui.Separator();
				if (ImGui.MenuItem("Remove Component")) remove = component;
				ImGui.EndPopup();
			}
			ImGui.SameLine(30);
			ImGui.PushStyleVar(ImGui.StyleVar.FramePadding, ImGui.Vec2(1, 1));
			bool enabled = component.Enabled;
			if (ImGui.Checkbox("##enabled", ref enabled))
			{
				component.Enabled = enabled;
				MarkDirty();
			}
			ImGui.PopStyleVar();
			ImGui.SameLine(54);
			ImGui.TextColored(Icons.ComponentColor, ComponentIcon(info != null ? (StringView)info.name : ""));
			ImGui.SameLine(ImGui.GetWindowWidth() - 30);
			if (ImGui.SmallButton(Icons.Menu))
				ImGui.OpenPopup("ComponentMenu");

			if (open)
			{
				fields.Clear();
				ComponentRegistry.GetFields(component, fields);
				bool changed = false;
				if (fields.Count > 0 && BeginPropertyTable("fields"))
				{
					for (let field in fields)
					{
						if (!field.hidden)
							changed |= DrawField(field);
					}
					ImGui.EndTable();
				}
				if (changed)
				{
					component.OnValidate();
					MarkDirty();
				}
				if(component is NavigationSurface) DrawNavigationTools((NavigationSurface)component);
				if(component is AudioSource) DrawAudioTools((AudioSource)component);
				if (component is VoxelTerrain)
					DrawTerrainTools((VoxelTerrain)component);
				else if (component is VoxelObject)
					DrawVoxelObjectTools((VoxelObject)component);
				else if (component is SkinnedMeshRenderer)
				{
					// List the clips found in the file; click one to play it.
					let skinned = (SkinnedMeshRenderer)component;
					if (skinned.Model != null)
					{
						ImGui.TextDisabled(scope String()..AppendF("{} bones, {} clips", skinned.Model.Joints.Count, skinned.Model.Clips.Count).CStr());
						for (let animation in skinned.Model.Clips)
						{
							if (ImGui.Selectable(animation.name.CStr(), skinned.CurrentClip == animation.name))
							{
								skinned.clip.Set(animation.name);
								skinned.Play(animation.name);
								MarkDirty();
							}
						}
					}
				}
			}
			ImGui.PopID();
		}
		if (moveIndex >= 0)
		{
			Swap!(gameObject.Components[moveIndex], gameObject.Components[moveIndex + move]);
			MarkDirty();
		}
		if (remove != null)
		{
			gameObject.RemoveComponent(remove);
			MarkDirty();
		}

		ImGui.Separator();
		ImGui.Spacing();
		ImGui.Spacing();
		let width = Math.Min(ImGui.GetContentRegionAvail().x, 230);
		ImGui.SetCursorPosX((ImGui.GetWindowWidth() - width) * 0.5f);
		if (ImGui.Button("Add Component", .(width, 26)))
		{
			mScriptCatalog.Refresh(Assets.ProjectPath,Project.Current.Name);
			mComponentSearch.Clear();
            mFocusComponentSearch = true;
			ImGui.OpenPopup("AddComponent");
		}
		if (ImGui.BeginPopup("AddComponent"))
		{
			ImGui.SetNextItemWidth(260);
            if (mFocusComponentSearch) { ImGui.SetKeyboardFocusHere(); mFocusComponentSearch = false; }
			ImGui.InputText("##filter", mComponentSearch, 0, "Search");
			ImGui.BeginChild("list", .(260, 320));
            for (let category in StringView[?]("Rendering", "Physics", "Animation", "Audio", "UI", "Particles", "World", "Networking", "AI", "Scripts"))
            {
                bool searching = !mComponentSearch.IsEmpty;
                if (!searching && !ImGui.BeginMenu(scope String(category).CStr())) continue;
                for (let info in ComponentRegistry.Types)
                {
                    if (!mScriptCatalog.IsVisible(info)) continue;
                    if (ComponentCategory(info.fullName, info.name) != category) continue;
                    let label = scope String(); NiceName(info.name, label);
                    if (searching && !info.name.Contains(mComponentSearch,true) && !label.Contains(mComponentSearch,true)
                        && !category.Contains(mComponentSearch,true)) continue;
                    if (ImGui.Selectable(scope $"{StringView(ComponentIcon(info.name))}  {label}##{info.fullName}"))
                    { gameObject.AddComponent(info.type); MarkDirty(); ImGui.CloseCurrentPopup(); }
                }
                if (!searching) ImGui.EndMenu();
            }
            if (mComponentClipboard.HasData)
            {
                ImGui.Separator();
                if (ImGui.Selectable("Paste Copied Component"))
                { mComponentClipboard.PasteNew(gameObject); MarkDirty(); ImGui.CloseCurrentPopup(); }
            }
			ImGui.EndChild();
			ImGui.EndPopup();
		}
	}

	/// Puts every field of a component back to the value a new one would have.
	void ResetComponent(Component component)
	{
		let fresh = ComponentRegistry.Create(component.GetType());
		if (fresh == null)
			return;
		defer delete fresh;
		List<FieldRef> from = scope .();
		List<FieldRef> to = scope .();
		ComponentRegistry.GetFields(fresh, from);
		ComponentRegistry.GetFields(component, to);
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer { for (let s in storage) delete s; }
		for (int i < Math.Min(from.Count, to.Count))
		{
			let text = scope String();
			SceneSerializer.WriteValue(from[i], text);
			tokens.Clear();
			SceneSerializer.Tokenize(text, tokens, storage);
			SceneSerializer.ReadValue(to[i], Span<StringView>(tokens.Ptr, tokens.Count));
		}
		component.OnValidate();
	}

	/// X / Y / Z fields with coloured axis letters, as in Unity's Inspector.
	bool DrawVector3(char8* id, ref Vector3 value, float speed)
	{
		bool changed = false;
		ImGui.PushID(id);
		let spacing = 4.0f;
		let letter = ImGui.CalcTextSize("X").x + 4;
		let width = Math.Max((ImGui.GetContentRegionAvail().x - letter * 3 - spacing * 2) / 3, 24);
		ImGui.AlignTextToFramePadding();
		ImGui.TextColored(.(0.95f, 0.45f, 0.42f, 1), "X");
		ImGui.SameLine(0, 4);
		ImGui.SetNextItemWidth(width);
		changed |= ImGui.DragFloat("##x", ref value.x, speed);
		ImGui.SameLine(0, spacing);
		ImGui.TextColored(.(0.55f, 0.85f, 0.42f, 1), "Y");
		ImGui.SameLine(0, 4);
		ImGui.SetNextItemWidth(width);
		changed |= ImGui.DragFloat("##y", ref value.y, speed);
		ImGui.SameLine(0, spacing);
		ImGui.TextColored(.(0.45f, 0.62f, 0.98f, 1), "Z");
		ImGui.SameLine(0, 4);
		ImGui.SetNextItemWidth(width);
		changed |= ImGui.DragFloat("##z", ref value.z, speed);
		ImGui.PopID();
		return changed;
	}

    static StringView ComponentCategory(StringView fullName, StringView name)
    {
        if (!fullName.StartsWith("Tessera.")) return "Scripts";
        if (name == "Camera" || name == "Light" || name == "MeshRenderer") return "Rendering";
        if (name == "Rigidbody" || name.EndsWith("Collider") || name == "CharacterController") return "Physics";
        if (name == "SkinnedMeshRenderer" || name == "Animator") return "Animation";
        if (name == "UIDocument") return "UI";
        if (name.StartsWith("Audio")) return "Audio";
        if(name.StartsWith("Navigation") || name.StartsWith("BehaviorTree")) return "AI";
        if (name == "ParticleSystem") return "Particles";
        if (name.StartsWith("Voxel") || name == "SpawnPoint") return "World";
        if (name.StartsWith("Network") || name == "CharacterMotor") return "Networking";
        return "Scripts";
    }

	static char8* ComponentIcon(StringView typeName)
	{
		if (typeName == "Camera") return Icons.Camera;
		if (typeName == "Light") return Icons.Light;
		if (typeName == "MeshRenderer") return Icons.Cube;
		if (typeName == "SkinnedMeshRenderer" || typeName == "Animator") return Icons.Character;
		if (typeName == "UIDocument") return Icons.Script;
		if (typeName == "Rigidbody") return Icons.Body;
		if (typeName.EndsWith("Collider")) return Icons.Collider;
		if (typeName == "VoxelTerrain") return Icons.Terrain;
		if (typeName == "VoxelObject") return Icons.Voxel;
		if (typeName == "ParticleSystem") return Icons.Particles;
		if (typeName.StartsWith("Network")) return Icons.Network;
		if (typeName == "CharacterMotor" || typeName == "CharacterController") return Icons.Character;
		return Icons.Script;
	}

	static char8* ObjectIcon(GameObject gameObject)
	{
		if (gameObject.IsFolder) return Icons.Folder;
		for (let component in gameObject.Components)
		{
			if (component is Camera) return Icons.Camera;
			if (component is Light) return Icons.Light;
			if (component is VoxelTerrain) return Icons.Terrain;
			if (component is ParticleSystem) return Icons.Particles;
			if (component is NetworkSession) return Icons.Network;
		}
		return Icons.Cube;
	}

	bool DrawField(FieldRef field)
	{
		let label = scope String();
		NiceName(field.name, label);
		BeginProperty(label.CStr());
		ImGui.PushID(field.ptr);
		defer ImGui.PopID();
		switch (field.kind)
		{
		case .Float:
			if (field.hasRange)
				return ImGui.SliderFloat("##v", ref *(float*)field.ptr, field.rangeMin, field.rangeMax);
			return ImGui.DragFloat("##v", ref *(float*)field.ptr, 0.02f);
		case .Int:
			return DrawInteger(field);
		case .Bool:
			return ImGui.Checkbox("##v", ref *(bool*)field.ptr);
        case .Double: return DrawDouble(field);
        case .Char:
            let text=scope String();let value=FieldNumbers.ReadUnsigned(field);if(value!=0) text.Append((char32)value);
            if(ImGui.InputText("##v",text)) return FieldNumbers.WriteUnsigned(field,text.IsEmpty ? 0 : (uint64)text.GetChar32(0).c);
            return false;
        case .Vector2: return DragVector("##v",&((Vector2*)field.ptr).x,2,0.02f);
        case .Vector4: return DragVector("##v",&((Vector4*)field.ptr).x,4,0.02f);
        case .Int3: return DragIntegerVector("##v",&((Int3*)field.ptr).x,3);
        case .Matrix4:
            bool changed=false;let matrix=(Matrix4*)field.ptr;
            for(int i<4) {ImGui.PushID((int32)i);changed |= DragVector("##row",&matrix.m[i*4],4,0.02f);ImGui.PopID();}
            return changed;
		case .Vector3:
			return DrawVector3("v", ref *(Vector3*)field.ptr, 0.05f);
		case .Quaternion:
			var euler = ((Quaternion*)field.ptr).EulerAngles;
			if (ImGui.DragFloat3("##v", ref euler, 0.5f))
			{
				*(Quaternion*)field.ptr = Quaternion.Euler(euler);
				return true;
			}
			return false;
		case .Color:
			return ImGui.ColorEdit4("##v", ref *(Color*)field.ptr, ImGui.ColorFlags.Float);
        case .String:
            let original=*(String*)field.ptr;
            let temporary=scope String();let text=original!=null ? original : temporary;
            bool changed;
            if(field.name=="mesh" || field.name=="model" || field.name=="texture" || field.name=="document" || field.name=="prefab" || field.name=="tree" || field.name=="controller" || field.name=="material" || field.name=="shader" || field.name=="bakedData" || field.name=="audioClip" || field.name.EndsWith("Prefab"))
                changed=DrawAssetPicker(text,field.name);
            else changed=ImGui.InputText("##v",text);
            if(changed && original==null) *(String*)field.ptr=new String(text);
            return changed;
		case .ObjectReference:
			return DrawObjectPicker(field);

        case .Enum:
            bool hasNames=false;for(let entry in Enum.GetEnumerator(field.type)) {hasNames=true;break;}
            if(!hasNames) return DrawInteger(field);
            let current=scope String();Enum.EnumToString(field.type,current,FieldNumbers.EnumValue(field));
            bool changed=false;
            if(ImGui.BeginCombo("##v",current.CStr()))
            {
                for(let (name,value) in Enum.GetEnumerator(field.type))
                    if(ImGui.Selectable(scope String(name).CStr(),value==FieldNumbers.EnumValue(field)))
                    {changed=FieldNumbers.Signed(field) ? FieldNumbers.WriteSigned(field,value) : FieldNumbers.WriteUnsigned(field,(uint64)value);}
                ImGui.EndCombo();
            }
            return changed;
		}
	}

	bool AcceptAssetKind(StringView path, StringView kind)
	{
		if (kind == "mesh" || kind == "model") return IsModelFile(path);
		if (kind == "texture") return IsImageFile(path);
        if(kind=="bakedData") return HasExtension(path,".tnav");
        if(kind=="audioClip") return IsAudioFile(path);
        if(kind=="tree") return HasExtension(path,".tbt");
        if(kind=="controller") return HasExtension(path,".tcontroller");
        if(kind=="material") return HasExtension(path,".tmat");
        if(kind=="shader") return HasExtension(path,".tcompute");
		if (kind == "document") return HasExtension(path, ".tui");
		return HasExtension(path, ".tprefab");
	}

	bool DrawAssetChoices(StringView folder, StringView kind, String path)
	{
		bool changed = false;
		for (let entry in Directory.EnumerateFiles(folder))
		{
			let name = scope String(); entry.GetFileName(name);
			if (IsHidden(name) || !AcceptAssetKind(name, kind)) continue;
			let relative = scope String(); ToRelative(scope $"{folder}/{name}", relative);
			if (ImGui.Selectable(relative.CStr(), path == relative))
			{ path.Set(relative); changed = true; ImGui.CloseCurrentPopup(); }
		}
		for (let entry in Directory.EnumerateDirectories(folder))
		{
			let name = scope String(); entry.GetFileName(name);
			if (!IsHidden(name)) changed |= DrawAssetChoices(scope $"{folder}/{name}", kind, path);
		}
		return changed;
	}

	bool DrawAssetPicker(String path, StringView kind)
	{
		ImGui.SetNextItemWidth(-28);
		bool changed = ImGui.InputText("##v", path);
		// The text field is the drop target; begin it before drawing another item.
		let drag=ImGui.GetDragDropPayload();
        if (drag!=null && ImGui.PayloadIsType(drag,"ASSET") && AcceptAssetKind(StringView((char8*)drag.data,drag.dataSize),kind)
            && ImGui.BeginDragDropTarget())
        {
            let payload = ImGui.AcceptDragDropPayload("ASSET");
            if (payload != null && AcceptAssetKind(StringView((char8*)payload.data, payload.dataSize), kind))
			{ path.Set(StringView((char8*)payload.data, payload.dataSize)); changed = true; }
			ImGui.EndDragDropTarget();
		}
		ImGui.SameLine();
		if (ImGui.Button("...")) ImGui.OpenPopup("AssetPicker");
		if (ImGui.BeginPopup("AssetPicker"))
		{
			if (ImGui.Selectable("None", path.IsEmpty)) { path.Clear(); changed = true; }
			if (kind == "mesh")
				for (let name in Assets.BuiltinMeshes)
					if (ImGui.Selectable(scope String(name).CStr(), path == name)) { path.Set(name); changed = true; }
			ImGui.Separator();
			changed |= DrawAssetChoices(Assets.ProjectPath, kind, path);
			ImGui.EndPopup();
		}
		return changed;
	}

	bool DrawObjectPicker(FieldRef field)
	{
		bool changed = false;
		let target = ComponentRegistry.ReferenceOwner(field);
		ImGui.SetNextItemWidth(-28);
		let text = scope String(target != null ? (StringView)target.Name : "None");
		ImGui.InputText("##v", text, ImGui.InputFlags.ReadOnly);
		if (ImGui.BeginDragDropTarget())
		{
			let payload = ImGui.AcceptDragDropPayload("GAMEOBJECT");
			if (payload != null && payload.dataSize == sizeof(uint32))
			{
				let go = mScene.FindById(*(uint32*)payload.data);
				if (go != null) changed = ComponentRegistry.AssignReference(field, go);
			}
			ImGui.EndDragDropTarget();
		}
		ImGui.SameLine();
		if (ImGui.Button("...")) ImGui.OpenPopup("ObjectPicker");
		if (ImGui.BeginPopup("ObjectPicker"))
		{
			if (ImGui.Selectable("None", target == null)) changed = ComponentRegistry.AssignReference(field, null);
			for (let go in mScene.Objects)
			{
				ImGui.PushID((int32)go.Id);
				if (field.type == typeof(GameObject) || field.type == typeof(Transform))
				{
					if (ImGui.Selectable(go.Name.CStr(), target == go)) changed = ComponentRegistry.AssignReference(field, go);
				}
				else for (int i < go.Components.Count)
				{
					let component = go.Components[i];
					if (component.GetType() != field.type && !component.GetType().IsSubtypeOf(field.type)) continue;
					ImGui.PushID((int32)i);
					if (ImGui.Selectable(scope $"{go.Name} ({component.GetType()})".CStr(), *(Object*)field.ptr == component))
						changed = ComponentRegistry.AssignReference(field, go, i);
					ImGui.PopID();
				}
				ImGui.PopID();
			}
			ImGui.EndPopup();
		}
		return changed;
	}
}
