using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// The UI tab: a visual editor for UI documents (.tui).
/// Left: the element tree. Middle: a live preview you can click to select elements.
/// Right: the selected element's tag, text, events and style properties. Save writes the markup back.
extension EditorApp
{
	UIDocumentData mUiData ~ delete _;
	String mUiPath = new .() ~ delete _;
	String mUiStatus = new .() ~ delete _;
	String mUiNewProperty = new .() ~ delete _;
	UIElement mUiSelected;
	bool mUiFocus;
	int32 mUiPreviewSize = 1;

	static readonly char8*[?] cUiTags = .("panel", "text", "button", "image", "input", "bar", "slider", "toggle", "canvas");
	// Sized by cUiTags so that a tag added there without a name and a hint here does not compile.
	static readonly char8*[cUiTags.Count] cUiTagNames = .("Panel", "Text", "Button", "Image", "Text Field", "Progress Bar", "Slider",
		"Toggle", "Canvas");
	static readonly char8*[cUiTags.Count] cUiTagHints = .("Groups and arranges other components", "A line of text", "Runs a method when pressed",
		"Shows a picture", "Lets the player type; bound to a field", "A bar filled by a bound number",
		"A handle dragged between two numbers; calls a method when moved", "A switch that is on or off; calls a method when changed",
		"An empty area that a method draws into every frame");

	static StringView UiTagName(StringView tag)
	{
		for (int i < cUiTags.Count)
		{
			if (tag == StringView(cUiTags[i]))
				return StringView(cUiTagNames[i]);
		}
		return tag;
	}

	/// Called when the markup or stylesheet was saved from the code editor: refresh the preview and the scene.
	void OnUiSourceSaved(StringView path)
	{
		if (mUiData != null)
		{
			let stylePath = scope String();
			UIDocumentData.StylePathFor(mUiPath, stylePath);
			if (path == mUiPath || path == stylePath)
			{
				mUiData.Load(mUiPath);
				mUiSelected = null;
			}
		}
		for (let component in mScene.Components)
		{
			if (let document = component as UIDocument)
				document.Reload();
		}
	}

	/// Opens the document's markup or its stylesheet in the Scripts tab. The stylesheet is moved
	/// into its own .tcss file the first time, so each language gets its own highlighting.
	void OpenUiSource(bool stylesheet)
	{
		if (stylesheet)
			mUiData.separateStyleFile = true;
		SaveUI();
		if (!stylesheet)
		{
			OpenScript(mUiPath);
			return;
		}
		let stylePath = scope String();
		UIDocumentData.StylePathFor(mUiPath, stylePath);
		OpenScript(stylePath);
	}
	static readonly char8*[?] cUiStyleNames = .("width", "height", "padding", "margin", "gap", "flex-direction", "flex-grow", "align-items",
		"justify-content", "background-color", "color", "font-size", "border-radius", "border-width", "border-color", "text-align",
		"position", "left", "top", "right", "bottom", "display");
	static readonly (int32 w, int32 h, char8* name)[?] cUiSizes = .((960, 540, "960 x 540"), (1280, 720, "1280 x 720"), (1920, 1080, "1920 x 1080"));

	void OpenUI(StringView path)
	{
        mShowUI=true; mDockUI=true;
		delete mUiData;
		mUiData = new UIDocumentData();
		mUiPath.Set(path);
		mUiSelected = null;
		mUiStatus.Clear();
		if (!mUiData.Load(path))
			mUiStatus.Set("Could not read the file.");
		mUiFocus = true;
	}

	void CreateUIAsset(StringView name)
	{
		if (!ProjectGenerator.IsValidName(name))
		{
			Log.Error("UI document names use letters, digits and underscores, and start with a letter.");
			return;
		}
		let path = scope $"{mBrowsePath}/{name}.tui";
		if (File.Exists(path))
		{
			Log.Error(scope $"{path} already exists.");
			return;
		}
		File.WriteAllText(path, """
			<style>
			#screen { width: 100%; height: 100%; align-items: center; justify-content: center }
			.card { width: 320; padding: 20; gap: 10; background-color: #1b2028f2; border-radius: 8 }
			.title { font-size: 24 }
			</style>

			<panel id="screen">
				<panel class="card">
					<text class="title">New UI</text>
					<button onclick="OnPressed">Button</button>
				</panel>
			</panel>

			""").IgnoreError();
		RefreshAssetList();
		OpenUI(path);
	}

	void SaveUI()
	{
		if (mUiData == null)
			return;
		let text = scope String();
		mUiData.Save(text);
		if (mUiData.separateStyleFile)
		{
			let stylePath = scope String();
			UIDocumentData.StylePathFor(mUiPath, stylePath);
			File.WriteAllText(stylePath, scope String(mUiData.styleText)..Append('\n')).IgnoreError();
		}
		if (File.WriteAllText(mUiPath, text) case .Ok)
		{
			mUiStatus.Set("Saved.");
			// Documents already showing in the scene pick the change up straight away.
			for (let component in mScene.Components)
			{
				if (let document = component as UIDocument)
					document.Reload();
			}
		}
		else
			mUiStatus.Set("Could not save.");
	}

	void DrawUiTree(UIElement element, int depth)
	{
		// "Button  Play", "Panel  card": what the element is and how to recognise it, without markup syntax.
		let label = scope String();
		label.Append(UiTagName(element.tag));
		if (!element.text.IsEmpty)
			label.AppendF("  \"{}\"", element.text.Length > 20 ? element.text.Substring(0, 20) : (StringView)element.text);
		else if (!element.Id.IsEmpty)
			label.AppendF("  {}", element.Id);
		else if (!element.attributes.Get("class").IsEmpty)
			label.AppendF("  {}", element.attributes.Get("class"));
		var flags = ImGui.TreeFlags.OpenOnArrow | ImGui.TreeFlags.SpanAvailWidth | ImGui.TreeFlags.DefaultOpen;
		if (element.children.Count == 0)
			flags |= ImGui.TreeFlags.Leaf;
		if (element == mUiSelected)
			flags |= ImGui.TreeFlags.Selected;
		ImGui.PushID(Internal.UnsafeCastToPtr(element));
		let open = ImGui.TreeNode(label.CStr(), flags);
		if (ImGui.IsItemClicked(0) && !ImGui.IsItemToggledOpen())
			mUiSelected = element;
		if (open)
		{
			for (let child in element.children)
				DrawUiTree(child, depth + 1);
			ImGui.TreePop();
		}
		ImGui.PopID();
	}

	/// Deepest element under a point in document space.
	UIElement PickUiElement(UIElement element, float x, float y)
	{
		if (!element.visible || x < element.x || y < element.y || x >= element.x + element.width || y >= element.y + element.height)
			return null;
		for (int i = element.children.Count - 1; i >= 0; i--)
		{
			let hit = PickUiElement(element.children[i], x, y);
			if (hit != null)
				return hit;
		}
		return element;
	}

	bool UiAttribute(char8* label, UIElement element, StringView name)
	{
		let value = scope String(element.attributes.Get(name));
		BeginProperty(label);
		ImGui.PushID(label);
		let changed = ImGui.InputText("##a", value);
		ImGui.PopID();
		if (changed)
		{
			if (value.IsEmpty)
				element.attributes.Remove(name);
			else
				element.attributes.Set(name, value);
		}
		return changed;
	}

	void DrawUIEditor()
	{
        if (!mShowUI) return;
        if (mDockUI && mAssetCenterDock!=0) { ImGui.SetNextWindowDockID(mAssetCenterDock); mDockUI=false; }
		if (mUiFocus && Time.FrameCount > 5)
		{
			ImGui.SetWindowFocus("UI");
			mUiFocus = false;
		}
		if (!ImGui.Begin("UI", &mShowUI, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse))
		{
			ImGui.End();
			return;
		}
		if (mUiData == null || mUiData.root == null)
		{
			ImGui.TextDisabled("Create an interface with Project > + > UI Document, or double-click a .tui file.");
			ImGui.End();
			return;
		}

		// ---- toolbar ----
		if (ImGui.SmallButton("Save")) SaveUI();
		ImGui.SameLine();
		if (ImGui.SmallButton("Open HTML")) OpenUiSource(false);
		ImGui.SameLine();
		if (ImGui.SmallButton("Open CSS")) OpenUiSource(true);
		ImGui.SameLine(0, 14);
		ImGui.SetNextItemWidth(120);
		if (ImGui.BeginCombo("##size", cUiSizes[mUiPreviewSize].name))
		{
			for (int32 i < (int32)cUiSizes.Count)
			{
				if (ImGui.Selectable(cUiSizes[i].name, mUiPreviewSize == i))
					mUiPreviewSize = i;
			}
			ImGui.EndCombo();
		}
		ImGui.SameLine();
		ImGui.TextDisabled(mUiStatus.CStr());
		ImGui.Separator();

		let total = ImGui.GetContentRegionAvail();
		let sideWidth = 250.0f;

		// ---- element tree ----
		ImGui.BeginChild("tree", .(sideWidth, 0), ImGui.ChildBorders);
		ImGui.TextDisabled("Components");
		for (int32 i < (int32)cUiTags.Count)
		{
			if (ImGui.Selectable(scope String()..AppendF("+  {}", StringView(cUiTagNames[i])).CStr()))
			{
				// New components go inside the selection when it can hold others, otherwise beside it.
				var parent = mUiSelected ?? mUiData.root;
				if (parent.tag != "panel")
					parent = parent.parent ?? mUiData.root;
				let created = parent.AddChild(StringView(cUiTags[i]));
				if (UIDocumentData.IsTextTag(created.tag))
					created.text.Set(created.tag == "button" ? "Button" : "Text");
				mUiSelected = created;
			}
			if (ImGui.IsItemHovered())
				ImGui.SetTooltip(cUiTagHints[i]);
		}
		ImGui.Spacing();
		ImGui.Separator();
		ImGui.TextDisabled("Hierarchy");
		for (let child in mUiData.root.children)
			DrawUiTree(child, 0);
		ImGui.EndChild();
		ImGui.SameLine();

		// ---- preview ----
		ImGui.BeginChild("preview", .(Math.Max(total.x - sideWidth * 2 - 16, 100), 0), 0, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse);
		let available = ImGui.GetContentRegionAvail();
		let designW = (float)cUiSizes[mUiPreviewSize].w;
		let designH = (float)cUiSizes[mUiPreviewSize].h;
		// The document is laid out at the size the panel can show, keeping the chosen aspect ratio.
		let scale = Math.Min(available.x / designW, available.y / designH);
		let viewW = designW * scale;
		let viewH = designH * scale;
		let origin = ImGui.GetCursorScreenPos();
		ImGui.InvisibleButton("##preview", .(Math.Max(viewW, 1), Math.Max(viewH, 1)));
		let previewHovered = ImGui.IsItemHovered();
		ImGui.DrawRectFilled(origin, .(origin.x + viewW, origin.y + viewH), .(0.16f, 0.19f, 0.23f, 1));
		mUiData.Layout(viewW, viewH);
		mUiData.Draw(origin, null, false);
		if (previewHovered && ImGui.IsMouseClicked(0))
		{
			let mouse = ImGui.GetMousePos();
			mUiSelected = PickUiElement(mUiData.root, mouse.x - origin.x, mouse.y - origin.y);
			if (mUiSelected == mUiData.root)
				mUiSelected = null;
		}
		if (mUiSelected != null)
		{
			let min = ImGui.Vec2(origin.x + mUiSelected.x, origin.y + mUiSelected.y);
			ImGui.DrawRect(min, .(min.x + mUiSelected.width, min.y + mUiSelected.height), .(1.0f, 0.62f, 0.15f, 1), 0, 2);
		}
		ImGui.EndChild();
		ImGui.SameLine();

		// ---- properties ----
		ImGui.BeginChild("properties", .(0, 0), ImGui.ChildBorders);
		if (mUiSelected == null)
			ImGui.TextWrapped("Click an element in the preview or the tree to edit it.");
		else
			DrawUiProperties(mUiSelected);
		ImGui.EndChild();
		ImGui.End();
	}

	void DrawUiProperties(UIElement element)
	{
		if (BeginPropertyTable("element"))
		{
			BeginProperty("Type");
			if (ImGui.BeginCombo("##tag", scope String(UiTagName(element.tag)).CStr()))
			{
				for (int32 i < (int32)cUiTags.Count)
				{
					if (ImGui.Selectable(cUiTagNames[i], element.tag == StringView(cUiTags[i])))
						element.tag.Set(StringView(cUiTags[i]));
				}
				ImGui.EndCombo();
			}
			if (UIDocumentData.IsTextTag(element.tag))
			{
				BeginProperty("Text");
				ImGui.InputText("##text", element.text);
			}
			UiAttribute("Id", element, "id");
			UiAttribute("Class", element, "class");
			UiAttribute("On Click", element, "onclick");
			UiAttribute("On Load", element, "onload");
			if (element.tag != "panel" && element.tag != "button")
				UiAttribute("Bind", element, "bind");
			if (element.tag == "image")
				UiAttribute("Source", element, "src");
			ImGui.EndTable();
		}

		ImGui.SeparatorText("Style");
		String remove = null;
		if (BeginPropertyTable("style"))
		{
			for (let item in element.style.items)
			{
				BeginProperty(item.key.CStr());
				ImGui.PushID(item.key.CStr());
				ImGui.SetNextItemWidth(-26);
				ImGui.InputText("##v", item.value);
				ImGui.SameLine();
				if (ImGui.SmallButton("x"))
					remove = item.key;
				ImGui.PopID();
			}
			ImGui.EndTable();
		}
		if (remove != null)
			element.style.Remove(scope String(remove));
		ImGui.SetNextItemWidth(-1);
		if (ImGui.BeginCombo("##addstyle", "Add style property..."))
		{
			for (let name in cUiStyleNames)
			{
				if (!element.style.Has(StringView(name)) && ImGui.Selectable(name))
				{
					let current = scope String(element.computed.Get(StringView(name)));
					element.style.Set(StringView(name), current.IsEmpty ? "0" : (StringView)current);
				}
			}
			ImGui.EndCombo();
		}
		ImGui.TextDisabled("Values from the stylesheet apply unless overridden here.");

		ImGui.SeparatorText("Element");
		let parent = element.parent;
		let index = parent != null ? parent.children.IndexOf(element) : -1;
		ImGui.BeginDisabled(index <= 0);
		if (ImGui.Button("Move Up"))
			Swap!(parent.children[index], parent.children[index - 1]);
		ImGui.EndDisabled();
		ImGui.SameLine();
		ImGui.BeginDisabled(parent == null || index < 0 || index >= parent.children.Count - 1);
		if (ImGui.Button("Move Down"))
			Swap!(parent.children[index], parent.children[index + 1]);
		ImGui.EndDisabled();
		ImGui.SameLine();
		if (ImGui.Button("Delete") && parent != null)
		{
			parent.children.Remove(element);
			delete element;
			mUiSelected = null;
		}
	}
}
