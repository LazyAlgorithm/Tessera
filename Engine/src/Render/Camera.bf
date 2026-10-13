using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Renders the scene from its Transform. The first enabled camera drives the Game view.
///
/// First-person games: objects on the Viewmodel Layer (the player's own arms and weapon, children of the camera) are
/// drawn in a pass of their own after the world, with their own field of view and a near clip close to the eye, over
/// whatever is in front of the camera, so a gun never pokes into a wall it is held against and keeps its shape however
/// wide the world's field of view is set. See docs/viewmodel.md.
[Component]
class Camera : Component
{
	[Range(10, 120)]
	public float fieldOfView = 60.0f;
	public float nearClip = 0.1f;
	public float farClip = 1000.0f;
	public bool orthographic = false;
	public float orthographicSize = 5.0f;

	/// The layer (Project Settings) whose objects are drawn as the viewmodel: after the world, over it. None: no
	/// viewmodel pass, and every layer is drawn with the world as usual.
	[Layer]
	public int32 viewmodelLayer = -1;
	/// The viewmodel's own field of view, so the arms and weapon look the same at any world field of view.
	[Range(10, 120)]
	public float viewmodelFieldOfView = 55.0f;
	/// How close to the eye the viewmodel may come before it is cut off.
	public float viewmodelNearClip = 0.01f;
	/// Whether the viewmodel casts shadows onto the world (usually not: a shadow of a gun held up to the eye looks
	/// wrong from the outside, and other players see a full body anyway). It always receives the world's shadows.
	public bool viewmodelCastsShadows = false;

	public override void OnRegister() => Scene.Cameras.Add(this);
	public override void OnUnregister() => Scene.Cameras.Remove(this);

	public Matrix4 ViewMatrix
	{
		get
		{
			let t = Transform;
			let position = t.Position;
			let rotation = t.Rotation;
			return Matrix4.LookAt(position, position + rotation * Vector3.Forward, rotation * Vector3.Up);
		}
	}

	public Matrix4 GetProjection(float aspect)
	{
		if (orthographic)
		{
			let h = orthographicSize;
			let w = h * aspect;
			return Matrix4.Ortho(-w, w, -h, h, nearClip, farClip, Gfx.HomogeneousDepth);
		}
		return Matrix4.Perspective(fieldOfView, aspect, nearClip, farClip, Gfx.HomogeneousDepth);
	}

	public CameraData GetCameraData(float aspect)
	{
		CameraData data;
		data.view = ViewMatrix;
		data.projection = GetProjection(aspect);
		data.position = Transform.Position;
		data.forward = Transform.Forward;
		data.near = nearClip;
		data.far = farClip;
		data.fieldOfView = fieldOfView;
		data.aspect = aspect;
		data.orthographic = orthographic;
		data.orthographicSize = orthographicSize;
		data.hasViewmodel = viewmodelLayer >= 0 && !orthographic;
		data.viewmodelLayer = viewmodelLayer;
		data.viewmodelCastsShadows = viewmodelCastsShadows;
		data.viewmodelProjection = Matrix4.Perspective(viewmodelFieldOfView, aspect, Math.Max(viewmodelNearClip, 0.001f), 50.0f, Gfx.HomogeneousDepth);
		return data;
	}

	public override void OnDrawGizmos(bool selected)
	{
		if (!selected)
			return;
		let data = GetCameraData(16.0f / 9.0f);
		var shortened = data;
		shortened.far = Math.Min(farClip, 8.0f);
		shortened.projection = orthographic ? data.projection : Matrix4.Perspective(fieldOfView, data.aspect, nearClip, shortened.far, Gfx.HomogeneousDepth);
		Gizmos.Lines.Frustum((shortened.projection * shortened.view).Inverse, .(0.9f, 0.9f, 0.9f, 1));
		// The viewmodel's own view, out to an arm's length, in amber: what is on the viewmodel layer and inside it
		// is what the player sees of their arms and weapon.
		if (viewmodelLayer >= 0 && !orthographic)
		{
			let reach = Matrix4.Perspective(viewmodelFieldOfView, data.aspect, Math.Max(viewmodelNearClip, 0.001f), 1.0f, Gfx.HomogeneousDepth);
			Gizmos.Lines.Frustum((reach * data.view).Inverse, .(1, 0.7f, 0.2f, 1));
		}
	}
}

/// Everything the renderer needs to know about a viewpoint.
struct CameraData
{
	public Matrix4 view;
	public Matrix4 projection;
	public Vector3 position;
	public Vector3 forward;
	public float near;
	public float far;
	public float fieldOfView;
	public float aspect;
	public bool orthographic;
	public float orthographicSize;
	/// A viewmodel pass (Camera.viewmodelLayer): objects on viewmodelLayer are drawn after the world with their own
	/// projection, over it. False (the default, as for the editor's own camera) draws every layer with the world.
	public bool hasViewmodel;
	public int32 viewmodelLayer;
	public bool viewmodelCastsShadows;
	public Matrix4 viewmodelProjection;

	/// Ray through a viewport point given in 0..1 coordinates, origin at the top left.
	public Ray ViewportPointToRay(float u, float v)
	{
		let invViewProj = (projection * view).Inverse;
		let x = u * 2.0f - 1.0f;
		let y = 1.0f - v * 2.0f;
		let nearPoint = invViewProj.Project(.(x, y, Gfx.HomogeneousDepth ? -1.0f : 0.0f));
		let farPoint = invViewProj.Project(.(x, y, 1.0f));
		return .(nearPoint, (farPoint - nearPoint).Normalized);
	}
}
