using System;
using System.Collections;
using Tessera;
using Bgfx;
namespace WaterBench;
class Program
{
 public static int Main(String[] args)
 {
  if(args.Count<8)return 1;
  let a=scope Bench();a.Kind.Set(args[0]);a.N=SceneSerializer.ParseInt(args[1]);a.Detail=SceneSerializer.ParseFloat(args[2]);a.Low=args[3]=="low";a.Headless=args[4]=="cpu";a.RequestedWidth=(int32)SceneSerializer.ParseInt(args[5]);a.RequestedHeight=a.RequestedWidth==3840 ? 2160 : a.RequestedWidth==1920 ? 1080 : 720;a.Width=a.RequestedWidth;a.Height=a.RequestedHeight;a.Warm=SceneSerializer.ParseInt(args[6]);a.Samples=SceneSerializer.ParseInt(args[7]);Gfx.ResetFlags=0;
  if(args.Count>8)a.Profile.Set(args[8]);
  if(args.Count>9)return a.Run(scope String[]("--frames",scope $"{a.Warm+a.Samples+1}","--screenshot",args[9]));
  return a.Run(args);
 }
}
class Bench : Application
{
 public String Kind=new .() ~ delete _,Profile=new .() ~ delete _;
 public int N,Warm,Samples,Frame;public int32 RequestedWidth,RequestedHeight;public float Detail;public bool Low;
 Scene scene=new .() ~ delete _;
 RenderView view ~ delete _;Camera camera;Water water;Mesh shape ~ delete _;
 List<Rigidbody> bodies=new .() ~ delete _;List<SoftBody> softs=new .() ~ delete _;List<Rope> ropes=new .() ~ delete _;
 bool valid=true;double checksum;uint64 previous;int baseGrids=-1,maxGrids;
	static Mesh Sheet(int cells, float size)
	{
		let mesh = new Mesh();
		for (int z <= cells)
		{
			for (int x <= cells)
				mesh.AddVertex(.((x / (float)cells - 0.5f) * size, 0, (z / (float)cells - 0.5f) * size), .Up, .White, .(x / (float)cells, z / (float)cells));
		}
		for (int z < cells)
		{
			for (int x < cells)
			{
				let a = (uint32)(z * (cells + 1) + x);
				mesh.AddTriangle(a, a + (uint32)cells + 1, a + 1);
				mesh.AddTriangle(a + 1, a + (uint32)cells + 1, a + (uint32)cells + 2);
			}
		}
		return mesh;
	}

	/// A level sheet pinned along its far edge (its last row, z = +size/2): the rest swings down and hangs from it.
	/// A box, half its size each way, each face cut into `cells` squares across (so it can dent and bend).
	static Mesh Box(Vector3 half, int cells)
	{
		let mesh = new Mesh();
		for (int face < 6)
		{
			let axis = face / 2;
			let sign = (face % 2 == 0) ? 1.0f : -1.0f;
			let start = (uint32)mesh.Vertices.Count;
			for (int j <= cells)
			{
				for (int i <= cells)
				{
					float[3] p = default;
					p[axis] = sign;
					p[(axis + 1) % 3] = i / (float)cells * 2 - 1;
					p[(axis + 2) % 3] = j / (float)cells * 2 - 1;
					float[3] n = default;
					n[axis] = sign;
					mesh.AddVertex(.(p[0] * half.x, p[1] * half.y, p[2] * half.z), .(n[0], n[1], n[2]), .White, .(i / (float)cells, j / (float)cells));
				}
			}
			for (int j < cells)
			{
				for (int i < cells)
				{
					let a = start + (uint32)(j * (cells + 1) + i);
					let c = a + (uint32)cells + 1;
					// Wound to face outward on either side.
					if (sign > 0)
					{
						mesh.AddTriangle(a, a + 1, c);
						mesh.AddTriangle(a + 1, c + 1, c);
					}
					else
					{
						mesh.AddTriangle(a, c, a + 1);
						mesh.AddTriangle(a + 1, c, c + 1);
					}
				}
			}
		}
		return mesh;
	}


 protected override bool LoadsPlayerQuality=>false;
 GameObject VisibleBox(StringView name,Vector3 at,Vector3 scale)
 {
  let o=scene.CreateGameObject(name);o.Transform.Position=at;o.Transform.LocalScale=scale;o.AddComponent<MeshRenderer>();return o;
 }
 protected override bool OnInit()
 {
  Audio.NoDevice=true;Gfx.SetVsync(false);RenderView.Antialias=false;RenderView.RenderScale=1;RenderView.MaxSceneHeight=0;Time.DeltaTime=Time.FixedDeltaTime;Scene.Active=scene;
  let begin=SDL.SDL_GetTicksNS();
  let floor=scene.CreateGameObject("Bottom");floor.Transform.Position=.(0,-20.5f,0);floor.AddComponent<BoxCollider>().size=.(2000,1,2000);
  if(Kind!="baseline" && Kind!="dry")
  {
   water=scene.CreateGameObject("Water").AddComponent<Water>();water.UseLook(Low ? .LowPoly : .Realistic);water.endless=Kind!="lake" && Kind!="large-lake";water.size=Kind=="large-lake" ? Vector2(8000,8000) : Vector2(80,80);water.depth=40;water.waveHeight=0.4f;water.gridSpacing=(Kind=="cloth" || Kind=="jelly" || Kind=="shell" || Kind=="rope") ? 0.5f : Math.Max(Detail,0.05f);water.flow=.(0.5f,0);
   if(Kind=="no-ssr")water.screenReflections=false;
  }
  if(Kind=="cloth")shape=Sheet((int)Detail,2);
  if(Kind=="jelly" || Kind=="shell")shape=Box(.(0.5f,0.5f,0.5f),(int)Detail);
  let cols=(int)Math.Ceiling(Math.Sqrt((double)Math.Max(N,1)));
  if(Kind=="bodies" || Kind=="dry" || Kind=="cloth" || Kind=="jelly" || Kind=="shell" || Kind=="rope")for(int i<N)
  {
   let at=Vector3((i%cols-(cols-1)*0.5f)*4,-0.1f,(i/cols-(cols-1)*0.5f)*4);let o=scene.CreateGameObject("Floater");o.Transform.Position=at;
   if(Kind=="cloth" || Kind=="jelly" || Kind=="shell")
   {
    o.AddComponent<MeshRenderer>().RuntimeMesh=shape;if(Kind=="shell"){o.AddComponent<ConvexCollider>();o.AddComponent<Rigidbody>().mass=40;}let soft=o.AddComponent<SoftBody>();soft.kind=Kind=="cloth" ? .Cloth : Kind=="shell" ? .Shell : .Jelly;soft.windDrag=0;softs.Add(soft);
   }
   else if(Kind=="rope") {let rope=o.AddComponent<Rope>();rope.holdStart=false;rope.length=3;rope.segments=(int32)Detail;rope.windDrag=0;ropes.Add(rope);}
   else {o.AddComponent<MeshRenderer>();o.AddComponent<BoxCollider>();let body=o.AddComponent<Rigidbody>();body.mass=40;bodies.Add(body);}
  }
  scene.StartPlay();scene.FixedUpdate();scene.Update();
  if(!Headless)
  {
   VisibleBox("Seabed",.(0,-3,0),.(200,0.3f,200));for(int i<12)VisibleBox("Pillar",.((i%4-1.5f)*5,-1,(i/4)*7+2),.(1,5,1));
   camera=scene.CreateGameObject("Camera").AddComponent<Camera>();camera.farClip=15000;camera.Transform.Position=.(0,3,-12);camera.Transform.Rotation=Quaternion.LookRotation(Vector3(0,0,30)-camera.Transform.Position,.Up);
   let sun=scene.CreateGameObject("Sun").AddComponent<Light>();sun.Transform.Rotation=Quaternion.Euler(45,-45,0);view=new .(10);view.ToBackbuffer=true;view.DrawShadows=true;
  }
  Console.WriteLine(scope $"CHECK,setup_ms,{(double)(SDL.SDL_GetTicksNS()-begin)/1e6}");
  if(Headless)
  {
   if(!Profile.IsEmpty){Profiler.NameThread("Water Benchmark");Profiler.Local.Clear();Profiler.Local.limit=(int32)Samples;Profiler.ComponentSamples=true;}
   for(int i<Warm+Samples){Frame=i;Time.FrameCount=i;if(!Profile.IsEmpty && i>=Warm){Profiler.Enabled=true;Profiler.BeginFrame();}Tick();if(!Profile.IsEmpty && i>=Warm)Profiler.EndFrame();}
   if(!Profile.IsEmpty){Profiler.Enabled=false;Profiler.Local.Save(Profile);Profiler.Local.SaveReport(scope $"{Profile}.md");}
   Finish();Running=false;
  }
  previous=SDL.SDL_GetTicksNS();return true;
 }
 void Tick()
 {
  let a=SDL.SDL_GetTicksNS();
  if(Kind.StartsWith("queries"))for(int q<N)
  {
   let point=Vector3((q%100)*0.7f,0,(q/100)*0.7f);water.SurfaceAt(point,Kind=="queries-day" ? 86400.0 : Time.Tick/(double)60,let height,let normal,let velocity);if(!height.IsFinite || !normal.x.IsFinite || Math.Abs(height)>2)valid=false;checksum+=height;
  }
  else Water.Simulate(scene,Time.FixedDeltaTime);
  let b=SDL.SDL_GetTicksNS();scene.Physics.Step(Time.FixedDeltaTime);Time.Tick++;let c=SDL.SDL_GetTicksNS();scene.Update();let d=SDL.SDL_GetTicksNS();
  if(scene.Physics.LastStepError!=0)valid=false;
  if(Frame>=Warm)Console.WriteLine(scope $"SAMPLE,{Frame-Warm},{(double)(b-a)/1e6},{(double)(c-b)/1e6},{(double)(d-c)/1e6},{(double)(d-a)/1e6}");
 }
 void Finish()
 {
  int floating=0;float span=0;
  for(let body in bodies){let p=body.Transform.Position;if(!p.x.IsFinite || !p.y.IsFinite || !p.z.IsFinite)valid=false;if(water!=null && water.IsFloating(body))floating++;checksum+=p.y;}
  for(let soft in softs){if(Kind=="shell" ? water.IsFloating(soft.GetComponent<Rigidbody>()) : water.IsFloating(soft))floating++;var lo=Vector3(float.MaxValue),hi=Vector3(float.MinValue);for(let p in soft.Positions){if(!p.x.IsFinite || !p.y.IsFinite || !p.z.IsFinite)valid=false;lo=Vector3.Min(lo,p);hi=Vector3.Max(hi,p);}span=Math.Max(span,Math.Max(hi.x-lo.x,Math.Max(hi.y-lo.y,hi.z-lo.z)));if(span>8)valid=false;}
  for(let rope in ropes){if(water.IsFloating(rope))floating++;for(let p in rope.Points)if(!p.x.IsFinite || !p.y.IsFinite || !p.z.IsFinite)valid=false;}
  if(N>0 && (Kind=="bodies" || Kind=="cloth" || Kind=="jelly" || Kind=="shell" || Kind=="rope") && floating<N*0.9f)valid=false;
  if(!Headless)
  {
   let stats=bgfx.get_stats();if(stats!=null)Console.WriteLine(scope $"CHECK,draws,{stats.numDraw}");
   if(water!=null){if(view.VisibleWater!=1 || !RenderResources.WaterProgram.Valid)valid=false;if(Kind=="underwater" && view.CameraWater==null)valid=false;Console.WriteLine(scope $"CHECK,visible_water,{view.VisibleWater}");Console.WriteLine(scope $"CHECK,underwater,{view.CameraWater!=null}");}
   Console.WriteLine(scope $"CHECK,grid_cache_count,{maxGrids}");
  }
  Console.WriteLine(scope $"CHECK,floating,{floating}");Console.WriteLine(scope $"CHECK,soft_max_span,{span}");Console.WriteLine(scope $"CHECK,checksum,{checksum}");Console.WriteLine(scope $"CHECK,valid,{valid}");
 }
 protected override void OnUpdate()
 {
  if(Headless || Frame>=Warm+Samples)return;
  if(Kind=="underwater")camera.Transform.Position=.(0,-2,-12);
  if(Kind=="waterline")camera.Transform.Position=.(0,Math.Sin(Frame*0.06f)*0.5f,-12);
  if(Kind=="travel" || Kind=="far") {let origin=Kind=="far" ? 100000.0f : 0;camera.Transform.Position=.(origin+Frame*7,3,origin-12);camera.Transform.Rotation=Quaternion.LookRotation(.(0,-0.08f,1),.Up);}
  Tick();
 }
 protected override void OnRender()
 {
  if(Frame>=Warm+Samples){Finish();Running=false;return;}
  let now=SDL.SDL_GetTicksNS();if(Frame>=Warm && Frame>0)Console.WriteLine(scope $"FRAME,{Frame-Warm},{(double)(now-previous)/1e6}");previous=now;
  view.Resize(RequestedWidth,RequestedHeight);let data=camera.GetCameraData((float)RequestedWidth/RequestedHeight);if(Frame==Warm){Console.WriteLine(scope $"CHECK,render_width,{view.[Friend]mWidth}");Console.WriteLine(scope $"CHECK,render_height,{view.[Friend]mHeight}");if(view.[Friend]mWidth!=RequestedWidth || view.[Friend]mHeight!=RequestedHeight)valid=false;}view.Render(scene,data);
  if(water!=null)
  {
   let mesh=view.[Friend]WaterGridFor(water,data,var model,let spacing);if(mesh.VertexCount<=0 || mesh.IndexCount<=0)valid=false;let grids=RenderView.[Friend]sWaterGrids.Count;maxGrids=Math.Max(maxGrids,grids);if(baseGrids<0)baseGrids=grids;if(grids!=baseGrids)valid=false;
   if(Frame==Warm)Console.WriteLine(scope $"CHECK,water_vertices,{mesh.VertexCount}");
  }
  if(Frame>=Warm && Frame%30==0){let stats=bgfx.get_stats();if(stats!=null && stats.gpuTimerFreq>0)Console.WriteLine(scope $"GPU,{Frame-Warm},{(double)(stats.gpuTimeEnd-stats.gpuTimeBegin)*1000/stats.gpuTimerFreq}");}
  Frame++;
 }
 protected override void OnShutdown(){scene.StopPlay();Audio.Shutdown();}
}
