# Optional snapshot bandwidth controls

Baseline: GitHub main `3d0fcc7c075c2112946ec8d0299695a923d4ef83`, verified against local files before editing. Engine, editor, scripts and native sources matched; 46 third-party example/project files differed only in newline representation. There were no missing files. The original source is retained locally under `/home/zerker24/NetworkingReview/baseline`.

All new behavior is opt-in. Existing scenes keep their legacy snapshot format and rates. Owner prediction always receives the full exact BodyState. Inputs already use packed button bits and quantized controls.

Set `NetworkManager.OptimizeSnapshots=true` on the server to use individually decodable snapshot packets (default payload ceiling 1100 bytes, configurable 256..1200). Packets from the same tick are accepted independently; delayed reliable final keys are checked by object tick, rather than discarded by the newest global tick. This avoids one enormous fragmented snapshot delaying every object and prediction correction. Optimized packets use a new message type: all peers must run this engine version before enabling them.

Per NetworkIdentity:

- `remoteFormat=Legacy`: retain existing compact/fullPrecision selection.
- `remoteFormat=ExactTransform`: exact position/quaternion only for nonowners (29 bytes including flags, plus object ID). No numerical precision loss.
- `remoteFormat=QuantizedTransform`: signed 24-bit positions at 10,000 steps/world unit, and the existing smallest-three quaternion (14 bytes including flags, plus ID). In metre-based worlds the position step is 0.1mm, with a conservative 0.12mm tested vector error bound. Positions outside +/-838 world units fall back to exact floats. Quaternion quantization has a separate bounded angular error. These affect remote interpolation, never host physics or owner prediction.
- `remoteIntervalTicks`: zero uses the global interval; e.g. 6 gives at most 10Hz at 60 server ticks. Lower rates can reduce visual responsiveness.
- `dormantWhenSleeping`: send a reliable final transform, then omit refreshes until wake/change. New clients get the sleeping state reliably. Sleep keys stop extrapolation; wake/change resumes updates. An unchanged transform never relies on an unacknowledged delta baseline.
- `distanceFiltered`: allow the session relevance radius to omit this object's remote transforms. Owned state is exempt. Re-entry forces updates even if stationary. This filters transforms only, not spawns, visibility or gameplay events.
- `snapshotPriority`: larger values are serviced first under budget, then oldest-delivered first within equal priority. Persistent high-priority traffic can delay lower-priority objects.

Per NetworkManager:

- `SnapshotBytesPerSecond`: optional per-client snapshot application-payload budget. Zero is unlimited. Reserves exact own prediction first; owner traffic can exceed an impossibly small budget. Integer scheduling uses a minimum 128 bytes per snapshot, so configured rates below that floor cannot be enforced. Does not cap reliable spawns, gameplay messages or transport overhead/retransmissions. Those must be included separately in hosting estimates.
- `SnapshotRelevanceRadius`: world-unit distance from the client's player, only for opted-in identities. Zero disables; no anchor means no filtering.
- `LosslessCompression`: ENet's range coder, set on BOTH endpoints before StartServer/StartClient. UDP payload compression is lossless for every float bit. Steam/WebRTC remain unchanged. Allocation/setup failure fails session startup instead of silently enabling only one end.
- `ProfileSnapshots`: opt-in CPU timing for snapshot encode/decode; exposes cumulative time, call counts and worst-call time. These are distinct from elapsed frame intervals.
- `WireBytesSent/Received`: ENet UDP payload totals including protocol headers, compression and retransmissions. They exclude IP/UDP headers. Application counters still measure messages before simulated packet loss and compression. Steam/WebRTC return zero (unsupported measurement), not a wire estimate.

The test fixture profiles are baseline, exact, quantized, sleep, rate, budget, compressed and all. They do not change normal game settings. `all` uses quantized transforms at 10Hz, dormancy and ENet compression; it does not enable relevance or a budget, keeping all 4096 props in the scaling workload. The budget profile exercises a 500,000 B/s per-client application snapshot allowance. Dedicated field-by-field deltas (position vs rotation etc.) are deliberately deferred at the user's request.

Tests: `python tools/run_network_bandwidth_tests.py --engine <engine-root>`. These exercise serialization, quantization error/fallback/truncation, ownership, same-tick batching, delayed final keys, rate limits, relevance/re-entry, destruction cleanup, actual native-body dormancy/wake, budget fairness and stopped extrapolation without requiring sockets. The game runner uses actual UDP host/client processes and checks each client's prediction, crash recovery and all-prop convergence. No headless test establishes visual quality or real internet/Steam behavior.
