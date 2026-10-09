using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// The Hierarchy panel.
extension EditorApp
{
	void DrawHierarchy()
	{
		if (ImGui.Begin("Hierarchy"))
		{
			DrawPrefabBar();
			if (ImGui.Button("+"))
				ImGui.OpenPopup("CreateObject");
			if (ImGui.BeginPopup("CreateObject"))
			{
				DrawCreateMenu();
				ImGui.EndPopup();
			}
			ImGui.SameLine();
			ImGui.SetNextItemWidth(-1);
			ImGui.InputText("##search", mHierarchySearch, 0, "Search");
			ImGui.Separator();

			ImGui.BeginChild("tree");
			let sceneLabel = scope String();
			sceneLabel.AppendF("{}{}", mScene.Name, mDirty ? "*" : "");
			if (ImGui.TreeNode(sceneLabel.CStr(), ImGui.TreeFlags.DefaultOpen | ImGui.TreeFlags.SpanAvailWidth))
			{
				for (int i = 0; i < mScene.Roots.Count; i++)
					DrawHierarchyNode(mScene.Roots[i]);
				ImGui.TreePop();
			}
			// Empty space: click to deselect, drop to un-parent, right click to create.
			let avail = ImGui.GetContentRegionAvail();
			ImGui.InvisibleButton("##empty", .(Math.Max(avail.x, 1), Math.Max(avail.y, 40)));
			if (ImGui.IsItemClicked(0))
				mSelectedId = 0;
			if (ImGui.BeginDragDropTarget())
			{
				let payload = ImGui.AcceptDragDropPayload("GAMEOBJECT");
				if (payload != null)
				{
					let dragged = mScene.FindById(*(uint32*)payload.data);
					if (dragged != null)
					{
						dragged.Transform.SetParent(null);
						MarkDirty();
					}
				}
				let asset = ImGui.AcceptDragDropPayload("ASSET");
				if (asset != null)
				{
					mSelectedId = 0;
					DropAssetIntoScene(StringView((char8*)asset.data, asset.dataSize), false, 0.5f, 0.5f);
				}
				ImGui.EndDragDropTarget();
			}
			if (ImGui.BeginPopupContextItem("HierarchyContext"))
			{
				DrawCreateMenu();
				ImGui.EndPopup();
			}
			ImGui.EndChild();
		}
		ImGui.End();
	}

	void DrawHierarchyNode(GameObject gameObject)
	{
		if (gameObject.Transient || gameObject.IsDestroyed)
			return;
		int visibleChildren = 0;
		for (let child in gameObject.Transform.Children)
		{
			if (!child.GameObject.Transient)
				visibleChildren++;
		}
		if (!mHierarchySearch.IsEmpty && visibleChildren == 0 && !gameObject.Name.Contains(mHierarchySearch, true))
			return;

		var flags = ImGui.TreeFlags.OpenOnArrow | ImGui.TreeFlags.SpanAvailWidth | ImGui.TreeFlags.OpenOnDoubleClick;
		if (visibleChildren == 0)
			flags |= ImGui.TreeFlags.Leaf;
		if (gameObject.Id == mSelectedId)
			flags |= ImGui.TreeFlags.Selected;
		let inactive = !gameObject.ActiveInHierarchy;
		if (inactive)
			ImGui.PushStyleColor(ImGui.Col.Text, .(0.5f, 0.5f, 0.5f, 1));
		ImGui.PushID((int32)gameObject.Id);
		let nodeLabel = scope String();
		nodeLabel.AppendF("{}  {}###node", StringView(ObjectIcon(gameObject)), gameObject.Name.IsEmpty ? "(unnamed)" : (StringView)gameObject.Name);
		if (gameObject.IsFolder && !inactive)
			ImGui.PushStyleColor(ImGui.Col.Text, Icons.FolderColor);
		let open = ImGui.TreeNode(nodeLabel.CStr(), flags);
		if (inactive || gameObject.IsFolder)
			ImGui.PopStyleColor();
		if (ImGui.IsItemClicked(0) && !ImGui.IsItemToggledOpen())
			mSelectedId = gameObject.Id;
		if (ImGui.IsItemHovered() && ImGui.IsMouseDoubleClicked(0))
		{
			mSelectedId = gameObject.Id;
			FocusSelected();
		}
		if (ImGui.BeginPopupContextItem())
		{
			mSelectedId = gameObject.Id;
			if (ImGui.MenuItem("Duplicate")) DuplicateSelected();
			if (ImGui.MenuItem("Delete")) DeleteSelected();
			if (ImGui.MenuItem("Frame in Scene")) FocusSelected();
			if (ImGui.MenuItem("Save as Prefab")) SaveSelectedAsPrefab();
			ImGui.Separator();
			DrawCreateMenu();
			ImGui.EndPopup();
		}
		if (ImGui.BeginDragDropSource())
		{
			var id = gameObject.Id;
			ImGui.SetDragDropPayload("GAMEOBJECT", &id, sizeof(uint32));
			ImGui.Text(gameObject.Name);
			ImGui.EndDragDropSource();
		}
		if (ImGui.BeginDragDropTarget())
		{
			let payload = ImGui.AcceptDragDropPayload("GAMEOBJECT");
			if (payload != null)
			{
				let dragged = mScene.FindById(*(uint32*)payload.data);
				if (dragged != null && dragged != gameObject)
				{
					dragged.Transform.SetParent(gameObject.Transform);
					MarkDirty();
				}
			}
			ImGui.EndDragDropTarget();
		}
		if (open)
		{
			for (int i = 0; i < gameObject.Transform.Children.Count; i++)
				DrawHierarchyNode(gameObject.Transform.Children[i].GameObject);
			ImGui.TreePop();
		}
		ImGui.PopID();
	}
}
