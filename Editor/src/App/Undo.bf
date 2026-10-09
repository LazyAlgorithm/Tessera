using System;
using System.Collections;
using Tessera;

namespace Tessera.Editor;

/// Undo and redo for scene edits. Each step is a saved copy of the scene; applying one only
/// rebuilds the objects that differ, so untouched objects (and streamed terrain) stay as they are.
/// Terrain sculpting and voxel carving are not part of the history.
extension EditorApp
{
	const int cMaxUndo = 64;

	List<String> mUndoStack = new .() ~ DeleteContainerAndItems!(_);
	List<String> mRedoStack = new .() ~ DeleteContainerAndItems!(_);
	String mBaseline = new .() ~ delete _;
	bool mUndoPending;

	bool CanUndo => mUndoStack.Count > 0 && mPlay == .Edit;
	bool CanRedo => mRedoStack.Count > 0 && mPlay == .Edit;

	void ResetUndo()
	{
		ClearAndDeleteItems!(mUndoStack);
		ClearAndDeleteItems!(mRedoStack);
		mBaseline.Clear();
		SceneSerializer.Save(mScene, mBaseline);
		mUndoPending = false;
	}

	/// Records a step once the user lets go, so a whole drag or text edit is one entry.
	void CommitUndoWhenIdle()
	{
		if (!mUndoPending || mPlay != .Edit || ImGui.IsAnyItemActive() || ImGui.IsMouseDown(0))
			return;
		mUndoPending = false;
		let current = new String();
		SceneSerializer.Save(mScene, current);
		if (current == mBaseline)
		{
			delete current;
			return;
		}
		mUndoStack.Add(new String(mBaseline));
		if (mUndoStack.Count > cMaxUndo)
		{
			delete mUndoStack[0];
			mUndoStack.RemoveAt(0);
		}
		ClearAndDeleteItems!(mRedoStack);
		mBaseline.Set(current);
		delete current;
	}

	void Undo()
	{
		CommitUndoWhenIdle();
		if (!CanUndo)
			return;
		let target = mUndoStack.PopBack();
		mRedoStack.Add(new String(mBaseline));
		ApplySnapshot(mBaseline, target);
		mBaseline.Set(target);
		delete target;
		mDirty = true;
	}

	void Redo()
	{
		if (!CanRedo)
			return;
		let target = mRedoStack.PopBack();
		mUndoStack.Add(new String(mBaseline));
		ApplySnapshot(mBaseline, target);
		mBaseline.Set(target);
		delete target;
		mDirty = true;
	}

	struct Block
	{
		public uint32 id;
		public uint32 parent;
		public StringView text;
	}

	/// Splits serialized scene text into one block per object.
	static void SplitBlocks(StringView text, List<Block> blocks)
	{
		int start = -1;
		Block current = default;
		int offset = 0;
		void Close(int end)
		{
			if (start >= 0)
			{
				current.text = text.Substring(start, end - start);
				blocks.Add(current);
			}
		}
		for (let line in text.Split('\n'))
		{
			if (line.StartsWith("object "))
			{
				Close(offset);
				start = offset;
				var parts = line.Split(' ');
				parts.GetNext();
				current.id = (uint32)SceneSerializer.ParseInt(parts.GetNext().GetValueOrDefault());
				parts.GetNext();
				current.parent = (uint32)SceneSerializer.ParseInt(parts.GetNext().GetValueOrDefault());
			}
			offset += line.Length + 1;
		}
		Close(Math.Min(offset, text.Length));
	}

	void ApplySnapshot(StringView from, StringView to)
	{
		List<Block> before = scope .();
		List<Block> after = scope .();
		SplitBlocks(from, before);
		SplitBlocks(to, after);
		Dictionary<uint32, StringView> beforeById = scope .();
		for (let block in before)
			beforeById[block.id] = block.text;

		// Objects that differ, plus everything beneath them (children are destroyed with a parent).
		HashSet<uint32> rebuild = scope .();
		HashSet<uint32> afterIds = scope .();
		for (let block in after)
		{
			afterIds.Add(block.id);
			if (!beforeById.TryGetValue(block.id, let old) || old != block.text)
				rebuild.Add(block.id);
		}
		bool grew = true;
		while (grew)
		{
			grew = false;
			for (let block in after)
			{
				if (block.parent != 0 && rebuild.Contains(block.parent) && rebuild.Add(block.id))
					grew = true;
			}
		}

		for (let block in before)
		{
			if (afterIds.Contains(block.id) && !rebuild.Contains(block.id))
				continue;
			let existing = mScene.FindById(block.id);
			if (existing != null)
				mScene.DestroyImmediate(existing);
		}
		let text = scope String();
		for (let block in after)
		{
			if (rebuild.Contains(block.id))
				text.Append(block.text);
		}
		if (!text.IsEmpty)
			SceneSerializer.LoadObjects(mScene, text);
		SceneSerializer.LoadEnvironment(mScene, to);
		if (mSelectedId != 0 && mScene.FindById(mSelectedId) == null)
			mSelectedId = 0;
	}

	void SaveSelectedAsPrefab()
	{
		let selected = Selected;
		if (selected == null)
			return;
		let name = scope String();
		for (let c in selected.Name.RawChars)
			name.Append(c.IsLetterOrDigit || c == '_' ? c : '_');
		if (name.IsEmpty)
			name.Set("Prefab");
		let path = scope $"{mBrowsePath}/{name}.tprefab";
		if (Prefab.Save(selected, path))
			Log.Info(scope $"Saved prefab {path}. Drag it from Project into the Scene to place copies.");
		else
			Log.Error(scope $"Could not write {path}");
		RefreshAssetList();
	}
}
