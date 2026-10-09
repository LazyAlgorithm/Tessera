using System;
using System.Collections;

namespace Tessera;

/// Position, rotation and scale of a GameObject, arranged in a parent/child hierarchy.
class Transform
{
	GameObject mGameObject;
	Transform mParent;
	Vector3 mLocalPosition = .Zero;
	Quaternion mLocalRotation = .Identity;
	Vector3 mLocalScale = .One;
	Matrix4 mWorld = .Identity;
	bool mDirty = true;

	public List<Transform> Children = new .() ~ delete _;
	/// Incremented whenever the world transform may have changed.
	public uint32 Version;

	public this(GameObject gameObject)
	{
		mGameObject = gameObject;
	}

	public GameObject GameObject => mGameObject;
	public Transform Parent => mParent;

	public Vector3 LocalPosition
	{
		get => mLocalPosition;
		set { mLocalPosition = value; MarkDirty(); }
	}

	public Quaternion LocalRotation
	{
		get => mLocalRotation;
		set { mLocalRotation = value; MarkDirty(); }
	}

	public Vector3 LocalScale
	{
		get => mLocalScale;
		set { mLocalScale = value; MarkDirty(); }
	}

	public Vector3 LocalEulerAngles
	{
		get => mLocalRotation.EulerAngles;
		set { mLocalRotation = Quaternion.Euler(value); MarkDirty(); }
	}

	public Matrix4 LocalMatrix => Matrix4.TRS(mLocalPosition, mLocalRotation, mLocalScale);

	public Matrix4 LocalToWorld
	{
		get
		{
			if (mDirty)
			{
				mWorld = mParent != null ? mParent.LocalToWorld * LocalMatrix : LocalMatrix;
				mDirty = false;
			}
			return mWorld;
		}
	}

	public Matrix4 WorldToLocal => LocalToWorld.Inverse;

	public Vector3 Position
	{
		get => LocalToWorld.Translation;
		set
		{
			if (mParent != null)
				mLocalPosition = mParent.WorldToLocal.TransformPoint(value);
			else
				mLocalPosition = value;
			MarkDirty();
		}
	}

	public Quaternion Rotation
	{
		get => mParent != null ? (mParent.Rotation * mLocalRotation).Normalized : mLocalRotation;
		set
		{
			if (mParent != null)
				mLocalRotation = (mParent.Rotation.Conjugate * value).Normalized;
			else
				mLocalRotation = value;
			MarkDirty();
		}
	}

	public Vector3 EulerAngles
	{
		get => Rotation.EulerAngles;
		set { Rotation = Quaternion.Euler(value); }
	}

	public Vector3 Forward => Rotation * Vector3.Forward;
	public Vector3 Right => Rotation * Vector3.Right;
	public Vector3 Up => Rotation * Vector3.Up;

	public void SetPositionAndRotation(Vector3 position, Quaternion rotation)
	{
		Position = position;
		Rotation = rotation;
	}

	public void Translate(Vector3 delta)
	{
		Position = Position + delta;
	}

	/// Rotates by euler angles in degrees, in local space.
	public void Rotate(Vector3 eulerDegrees)
	{
		mLocalRotation = (mLocalRotation * Quaternion.Euler(eulerDegrees)).Normalized;
		MarkDirty();
	}

	public void LookAt(Vector3 target)
	{
		let direction = target - Position;
		if (direction.LengthSquared > 1.0e-10f)
			Rotation = Quaternion.LookRotation(direction, Vector3.Up);
	}

	public Vector3 TransformPoint(Vector3 local) => LocalToWorld.TransformPoint(local);
	public Vector3 InverseTransformPoint(Vector3 world) => WorldToLocal.TransformPoint(world);

	public bool IsChildOf(Transform other)
	{
		var t = this;
		while (t != null)
		{
			if (t == other)
				return true;
			t = t.mParent;
		}
		return false;
	}

	/// Re-parents this transform. Pass null to move it to the scene root.
	public void SetParent(Transform parent, bool keepWorldPose = true)
	{
		if (parent == mParent || (parent != null && parent.IsChildOf(this)))
			return;
		let world = LocalToWorld;
		if (mParent != null)
			mParent.Children.Remove(this);
		else
			mGameObject.Scene?.[Friend]mRoots.Remove(mGameObject);
		mParent = parent;
		if (mParent != null)
			mParent.Children.Add(this);
		else
			mGameObject.Scene?.[Friend]mRoots.Add(mGameObject);
		if (keepWorldPose)
		{
			let local = mParent != null ? mParent.WorldToLocal * world : world;
			local.Decompose(out mLocalPosition, out mLocalRotation, out mLocalScale);
		}
		MarkDirty();
	}

	void MarkDirty()
	{
		Version++;
		if (mDirty)
		{
			// Children may still hold a clean matrix when only the version changed.
			for (let child in Children)
				child.MarkDirty();
			return;
		}
		mDirty = true;
		for (let child in Children)
			child.MarkDirty();
	}
}
