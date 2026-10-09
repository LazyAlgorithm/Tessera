using System;
using System.Collections;
using System.IO;
namespace Tessera;

/// Chunk-addressable surface grid, or a volume grid for flying agents.
/// Positions are agent feet for walking, and centers for flying.
class NavigationData
{
    public struct Cell { public bool walkable; public Vector3 position; public uint32 links; }
    /// Link directions: 0-5 are the axes, 6-9 the horizontal diagonals, 10-25 every offset that also moves up or down.
    public const int32 DirectionCount=26;
    public Vector3 origin;
    public float cellSize=1,agentRadius=0.3f,agentHeight=1.8f,maxStep=0.5f,maxSlope=45;
    public int32 width=32,height=1,depth=32,chunkSize=16;
    public bool flying;
    /// Unique across every NavigationData, so an agent notices a rebake that replaced the object as well as an in-place rebuild.
    public int32 Revision;
    static int32 sRevisions;
    public void Touch() { Revision=++sRevisions; }
    /// True when the last FindPath stopped at its visit budget instead of proving the goal unreachable.
    public bool BudgetExceeded;
    // Search scratch, kept between searches; a stamp marks the entries the current search has written.
    List<float> mCost=new .() ~ delete _;
    List<int32> mParent=new .() ~ delete _;
    List<int32> mSeen=new .() ~ delete _;
    List<int32> mClosed=new .() ~ delete _;
    List<HeapItem> mOpen=new .() ~ delete _;
    int32 mSearch;
    // Connected-region label per cell, rebuilt lazily after the grid changes.
    List<int32> mRegions=new .() ~ delete _;
    int32 mRegionRevision=-1;
    public List<Cell> cells=new .() ~ delete _;
    public int32 Index(int32 x,int32 y,int32 z)=>x+width*(z+depth*y);
    public bool Inside(int32 x,int32 y,int32 z)=>x>=0 && x<width && y>=0 && y<height && z>=0 && z<depth;
    public Vector3 Center(int32 x,int32 y,int32 z)=>origin+.( (x+0.5f)*cellSize,(y+0.5f)*cellSize,(z+0.5f)*cellSize);
    public static void Offset(int32 direction,out int32 x,out int32 y,out int32 z)
    {
        x=0;y=0;z=0;
        switch(direction)
        {
        case 0:x=1; case 1:x=-1; case 2:z=1; case 3:z=-1; case 4:y=1; case 5:y=-1;
        case 6,7,8,9:x=direction<8 ? 1 : -1;z=(direction&1)==0 ? 1 : -1;
        default:
            // Eight horizontal offsets one layer up, then the same eight one layer down.
            let k=(direction-10)%8;Offset(k<4 ? k : k+2,out x,out y,out z);y=direction<18 ? 1 : -1;
        }
    }
    public static int32 Opposite(int32 direction)
    {
        if(direction<6) return direction^1;
        if(direction<10) return 15-direction;
        let k=(direction-10)%8;
        return 10+(direction<18 ? 8 : 0)+(k<4 ? k^1 : 11-k);
    }
    /// Walking surfaces link along X/Z only, diagonals included.
    public bool Uses(int32 direction)=>flying || direction<4 || (direction>=6 && direction<10);
    /// Shortest possible travel between two cells over this grid's link directions; never more than the real cost.
    float Estimate(int32 a,int32 b)
    {
        var dx=(float)Math.Abs(a%width-b%width);var dz=(float)Math.Abs((a/width)%depth-(b/width)%depth);var dy=(float)Math.Abs(a/(width*depth)-b/(width*depth));
        if(dx<dy) Swap!(dx,dy);if(dx<dz) Swap!(dx,dz);if(dy<dz) Swap!(dy,dz);
        return (dx+0.41421356f*dy+0.31783725f*dz)*cellSize;
    }
    public int32 Neighbor(int32 index,int32 direction)
    {
        let x=index%width; let z=(index/width)%depth; let y=index/(width*depth);
        Offset(direction,let dx,let dy,let dz);
        return Inside(x+dx,y+dy,z+dz) ? Index(x+dx,y+dy,z+dz) : -1;
    }
    public bool Configure(Vector3 minimum,Vector3 size,float spacing,bool flight,int32 chunk,String error)
    {
        if(!minimum.x.IsFinite || !minimum.y.IsFinite || !minimum.z.IsFinite || !spacing.IsFinite || spacing<0.05f || !size.x.IsFinite || !size.y.IsFinite || !size.z.IsFinite || size.x<=0 || size.y<=0 || size.z<=0)
        { error.Set("Navigation size and cell spacing must be finite and positive."); return false; }
        let w=Math.Ceiling(size.x/spacing); let h=flight ? Math.Ceiling(size.y/spacing) : 1; let d=Math.Ceiling(size.z/spacing);
        if(w*h*d>1000000 || w>4096 || h>4096 || d>4096) { error.Set("Navigation grid exceeds one million cells. Increase cell size or reduce bounds."); return false; }
        origin=minimum;cellSize=spacing;flying=flight;chunkSize=Math.Max(chunk,1);
        width=(int32)w;height=(int32)h;depth=(int32)d;cells.Clear();cells.Resize(width*height*depth); return true;
    }
    /// Closest usable cell within maxDistance. The cell the point is in wins when it is usable, so a point beside a thin
    /// wall is not moved across it. A region limits the answer to cells connected to that region.
    public int32 Nearest(Vector3 point,float maxDistance,int32 region=-1)
    {
        if(!maxDistance.IsFinite || maxDistance<0 || !point.x.IsFinite || !point.y.IsFinite || !point.z.IsFinite || cells.Count!=width*height*depth) return -1;
        if(region>=0) EnsureRegions();
        int32 best=-1;float distance=maxDistance*maxDistance;
        int32 Bound(float p,int32 limit)=>(int32)Mathf.Clamp(Math.Floor(p/cellSize),0,limit-1);
        let cx=(int32)Math.Floor((point.x-origin.x)/cellSize);let cz=(int32)Math.Floor((point.z-origin.z)/cellSize);let cy=flying ? (int32)Math.Floor((point.y-origin.y)/cellSize) : 0;
        if(Inside(cx,cy,cz))
        {
            let i=Index(cx,cy,cz);
            if(cells[i].walkable && (region<0 || mRegions[i]==region) && (cells[i].position-point).LengthSquared<=distance) return i;
        }
        let x0=Bound(point.x-origin.x-maxDistance,width);let x1=Bound(point.x-origin.x+maxDistance,width);
        let z0=Bound(point.z-origin.z-maxDistance,depth);let z1=Bound(point.z-origin.z+maxDistance,depth);
        let y0=flying ? Bound(point.y-origin.y-maxDistance,height) : 0;let y1=flying ? Bound(point.y-origin.y+maxDistance,height) : 0;
        for(int32 y=y0;y<=y1;y++) for(int32 z=z0;z<=z1;z++) for(int32 x=x0;x<=x1;x++)
        {
            let i=Index(x,y,z);if(!cells[i].walkable || (region>=0 && mRegions[i]!=region)) continue;
            let d=(cells[i].position-point).LengthSquared;if(d<=distance) {distance=d;best=i;}
        }
        return best;
    }
    struct HeapItem { public int32 id; public float priority; public this(int32 id,float priority) {this.id=id;this.priority=priority;} }
    static void Push(List<HeapItem> heap,HeapItem item)
    {
        heap.Add(item); int index=heap.Count-1;
        while(index>0) { let parent=(index-1)/2; if(heap[parent].priority<=item.priority) break; heap[index]=heap[parent];index=parent; }
        heap[index]=item;
    }
    static HeapItem Pop(List<HeapItem> heap)
    {
        let result=heap[0]; let tail=heap.Back;heap.RemoveAt(heap.Count-1);
        if(heap.Count>0)
        {
            int index=0;
            while(index*2+1<heap.Count)
            {
                var child=index*2+1;if(child+1<heap.Count && heap[child+1].priority<heap[child].priority) child++;
                if(tail.priority<=heap[child].priority) break;heap[index]=heap[child];index=child;
            }
            heap[index]=tail;
        }
        return result;
    }
    /// Labels cells so two cells with different labels can never reach each other. Links are treated as two-way here, so
    /// equal labels do not promise a route; they only make the common unreachable case free.
    void EnsureRegions()
    {
        if(mRegionRevision==Revision && mRegions.Count==cells.Count) return;
        mRegions.Clear();mRegions.Resize(cells.Count);for(int i<cells.Count) mRegions[i]=-1;
        List<int32> stack=scope .();int32 next=0;
        for(int32 seed=0;seed<(int32)cells.Count;seed++)
        {
            if(!cells[seed].walkable || mRegions[seed]>=0) continue;
            mRegions[seed]=next;stack.Add(seed);
            while(stack.Count>0)
            {
                let id=stack.PopBack();
                for(int32 direction=0;direction<DirectionCount;direction++)
                {
                    if(!Uses(direction)) continue;
                    let other=Neighbor(id,direction);if(other<0 || !cells[other].walkable || mRegions[other]>=0) continue;
                    if((cells[id].links & (1u<<direction))==0 && (cells[other].links & (1u<<Opposite(direction)))==0) continue;
                    mRegions[other]=next;stack.Add(other);
                }
            }
            next++;
        }
        mRegionRevision=Revision;
    }
    public int32 Region(int32 cell) { EnsureRegions(); return cell>=0 && cell<mRegions.Count ? mRegions[cell] : -1; }
    /// One point per cell from the cell nearest `from` to the cell nearest `to`. The goal snaps to a cell connected to the
    /// start when one is in range, and a goal in another region fails without searching.
    public bool FindPath(Vector3 from,Vector3 to,List<Vector3> path,float snapDistance=2,int32 maxVisited=200000)
    {
        path.Clear();BudgetExceeded=false; if(cells.Count!=width*height*depth) return false;
        let start=Nearest(from,snapDistance);if(start<0) return false;
        EnsureRegions();
        let goal=Nearest(to,snapDistance,mRegions[start]);if(goal<0) return false;
        if(mSeen.Count!=cells.Count)
        {
            mCost.Clear();mCost.Resize(cells.Count);mParent.Clear();mParent.Resize(cells.Count);
            mSeen.Clear();mSeen.Resize(cells.Count);mClosed.Clear();mClosed.Resize(cells.Count);
            for(int i<cells.Count) {mSeen[i]=0;mClosed[i]=0;}
            mSearch=0;
        }
        mSearch++;mOpen.Clear();
        mCost[start]=0;mParent[start]=-1;mSeen[start]=mSearch;Push(mOpen,.(start,0)); int visited=0;
        while(mOpen.Count>0)
        {
            let id=Pop(mOpen).id;if(mClosed[id]==mSearch) continue;
            if(visited>=maxVisited) {BudgetExceeded=true;break;}
            mClosed[id]=mSearch;visited++;
            if(id==goal)
            {
                var cursor=goal; while(cursor>=0) {path.Add(cells[cursor].position);cursor=mParent[cursor];}
                for(int i=0;i<path.Count/2;i++) {let p=path[i];path[i]=path[path.Count-1-i];path[path.Count-1-i]=p;}
                return true;
            }
            for(int32 direction=0;direction<DirectionCount;direction++)
            {
                if(!Uses(direction) || (cells[id].links & (1u<<direction))==0) continue;
                let next=Neighbor(id,direction);if(next<0 || mClosed[next]==mSearch || !cells[next].walkable) continue;
                let g=mCost[id]+(cells[next].position-cells[id].position).Length;
                if(mSeen[next]==mSearch && g>=mCost[next]) continue;
                mCost[next]=g;mParent[next]=id;mSeen[next]=mSearch;
                // The slight overweight breaks ties toward the goal, so open space is not flooded.
                Push(mOpen,.(next,g+Estimate(next,goal)*1.001f));
            }
        }
        return false;
    }
    static void Put(List<uint8> bytes,uint32 value) { for(int shift=0;shift<32;shift+=8) bytes.Add((uint8)(value>>shift)); }
    static void Put(List<uint8> bytes,float value) { var copy=value;Put(bytes,*(uint32*)&copy); }
    static uint32 Get(List<uint8> bytes,ref int cursor) { let v=(uint32)bytes[cursor] | ((uint32)bytes[cursor+1]<<8) | ((uint32)bytes[cursor+2]<<16) | ((uint32)bytes[cursor+3]<<24);cursor+=4;return v; }
    static float GetFloat(List<uint8> bytes,ref int cursor) { var bits=Get(bytes,ref cursor);return *(float*)&bits; }
    bool ValidGrid(int64 count)=>width>0 && height>0 && depth>0 && width<=4096 && height<=4096 && depth<=4096 && (int64)width*height*depth<=1000000 && cellSize>=0.05f && cellSize.IsFinite && chunkSize>=1 && (flying || height==1) && count==(int64)width*height*depth && origin.x.IsFinite && origin.y.IsFinite && origin.z.IsFinite;
    /// Binary: "TNAV", version 2, the grid settings, then one word per cell (links, top bit = usable) plus the floor
    /// height for walking cells. Everything else about a cell follows from its index.
    public bool Save(StringView path,String error)
    {
        List<uint8> bytes=scope .();bytes.Reserve(64+cells.Count*(flying ? 4 : 8));
        bytes.Add((uint8)'T');bytes.Add((uint8)'N');bytes.Add((uint8)'A');bytes.Add((uint8)'V');Put(bytes,(uint32)2);
        Put(bytes,origin.x);Put(bytes,origin.y);Put(bytes,origin.z);Put(bytes,cellSize);
        Put(bytes,(uint32)width);Put(bytes,(uint32)height);Put(bytes,(uint32)depth);Put(bytes,(uint32)chunkSize);Put(bytes,flying ? 1u : 0u);
        Put(bytes,agentRadius);Put(bytes,agentHeight);Put(bytes,maxStep);Put(bytes,maxSlope);
        for(let c in cells) {Put(bytes,(c.links & 0x7FFFFFFF) | (c.walkable ? 0x80000000u : 0u));if(!flying) Put(bytes,c.position.y);}
        if(File.WriteAll(path,bytes) case .Err) {error.Set("Cannot write navigation asset.");return false;}return true;
    }
    public bool Load(StringView path,String error)
    {
        List<uint8> bytes=scope .();if(AssetPack.ReadAll(path,bytes) case .Err) {error.Set("Cannot read navigation asset.");return false;}
        if(bytes.Count<4 || bytes[0]!=(uint8)'T' || bytes[1]!=(uint8)'N' || bytes[2]!=(uint8)'A' || bytes[3]!=(uint8)'V') return LoadText(StringView((char8*)bytes.Ptr,bytes.Count),error);
        const int cHeader=60;int cursor=4;cells.Clear();
        if(bytes.Count<cHeader || Get(bytes,ref cursor)!=2) {error.Set("Unsupported navigation asset version.");return false;}
        origin.x=GetFloat(bytes,ref cursor);origin.y=GetFloat(bytes,ref cursor);origin.z=GetFloat(bytes,ref cursor);cellSize=GetFloat(bytes,ref cursor);
        width=(int32)Get(bytes,ref cursor);height=(int32)Get(bytes,ref cursor);depth=(int32)Get(bytes,ref cursor);chunkSize=(int32)Get(bytes,ref cursor);flying=Get(bytes,ref cursor)==1;
        agentRadius=GetFloat(bytes,ref cursor);agentHeight=GetFloat(bytes,ref cursor);maxStep=GetFloat(bytes,ref cursor);maxSlope=GetFloat(bytes,ref cursor);
        let count=(int64)(bytes.Count-cHeader)/(flying ? 4 : 8);
        if(!ValidGrid(count) || (int64)bytes.Count!=cHeader+count*(flying ? 4 : 8)) {width=height=depth=0;error.Set("Invalid navigation dimensions.");return false;}
        cells.Resize((int)count);
        for(int32 y=0;y<height;y++) for(int32 z=0;z<depth;z++) for(int32 x=0;x<width;x++)
        {
            let word=Get(bytes,ref cursor);Cell cell=default;cell.walkable=(word & 0x80000000)!=0;cell.links=word & 0x7FFFFFFF;cell.position=Center(x,y,z);
            if(!flying)
            {
                cell.position.y=GetFloat(bytes,ref cursor);
                if(!cell.position.y.IsFinite) {cells.Clear();error.Set("Navigation cell has a non-finite position.");return false;}
            }
            cells[Index(x,y,z)]=cell;
        }
        Touch();return true;
    }
    /// Reads the version 1 text format written by earlier builds. Those assets have no diagonal links; bake again to add them.
    bool LoadText(StringView text,String error)
    {
        List<StringView> tokens=scope .();List<String> storage=scope .();defer {for(let item in storage) delete item;}
        bool header=false,grid=false;cells.Clear();
        for(let line in text.Split('\n'))
        {
            tokens.Clear();SceneSerializer.Tokenize(line,tokens,storage);if(tokens.Count==0) continue;
            if(tokens.Count==2 && tokens[0]=="navigation" && tokens[1]=="1" && !header) header=true;
            else if(tokens.Count==15 && tokens[0]=="grid" && header && !grid)
            {
                origin=.(SceneSerializer.ParseFloat(tokens[1]),SceneSerializer.ParseFloat(tokens[2]),SceneSerializer.ParseFloat(tokens[3]));
                cellSize=SceneSerializer.ParseFloat(tokens[4]);width=SceneSerializer.ParseInt(tokens[5]);height=SceneSerializer.ParseInt(tokens[6]);depth=SceneSerializer.ParseInt(tokens[7]);chunkSize=SceneSerializer.ParseInt(tokens[8]);flying=tokens[9]=="1";
                agentRadius=SceneSerializer.ParseFloat(tokens[10]);agentHeight=SceneSerializer.ParseFloat(tokens[11]);maxStep=SceneSerializer.ParseFloat(tokens[12]);maxSlope=SceneSerializer.ParseFloat(tokens[13]);
                if(width<=0 || height<=0 || depth<=0 || width>4096 || height>4096 || depth>4096 || (int64)width*height*depth>1000000 || cellSize<0.05f || !cellSize.IsFinite || chunkSize<1 || (!flying && height!=1) || SceneSerializer.ParseInt(tokens[14])!=(int64)width*height*depth || !origin.x.IsFinite || !origin.y.IsFinite || !origin.z.IsFinite) {error.Set("Invalid navigation dimensions.");return false;}grid=true;
            }
            else if(tokens.Count==6 && tokens[0]=="cell" && grid && cells.Count<width*height*depth)
                cells.Add(.(){walkable=tokens[1]=="1",position=.(SceneSerializer.ParseFloat(tokens[2]),SceneSerializer.ParseFloat(tokens[3]),SceneSerializer.ParseFloat(tokens[4])),links=(uint32)SceneSerializer.ParseInt(tokens[5]) & 0x3F});
            else {error.Set("Malformed navigation asset.");return false;}
        }
        for(let cell in cells) if(!cell.position.x.IsFinite || !cell.position.y.IsFinite || !cell.position.z.IsFinite) {error.Set("Navigation cell has a non-finite position.");return false;}
        if(!grid || cells.Count!=width*height*depth) {error.Set("Incomplete navigation asset.");return false;}Touch();return true;
    }
}
