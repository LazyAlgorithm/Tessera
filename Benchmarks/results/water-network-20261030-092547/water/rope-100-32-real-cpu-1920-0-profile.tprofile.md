# Tessera Profiler report

Frames 120 to 239 (120 recorded). Times are on the recording machine; GPU times lag the CPU by a frame or two.
Self time = time in a marker less the markers inside it. 'Present (waiting for the GPU)' and 'Sleep' are idle waits, not work.

## Frame times

| | average | median | 95% | 99% | worst | best |
|---|---|---|---|---|---|---|
| Frame interval (what players see) | 2.061 ms | 2.052 ms | 2.104 ms | 2.231 ms | 2.450 ms | 2.004 ms |
| CPU main thread | 2.038 ms | 2.030 ms | 2.082 ms | 2.208 ms | 2.417 ms | 1.982 ms |
| GPU | not recorded | | | | | |

Spikes (frames taking over twice the median interval): 0.

## Main thread by category (average self time per frame)

- Other: 2.010 ms
- Scripts: 0.018 ms
- Rendering: 0.009 ms
- Animation: 0.000 ms
- Audio: 0.000 ms
- Physics: 0.000 ms
- AI: 0.000 ms

## Thread 'Water Benchmark': markers by average self time per frame

| marker | category | self/frame | total/frame | calls/frame | worst frame total | in frames |
|---|---|---|---|---|---|---|
| Rope.LateUpdate() | Other | 1.495 ms | 1.495 ms | 100 | 1.877 ms | 120/120 |
| Frame | Other | 0.509 ms | 2.038 ms | 1 | 2.417 ms | 120/120 |
| LateUpdate (every component) | Scripts | 0.007 ms | 1.505 ms | 1 | 1.890 ms | 120/120 |
| OnFrame (every component) | Scripts | 0.006 ms | 0.012 ms | 1 | 0.045 ms | 120/120 |
| Update (every component) | Scripts | 0.005 ms | 0.012 ms | 1 | 0.016 ms | 120/120 |
| Rope.Update() | Other | 0.003 ms | 0.003 ms | 100 | 0.007 ms | 120/120 |
| MeshRenderer.OnFrame() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.009 ms | 120/120 |
| MeshRenderer.Update() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.007 ms | 120/120 |
| Rope.OnFrame() | Other | 0.003 ms | 0.003 ms | 100 | 0.006 ms | 120/120 |
| MeshRenderer.LateUpdate() | Rendering | 0.003 ms | 0.003 ms | 100 | 0.004 ms | 120/120 |
| IK | Animation | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Skinning | Animation | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Audio.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Start | Scripts | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Navigation Paths | AI | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| VoiceChat.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Destroy | Scripts | 0.000 ms | 0.000 ms | 1 | 0.001 ms | 120/120 |
| BoxCollider.Update() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.OnFrame() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| BoxCollider.OnFrame() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| BoxCollider.LateUpdate() | Physics | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.LateUpdate() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.Update() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |

## The 5 slowest frames (main thread call tree, rows over 0.05 ms)

### Frame 168: interval 2.450 ms, CPU 2.208 ms, GPU -

```
Frame  total 2.208 ms, self 0.581 ms
  LateUpdate (every component)  total 1.597 ms, self 0.007 ms
    Rope.LateUpdate()  total 1.587 ms, self 1.587 ms, 100 calls
```

### Frame 167: interval 2.014 ms, CPU 2.417 ms, GPU -

```
Frame  total 2.417 ms, self 0.494 ms
  LateUpdate (every component)  total 1.890 ms, self 0.009 ms
    Rope.LateUpdate()  total 1.877 ms, self 1.877 ms, 100 calls
```

### Frame 169: interval 2.231 ms, CPU 2.003 ms, GPU -

```
Frame  total 2.002 ms, self 0.479 ms
  LateUpdate (every component)  total 1.499 ms, self 0.007 ms
    Rope.LateUpdate()  total 1.489 ms, self 1.489 ms, 100 calls
```

### Frame 237: interval 2.148 ms, CPU 2.061 ms, GPU -

```
Frame  total 2.061 ms, self 0.540 ms
  LateUpdate (every component)  total 1.498 ms, self 0.007 ms
    Rope.LateUpdate()  total 1.488 ms, self 1.488 ms, 100 calls
```

### Frame 236: interval 2.072 ms, CPU 2.126 ms, GPU -

```
Frame  total 2.126 ms, self 0.610 ms
  LateUpdate (every component)  total 1.493 ms, self 0.007 ms
    Rope.LateUpdate()  total 1.483 ms, self 1.483 ms, 100 calls
```

## Counters (first, lowest, average, highest, last)


Counters in bytes are plain byte counts. Memory that grows from first to last without coming down can be a leak.
