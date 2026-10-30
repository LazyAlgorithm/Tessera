using System;
using System.Collections;
using Tessera;
namespace NetBench;
[Component]
class Player : NetworkBehaviour
{
 public override void GatherInput(ref NetInput input){input=default;if(App.Active!=null && App.Active.Elapsed>=0 && App.Active.Elapsed<6){input.moveX=0.4f;input.moveZ=0.2f;}}
 public override void Simulate(NetInput input,float dt){Transform.Position+=Vector3(input.moveX,0,input.moveZ)*3*dt;}
}
class Program
{
 public static int Main(String[] args)
 {
  if(args.Count<9)return 1;let a=scope App();a.Server=args[0]=="server";a.N=SceneSerializer.ParseInt(args[1]);a.Profile.Set(args[2]);a.WaterMode.Set(args[3]);a.Clients=SceneSerializer.ParseInt(args[4]);a.Port=(uint16)SceneSerializer.ParseInt(args[5]);a.Lag=SceneSerializer.ParseInt(args[6]);a.Jitter=SceneSerializer.ParseInt(args[7]);a.Loss=SceneSerializer.ParseFloat(args[8]);a.Headless=true;return a.Run(args);
 }
}
class App : Application
{
 public static App Active;
 public bool Server;public int N,Clients,Lag,Jitter;public uint16 Port;public float Loss;
 public String Profile=new .() ~ delete _,WaterMode=new .() ~ delete _;
 Scene scene=new .() ~ delete _;Water water;List<Rigidbody> bodies=new .() ~ delete _;
 List<Vector3> bases=new .() ~ delete _;List<int32> ids=new .() ~ delete _;HashSet<int32> results=new .() ~ delete _;
 uint32 startTick;bool started,reported,valid=true,sentTruth,gotTruth;int finalTickChecks;float truthError;uint64 previous;double updateTotal,updateWorst;int updates;
 uint32 lastWireOut,lastWireIn;double wireOut,wireIn;int64 appOut,appIn,transportOut;float lastSample;int samples;
 int lastPhase=-1;float doneReal=-1;float startReal;float waveError;bool changedWater;int peakFloating;int lastFeatureStep=-1;float meterStart=-1;uint32 meterTick;float maxBodyCorrection,maxPlayerCorrection;
 public double Elapsed=>started ? (scene.Network.ServerTick-startTick)/60.0 : -1;
 static GameObject MakePlayer(Scene s){let o=s.CreateGameObject("Player");o.Transform.Position=.(0,2,0);o.AddComponent<NetworkIdentity>();o.AddComponent<Player>();return o;}
 static void StartMessage(int32 sender,ref NetReader reader){if(Active!=null && sender==0){Active.startTick=reader.Read<uint32>();Active.started=reader.Ok;Active.startReal=Time.RealTime;}}
 static void TruthMessage(int32 sender,ref NetReader reader)
 {
  if(Active==null || sender!=0)return;let a=Active;let count=reader.Read<int32>();float worst=0;bool good=count==a.N;
  for(int i=0;i<count && reader.Ok;i++){let pos=reader.Read<Vector3>();if(i<a.bodies.Count)worst=Math.Max(worst,(pos-a.bodies[i].Transform.Position).Length);}
  let wet=reader.Read<bool>();
  if(wet){let wave=reader.Read<float>();let level=reader.Read<float>();let time=reader.Read<double>();let expected=reader.Read<float>();if(a.water==null)good=false;else {a.water.SurfaceAt(.Zero,time,let h,?,?);a.waveError=Math.Abs(h-expected);if(a.water.waveHeight!=wave || Math.Abs(a.water.Level-level)>0.05f || a.waveError>0.001f)good=false;}}
  let mixed=reader.Read<bool>();if(mixed)for(int i=0;i<count && reader.Ok;i++){let enabled=reader.Read<bool>();let intensity=reader.Read<float>();let color=reader.Read<Color>();let light=a.bodies[i].GetComponent<Light>();if(light==null || light.Enabled!=enabled || light.intensity!=intensity || light.color!=color)good=false;}
  a.truthError=worst;a.gotTruth=true;if(!reader.Ok || !good || worst>0.2f)a.valid=false;
 }
 static void ResultMessage(int32 sender,ref NetReader reader){if(Active!=null && sender>0){if(reader.Read<uint8>()!=1)Active.valid=false;Active.results.Add(sender);}}
 protected override bool OnInit()
 {
  Active=this;Audio.NoDevice=true;Time.DeltaTime=Time.FixedDeltaTime;Scene.Active=scene;NetworkManager.RegisterPrefab("BenchPlayer",new =>MakePlayer);NetworkManager.RegisterMessage(210,new =>StartMessage);NetworkManager.RegisterMessage(211,new =>TruthMessage);NetworkManager.RegisterMessage(212,new =>ResultMessage);
  NetworkManager.SimulatedLagMs=(int32)Lag;NetworkManager.SimulatedJitterMs=(int32)Jitter;NetworkManager.SimulatedLossPercent=Loss;
  let floor=scene.CreateGameObject("Ground");floor.Transform.Position=.(0,-20.5f,0);floor.AddComponent<BoxCollider>().size=.(1024,1,1024);
  if(WaterMode!="none"){water=scene.CreateGameObject("Ocean").AddComponent<Water>();water.endless=true;water.depth=40;water.waveHeight=WaterMode=="waves" ? 0.6f : 0;}
  for(int i<N)
  {
   let o=scene.CreateGameObject("Prop");o.Transform.Position=.(10+(i%64)*1.5f,-0.1f,(i/64)*1.5f);o.AddComponent<BoxCollider>();let b=o.AddComponent<Rigidbody>();b.mass=40;b.useGravity=water!=null;bodies.Add(b);bases.Add(o.Transform.Position);
   let identity=o.AddComponent<NetworkIdentity>();
   if(Profile!="default")
   {
    identity.fullPrecision=true;identity.physicsPrediction=.Off;identity.remoteFormat=Profile=="exact" ? .Legacy : .QuantizedBody;identity.dormantWhenSleeping=true;
    if(Profile=="optimized" || Profile=="framed" || Profile=="mixed")identity.remoteIntervalTicks=6;
   }
   if(Profile=="mixed")o.AddComponent<Light>().type=.Point;
  }
  scene.StartPlay();scene.FixedUpdate();scene.Update();scene.Network=new .(scene);scene.Network.PlayerPrefab.Set("BenchPlayer");scene.Network.ProfileSnapshots=true;scene.Network.OptimizeSnapshots=Profile!="default";scene.Network.LosslessCompression=Profile=="optimized" || Profile=="mixed";scene.Network.MessageCompression=Profile=="framed";if(Profile=="budget")scene.Network.SnapshotBytesPerSecond=64000;
  bool ok=Server ? scene.Network.StartServer(Port,true) : scene.Network.StartClient("127.0.0.1",Port);if(!ok)return false;previous=SDL.SDL_GetTicksNS();return true;
 }
 void Meter(int phase)
 {
  if(Time.RealTime-lastSample<1)return;let net=scene.Network;let outBytes=net.WireBytesSent;let inBytes=net.WireBytesReceived;let duration=Math.Max(Time.RealTime-lastSample,0.001f);
  if(lastSample>0 && phase==lastPhase && phase>=0)
  {
   let wo=(outBytes-lastWireOut)/duration;let wi=(inBytes-lastWireIn)/duration;
   Console.WriteLine(scope $"TRAFFIC,{phase},{net.BytesSentPerSecond},{net.BytesReceivedPerSecond},{net.TransportBytesSentPerSecond},{wo},{wi},{net.Tick}");
   if(phase==0 || phase==1){wireOut+=wo;wireIn+=wi;appOut+=net.BytesSentPerSecond;appIn+=net.BytesReceivedPerSecond;transportOut+=net.TransportBytesSentPerSecond;samples++;}
  }
  lastSample=Time.RealTime;lastWireOut=outBytes;lastWireIn=inBytes;lastPhase=phase;
 }
 protected override void OnFixedUpdate()
 {
  if(Server && started && Elapsed<6 && water==null)for(int i<bodies.Count){let b=bodies[i];b.Velocity=.(0.4f*Math.Sin((float)Elapsed*2+i*0.1f),0,0.3f*Math.Cos((float)Elapsed));}
  if(Server && started && Elapsed>=6 && water==null)for(let b in bodies)b.Velocity=.Zero;
  let a=SDL.SDL_GetTicksNS();scene.FixedUpdate();let ms=(double)(SDL.SDL_GetTicksNS()-a)/1e6;if(started && Elapsed>=1 && Elapsed<10){updateTotal+=ms;updateWorst=Math.Max(updateWorst,ms);updates++;}
  if(scene.Physics.LastStepError!=0)valid=false;
 }
 protected override void OnUpdate()
 {
  scene.Update();let net=scene.Network;if(started && Elapsed>=1 && Elapsed<10){maxBodyCorrection=Math.Max(maxBodyCorrection,net.[Friend]mStatBodyWorst);maxPlayerCorrection=Math.Max(maxPlayerCorrection,net.LastCorrection);}
  if(Server && !started && net.ClientCount==Clients){started=true;startTick=net.Tick;startReal=Time.RealTime;let w=scope NetWriter();w.Write(startTick);net.SendToAll(210,w);}
  let elapsed=Elapsed;
  if(elapsed>=2 && meterStart<0){meterStart=Time.RealTime;meterTick=net.Tick;}
  if(Server && water!=null && elapsed>3 && !changedWater){changedWater=true;water.waveHeight=0.9f;water.Transform.Position=.(0,0.2f,0);}
  if(Server && water!=null && elapsed>2 && elapsed<8){int floating=0;for(let b in bodies)if(water.IsFloating(b))floating++;peakFloating=Math.Max(peakFloating,floating);}
  if(Server && Profile=="mixed" && elapsed>0 && elapsed<9){let step=(int)(elapsed*2);if(step!=lastFeatureStep){lastFeatureStep=step;for(let b in bodies){let light=b.GetComponent<Light>();light.Enabled=step%3!=0;light.intensity=1+(step%4);light.color=.FromBytes((uint8)(20+step*11%200),80,200);}}}
  int phase=elapsed<1 ? -1 : elapsed<6 ? 0 : elapsed<10 ? 1 : 2;Meter(phase);
  for(let b in bodies){let pos=b.Transform.Position;if(!pos.x.IsFinite || !pos.y.IsFinite || !pos.z.IsFinite)valid=false;}
  if(Server && elapsed>=10 && !sentTruth)
  {
   // Freeze at a server-authoritative final state; verify every prop, not just a representative one.
   if(water!=null)water.floatRigidbodies=false;
   for(let b in bodies){b.Velocity=.Zero;b.useGravity=false;b.isKinematic=true;b.RebuildBody();}
   sentTruth=true;doneReal=Time.RealTime;
  }
  if(Server && sentTruth && Time.RealTime-doneReal>1 && finalTickChecks==0){let w=scope NetWriter();w.Write((int32)bodies.Count);for(let b in bodies)w.Write(b.Transform.Position);w.Write(water!=null);if(water!=null){w.Write(water.waveHeight);w.Write(water.Level);let time=net.Tick/(double)60;w.Write(time);water.SurfaceAt(.Zero,time,let h,?,?);w.Write(h);}w.Write(Profile=="mixed");if(Profile=="mixed")for(let b in bodies){let light=b.GetComponent<Light>();w.Write(light.Enabled);w.Write(light.intensity);w.Write(light.color);}net.SendToAll(211,w);finalTickChecks++;}
  if(!Server && gotTruth && !reported)
  {
   reported=true;let w=scope NetWriter();w.Write((uint8)(valid ? 1 : 0));net.SendToServer(212,w);doneReal=Time.RealTime;
  }
  if(Server && results.Count==Clients && started){Report();Running=false;}
  if(!Server && reported && Time.RealTime-doneReal>0.8f){Report();Running=false;}
  if(Time.RealTime>35){valid=false;Report();Running=false;}
 }
 void Report()
 {
  let net=scene.Network;Console.WriteLine(scope $"CHECK,max_body_correction,{maxBodyCorrection}");Console.WriteLine(scope $"CHECK,max_player_correction,{maxPlayerCorrection}");if(Server && water!=null && peakFloating<N*0.9f)valid=false;Console.WriteLine(scope $"CHECK,peak_floating,{peakFloating}");Console.WriteLine(scope $"CHECK,wave_error,{waveError}");Console.WriteLine(scope $"CHECK,effective_tick_hz,{(net.Tick-meterTick)/Math.Max(Time.RealTime-meterStart,0.001f)}");Console.WriteLine(scope $"METRICS,{(Server ? "server" : "client")},{N},{Profile},{WaterMode},{Clients},{wireOut/Math.Max(samples,1)},{wireIn/Math.Max(samples,1)},{appOut/Math.Max(samples,1)},{appIn/Math.Max(samples,1)},{transportOut/Math.Max(samples,1)},{updateTotal/Math.Max(updates,1)},{updateWorst},{truthError},{net.SnapshotsReceived},{net.Rollbacks},{(double)net.SnapshotBuildNanoseconds/Math.Max(net.SnapshotBuildCalls,1)/1e6},{(double)net.SnapshotReadNanoseconds/Math.Max(net.SnapshotReadCalls,1)/1e6},{valid}");
  Console.WriteLine(scope $"CHECK,elapsed,{Elapsed}");Console.WriteLine(scope $"CHECK,connected,{net.IsConnected}");Console.WriteLine(scope $"CHECK,truth,{gotTruth || Server && results.Count==Clients}");Console.WriteLine(scope $"CHECK,valid,{valid && (Server ? results.Count==Clients : gotTruth)}");
 }
 protected override void OnShutdown(){scene.Network?.Stop();scene.StopPlay();Audio.Shutdown();if(Active==this)Active=null;}
}
