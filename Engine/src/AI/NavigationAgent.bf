using System;
using System.Collections;
namespace Tessera;

[Component]
class NavigationAgent : AIMovementDriver
{
    public NavigationSurface surface;
    bool mFoundSurface;
    public float snapDistance=2;
    public Vector3 baseOffset; // Offset from object origin to agent feet (walking) or center (flying).
    /// Shortest time between two path searches. A search runs only when the destination or the navigation data changed,
    /// or the agent was pushed off its path.
    public float repathInterval=0.3f;
    public bool faceMovement=true;
    /// Degrees per second when turning to face movement; 0 turns instantly.
    public float turnSpeed=720;
    List<Vector3> mPath=new .() ~ delete _;
    Vector3 mDestination;
    float mSpeed,mStop,mTimer,mRetry,mDeviation;
    int32 mWaypoint,mRevision=-1;
    bool mRequested,mFailed,mDirty,mDriving;
    public override bool PathFailed=>mFailed;
    public override bool HasArrived=>mRequested && !mFailed && mPath.Count>0 && mWaypoint>=mPath.Count;
    public List<Vector3> Path=>mPath;
    bool Flying=>surface?.Data!=null && surface.Data.flying;
    Vector3 Feet=>Transform.Position+baseOffset;
    /// Walking compares positions on the ground plane, so a pivot that floats above or sinks below the baked floor still arrives.
    float Distance(Vector3 a,Vector3 b) { var d=a-b;if(!Flying) d.y=0;return d.Length; }
    float SegmentDistance(Vector3 point,Vector3 a,Vector3 b)
    {
        var ab=b-a;var ap=point-a;if(!Flying) {ab.y=0;ap.y=0;}
        let length=ab.LengthSquared;let t=length>0.000001f ? Mathf.Clamp((ap.x*ab.x+ap.y*ab.y+ap.z*ab.z)/length,0,1) : 0;
        return (ap-ab*t).Length;
    }
    public override void SetDestination(Vector3 point,float speed,float stoppingDistance)
    {
        if(NetworkSync.IsClientOf(Scene)) return;
        mSpeed=Math.Max(speed,0);mStop=Math.Max(stoppingDistance,0.05f);
        // With no surface set, the one in the scene's world state (looked for again when the world state changes).
        if(surface==null || (mFoundSurface && !surface.GameObject.InActiveWorld))
        {
            for(let component in Scene.Components) if(let candidate=component as NavigationSurface) if(candidate.IsActiveAndEnabled && candidate.GameObject.InActiveWorld) {if(candidate!=surface) mDirty=true;surface=candidate;mFoundSurface=true;break;}
        }
        if(!mRequested || (point-mDestination).LengthSquared>0.01f) mDirty=true;
        mDestination=point;mRequested=true;
        if(mDirty && (mTimer<=0 || mPath.Count==0)) Repath();
    }
    void Repath()
    {
        mTimer=Math.Max(repathInterval,0.01f);mWaypoint=0;mDirty=false;mRetry=Math.Max(repathInterval,1);
        let data=surface?.Data;
        mFailed=data==null || !data.FindPath(Feet,mDestination+baseOffset,mPath,snapDistance);
        if(data!=null) mRevision=data.Revision;
        if(mFailed) {mPath.Clear();return;}
        // Cells in a straight line become one leg, so the agent does not slow for a waypoint in every cell.
        int kept=1;
        for(int i=1;i<mPath.Count;i++)
        {
            if(i<mPath.Count-1)
            {
                let a=(mPath[i]-mPath[kept-1]).Normalized;let b=(mPath[i+1]-mPath[i]).Normalized;
                if(a.x*b.x+a.y*b.y+a.z*b.z>0.9999f) continue;
            }
            mPath[kept++]=mPath[i];
        }
        if(kept<mPath.Count) mPath.RemoveRange(kept,mPath.Count-kept);
        if(mPath.Count>1) mWaypoint=1;
        // The agent may start up to the snap distance away from the first cell; that much is not being off the path.
        mDeviation=Math.Max(data.cellSize*1.5f,(mWaypoint==1 ? SegmentDistance(Feet,mPath[0],mPath[1]) : 0)+data.cellSize*0.5f);
    }
    public override void StopMovement()
    {
        mRequested=false;mDirty=false;mPath.Clear();mWaypoint=0;Halt();
    }
    /// Stops the velocity this agent was applying. An agent that is not steering leaves its body alone.
    void Halt()
    {
        if(!mDriving) return;mDriving=false;
        let body=GetComponent<Rigidbody>();
        if(body!=null && body.HasBody && !body.isKinematic)
        {
            var velocity=body.Velocity;velocity.x=0;velocity.z=0;
            if(Flying) velocity.y=0;
            body.Velocity=velocity;
        }
    }
    Vector3 Desired(float dt)
    {
        if(!mRequested || mFailed || mWaypoint>=mPath.Count || surface?.Data==null) return .Zero;
        let position=Feet;
        while(mWaypoint<mPath.Count && Distance(mPath[mWaypoint],position)<=(mWaypoint==mPath.Count-1 ? mStop : Math.Min(0.1f,surface.Data.cellSize*0.2f))) mWaypoint++;
        if(mWaypoint>=mPath.Count) return .Zero;
        var delta=mPath[mWaypoint]-position;
        let body=GetComponent<Rigidbody>();
        // Gravity or the character controller keeps these on the floor, so they are only steered sideways.
        if(((body!=null && !body.isKinematic) || GetComponent<CharacterController>()!=null) && !surface.Data.flying) delta.y=0;
        if(faceMovement && delta.x*delta.x+delta.z*delta.z>0.00001f)
        {
            var yaw=Math.Atan2(delta.x,delta.z)*Mathf.Rad2Deg;
            if(turnSpeed>0)
            {
                let forward=Transform.Forward;let current=Math.Atan2(forward.x,forward.z)*Mathf.Rad2Deg;
                var turn=yaw-current;while(turn>180) turn-=360;while(turn<-180) turn+=360;
                yaw=current+Mathf.Clamp(turn,-turnSpeed*dt,turnSpeed*dt);
            }
            Transform.Rotation=Quaternion.Euler(0,yaw,0);
        }
        if(delta.LengthSquared<0.00000001f) return .Zero;
        return delta.Normalized*Math.Min(mSpeed,delta.Length/Math.Max(dt,0.001f));
    }
    public override void Update()
    {
        // In multiplayer the server moves agents; a client's copy follows what the server sends.
        if(NetworkSync.IsClientOf(Scene)) return;
        mTimer-=Time.DeltaTime;
        if(mRequested)
        {
            let data=surface?.Data;
            if(data!=null && data.Revision!=mRevision) mDirty=true;
            // A failed search is retried slowly in case the agent has since moved somewhere routable.
            if(mFailed) {mRetry-=Time.DeltaTime;if(mRetry<=0) mDirty=true;}
            else if(mWaypoint>0 && mWaypoint<mPath.Count && SegmentDistance(Feet,mPath[mWaypoint-1],mPath[mWaypoint])>mDeviation) mDirty=true;
            if(mDirty && mTimer<=0) Repath();
        }
        let body=GetComponent<Rigidbody>();
        if(GetComponent<CharacterController>()==null && (body==null || body.isKinematic)) Transform.Position+=Desired(Time.DeltaTime)*Time.DeltaTime;
    }
    public override void FixedUpdate()
    {
        if(NetworkSync.IsClientOf(Scene)) return;
        let controller=GetComponent<CharacterController>();
        if(controller!=null)
        {
            // A character controller walks the path itself: it climbs steps, stays on slopes and keeps falling when idle.
            let wanted=Desired(Time.FixedDeltaTime);
            if(Flying) controller.Move(wanted,Time.FixedDeltaTime);
            else controller.SimpleMove(wanted,Time.FixedDeltaTime);
            return;
        }
        let body=GetComponent<Rigidbody>();if(body==null || body.isKinematic || !body.HasBody) return;
        let desired=Desired(Time.FixedDeltaTime);
        // Velocity is only written while following a path; an idle or arrived agent can be pushed, thrown or dropped.
        if(!mRequested || mFailed || mWaypoint>=mPath.Count) {Halt();return;}
        mDriving=true;var velocity=body.Velocity;velocity.x=desired.x;velocity.z=desired.z;
        if(Flying) velocity.y=desired.y;
        body.Velocity=velocity;
    }
    public override void OnDisable() {StopMovement();}
}
