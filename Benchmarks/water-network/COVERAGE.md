# Networking coverage ledger

Baseline engine revision: `6cfa1faa` (Linux desktop); the report separately records the tested buoyancy rollback patch. These checks exercise existing networked features; the full CPU suite additionally checks engine behavior outside networking. Passing the CPU suite does not imply every engine component has its own replication protocol.

| Area | Evidence |
|---|---|
| Map sharing, chunked 3 MB downloads, hash verification, version replacement, missing maps | Maps fixture (additional to the listed 53 fixtures) |
| Server lag compensation and shot rewind | Network fixture |
| Session lifecycle, player identities, host/client, kicking, offline behavior | Network fixture; independent-process UDP load harness |
| Automatic identities, transforms, rigid bodies, player input and smoothing | Network and PhysicsPrediction fixtures; UDP load harness |
| `[Sync]` fields, server authority, events, spawn/despawn, late join | Network fixture |
| Voxel object edits and voxel terrain edits | Network fixture, workflow byte deltas |
| Audio playback, animator parameters, materials | Network fixture, workflow byte deltas |
| Character shape changes | Network and CharacterController fixtures |
| Switches, lights, particles and decals | Network fixture; repeated light changes in mixed load scenario |
| Dialogue and sequences | Dialogue and Sequencer fixtures in complete CPU run |
| Soft-body position, shell dents/repair, authority and late joins | SoftBodies fixture |
| Rope ties, ownership, snapping, release and late joins | SoftBodies fixture |
| Water settings/level, shared clock, late joins, floating props | Water fixture; independent-process water load harness |
| Voice encoding/playback/relay, teams, proximity, mute, loss, flooding, malformed packets | Voice fixture; synthetic tone input, no microphone hardware required |
| Quantization bounds/fallback, truncation, compression exactness and allocation limits | NetworkBandwidth fixture |
| Batching, MTU, budgets, relevance re-entry, sleep/wake, stale keys, coherent ownership correction | NetworkBandwidth fixture |
| Physics rollback and replay, mixed physics/controller prediction | PhysicsPrediction fixture |
| Invalid inputs, message floods, speed manipulation, file integrity and server enforcement | AntiCheat fixture |
| HTTPS, missing resources, downloads and cancellation | Http fixture in complete CPU run |
| Steam unavailable-library behavior and transport-independent compressed framing | Network/NetworkBandwidth fixtures; framed UDP load profile |

## Transport limits

Real ENet UDP sockets were used, including separate host/client processes in the load tests. Delay/jitter/loss use the engine's application send simulator. This is not a router/NIC impairment test; ENet's own control datagrams are not independently lost by that simulator. Wire counters measure ENet UDP payload bytes, including ENet headers, compression and retransmissions, but exclude IP/UDP/link headers.

Live Steam transport was unavailable (`libsteam_api.so` missing). Framing over UDP validates the common compression format, not live Steam sessions. Browser/WebRTC, consoles/mobile devices, NAT traversal, distant internet servers and long-duration endurance sessions were not validated by this desktop run.

The load harness validates final convergence after authoritative freezing; prediction fixtures provide separate movement/rollback checks. Final convergence alone is not a visual smoothness guarantee during motion. Optional optimized load settings change snapshot cadence and physics prediction policy as well as compression: they are configuration comparisons, not compression-only speedups.
