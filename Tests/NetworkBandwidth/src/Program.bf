using System;
using System.Collections;
using Tessera;
namespace NetworkBandwidthTests;

class CaptureTransport : NetTransport
{
    public int64 bytes;
    public int maxPacket,packets,reliablePackets;
    public List<uint8> last=new .() ~ delete _;
    public NetworkManager receiver;
    public bool drop;
    public override bool Host(uint16 port)=>true;
    public override bool Connect(StringView address,uint16 port,out void* server) { server=null;return true; }
    public override bool Poll(out NetEvent event) { event=default;return false; }
    public override void Send(void* peer,Span<uint8> data,bool reliable)
    {
        bytes+=data.Length;maxPacket=Math.Max(maxPacket,data.Length);packets++;if(reliable)reliablePackets++;
        last.Clear();last.AddRange(data);
        if(receiver!=null && !drop)
        {
            var reader=NetReader(data.Ptr,data.Length);let type=reader.Read<uint8>();
            if(type==8)receiver.[Friend]ReadSnapshot(ref reader,true);
        }
    }
    public override void Disconnect(void* peer) {}
    public override void Flush() {}
    public override void Close() {}
    public void Reset() { bytes=0;packets=0;maxPacket=0;reliablePackets=0; }
}
class Program
{
    static bool ok=true;
    static void Check(bool pass,StringView label) { Console.WriteLine(scope $"{(pass ? "PASS" : "FAIL")}: {label}");ok &= pass; }
    static NetworkManager Setup(Scene scene,bool server)
    {
        let net=new NetworkManager(scene);scene.Network=net;net.[Friend]mMode=server ? .Server : .Client;
        net.LocalClientId=server ? -1 : 1;net.[Friend]mConnected=true;
        net.[Friend]RegisterSceneIdentities();return net;
    }
    static void Step(NetworkManager net,int ticks=3)
    { net.[Friend]mTick+=(uint32)ticks;net.[Friend]SendSnapshots(); }
    static void Codec()
    {
        let writer=scope NetWriter();
        for(int i<1000)
        {
            let position=Vector3(i*0.713f-340,-0.123456f,i*0.031f);
            let rotation=Quaternion.Euler(i*1.37f,i*2.71f,i*0.19f);
            writer.Clear();NetPack.WriteTransform(writer,position,rotation,true);
            var reader=NetReader(writer.Data.Ptr,writer.Data.Count);let flags=reader.Read<uint8>();
            Vector3 decoded;Quaternion turn;NetPack.ReadTransform(ref reader,flags,out decoded,out turn);
            if(!reader.Ok || writer.Data.Count!=14 || (decoded-position).Length>0.00012f || Math.Abs(Quaternion.Dot(turn,rotation))<0.99999f) { Check(false,"fine transform error bounds");return; }
        }
        Check(true,"1000 fine transforms stay within 0.12mm and rotation bounds");
        writer.Clear();let far=Vector3(9000,-25000,1.23456f);let q=Quaternion.Euler(17,83,9);
        NetPack.WriteTransform(writer,far,q,true);var reader=NetReader(writer.Data.Ptr,writer.Data.Count);
        let flags=reader.Read<uint8>();Vector3 decoded;Quaternion turn;NetPack.ReadTransform(ref reader,flags,out decoded,out turn);
        Check(flags==NetPack.FlagExactTransform && far==decoded && q==turn,"out-of-range quantization falls back to exact floats");
        for(int size<writer.Data.Count)
        { var shortReader=NetReader(writer.Data.Ptr,size);let f=shortReader.Read<uint8>();NetPack.ReadTransform(ref shortReader,f,out decoded,out turn);if(shortReader.Ok)ok=false; }
        Check(ok,"all truncated transform records are rejected");
    }
    static void Delivery()
    {
        let scene=scope Scene();let remote=scope Scene();
        let obj=scene.CreateGameObject("Prop");let identity=obj.AddComponent<NetworkIdentity>();identity.fullPrecision=true;identity.remoteFormat=.ExactTransform;
        let copy=remote.CreateGameObject("Prop");let other=copy.AddComponent<NetworkIdentity>();
        let net=Setup(scene,true);let client=Setup(remote,false);
        let transport=new CaptureTransport();net.[Friend]mTransport=transport;transport.receiver=client;
        net.[Friend]mClients.Add(new .());let connection=net.[Friend]mClients.Back;connection.id=1;connection.peer=(void*)1;
        net.OptimizeSnapshots=true;
        obj.Transform.Position=.(1.123456f,2,3);Step(net);
        Check(other.HasKeys && other.NewestKeyTick==3,"batched exact transform reaches client");
        Check(transport.maxPacket<=1100,"snapshot packets fit configured MTU limit");
        // A later snapshot for another object must not discard a delayed reliable final key for this one.
        let delayed=scope NetWriter();delayed.Data.AddRange(transport.last);
        transport.drop=true;obj.Transform.Position=.(4,2,3);Step(net);delayed.Data.Clear();delayed.Data.AddRange(transport.last);transport.drop=false;
        client.[Friend]mLastSnapshotTick=30;
        var rr=NetReader(delayed.Data.Ptr,delayed.Data.Count);rr.Read<uint8>();client.[Friend]ReadSnapshot(ref rr,true);
        Check(other.NewestKeyTick==6,"delayed object key survives a newer global packet tick");
        client.[Friend]mLastSnapshotTick=6;
        identity.ownerId=1;transport.Reset();Step(net);
        var ownReader=NetReader(transport.last.Ptr,transport.last.Count);ownReader.Read<uint8>();ownReader.Read<uint32>();ownReader.Read<uint32>();ownReader.Read<uint8>();ownReader.Read<int8>();ownReader.Read<uint16>();NetworkManager.ReadNetId(ref ownReader);
        Check(ownReader.Read<uint8>()==NetPack.FlagFull,"owner keeps exact BodyState despite remote transform option");
        identity.ownerId=0;identity.remoteIntervalTicks=12;obj.Transform.Position=.(5,2,3);transport.Reset();Step(net);
        Check(transport.bytes==13,"remote rate limit sends only heartbeat before due tick");
        Step(net,12);Check(transport.bytes>26,"pending changed transform is delivered once rate permits");
        // Add a player anchor and opt the prop into relevance.
        let player=scene.CreateGameObject("Player");let pi=player.AddComponent<NetworkIdentity>();pi.ownerId=1;pi.PrefabName.Set("anchor");pi.NetId=player.Id;net.[Friend]Register(pi);
        identity.distanceFiltered=true;net.SnapshotRelevanceRadius=1;transport.Reset();Step(net,12);
        Check(!connection.delivered.ContainsKey(identity.NetId),"out-of-radius state is removed from delivery history");
        obj.Transform.Position=.Zero;Step(net,12);
        Check(connection.delivered.ContainsKey(identity.NetId),"re-entering relevance forces a fresh transform");
        let removedId=identity.NetId;net.[Friend]Unregister(identity);scene.DestroyImmediate(obj);Check(!connection.delivered.ContainsKey(removedId),"destroy removes per-client delivery state");
    }
    static void Dormancy()
    {
        let scene=scope Scene();let obj=scene.CreateGameObject("Sleepy");obj.AddComponent<BoxCollider>();let body=obj.AddComponent<Rigidbody>();body.useGravity=false;
        let id=obj.AddComponent<NetworkIdentity>();id.fullPrecision=true;id.remoteFormat=.ExactTransform;id.dormantWhenSleeping=true;
        scene.StartPlay();let net=Setup(scene,true);let transport=new CaptureTransport();net.[Friend]mTransport=transport;net.OptimizeSnapshots=true;
        net.[Friend]mClients.Add(new .());let connection=net.[Friend]mClients.Back;connection.id=1;connection.peer=(void*)1;
        body.EnsureBody();body.Sleep();Step(net);Check(transport.reliablePackets==1,"sleeping final transform uses reliable delivery");
        transport.Reset();for(int i<100)Step(net);
        Check(transport.bytes==1300 && transport.reliablePackets==0,"sleeping objects need only session heartbeats across refresh periods");
        body.AddImpulse(.(0.01f,0,0));obj.Transform.Position=.(1,0,0);Step(net);Check(transport.bytes>1313,"wake resumes transform delivery");
    }
    static void BatchingAndBudget()
    {
        let scene=scope Scene();let remote=scope Scene();
        let copies=scope List<NetworkIdentity>();
        for(int i<512)
        {
            let obj=scene.CreateGameObject("Prop");obj.Transform.Position=.(i*0.01f,1,2);
            let id=obj.AddComponent<NetworkIdentity>();id.fullPrecision=true;id.remoteFormat=.ExactTransform;
            copies.Add(remote.CreateGameObject("Prop").AddComponent<NetworkIdentity>());
        }
        let net=Setup(scene,true);let client=Setup(remote,false);
        let transport=new CaptureTransport();net.[Friend]mTransport=transport;transport.receiver=client;
        net.[Friend]mClients.Add(new .());let connection=net.[Friend]mClients.Back;connection.id=1;connection.peer=(void*)1;
        net.OptimizeSnapshots=true;Step(net);
        bool all=true;for(let copy in copies)all &= copy.NewestKeyTick==3;
        Check(all && transport.packets>10 && transport.maxPacket<=1100,"all same-tick chunks arrive independently within MTU");
        net.SnapshotBytesPerSecond=10000;transport.Reset();
        for(let id in net.Identities)id.Transform.Position+=.(0,1,0);
        bool within=true;
        for(int i<110)
        {
            let before=transport.bytes;Step(net);within &= transport.bytes-before<=500;
        }
        all=true;for(let copy in copies)all &= copy.NewestKeyTick>3;
        Check(within && all,"budget caps every snapshot and oldest-first scheduling eventually delivers every prop");
        // A sleeping key must not extrapolate along the preceding moving trajectory.
        let copy=copies[0];copy.PushKey(1000,.(1,0,0),.Identity);copy.PushKey(1003,.(2,0,0),.Identity,true);
        BodyState state;copy.Sample(1006,3,out state);
        Check(state.position==Vector3(2,0,0) && state.linearVelocity==.Zero,"reliable sleep key stops extrapolation exactly");
    }
    public static int Main()
    {
        Time.DeltaTime=Time.FixedDeltaTime;Codec();Delivery();Dormancy();BatchingAndBudget();
        Console.WriteLine(ok ? "NETWORK BANDWIDTH TESTS PASSED" : "NETWORK BANDWIDTH TESTS FAILED");return ok ? 0 : 1;
    }
}
