using System;
using System.Collections;
using System.IO;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// The Scene tab: camera, picking, gizmos.
extension EditorApp
{
	void DrawSceneView()
	{
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(0, 0));
		let open = ImGui.Begin("Scene", null, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse);
		ImGui.PopStyleVar();
		let sceneDock = ImGui.GetWindowDockID();
		if (sceneDock != 0)
			mAssetCenterDock = sceneDock;
		mSceneHovered = false;
		if (open)
		{
			let size = ImGui.GetContentRegionAvail();
			let origin = ImGui.GetCursorScreenPos();
			if (size.x > 8 && size.y > 8)
			{
				mSceneSize = size;
				UpdateSceneCamera(size.x / size.y);
				if (mSceneView.Width > 0)
					ImGui.Image(mSceneView.OutputTexture, .(mSceneView.Width, mSceneView.Height));
				mSceneHovered = ImGui.IsItemHovered();
				if (ImGui.BeginDragDropTarget())
				{
					let asset = ImGui.AcceptDragDropPayload("ASSET");
					if (asset != null)
					{
						let mouse = ImGui.GetMousePos();
						DropAssetIntoScene(StringView((char8*)asset.data, asset.dataSize), true, (mouse.x - origin.x) / size.x, (mouse.y - origin.y) / size.y);
					}
					ImGui.EndDragDropTarget();
				}
				HandleSceneCameraInput();

				let selected = Selected;
				// An active sculpting or placing tool owns the mouse instead of selection and the transform gizmo.
				bool gizmoActive = UpdateBrush(selected, origin, size) || UpdatePlacement(origin, size);
				if (selected != null && !gizmoActive && !selected.IsFolder)
				{
					ImGui.tn_gizmo_begin(origin.x, origin.y, size.x, size.y, false);
					var world = selected.Transform.LocalToWorld;
					var view = mSceneCamera.view;
					var projection = mSceneCamera.projection;
					float[3] snap = .(mSnapMove, mSnapMove, mSnapMove);
					if (mGizmoOperation == 1)
						snap = .(mSnapRotate, mSnapRotate, mSnapRotate);
					else if (mGizmoOperation == 2)
						snap = .(mSnapScale, mSnapScale, mSnapScale);
					let snapping = SnapActive;
					if (ImGui.tn_gizmo_manipulate(&view.m, &projection.m, mGizmoOperation, mGizmoLocal, &world.m, snapping ? &snap : null))
					{
						let parent = selected.Transform.Parent;
						let local = parent != null ? parent.WorldToLocal * world : world;
						Vector3 t, s;
						Quaternion q;
						local.Decompose(out t, out q, out s);
						selected.Transform.LocalPosition = t;
						selected.Transform.LocalRotation = q;
						selected.Transform.LocalScale = s;
						MarkDirty();
					}
					gizmoActive = ImGui.tn_gizmo_is_using() || ImGui.tn_gizmo_is_over();
				}

				if (mSceneHovered && ImGui.IsMouseClicked(0) && !gizmoActive && !mFlying)
				{
					let mouse = ImGui.GetMousePos();
					Pick((mouse.x - origin.x) / size.x, (mouse.y - origin.y) / size.y);
				}

				UpdateQuickAdd(origin, size);
				DrawSceneOverlays(origin, size);
				let stats = scope String();
				stats.AppendF("{} draws  {} instances  {}k tris", mSceneView.DrawCalls, mSceneView.Instances, mSceneView.Triangles / 1000);
				ImGui.DrawText(.(origin.x + 10, origin.y + 8), .(1, 1, 1, 0.65f), stats.CStr());
				if (mFlying)
					ImGui.DrawText(.(origin.x + 10, origin.y + size.y - 24), .(1, 1, 1, 0.65f), scope $"WASD move, Q/E down/up, Shift faster, wheel sets speed ({mCamSpeed:0.0} m/s)" .CStr());
			}
		}
		ImGui.End();
	}

	void UpdateSceneCamera(float aspect)
	{
		let rotation = Quaternion.Euler(mCamPitch, mCamYaw, 0);
		let forward = rotation * Vector3.Forward;
		mSceneCamera.position = mCamPosition;
		mSceneCamera.forward = forward;
		mSceneCamera.near = 0.1f;
		mSceneCamera.far = 2000.0f;
		mSceneCamera.fieldOfView = 60;
		mSceneCamera.aspect = aspect;
		mSceneCamera.orthographic = false;
		mSceneCamera.orthographicSize = 5;
		mSceneCamera.view = Matrix4.LookAt(mCamPosition, mCamPosition + forward, rotation * Vector3.Up);
		mSceneCamera.projection = Matrix4.Perspective(60, aspect, 0.1f, 2000.0f, Gfx.HomogeneousDepth);
	}

	void HandleSceneCameraInput()
	{
		// Right mouse: fly. Middle mouse: pan. Wheel: dolly.
		if (mSceneHovered && ImGui.IsMouseClicked(1))
			mFlying = true;
		if (!ImGui.IsMouseDown(1))
			mFlying = false;
		let rotation = Quaternion.Euler(mCamPitch, mCamYaw, 0);
		let forward = rotation * Vector3.Forward;
		let right = rotation * Vector3.Right;
		let up = rotation * Vector3.Up;
		if (mFlying)
		{
			let delta = Input.MouseDelta;
			mCamYaw += delta.x * 0.18f;
			mCamPitch = Mathf.Clamp(mCamPitch + delta.y * 0.18f, -89, 89);
			// The wheel sets the flying speed, as in Unity.
			let flyWheel = Input.MouseWheel;
			if (flyWheel != 0)
				mCamSpeed = Math.Clamp(mCamSpeed * Math.Pow(1.2f, flyWheel), 0.25f, 400);
			var speed = mCamSpeed * Time.UnscaledDeltaTime;
			if (Input.GetKey(.LeftShift))
				speed *= 4;
			if (Input.GetKey(.W))
				mCamPosition = mCamPosition + forward * speed;
			if (Input.GetKey(.S))
				mCamPosition = mCamPosition - forward * speed;
			if (Input.GetKey(.D))
				mCamPosition = mCamPosition + right * speed;
			if (Input.GetKey(.A))
				mCamPosition = mCamPosition - right * speed;
			if (Input.GetKey(.E))
				mCamPosition = mCamPosition + Vector3.Up * speed;
			if (Input.GetKey(.Q))
				mCamPosition = mCamPosition - Vector3.Up * speed;
		}
		else if (mSceneHovered)
		{
			if (ImGui.IsMouseDown(2))
			{
				let delta = Input.MouseDelta;
				let pan = 0.02f * Math.Clamp(mCamSpeed / 12, 0.1f, 10);
				mCamPosition = mCamPosition - right * (delta.x * pan) + up * (delta.y * pan);
			}
			let wheel = Input.MouseWheel;
			if (wheel != 0)
				mCamPosition = mCamPosition + forward * (wheel * 1.5f * Math.Clamp(mCamSpeed / 12, 0.05f, 10));
		}
	}

	void Pick(float u, float v)
	{
		let ray = mSceneCamera.ViewportPointToRay(u, v);
		GameObject best = null;
		float bestDistance = float.MaxValue;
		for (let renderer in mScene.Renderers)
		{
			// Hidden by the world state shown: not clickable either.
			if (!renderer.IsActiveAndEnabled || !renderer.GameObject.InActiveWorld)
				continue;
			let mesh = renderer.ActiveMesh;
			if (mesh == null)
				continue;
			let boundsHit = renderer.WorldBounds.IntersectRay(ray);
			if (boundsHit < 0 || boundsHit > bestDistance)
				continue;
			var distance = boundsHit;
			if (mesh.Indices.Count > 0 && mesh.Indices.Count < 200000)
			{
				// Refine against the triangles in the mesh's own space.
				let toLocal = renderer.Transform.WorldToLocal;
				let localOrigin = toLocal.TransformPoint(ray.origin);
				let localEnd = toLocal.TransformPoint(ray.origin + ray.direction);
				let localRay = Ray(localOrigin, (localEnd - localOrigin).Normalized);
				let t = mesh.Raycast(localRay);
				if (t < 0)
					continue;
				let worldPoint = renderer.Transform.LocalToWorld.TransformPoint(localRay.GetPoint(t));
				distance = (worldPoint - ray.origin).Length;
			}
			if (distance < bestDistance)
			{
				bestDistance = distance;
				best = renderer.GameObject;
			}
		}
		// Generated children (voxel chunks) select the object that owns them.
		while (best != null && best.Transient && best.Transform.Parent != null)
			best = best.Transform.Parent.GameObject;
		mSelectedId = best != null ? best.Id : 0;
	}

	void BuildGizmos()
	{
		if (mShowGrid)
			Gizmos.Lines.Grid(mCamPosition, 60, 1.0f, .(1, 1, 1, 0.07f), .(1, 1, 1, 0.18f));
		let selected = Selected;
		for (let component in mScene.Components)
		{
			if (component.IsActiveAndEnabled)
				component.OnDrawGizmos(component.GameObject == selected);
		}
		if (selected != null)
		{
			let renderer = selected.GetComponent<MeshRenderer>();
			if (renderer != null && renderer.ActiveMesh != null)
				Gizmos.Lines.Box(renderer.ActiveMesh.Bounds, selected.Transform.LocalToWorld, .(1.0f, 0.62f, 0.15f, 1));
		}
		BuildMapBuilderGizmos();
	}
}
