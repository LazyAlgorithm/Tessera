using System;

namespace Tessera;

/// Base API for navigation and project movement components.
[Component]
abstract class AIMovementDriver : Component
{
	public abstract void SetDestination(Vector3 point, float speed, float stoppingDistance);
	public abstract void StopMovement();
	public virtual bool PathFailed => false;
	public virtual bool HasArrived => false;
}
