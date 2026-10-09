using System;
using System.Collections;
using Tessera;
namespace ShapeQueryTests;
class Program
{
    static bool Check(bool condition, StringView name)
    {
        Console.WriteLine(scope $"{condition ? "PASS" : "FAIL"}: {name}");
        return condition;
    }
    static uint32 AddBox(Scene scene, Vector3 position, Vector3 size, out GameObject go)
    {
        go=scene.CreateGameObject("Target"); go.Transform.Position=position;
        ShapeDesc desc=default; desc.kind=.Box; desc.halfExtents=size*0.5f;
        return scene.Physics.CreateBody(go.Transform,desc,null);
    }
    public static int Main(String[] args)
    {
        Console.WriteLine("Shape query integration tests");
        bool ok=true; ShapeCastHit hit;
        let empty=scope Scene();
        ok &= Check(!empty.Physics.SphereCast(.Zero,0.5f,.Forward,10,out hit),"empty world safely misses");
        let scene=scope Scene();
        let nearId=AddBox(scene,.(0,0,5),.One,let nearGo);
        AddBox(scene,.(0,0,9),.One,let farGo);
        ok &= Check(scene.Physics.SphereCast(.Zero,0.5f,.(0,0,2),10,out hit) && hit.gameObject==nearGo && Math.Abs(hit.distance-4)<0.02f && hit.normal.z < -0.95f && Math.Abs(hit.point.z-4.5f)<0.02f,"closest sphere contact, normalized direction, point and outward normal");
        ok &= Check(scene.Physics.SphereCast(.Zero,0.5f,.Forward,10,out hit,nearId) && hit.gameObject==farGo && Math.Abs(hit.distance-8)<0.02f,"ignoring the closest body still finds the next body");
        ok &= Check(!scene.Physics.SphereCast(.Zero,0.5f,.Forward,3,out hit),"maximum distance limits sweep");
        ok &= Check(scene.Physics.CapsuleCast(.(0,-0.5f,0),.(0,0.5f,0),0.5f,.Forward,10,out hit) && Math.Abs(hit.distance-4)<0.03f,"vertical capsule sweep");
        ok &= Check(scene.Physics.CapsuleCast(.(0,0,-1),.(0,0,1),0.5f,.Forward,10,out hit) && Math.Abs(hit.distance-3)<0.03f,"horizontal capsule endpoints set orientation");
        ok &= Check(scene.Physics.CapsuleCast(.Zero,.Zero,0.5f,.Forward,10,out hit) && Math.Abs(hit.distance-4)<0.02f,"coincident capsule endpoints act as sphere");
        ok &= Check(scene.Physics.BoxCast(.Zero,.(1,1,2),.Identity,.Forward,10,out hit) && Math.Abs(hit.distance-3.5f)<0.04f,"box full dimensions");
        ok &= Check(scene.Physics.BoxCast(.Zero,.(1,1,2),Quaternion.Euler(0,90,0),.Forward,10,out hit) && Math.Abs(hit.distance-4)<0.04f,"rotated box sweep");
        ok &= Check(scene.Physics.SphereCast(.(0,0,5),0.5f,.Forward,10,out hit) && hit.distance==0 && hit.penetrationDepth>0,"starting overlap reports zero travel and penetration");
        ok &= Check(!scene.Physics.SphereCast(.Zero,-1,.Forward,10,out hit) && !scene.Physics.SphereCast(.Zero,0.5f,.Zero,10,out hit) && !scene.Physics.BoxCast(.Zero,.(1,0,1),.Identity,.Forward,10,out hit),"invalid radius, direction and size safely miss");
        List<ShapeCastHit> hits=scope .();
        ok &= Check(scene.Physics.OverlapSphere(.(0,0,5),0.75f,hits)==1 && hits[0].gameObject==nearGo,"sphere overlap returns mapped body");
        ok &= Check(scene.Physics.OverlapBox(.(0,0,5),.One,.Identity,hits,nearId)==0 && hits.Count==0,"overlap ignores body and clears results");
        ok &= Check(scene.Physics.OverlapCapsule(.(0,-0.5f,5),.(0,0.5f,5),0.5f,hits)==1,"capsule overlap");
        let many=scope Scene();
        for(int i=0;i<80;i++) AddBox(many,.(i*0.1f,0,0),.One,let go);
        ok &= Check(many.Physics.OverlapSphere(.(4,0,0),10,hits)==80 && hits.Count==80,"overlap buffer grows without truncating results");
        return ok ? 0 : 1;
    }
}
