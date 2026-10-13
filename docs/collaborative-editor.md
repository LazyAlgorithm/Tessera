# Collaborative editor — implementation plan (experimental branch)

Status: design groundwork only. No runtime synchronization is implemented yet.

## Existing Tessera integration points

- `Editor/src/App/EditorApp.bf`: owns scene, selection (`mSelectedId`), play state and editor lifecycle.
- `Editor/src/App/EditorScene.bf`: `MarkDirty`, `SaveScene`, `OpenScene`, `NewScene`; saving currently serializes the entire scene.
- `Editor/src/App/Undo.bf`: undo/redo stores full serialized scene snapshots; `ApplySnapshot` applies differences. This is **not** a safe multi-user undo model.
- `Editor/src/Scripts/ScriptEditor.bf`: script text lives in native `tn_code_*` editor handles and triggers background compilation on save. Collaborative cursors and text operations need an API at this native editor boundary.
- `Engine/src/Net/`: gameplay networking exists; editor collaboration must use a distinct session/protocol to avoid mixing gameplay authority with authoring.

## Safety constraints

1. Collaboration is opt-in and off by default.
2. Never overwrite local scene files from incoming messages without durable backup and explicit user action.
3. Do not transmit unsaved or private assets until a project/session is explicitly shared.
4. Reject incoming edits during play mode initially; the host coordinates an edit-mode-only session.
5. Keep the existing local undo behavior for offline/single-user editing. Shared undo must invert **authored operations**, not restore a full-scene snapshot.
6. All remotely referenced objects need persistent, globally unique IDs. Existing `uint32` scene IDs must be mapped to stable collaboration IDs, with mapping persisted across save/reload.

## Proposed protocol v1

Each operation carries `sessionId`, `authorId`, `operationId`, `baseRevision`, `entityGuid`, `kind`, `payload`, and `timestamp` (timestamp is informational, never an authority for ordering). The host assigns monotonically increasing committed revisions and deduplicates operation IDs.

Initial kinds: `CreateEntity`, `DeleteEntity`, `SetComponentProperty`, `ReparentEntity`. Transform drags use a short-lived ownership lease; the host validates every operation and rejects conflicting hierarchy cycles, missing entities, or stale leases.

Presence (`selection`, `cursor`, `camera`, `displayName`, `color`) is ephemeral, rate-limited and not written to project history.

## Phase plan

1. **Discovery and identity**: inspect scene serialization and object creation paths; add stable GUID mapping and tests before networking.
2. **Live sessions**: opt-in host/join, connection status and presence, transport authentication, version handshake, snapshot + operation replay.
3. **Scene operations**: route local edit commands through one operation API; support transforms, properties, hierarchy, create/delete, validation and inverse operations.
4. **Scripts**: add native editor change callbacks, integrate a tested sequence CRDT, remote cursor overlays and compilation debounce.
5. **Offline-first**: append-only local journal, idempotent replay, durable snapshots, causal reconciliation and explicit conflicts for incompatible binary assets.
6. **Git**: user-controlled commits/branches and LFS for large assets; never commit each keystroke.

## Acceptance tests before claiming functional support

- Two editor processes converge after interleaved independent edits.
- A disconnected editor rejoins and replays each operation exactly once.
- Delete vs. edit, concurrent reparent, and concurrent transform produce deterministic outcomes.
- Local undo never silently reverses another author's changes.
- Malformed and unauthorized operations cannot corrupt or overwrite the project.
- Existing single-user project open/save/play behavior remains unchanged.

## Immediate next engineering task

Inspect `SceneSerializer`, `GameObject` IDs and editor mutation sites to establish persistent GUIDs and a single mutation hook. Do not wire network replication directly into `MarkDirty`: it signals unspecific changes and cannot identify the edit or its author.

## Connectivity requirement: no manual port forwarding, no dedicated session server

**Preferred mode: direct peer-to-peer.** One editor instance acts as the session authority; every participant retains a local project copy. Do not require inbound router configuration or a permanently hosted Tessera collaboration server.

- Use ICE-style connectivity checks and UDP NAT hole punching where possible. A STUN service can discover public-facing addresses; STUN is infrastructure, not a project-hosting server.
- Provide an out-of-band, copy/paste invitation exchange (offer/answer or candidate exchange) so Tessera does not require its own signaling service. Both peers may need to exchange messages more than once during negotiation.
- Encrypt and authenticate the peer channel; invitation material must be short-lived and bound to a session key. Require explicit host approval for joining and project sharing.
- Discover LAN peers automatically as a convenience, but never expose an unauthenticated editing endpoint.
- Detect and clearly report NAT/firewall combinations that prohibit direct connections. **No-port-forwarding plus no relay cannot guarantee connectivity across all networks.** A future opt-in TURN/relay mode can improve reachability, but would use a server.
- Reconnection must use durable operation IDs and host-authoritative revision checkpoints, independent of the transport.
- Do not assume the existing gameplay networking implements ICE, STUN, NAT punching, or authenticated editor transport; inspect before selecting dependencies.

### First transport milestone

Two desktop editors on separate networks exchange invitations out of band, establish an authenticated encrypted direct channel without router changes where NAT traversal permits, and transfer a read-only session handshake. Keep scene mutations disabled until protocol validation and operation identity are complete.
