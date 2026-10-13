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

## Updated product requirement: project-centric offline-first collaboration

Collaboration belongs to a **persistent project**, not an ephemeral host session. Every authorized member keeps a complete local project copy and may edit offline. A coordinator is elected only to sequence connected edits; it is not the project owner.

### Project identity and authorization

- Generate a persistent project UUID and a creator public-key identity at project creation. Member identities use independent signing keys, not display names or editable Git author fields.
- Maintain a signed membership/role manifest with monotonically increasing membership epochs. Only the creator key can add/remove members, change roles, or transfer ownership (explicit signed transfer).
- Creator-only permissions must be enforced cryptographically by peers and during merge. Git repository permissions and a read-only editor panel alone do not enforce ownership on independently hosted copies. An offline revoked member may retain their existing copy; future secrecy requires key rotation and has unavoidable limitations.
- Store creator-signed governance events in an append-only history. Peers verify signatures and hashes before accepting them. Preserve authorship of every operation with an author signature and causal metadata.

### Replication and offline merge

- Each member persists local operations and assets, a last-known shared checkpoint, and causal frontier. Local editing never requires the coordinator.
- On reconnect, exchange manifests and missing content hashes, authenticate peers, reconcile causal histories, merge non-conflicting operations and show unresolved semantic conflicts to users. Do not silently choose a winner for destructive conflicting changes.
- Text documents use a tested CRDT with stable character identifiers. Scene structure uses typed operations and validation; binary assets use versioned content hashes and explicit conflict choices.
- Retain enough operation history for rejoining long-offline members; garbage collection and compaction require safe checkpoints and retention policy.

### Coordinator migration and partitions

- A coordinator sequences connected operations and periodically replicates its committed log. On coordinator loss, peers pause **shared commits** while retaining local edit capability.
- A replacement is elected only with an agreed membership epoch and quorum of eligible reachable peers. Without quorum, operate offline and reconcile later; never present a partition as fully synchronized.
- Rejoining old coordinators must catch up before they can coordinate. Handle simultaneous coordinator loss, stale revisions, and conflicting governance epochs.
- No central service means peers must exchange rendezvous/invitation information out of band and may be unable to connect through some NAT/firewall configurations.

### Contribution attribution and Git

- Record signed per-operation author, affected entity/component/document, operation category, causal parent(s), and accepted/reverted state. Aggregate per-member activity by file, scene, component, and time period.
- Clearly distinguish **activity metrics** (operations/lines/objects) from actual impact or quality; deduplicate retries, exclude remote replays, and count reversions appropriately.
- Generate Git commits/snapshots from validated shared checkpoints, with commit metadata and optional per-author summaries. Do not rely on Git author strings as trusted provenance.
- The creator has exclusive authority to change membership and ownership metadata; **everyone may view** contribution history. Project creators cannot prevent a local Git clone holder from editing their own history, but peers can reject unsigned/invalid governance history.

### Proposed milestone order

1. Persistent project/member identities, signed manifest, and local operation journal.
2. Deterministic scene operation model and local undo isolation.
3. Peer reconciliation and explicit conflict review using two local project copies (no networking yet).
4. P2P authenticated transport, live presence, and synchronization.
5. Coordinator election/failover, partitions and recovery.
6. Collaborative text editing, asset exchange, contribution dashboard, and Git snapshots.

**Status:** design only; no implementation or runtime validation claimed.

## GitHub-backed project workflow: owner-approved collaboration branches

- Authenticate desktop users with a GitHub App OAuth/device flow and minimal repository permissions. GitHub identity is for attribution and repository authorization; P2P membership is authenticated independently.
- Each persistent Tessera project references an owner-controlled upstream GitHub repository and default branch. Contributors can keep local clones and optionally individual forks/independent remotes.
- Each collaborative workstream has a stable named branch such as `collab/level-design-01`. The branch represents the workstream, **not** the lifetime of a P2P connection; users can leave, rejoin, and work offline.
- Local edits are journaled immediately. Reconnecting peers reconcile and validate changes before generating a Git checkpoint. A single integration coordinator prepares canonical checkpoint commits so shared operations are not duplicated across forks.
- A designated integration actor with appropriate GitHub permissions pushes the collaboration branch to upstream or an authorized fork and opens/updates a pull request. If contributors lack upstream write access, use an authorized owner-side integration process or PR from a fork; never assume a peer can push upstream.
- The owner reviews and explicitly merges the PR to the protected default branch, or leaves the branch open/archives it. **Session end must never automatically merge to main.**
- Keep creator/owner authority separate from ephemeral coordinator election. Changing P2P coordinator must not grant GitHub repository write access.
- Show GitHub commit and PR provenance alongside Tessera's signed per-operation contribution log. Do not count replicated operations twice.
- Handle stale collaboration branches, base-branch updates, conflicting Git commits, failed pushes, and offline peers before finalizing checkpoints. Ensure user approval for destructive history rewriting.

Status: product and technical specification only; no working branch-sync implementation yet.
