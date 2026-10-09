using System;
using System.Collections;
namespace Tessera;

[Component]
class NavigationSurface : Component
{
    public String bakedData=new .() ~ delete _;
    public Vector3 size=.(32,10,32);
    public float cellSize=1,agentRadius=0.3f,agentHeight=1.8f,maxStep=0.5f,maxSlope=45;
    public int32 chunkSize=16;
    public bool flying,includeRenderMeshes=true,rebuildOnStart;
    public bool drawNavigation=true;
    NavigationData mData ~ delete _;
    public NavigationData Data=>mData;
    public override void Awake() { if(!bakedData.IsEmpty) LoadData(); }
    public override void Start() { if(rebuildOnStart) Bake(); }
    public bool LoadData()
    {
        let path=scope String();Assets.ResolvePath(bakedData,path);let candidate=new NavigationData();let error=scope String();
        if(!candidate.Load(path,error)) {delete candidate;Log.Warning(error);return false;}
        delete mData;mData=candidate;return true;
    }
    public bool Bake()
    {
        let candidate=new NavigationData();let error=scope String();
        if(!candidate.Configure(Transform.Position,size,cellSize,flying,chunkSize,error)) {delete candidate;Log.Warning(error);return false;}
        candidate.agentRadius=agentRadius;candidate.agentHeight=agentHeight;candidate.maxStep=maxStep;candidate.maxSlope=maxSlope;
        if(!NavigationBaker.Bake(candidate,Scene,size.y,error,includeRenderMeshes)) {delete candidate;Log.Warning(error);return false;}
        delete mData;mData=candidate;return true;
    }
    public bool SaveData()
    {
        if(mData==null || bakedData.IsEmpty) return false;let path=scope String();Assets.ResolvePath(bakedData,path);let error=scope String();
        if(!mData.Save(path,error)) {Log.Warning(error);return false;}return true;
    }
    public bool Rebuild(Bounds changed)
    {
        if(mData==null) return Bake();let world=scope PhysicsWorld();let error=scope String();
        if(!changed.IsValid) {Log.Warning("Invalid navigation rebuild bounds.");return false;}
        NavigationBaker.BuildGeometry(Scene,world,includeRenderMeshes,true,NavigationBaker.QueryBounds(mData,size.y,changed));
        let ok=NavigationBaker.Rebuild(mData,world,size.y,changed,error);if(!ok) Log.Warning(error);return ok;
    }
    /// Selected: the bake volume as a box, walkable floor as a see-through blue overlay with its edges outlined, and for a
    /// flight volume the free cells that touch something solid.
    public override void OnDrawGizmos(bool selected)
    {
        if(!selected) return;
        // The box follows the fields being edited; a bake that used other bounds shows as a second, dimmer box.
        let area=Bounds(Transform.Position,Transform.Position+size);
        Gizmos.Lines.Box(area,.(0.2f,0.8f,1,1));
        let data=mData;if(data==null) return;
        let baked=Bounds(data.origin,data.origin+.(data.width*data.cellSize,data.flying ? data.height*data.cellSize : size.y,data.depth*data.cellSize));
        if((baked.min-area.min).Length>0.01f || (baked.max-area.max).Length>0.01f) Gizmos.Lines.Box(baked,.(0.2f,0.8f,1,0.35f));
        if(!drawNavigation) return;
        const int cBudget=20000;let edge=Color(0.05f,0.35f,0.75f,1);
        if(!data.flying)
        {
            let h=data.cellSize*0.5f;let lift=Vector3(0,0.04f,0);int quads=0;
            for(int32 z=0;z<data.depth;z++) for(int32 x=0;x<data.width;x++)
            {
                let cell=data.cells[data.Index(x,0,z)];if(!cell.walkable) continue;
                // A row of cells at one height is a single quad, so a large flat floor stays cheap to draw.
                var end=x;
                while(end+1<data.width && data.cells[data.Index(end+1,0,z)].walkable && Math.Abs(data.cells[data.Index(end+1,0,z)].position.y-cell.position.y)<0.005f) end++;
                if(quads++<cBudget)
                {
                    let a=cell.position+lift;let b=data.cells[data.Index(end,0,z)].position+lift;
                    Gizmos.Triangles.Quad(a+.(-h,0,-h),b+.(h,0,-h),b+.(h,0,h),a+.(-h,0,h),.(0.05f,0.4f,1,0.5f));
                }
                for(var run=x;run<=end;run++)
                {
                    // Outline every side an agent cannot cross.
                    let links=data.cells[data.Index(run,0,z)].links;let p=data.cells[data.Index(run,0,z)].position+lift;
                    if(quads>cBudget) break;
                    if((links & 1)==0) Gizmos.Lines.Line(p+.(h,0,-h),p+.(h,0,h),edge);
                    if((links & 2)==0) Gizmos.Lines.Line(p+.(-h,0,-h),p+.(-h,0,h),edge);
                    if((links & 4)==0) Gizmos.Lines.Line(p+.(-h,0,h),p+.(h,0,h),edge);
                    if((links & 8)==0) Gizmos.Lines.Line(p+.(-h,0,-h),p+.(h,0,-h),edge);
                }
                x=end;
            }
            return;
        }
        // A flight volume is mostly open space, so only cells beside something solid are drawn; they outline the obstacles.
        // When there are still too many, every Nth is drawn so the whole volume stays covered.
        bool Shown(NavigationData.Cell cell)
        {
            if(!cell.walkable) return false;
            for(int32 direction=0;direction<6;direction++) if((cell.links & (1u<<direction))==0) return true;
            return false;
        }
        int total=0;for(let cell in data.cells) if(Shown(cell)) total++;
        let stride=Math.Max((total+cBudget-1)/cBudget,1);int index=0;let s=Math.Min(0.15f,data.cellSize*0.3f);
        for(let cell in data.cells) if(Shown(cell) && index++%stride==0)
        {
            let p=cell.position;Gizmos.Lines.Line(p-.(s,0,0),p+.(s,0,0),edge);Gizmos.Lines.Line(p-.(0,0,s),p+.(0,0,s),edge);Gizmos.Lines.Line(p-.(0,s,0),p+.(0,s,0),edge);
        }
    }
}
