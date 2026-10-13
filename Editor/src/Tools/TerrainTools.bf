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

	static readonly char8*[?] cBrushNames = .("Raise", "Lower", "Smooth", "Flatten", "Paint");
	static readonly char8*[?] cLayerNames = .("Automatic", "Grass", "Rock", "Sand", "Snow", "Dirt");

	void DrawTerrainTools(VoxelTerrain terrain)
	{
		// Tiles are independent fixed terrains. Snap new tiles to the selected tile's grid.
		if (terrain.mode == .Fixed)
		{
			ImGui.SeparatorText("Adjacent Tiles");
			if (ImGui.Button("+X")) AddAdjacentTerrain(terrain, 1, 0);
			ImGui.SameLine();
			if (ImGui.Button("-X")) AddAdjacentTerrain(terrain, -1, 0);
			ImGui.SameLine();
			if (ImGui.Button("+Z")) AddAdjacentTerrain(terrain, 0, 1);
			ImGui.SameLine();
			if (ImGui.Button("-Z")) AddAdjacentTerrain(terrain, 0, -1);
			ImGui.TextDisabled("Tiles share size, voxel scale, and materials.");
		}
		ImGui.Spacing();
		ImGui.SeparatorText("Terrain Tools");
		let width = (ImGui.GetContentRegionAvail().x - 4 * 6) / 5;
		for (int32 i < 5)
		{
			if (i > 0)
				ImGui.SameLine();
			if (ToolButton(cBrushNames[i], mBrushTool == i, width))
				mBrushTool = mBrushTool == i ? -1 : i;
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
			ImGui.TextWrapped("Drag in the Scene view to apply. Shift swaps Raise and Lower. Flatten uses the height where the stroke starts.");
		else
			ImGui.TextDisabled("Pick a tool to sculpt or paint in the Scene view.");

		let status = scope String();
		status.AppendF("{} chunks, {} pending{}", terrain.ChunkCount, terrain.PendingChunks, terrain.HasUnsavedEdits ? ", unsaved edits" : "");
		ImGui.TextDisabled(status.CStr());
		if (ImGui.Button("Regenerate"))
			terrain.Regenerate();
		ImGui.SameLine();
		ImGui.TextDisabled(terrain.editsFile.IsEmpty ? "Edits are saved with the scene" : terrain.editsFile.CStr());
	}

	/// Create a matching terrain tile on an exact shared grid edge.
	void AddAdjacentTerrain(VoxelTerrain source, int32 dx, int32 dz)
	{
		let size = source.AreaSize;
		let offset = Vector3(dx * size.x, 0, dz * size.y);
		let target = source.Transform.Position + offset;
		for (let existing in mScene.Components)
		{
			let other = existing as VoxelTerrain;
			if (other == null || other == source || other.mode != .Fixed)
				continue;
			if ((other.Transform.Position - target).Length < 0.01f)
			{
				Log.Warning("A terrain tile already occupies that location.");
				return;
			}
		}
		let tile = mScene.CreateGameObject("Terrain Tile");
		tile.Transform.Position = target;
		let terrain = tile.AddComponent<VoxelTerrain>();
		terrain.mode = .Fixed;
		terrain.sizeX = source.sizeX;
		terrain.sizeZ = source.sizeZ;
		terrain.voxelSize = source.voxelSize;
		terrain.flatHeight = source.flatHeight;
		terrain.minChunkY = source.minChunkY;
		terrain.maxChunkY = source.maxChunkY;
		terrain.style = source.style;
		terrain.grassColor = source.grassColor;
		terrain.rockColor = source.rockColor;
		terrain.sandColor = source.sandColor;
		terrain.snowColor = source.snowColor;
		terrain.dirtColor = source.dirtColor;
		mSelectedId = tile.Id;
		MarkDirty();
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
			mBrushStroke = false;
			return false;
		}
		let terrain = selected.GetComponent<VoxelTerrain>();
		let voxels = selected.GetComponent<VoxelObject>();
		if (terrain == null && voxels == null)
			return false;
		if (!mSceneHovered || mFlying)
		{
			mBrushStroke = false;
			return true;
		}
		let mouse = ImGui.GetMousePos();
		let ray = mSceneCamera.ViewportPointToRay((mouse.x - origin.x) / size.x, (mouse.y - origin.y) / size.y);
		let down = ImGui.IsMouseDown(0);
		let color = Color(1.0f, 0.85f, 0.2f, 1);

		if (terrain != null)
		{
			Vector3 point;
			if (!terrain.Raycast(ray, 800, out point))
			{
				mBrushStroke = false;
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
				mBrushStroke = true;
				let amount = mode == .Paint ? 1.0f : mBrushStrength * Math.Min(Time.UnscaledDeltaTime, 0.05f) * 6.0f;
				terrain.Brush(point, mBrushSize, amount, mode, mPaintLayer, mFlattenHeight);
				// A brush crossing a shared edge also edits the adjacent tile.
				for (let component in mScene.Components)
				{
					let neighbor = component as VoxelTerrain;
					if (neighbor == null || neighbor == terrain || neighbor.mode != .Fixed)
						continue;
					let local = neighbor.Transform.InverseTransformPoint(point);
					let area = neighbor.AreaSize;
					if (local.x >= -mBrushSize && local.z >= -mBrushSize && local.x <= area.x + mBrushSize && local.z <= area.y + mBrushSize)
						neighbor.Brush(point, mBrushSize, amount, mode, mPaintLayer, mFlattenHeight);
				}
				MarkDirty();
			}
			else
				mBrushStroke = false;
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
