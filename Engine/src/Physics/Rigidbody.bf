using System;
using System.Collections;

namespace Tessera;

/// Makes the object a simulated body. Needs a Collider on the same GameObject.
[Component]
class Rigidbody : Component
{
	public float mass = 1.0f;
	public bool useGravity = true;
	public bool isKinematic = false;
	[Range(0, 2)]
	public float friction = 0.5f;
	[Range(0, 1)]
	public float bounciness = 0.0f;
	public float linearDamping = 0.05f;
	public float angularDamping = 0.05f;
	public bool freezeRotation = false;
	public bool continuousCollision = false;
	public bool allowSleeping = true;
	/// Debris rests on scenery and is drawn like anything else, but nothing that moves is stopped by it: characters
	/// and other bodies pass through, and rays and shape queries ignore it. For corpses, dropped items, rubble.
	public bool debris = false;

	uint32 mBody = uint32.MaxValue;

	public uint32 BodyId => mBody;
	public bool HasBody => mBody != uint32.MaxValue;

	bool mReady;

	public override void Start()
	{
		mReady = true;
		CreateBody();
	}

	public override void OnEnable()
	{
		if (mReady)
			CreateBody();
	}

	/// Creates the body now if it does not exist yet (normally this happens in Start).
	public void EnsureBody()
	{
		mReady = true;
		CreateBody();
	}

	void CreateBody()
	{
		if (mBody != uint32.MaxValue)
			return;
		let collider = GetComponent<Collider>();
		if (collider == null)
		{
			Log.Warning(scope $"Rigidbody on '{GameObject.Name}' has no Collider and will not simulate.");
			return;
		}
		mBody = Scene.Physics.CreateBody(Transform, collider.GetShape(), this);
	}

	public override void OnDestroy()
	{
		mReady = false;
	}

	/// Recreates the body after its collider changed size, keeping position and velocity.
	public void RebuildBody()
	{
		if (!HasBody)
		{
			if (mReady)
				CreateBody();
			return;
		}
		let state = State;
		OnDisable();
		CreateBody();
		if (HasBody)
			SetState(state);
	}

	public override void OnDisable()
	{
		if (mBody != uint32.MaxValue)
		{
			Scene.Physics.DestroyBody(mBody);
			mBody = uint32.MaxValue;
		}
	}

	public Vector3 Velocity
	{
		get => Scene.Physics.GetLinearVelocity(mBody);
		set { Scene.Physics.SetLinearVelocity(mBody, value); }
	}

	public Vector3 AngularVelocity
	{
		get => Scene.Physics.GetAngularVelocity(mBody);
		set { Scene.Physics.SetAngularVelocity(mBody, value); }
	}

	public void AddForce(Vector3 force) => Scene.Physics.AddForce(mBody, force);
	public void AddForceAtPosition(Vector3 force, Vector3 worldPoint) => Scene.Physics.AddForceAtPosition(mBody, force, worldPoint);
	public Vector3 GetPointVelocity(Vector3 worldPoint) => Scene.Physics.GetPointVelocity(mBody, worldPoint);
	public void AddImpulse(Vector3 impulse) => Scene.Physics.AddImpulse(mBody, impulse);
	/// Sleep until disturbed by physics; the body stays dynamic and collision-enabled.
	public void Sleep() => Scene.Physics.Sleep(mBody);
	public bool IsSleeping => HasBody && Scene.Physics.IsSleeping(mBody);
	public BodyState State => Scene.Physics.GetState(mBody);
	public void SetState(BodyState state) => Scene.Physics.SetState(mBody, state);
}
