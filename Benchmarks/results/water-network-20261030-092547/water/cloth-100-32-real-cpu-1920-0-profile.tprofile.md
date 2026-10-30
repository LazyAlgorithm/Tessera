# Tessera Profiler report

Frames 120 to 239 (120 recorded). Times are on the recording machine; GPU times lag the CPU by a frame or two.
Self time = time in a marker less the markers inside it. 'Present (waiting for the GPU)' and 'Sleep' are idle waits, not work.

## Frame times

| | average | median | 95% | 99% | worst | best |
|---|---|---|---|---|---|---|
| Frame interval (what players see) | 14.858 ms | 14.856 ms | 15.212 ms | 15.376 ms | 15.380 ms | 14.327 ms |
| CPU main thread | 14.830 ms | 14.829 ms | 15.181 ms | 15.351 ms | 15.354 ms | 14.298 ms |
| GPU | not recorded | | | | | |

Spikes (frames taking over twice the median interval): 0.

## Main thread by category (average self time per frame)

- Other: 14.799 ms
- Scripts: 0.019 ms
- Rendering: 0.010 ms
- Audio: 0.000 ms
- Animation: 0.000 ms
- Physics: 0.000 ms
- AI: 0.000 ms

## Thread 'Water Benchmark': markers by average self time per frame

| marker | category | self/frame | total/frame | calls/frame | worst frame total | in frames |
|---|---|---|---|---|---|---|
| Frame | Other | 9.610 ms | 14.829 ms | 1 | 15.354 ms | 120/120 |
| SoftBody.LateUpdate() | Other | 5.183 ms | 5.183 ms | 100 | 5.644 ms | 120/120 |
| OnFrame (every component) | Scripts | 0.007 ms | 0.014 ms | 1 | 0.034 ms | 120/120 |
| LateUpdate (every component) | Scripts | 0.007 ms | 5.193 ms | 1 | 5.656 ms | 120/120 |
| Update (every component) | Scripts | 0.005 ms | 0.012 ms | 1 | 0.018 ms | 120/120 |
| MeshRenderer.LateUpdate() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.030 ms | 120/120 |
| MeshRenderer.Update() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.005 ms | 120/120 |
| SoftBody.OnFrame() | Other | 0.003 ms | 0.003 ms | 100 | 0.007 ms | 120/120 |
| MeshRenderer.OnFrame() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.005 ms | 120/120 |
| SoftBody.Update() | Other | 0.003 ms | 0.003 ms | 100 | 0.005 ms | 120/120 |
| VoiceChat.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| Audio.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| Skinning | Animation | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| IK | Animation | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| BoxCollider.OnFrame() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Navigation Paths | AI | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.OnFrame() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Start | Scripts | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| BoxCollider.Update() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| BoxCollider.LateUpdate() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.LateUpdate() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Destroy | Scripts | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.Update() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |

## The 5 slowest frames (main thread call tree, rows over 0.05 ms)

### Frame 232: interval 15.380 ms, CPU 14.552 ms, GPU -

```
Frame  total 14.552 ms, self 9.531 ms
  LateUpdate (every component)  total 4.995 ms, self 0.007 ms
    SoftBody.LateUpdate()  total 4.986 ms, self 4.986 ms, 100 calls
```

### Frame 238: interval 15.376 ms, CPU 15.314 ms, GPU -

```
Frame  total 15.313 ms, self 9.861 ms
  LateUpdate (every component)  total 5.426 ms, self 0.007 ms
    SoftBody.LateUpdate()  total 5.416 ms, self 5.416 ms, 100 calls
```

### Frame 231: interval 14.742 ms, CPU 15.354 ms, GPU -

```
Frame  total 15.354 ms, self 9.899 ms
  LateUpdate (every component)  total 5.422 ms, self 0.007 ms
    SoftBody.LateUpdate()  total 5.412 ms, self 5.412 ms, 100 calls
```

### Frame 237: interval 14.902 ms, CPU 15.351 ms, GPU -

```
Frame  total 15.351 ms, self 10.080 ms
  LateUpdate (every component)  total 5.245 ms, self 0.007 ms
    SoftBody.LateUpdate()  total 5.235 ms, self 5.235 ms, 100 calls
```

### Frame 239: interval 15.344 ms, CPU 15.012 ms, GPU -

```
Frame  total 15.011 ms, self 9.702 ms
  LateUpdate (every component)  total 5.284 ms, self 0.007 ms
    SoftBody.LateUpdate()  total 5.274 ms, self 5.274 ms, 100 calls
```

## Counters (first, lowest, average, highest, last)


Counters in bytes are plain byte counts. Memory that grows from first to last without coming down can be a leak.
