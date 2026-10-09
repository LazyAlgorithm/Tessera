using System;
using System.Collections;

namespace Tessera;

/// How a network session reaches other machines.
[Reflect(.All)]
enum NetworkTransportKind : int32
{
	/// UDP straight to an IP address and port (ENet). Works on a LAN, or over the internet with the port forwarded.
	Direct,
	/// Through Steam: players are found by Steam ID and traffic goes over Steam's relay network, so nobody
	/// forwards a port or reveals an address. Needs the Steam client running.
	Steam
}

enum NetEventKind { Connected, Disconnected, Data }

struct NetEvent
{
	public NetEventKind kind;
	/// Who it concerns; the same value is passed back to Send.
	public void* peer;
	/// Valid until the next call to Poll.
	public uint8* data;
	public int length;
}

/// Carries packets for NetworkManager. One reliable ordered stream and one unreliable stream per peer.
abstract class NetTransport
{
	/// Starts accepting connections.
	public abstract bool Host(uint16 port);
	/// Starts connecting to a host. A Connected event follows when it succeeds.
	public abstract bool Connect(StringView address, uint16 port, out void* server);
	/// Next thing that happened, or false when there is nothing more for now.
	public abstract bool Poll(out NetEvent event);
	public abstract void Send(void* peer, Span<uint8> data, bool reliable);
	public abstract void Disconnect(void* peer);
	/// Pushes queued packets out now.
	public abstract void Flush();
	public abstract void Close();

	public static NetTransport Create(NetworkTransportKind kind)
	{
		switch (kind)
		{
		case .Steam: return new SteamTransport();
		case .Direct: return new ENetTransport();
		}
	}
}

/// UDP through ENet.
class ENetTransport : NetTransport
{
	static bool sReady;
	void* mHost;
	ENet.Packet* mHeld;

	public this()
	{
		if (!sReady)
		{
			ENet.enet_initialize();
			sReady = true;
		}
	}

	public ~this() { Close(); }

	public override bool Host(uint16 port)
	{
		Close();
		ENet.Address address;
		address.host = 0;
		address.port = port;
		mHost = ENet.enet_host_create(&address, 32, 2, 0, 0);
		if (mHost == null)
			Log.Error(scope $"Could not open UDP port {port}.");
		return mHost != null;
	}

	public override bool Connect(StringView address, uint16 port, out void* server)
	{
		Close();
		server = null;
		mHost = ENet.enet_host_create(null, 1, 2, 0, 0);
		if (mHost == null)
			return false;
		ENet.Address target = default;
		ENet.enet_address_set_host(&target, scope String(address).CStr());
		target.port = port;
		server = ENet.enet_host_connect(mHost, &target, 2, 0);
		if (server == null)
		{
			Close();
			return false;
		}
		return true;
	}

	void Release()
	{
		if (mHeld != null)
			ENet.enet_packet_destroy(mHeld);
		mHeld = null;
	}

	public override bool Poll(out NetEvent event)
	{
		event = default;
		Release();
		if (mHost == null)
			return false;
		ENet.Event raw = default;
		while (ENet.enet_host_service(mHost, &raw, 0) > 0)
		{
			event.peer = raw.peer;
			switch (raw.type)
			{
			case ENet.EventConnect:
				event.kind = .Connected;
				return true;
			case ENet.EventDisconnect:
				event.kind = .Disconnected;
				return true;
			case ENet.EventReceive:
				event.kind = .Data;
				event.data = raw.packet.data;
				event.length = (int)raw.packet.dataLength;
				mHeld = raw.packet;
				return true;
			default:
			}
		}
		return false;
	}

	public override void Send(void* peer, Span<uint8> data, bool reliable)
	{
		if (mHost == null || peer == null)
			return;
		let packet = ENet.enet_packet_create(data.Ptr, (uint)data.Length, reliable ? ENet.FlagReliable : 0);
		ENet.enet_peer_send(peer, reliable ? 0 : 1, packet);
	}

	public override void Disconnect(void* peer)
	{
		if (mHost != null && peer != null)
			ENet.enet_peer_disconnect_now(peer, 0);
	}

	public override void Flush()
	{
		if (mHost != null)
			ENet.enet_host_flush(mHost);
	}

	public override void Close()
	{
		Release();
		if (mHost != null)
		{
			ENet.enet_host_flush(mHost);
			ENet.enet_host_destroy(mHost);
		}
		mHost = null;
	}
}
