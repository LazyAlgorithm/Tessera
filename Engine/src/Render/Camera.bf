using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Renders the scene from its Transform. The first enabled camera drives the Game view.
[Component]
class Camera : Component
{
	[Range(10, 120)]
	public float fieldOfView = 60.0f;
	public float nearClip = 0.1f;
	public float farClip = 1000.0f;
	public bool orthographic = false;
	public float orthographicSize = 5.0f;

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
