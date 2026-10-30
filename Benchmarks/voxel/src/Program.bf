using System;
using System.Collections;
using Tessera;
using Bgfx;
namespace VoxelBench;
class Program
{
 public static int Main(String[] args)
 {
  if(args.Count<8)return 1;
  let app=scope Bench();app.Kind.Set(args[0]);app.N=SceneSerializer.ParseInt(args[1]);app.Res=SceneSerializer.ParseInt(args[2]);app.Hits=SceneSerializer.ParseInt(args[3]);app.Collision.Set(args[4]);app.Headless=args[5]=="cpu";app.Warm=SceneSerializer.ParseInt(args[6]);app.Samples=SceneSerializer.ParseInt(args[7]);
  app.Width=args[5]=="hq" ? 1920 : 1280;app.Height=args[5]=="hq" ? 1080 : 720;Gfx.ResetFlags=0;
  if(args.Count>8)app.Profile.Set(args[8]);
  if(args.Count>9)return app.Run(scope String[]("--frames",scope $"{app.Warm+app.Samples+1}","--screenshot",args[9]));
  return app.Run(args);
 }
}
class Bench : Application
{
 public String Kind=new .() ~ delete _,Collision=new .() ~ delete _,Profile=new .() ~ delete _;
 public int N,Res,Hits,Warm,Samples,Frame;
 Scene scene=new .() ~ delete _;
 RenderView view ~ delete _;
 Camera camera;
 List<VoxelObject> voxels=new .() ~ delete _;
 List<int8[]> original=new .() ~ {for(let a in _)delete a;delete _;};
 uint64 previous;
 bool valid=true;
 int changed,spawned,peakObjects;
 double checksum;
 protected override bool LoadsPlayerQuality=>false;
 int Solid(VoxelObject v){int s=0;for(let d in v.[Friend]mDensity)if(d>0)s++;return s;}
 void Custom(VoxelObject v)
 {
  let count=v.[Friend]mSamples;let cell=v.GridSize/(count-1);
  for(int z<count)for(int y<count)for(int x<count)
  {
   let p=Vector3(x,y,z)*cell-Vector3(v.GridSize*0.5f);float d;
   if(Kind=="split")
   {
    let left=Math.Max(Math.Abs(p.x+1)-0.6f,Math.Max(Math.Abs(p.y)-0.65f,Math.Abs(p.z)-0.65f));
    let right=Math.Max(Math.Abs(p.x-1)-0.6f,Math.Max(Math.Abs(p.y)-0.65f,Math.Abs(p.z)-0.65f));
    let bridge=Math.Max(Math.Abs(p.x)-1,Math.Max(Math.Abs(p.y)-0.18f,Math.Abs(p.z)-0.18f));d=Math.Min(Math.Min(left,right),bridge);
   }
   else d=Math.Max(Math.Abs(p.x)-1.6f,Math.Max(Math.Abs(p.y)-1.6f,Math.Abs(p.z)-0.35f));
   v.[Friend]mDensity[x+y*count+z*count*count]=(int8)Mathf.Clamp(-d/cell*32,-127,127);
  }
  v.[Friend]mCustom=true;
 }
 protected override bool OnInit()
 {
  Audio.NoDevice=true;RenderView.Antialias=Width==1920;RenderView.RenderScale=1;RenderView.MaxSceneHeight=0;Gfx.SetVsync(false);Time.DeltaTime=Time.FixedDeltaTime;Time.UnscaledDeltaTime=Time.FixedDeltaTime;Scene.Active=scene;
  let begin=SDL.SDL_GetTicksNS();
  let floor=scene.CreateGameObject("Floor");floor.Transform.Position=.(0,-0.5f,0);floor.AddComponent<BoxCollider>().size=.(1024,1,1024);
  let columns=(int)Math.Ceiling(Math.Sqrt((double)Math.Max(N,1)));
  for(int i<N)
  {
   let o=scene.CreateGameObject("Destructible");let spacing=Kind=="debris" ? 1.0f : 4.5f;
   o.Transform.Position=.((i%columns-(columns-1)*0.5f)*spacing,Kind=="debris" ? 1.0f : 2.0f,(i/columns-(columns-1)*0.5f)*spacing);
   let renderer=o.AddComponent<MeshRenderer>();
   if(Kind=="shared" && i>0){renderer.RuntimeMesh=voxels[0].[Friend]mMesh;if(Collision=="mesh")o.AddComponent<MeshCollider>();continue;}
   let v=o.AddComponent<VoxelObject>();v.resolution=(int32)Res;v.size=Kind=="debris" ? 1 : 4;v.shape=.Box;v.anchored=Collision!="dynamic";v.breakOffPieces=Kind=="split" || Kind=="shots-split";v.minimumPieceSize=6;
   if(Kind=="model-cube" || Kind=="model-sphere"){v.shape=.Mesh;v.mesh.Set(Kind=="model-cube" ? "builtin:cube" : "builtin:sphere");}
   v.Fill();
   if(Kind=="slab" || Kind=="split")Custom(v);
   v.Rebuild();
   if(Collision=="mesh")o.AddComponent<MeshCollider>();
   if(Collision=="dynamic"){o.AddComponent<ConvexCollider>();o.AddComponent<Rigidbody>().mass=5;}
   voxels.Add(v);
   let copy=new int8[v.[Friend]mDensity.Count];Array.Copy(v.[Friend]mDensity,copy,copy.Count);original.Add(copy);
  }
  scene.StartPlay();scene.FixedUpdate();scene.Update();
  Console.WriteLine(scope $"CHECK,setup_ms,{(double)(SDL.SDL_GetTicksNS()-begin)/1e6}");
  Console.WriteLine(scope $"CHECK,base_objects,{scene.Objects.Count}");
  if(!Headless)
  {
   camera=scene.CreateGameObject("Camera").AddComponent<Camera>();let distance=(float)Math.Max(14,columns*5);camera.Transform.Position=.(0,distance*0.65f,-distance);camera.Transform.Rotation=Quaternion.LookRotation(Vector3(0,2,0)-camera.Transform.Position,.Up);camera.farClip=2000;
   let sun=scene.CreateGameObject("Sun").AddComponent<Light>();sun.Transform.Rotation=Quaternion.Euler(45,-45,0);view=new .(10);view.ToBackbuffer=true;view.DrawShadows=Width==1920;
   // Drain initial mesh uploads once, before any loops that rebuild more meshes.
   bgfx.frame(0);
  }
  if(Headless)
  {
   if(!Profile.IsEmpty){Profiler.NameThread("Voxel Benchmark");Profiler.Local.Clear();Profiler.Local.limit=(int32)Samples;Profiler.ComponentSamples=true;}
   for(int i<Warm+Samples){Frame=i;if(!Profile.IsEmpty && i>=Warm){Profiler.Enabled=true;Profiler.BeginFrame();}Tick();if(!Profile.IsEmpty && i>=Warm)Profiler.EndFrame();}
   if(!Profile.IsEmpty){Profiler.Enabled=false;Profiler.Local.Save(Profile);Profiler.Local.SaveReport(scope $"{Profile}.md");}
   Finish();Running=false;
  }
  previous=SDL.SDL_GetTicksNS();return true;
 }
 bool Edits=>Kind=="batch" || Kind=="shots" || Kind=="shots-split" || Kind=="burst" || Kind=="slab" || Kind=="split" || Kind=="blast";
 bool ApplyDensity(VoxelObject v,Vector3 point,float radius)
 {
  let samples=v.[Friend]mSamples;let cell=v.GridSize/(samples-1);let center=point-v.[Friend]mCenter+Vector3(v.GridSize*0.5f);let reach=radius+cell;
  let x0=Math.Max(0,(int)Math.Floor((center.x-reach)/cell)),x1=Math.Min(samples-1,(int)Math.Ceiling((center.x+reach)/cell));
  let y0=Math.Max(0,(int)Math.Floor((center.y-reach)/cell)),y1=Math.Min(samples-1,(int)Math.Ceiling((center.y+reach)/cell));
  let z0=Math.Max(0,(int)Math.Floor((center.z-reach)/cell)),z1=Math.Min(samples-1,(int)Math.Ceiling((center.z+reach)/cell));bool changed=false;
  for(int z=z0;z<=z1;z++)for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++)
  {
   let cut=((Vector3(x,y,z)*cell-center).Length-radius)/cell*32;let index=x+y*samples+z*samples*samples;
   if(cut<v.[Friend]mDensity[index]){if(v.[Friend]mDensity[index]>-100)v.[Friend]mCarved[index]=true;v.[Friend]mDensity[index]=(int8)Mathf.Clamp(cut,-127,127);changed=true;}
  }
  return changed;
 }
 void Tick()
 {
  // Restore only densities outside the timer; no Fill, mesh rebuild or collision cooking is hidden in the edit measurement.
  if(Edits)for(int i<voxels.Count){voxels[i].[Friend]DestroyPieces();Array.Copy(original[i],voxels[i].[Friend]mDensity,original[i].Count);Array.Clear(voxels[i].[Friend]mCarved,0,voxels[i].[Friend]mCarved.Count);}
  if(Edits)scene.Update();
  int before=0;if(Edits)for(let v in voxels)before+=Solid(v);
  let objectsBefore=scene.Objects.Count;
  let a=SDL.SDL_GetTicksNS();int success=0;
  if(Edits)
  {
   for(int h<Hits)
   {
    let v=voxels[h%voxels.Count];Vector3 at;float radius;
    if(Kind=="split"){at=.Zero;radius=0.42f;}
    else if(Kind=="blast"){at=.(0,0,-1.0f);radius=1;}
    else if(Kind=="slab"){at=.Zero;radius=0.5f;}
    else
    {
     let index=(Kind=="burst" || Kind=="batch") ? h : 14;
     let front=v.[Friend]mMesh.Bounds.Center.z-v.[Friend]mMesh.Bounds.Extents.z;
     at=.((index%6-2.5f)*0.48f,(index/6-2.5f)*0.48f,front+0.05f);radius=0.32f;
    }
    if(Kind=="batch" ? ApplyDensity(v,at,radius) : v.CarveLocal(at,radius))success++;
   }
  }
  if(Kind=="batch")for(int i<Math.Min(Hits,voxels.Count))voxels[i].Rebuild();
  if(Kind=="debris")for(let v in voxels) v.Transform.Position=v.Transform.Position+Vector3(0,0.001f*Math.Sin(Frame*0.2f),0);
  int hits=0;
  if(Kind=="rays")for(int q<1000){let v=voxels[q%voxels.Count];RaycastHit hit;if(scene.Physics.Raycast(v.Transform.Position+Vector3(0,0,-5),.(0,0,1),10,out hit))hits++;}
  let b=SDL.SDL_GetTicksNS();scene.FixedUpdate();let c=SDL.SDL_GetTicksNS();scene.Update();let d=SDL.SDL_GetTicksNS();
  if(scene.Physics.LastStepError!=0)valid=false;
  if(Edits)
  {
   int after=0;for(let v in voxels)after+=Solid(v);
   if(success!=Hits || after>=before)valid=false;
   changed+=success;spawned+=Math.Max(scene.Objects.Count-objectsBefore,0);peakObjects=Math.Max(peakObjects,scene.Objects.Count);
   if(Kind=="split" && scene.Objects.Count<=objectsBefore)valid=false;
   if(Kind=="split")for(let o in scene.Objects){let v=o.GetComponent<VoxelObject>();if(v!=null && (v.[Friend]mSamples!=Res+1 || v.[Friend]mDensity.Count!=(Res+1)*(Res+1)*(Res+1)))valid=false;}
   if(Kind=="slab")
   {
    let v=voxels[0];RaycastHit hole;
    if(scene.Physics.Raycast(v.Transform.Position+Vector3(0,0,-5),.(0,0,1),10,out hole))valid=false;
   }
  }
  if(Kind=="rays" && hits!=1000)valid=false;
  checksum+=hits;
  if(Frame>=Warm)Console.WriteLine(scope $"SAMPLE,{Frame-Warm},{(double)(b-a)/1e6},{(double)(c-b)/1e6},{(double)(d-c)/1e6},{(double)(d-a)/1e6},{success}");
 }
 void Finish()
 {
  uint64 densityHash=1469598103934665603;for(let v in voxels)for(let d in v.[Friend]mDensity)densityHash=(densityHash^(uint64)((int32)d&255))*1099511628211;
  Console.WriteLine(scope $"CHECK,density_hash,{densityHash}");
  int64 vertices=0,triangles=0,samples=0;for(let v in voxels){vertices+=v.[Friend]mMesh.Vertices.Count;triangles+=v.[Friend]mMesh.Indices.Count/3;samples+=v.[Friend]mDensity.Count;for(let p in v.[Friend]mMesh.Vertices)if(!p.position.x.IsFinite || !p.position.y.IsFinite || !p.position.z.IsFinite)valid=false;}
  if(!Headless){let stats=bgfx.get_stats();if(stats!=null)Console.WriteLine(scope $"CHECK,draws,{stats.numDraw}");}
  Console.WriteLine(scope $"CHECK,vertices,{vertices}");Console.WriteLine(scope $"CHECK,triangles,{triangles}");Console.WriteLine(scope $"CHECK,grid_samples,{samples}");Console.WriteLine(scope $"CHECK,changed_carves,{changed}");Console.WriteLine(scope $"CHECK,spawned_fragments,{spawned}");Console.WriteLine(scope $"CHECK,peak_objects,{peakObjects}");Console.WriteLine(scope $"CHECK,checksum,{checksum}");Console.WriteLine(scope $"CHECK,valid,{valid}");
 }
 protected override void OnUpdate(){if(!Headless && Frame<Warm+Samples)Tick();}
 protected override void OnRender()
 {
  if(Frame>=Warm+Samples){Finish();Running=false;return;}
  let now=SDL.SDL_GetTicksNS();if(Frame>=Warm && Frame>0)Console.WriteLine(scope $"FRAME,{Frame-Warm},{(double)(now-previous)/1e6}");previous=now;Frame++;
  view.Resize(Width,Height);view.Render(scene,camera.GetCameraData((float)Width/Height));
 }
 protected override void OnShutdown(){scene.StopPlay();Audio.Shutdown();}
}
