using System;
using System.Collections;
using Tessera;

namespace Tessera.Editor;

/// Sculpting and painting brushes for VoxelTerrain, and carving for VoxelObject, used from the Scene view.
extension EditorApp
{
	int32 mBrushTool = -1;
	float mBrushSize = 6.0f;
	float mBrushStrength = 0.6f;
	int32 mPaintLayer = 1;
	float mFlattenHeight;
	bool mBrushStroke;
	/// The terrain a stroke is being recorded on, for undo.
	uint32 mStrokeTerrain;
	int32 mSelectedTile;
	String mBakeGenerator = new .() ~ delete _;

	const int32 cTilesTool = 5;
	static readonly char8*[?] cBrushNames = .("Raise", "Lower", "Smooth", "Flatten", "Paint", "Tiles");
	static readonly char8*[?] cLayerNames = .("Automatic", "Grass", "Rock", "Sand", "Snow", "Dirt");

	void DrawTerrainTools(VoxelTerrain terrain)
	{
		ImGui.Spacing();
		ImGui.SeparatorText("Terrain Tools");
		let width = (ImGui.GetContentRegionAvail().x - 4 * 7) / 6;
		for (int32 i < 6)
		{
			if (i > 0)
				ImGui.SameLine();
			if (ToolButton(cBrushNames[i], mBrushTool == i, width))
				mBrushTool = mBrushTool == i ? -1 : i;
		}

		// What shapes ground nobody has sculpted.
		if (BeginPropertyTable("terraingen"))
		{
			BeginProperty("Generator");
			if (ImGui.BeginCombo("##generator", terrain.generator.IsEmpty ? (terrain.mode == .Endless ? "Sample noise" : "Flat") : terrain.generator.CStr()))
			{
				if (ImGui.Selectable(terrain.mode == .Endless ? "Sample noise" : "Flat", terrain.generator.IsEmpty))
				{
					terrain.generator.Clear();
					terrain.OnValidate();
					MarkDirty();
				}
				List<Type> types = scope .();
				TerrainGenerator.Types(types);
				for (let type in types)
				{
					let name = type.GetFullName(.. scope .());
					if (type == typeof(NoiseTerrainGenerator))
						continue;
					if (ImGui.Selectable(type.GetName(.. scope .()), terrain.generator == name))
					{
						terrain.generator.Set(name);
						terrain.OnValidate();
						MarkDirty();
					}
				}
				ImGui.EndCombo();
			}
			ImGui.EndTable();
		}

		if (mBrushTool == cTilesTool)
		{
			DrawTileTools(terrain);
			return;
		}
		if (BeginPropertyTable("brush"))
		{
			BeginProperty("Brush Size");
			ImGui.SliderFloat("##size", ref mBrushSize, 1, 40, "%.1f");
			BeginProperty("Strength");
			ImGui.SliderFloat("##strength", ref mBrushStrength, 0.05f, 2, "%.2f");
			if (mBrushTool == (int32)VoxelBrush.Paint)
			{
				BeginProperty("Layer");
				if (ImGui.BeginCombo("##layer", cLayerNames[mPaintLayer]))
				{
					for (int32 i < 6)
					{
						if (ImGui.Selectable(cLayerNames[i], mPaintLayer == i))
							mPaintLayer = i;
					}
					ImGui.EndCombo();
				}
			}
			if (mBrushTool == (int32)VoxelBrush.Flatten)
			{
				BeginProperty("Height");
				ImGui.DragFloat("##height", ref mFlattenHeight, 0.1f);
			}
			ImGui.EndTable();
		}
		if (mBrushTool >= 0)
			ImGui.TextWrapped("Drag in the Scene view to apply; brushes carry on across tile edges. Shift swaps Raise and Lower. Flatten uses the height where the stroke starts. Ctrl+Z undoes a stroke.");
		else
			ImGui.TextDisabled("Pick a tool to sculpt or paint in the Scene view, or Tiles to add, move and remove tiles.");

		let status = scope String();
		status.AppendF("{} tiles, {} chunks, {} pending{}", terrain.TileCount, terrain.ChunkCount, terrain.PendingChunks, terrain.HasUnsavedEdits ? ", unsaved edits" : "");
		ImGui.TextDisabled(status.CStr());
		if (ImGui.Button("Regenerate"))
			terrain.Regenerate();
		ImGui.SameLine();
		ImGui.TextDisabled(terrain.editsFolder.IsEmpty ? "Sculpting is saved with the scene" : terrain.editsFolder.CStr());
	}

	void DrawTileTools(VoxelTerrain terrain)
	{
		if (terrain.mode != .Fixed)
		{
			ImGui.TextWrapped("Tiles are for a Fixed terrain. An Endless one is generated around the camera.");
			return;
		}
		let status = scope String();
		status.AppendF("{} tiles of {} x {} chunks ({} m square)", terrain.TileCount, terrain.tileSize, terrain.tileSize, (int)terrain.TileWorldSize);
		ImGui.TextDisabled(status.CStr());
		ImGui.TextWrapped("In the Scene view: click a + to add a tile beside the others, Ctrl+click any empty place to add one apart from them, click a tile to select it, Shift+click an empty place to move the selected tile there.");
		TerrainTile tile = default;
		if (mSelectedTile == 0 || !terrain.FindTile(mSelectedTile, out tile))
		{
			mSelectedTile = 0;
			ImGui.TextDisabled("No tile selected.");
			return;
		}
		ImGui.Spacing();
		ImGui.Text(scope $"Tile {tile.id} at ({tile.x}, {tile.z})");
		void Move(char8* label, int32 dx, int32 dz)
		{
			let free = terrain.TileAt(tile.x + dx, tile.z + dz) == 0;
			ImGui.BeginDisabled(!free);
			if (ImGui.Button(label) && terrain.MoveTile(tile.id, tile.x + dx, tile.z + dz))
				MarkDirty();
			ImGui.EndDisabled();
		}
		Move("Move -X", -1, 0);
		ImGui.SameLine();
		Move("Move +X", 1, 0);
		ImGui.SameLine();
		Move("Move -Z", 0, -1);
		ImGui.SameLine();
		Move("Move +Z", 0, 1);
		if (ImGui.Button("Remove Tile"))
		{
			terrain.RemoveTile(tile.id);
			mSelectedTile = 0;
			MarkDirty();
			return;
		}
		ImGui.SameLine();
		ImGui.TextDisabled("leaves a hole; undo brings it back");

		ImGui.Spacing();
		List<Type> types = scope .();
		TerrainGenerator.Types(types);
		if (mBakeGenerator.IsEmpty && types.Count > 0)
			types[0].GetFullName(mBakeGenerator);
		ImGui.SetNextItemWidth(ImGui.GetContentRegionAvail().x * 0.55f);
		if (ImGui.BeginCombo("##bake", mBakeGenerator.IsEmpty ? "(no generators)" : mBakeGenerator.CStr()))
		{
			for (let type in types)
			{
				let name = type.GetFullName(.. scope .());
				if (ImGui.Selectable(name, mBakeGenerator == name))
					mBakeGenerator.Set(name);
			}
			ImGui.EndCombo();
		}
		ImGui.SameLine();
		ImGui.BeginDisabled(mBakeGenerator.IsEmpty);
		if (ImGui.Button("Apply Generator"))
		{
			let generator = TerrainGenerator.Create(mBakeGenerator);
			if (generator != null)
			{
				terrain.BeginEditRecord();
				terrain.ApplyGenerator(generator, tile.id);
				PushTerrainUndo(terrain, terrain.EndEditRecord());
				delete generator;
				MarkDirty();
			}
		}
		ImGui.EndDisabled();
		ImGui.TextDisabled("replaces this tile's ground with the generator's, as if sculpted");
	}

	/// Finishes the brush stroke in progress, keeping it as one undo step.
	void EndBrushStroke()
	{
		mBrushStroke = false;
		if (mStrokeTerrain == 0)
			return;
		let owner = mScene.FindById(mStrokeTerrain);
		mStrokeTerrain = 0;
		let terrain = owner?.GetComponent<VoxelTerrain>();
		if (terrain != null)
			PushTerrainUndo(terrain, terrain.EndEditRecord());
	}

	/// The tile grid in the Scene view: outlines, + where a tile can go, and clicks to add, select and move.
	void UpdateTileTool(VoxelTerrain terrain, Ray ray)
	{
		if (terrain.mode != .Fixed)
			return;
		let w = terrain.TileWorldSize;
		let height = terrain.flatHeight + 0.05f;
		let toWorld = terrain.Transform.LocalToWorld;
		void Square(int32 x, int32 z, float inset, Color color)
		{
			let a = toWorld.TransformPoint(.(x * w + inset, height, z * w + inset));
			let b = toWorld.TransformPoint(.((x + 1) * w - inset, height, z * w + inset));
			let c = toWorld.TransformPoint(.((x + 1) * w - inset, height, (z + 1) * w - inset));
			let d = toWorld.TransformPoint(.(x * w + inset, height, (z + 1) * w - inset));
			Gizmos.Lines.Line(a, b, color);
			Gizmos.Lines.Line(b, c, color);
			Gizmos.Lines.Line(c, d, color);
			Gizmos.Lines.Line(d, a, color);
		}
		void Plus(int32 x, int32 z, Color color)
		{
			let center = Vector3((x + 0.5f) * w, height, (z + 0.5f) * w);
			let arm = w * 0.12f;
			Gizmos.Lines.Line(toWorld.TransformPoint(center - Vector3(arm, 0, 0)), toWorld.TransformPoint(center + Vector3(arm, 0, 0)), color);
			Gizmos.Lines.Line(toWorld.TransformPoint(center - Vector3(0, 0, arm)), toWorld.TransformPoint(center + Vector3(0, 0, arm)), color);
		}

		// Where the mouse is on the grid.
		bool hovering = false;
		int32 hx = 0, hz = 0;
		let toLocal = terrain.Transform.WorldToLocal;
		let o = toLocal.TransformPoint(ray.origin);
		let dir = toLocal.TransformDirection(ray.direction);
		if (Math.Abs(dir.y) > 0.0001f)
		{
			let t = (terrain.flatHeight - o.y) / dir.y;
			if (t > 0)
			{
				let p = o + dir * t;
				hx = (int32)Math.Floor(p.x / w);
				hz = (int32)Math.Floor(p.z / w);
				hovering = true;
			}
		}

		List<TerrainTile> tiles = scope .();
		terrain.GetTiles(tiles);
		HashSet<int64> taken = scope .();
		for (let tile in tiles)
			taken.Add(((int64)tile.x << 32) | (uint32)tile.z);
		bool Taken(int32 x, int32 z) => taken.Contains(((int64)x << 32) | (uint32)z);
		HashSet<int64> slots = scope .();
		for (let tile in tiles)
		{
			let selected = tile.id == mSelectedTile;
			let hovered = hovering && hx == tile.x && hz == tile.z;
			Square(tile.x, tile.z, 0, selected ? Color(1, 0.85f, 0.2f, 1) : (hovered ? Color(1, 1, 1, 1) : Color(0.45f, 0.8f, 0.45f, 0.9f)));
			if (selected)
				Square(tile.x, tile.z, w * 0.01f, Color(1, 0.85f, 0.2f, 1));
			for (int i < 4)
			{
				let x = tile.x + (i == 0 ? 1 : (i == 1 ? -1 : 0));
				let z = tile.z + (i == 2 ? 1 : (i == 3 ? -1 : 0));
				if (!Taken(x, z) && slots.Add(((int64)x << 32) | (uint32)z))
					Plus(x, z, hovering && hx == x && hz == z ? Color(1, 1, 1, 1) : Color(0.6f, 0.75f, 1, 0.8f));
			}
		}
		if (tiles.Count == 0)
		{
			slots.Add(0);
			Plus(0, 0, Color(0.6f, 0.75f, 1, 0.8f));
		}
		if (!hovering)
			return;
		let slot = ((int64)hx << 32) | (uint32)hz;
		let free = !Taken(hx, hz);
		if (free && !slots.Contains(slot))
			Square(hx, hz, w * 0.02f, Color(0.6f, 0.75f, 1, ImGui.IsKeyDown(ImGui.Key.LeftCtrl) || ImGui.IsKeyDown(ImGui.Key.LeftShift) ? 0.8f : 0.25f));
		if (!ImGui.IsMouseClicked(0))
			return;
		if (!free)
		{
			mSelectedTile = terrain.TileAt(hx, hz);
			return;
		}
		if (ImGui.IsKeyDown(ImGui.Key.LeftShift) && mSelectedTile != 0)
		{
			if (terrain.MoveTile(mSelectedTile, hx, hz))
				MarkDirty();
		}
		else if (slots.Contains(slot) || ImGui.IsKeyDown(ImGui.Key.LeftCtrl))
		{
			let id = terrain.AddTile(hx, hz);
			if (id != 0)
			{
				mSelectedTile = id;
				MarkDirty();
			}
		}
	}

	void DrawVoxelObjectTools(VoxelObject voxels)
	{
		ImGui.Spacing();
		ImGui.SeparatorText("Carving");
		if (ToolButton("Carve in Scene", mBrushTool == 1, 140))
			mBrushTool = mBrushTool == 1 ? -1 : 1;
		ImGui.SameLine();
		if (ImGui.Button("Reset Shape"))
		{
			voxels.ResetShape();
			MarkDirty();
		}
		ImGui.SetNextItemWidth(-1);
		ImGui.SliderFloat("##carvesize", ref mBrushSize, 0.1f, 10, "Brush %.2f");
		ImGui.TextWrapped("At runtime call Carve(point, radius) from a script; loose pieces break off and fall.");
	}

	/// Runs the active brush under the mouse. Returns true when the brush is in control of the mouse.
	bool UpdateBrush(GameObject selected, ImGui.Vec2 origin, ImGui.Vec2 size)
	{
		if (mBrushTool < 0 || selected == null)
		{
			EndBrushStroke();
			return false;
		}
		let terrain = selected.GetComponent<VoxelTerrain>();
		let voxels = selected.GetComponent<VoxelObject>();
		if (terrain == null && voxels == null)
		{
			EndBrushStroke();
			return false;
		}
		if (!mSceneHovered || mFlying)
		{
			EndBrushStroke();
			return true;
		}
		let mouse = ImGui.GetMousePos();
		let ray = mSceneCamera.ViewportPointToRay((mouse.x - origin.x) / size.x, (mouse.y - origin.y) / size.y);
		let down = ImGui.IsMouseDown(0);
		let color = Color(1.0f, 0.85f, 0.2f, 1);

		if (terrain != null && mBrushTool == cTilesTool)
		{
			EndBrushStroke();
			UpdateTileTool(terrain, ray);
			return true;
		}
		if (terrain != null)
		{
			Vector3 point;
			if (!terrain.Raycast(ray, 800, out point))
			{
				if (!down)
					EndBrushStroke();
				return true;
			}
			Gizmos.Lines.Circle(point, .Up, mBrushSize, color, 48);
			Gizmos.Lines.Line(point, point + Vector3(0, mBrushSize * 0.5f, 0), color);
			if (down)
			{
				var mode = (VoxelBrush)mBrushTool;
				if (ImGui.IsKeyDown(ImGui.Key.LeftShift))
				{
					if (mode == .Raise) mode = .Lower;
					else if (mode == .Lower) mode = .Raise;
				}
				if (!mBrushStroke && mode == .Flatten)
					mFlattenHeight = point.y;
				if (!mBrushStroke && mPlay == .Edit)
				{
					// A whole stroke, mouse down to up, is one undo step.
					terrain.BeginEditRecord();
					mStrokeTerrain = terrain.GameObject.Id;
				}
				mBrushStroke = true;
				let amount = mode == .Paint ? 1.0f : mBrushStrength * Math.Min(Time.UnscaledDeltaTime, 0.05f) * 6.0f;
				terrain.Brush(point, mBrushSize, amount, mode, mPaintLayer, mFlattenHeight);
				MarkDirty();
			}
			else
				EndBrushStroke();
			return true;
		}

		// Destructible object: find the hit on its current mesh.
		let renderer = selected.GetComponent<MeshRenderer>();
		let mesh = renderer != null ? renderer.ActiveMesh : null;
		if (mesh == null)
			return true;
		let toLocal = selected.Transform.WorldToLocal;
		let localOrigin = toLocal.TransformPoint(ray.origin);
		let localRay = Ray(localOrigin, (toLocal.TransformPoint(ray.origin + ray.direction) - localOrigin).Normalized);
		let t = mesh.Raycast(localRay);
		if (t < 0)
			return true;
		let hit = selected.Transform.TransformPoint(localRay.GetPoint(t));
		let radius = Math.Min(mBrushSize, 10.0f) * 0.25f;
		Gizmos.Lines.Sphere(hit, radius, color);
		if (down && voxels.Carve(hit, radius))
			MarkDirty();
		return true;
	}
}
