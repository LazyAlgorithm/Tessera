# Tessera Profiler report

Frames 120 to 239 (120 recorded). Times are on the recording machine; GPU times lag the CPU by a frame or two.
Self time = time in a marker less the markers inside it. 'Present (waiting for the GPU)' and 'Sleep' are idle waits, not work.

## Frame times

| | average | median | 95% | 99% | worst | best |
|---|---|---|---|---|---|---|
| Frame interval (what players see) | 1.713 ms | 1.713 ms | 1.729 ms | 1.770 ms | 1.945 ms | 1.526 ms |
| CPU main thread | 1.289 ms | 1.286 ms | 1.298 ms | 1.346 ms | 1.526 ms | 1.273 ms |
| GPU | not recorded | | | | | |

Spikes (frames taking over twice the median interval): 0.

## Main thread by category (average self time per frame)

- Other: 0.777 ms
- Scripts: 0.234 ms
- Physics: 0.185 ms
- Rendering: 0.093 ms
- Audio: 0.000 ms
- Animation: 0.000 ms
- AI: 0.000 ms

## Thread 'Water Benchmark': markers by average self time per frame

| marker | category | self/frame | total/frame | calls/frame | worst frame total | in frames |
|---|---|---|---|---|---|---|
| Frame | Other | 0.776 ms | 1.289 ms | 1 | 1.525 ms | 120/120 |
| OnFrame (every component) | Scripts | 0.081 ms | 0.173 ms | 1 | 0.272 ms | 120/120 |
| Update (every component) | Scripts | 0.077 ms | 0.170 ms | 1 | 0.227 ms | 120/120 |
| LateUpdate (every component) | Scripts | 0.076 ms | 0.170 ms | 1 | 0.258 ms | 120/120 |
| MeshRenderer.LateUpdate() | Rendering | 0.031 ms | 0.031 ms | 1000 | 0.102 ms | 120/120 |
| MeshRenderer.Update() | Rendering | 0.031 ms | 0.031 ms | 1000 | 0.073 ms | 120/120 |
| BoxCollider.OnFrame() | Physics | 0.031 ms | 0.031 ms | 1001 | 0.059 ms | 120/120 |
| MeshRenderer.OnFrame() | Rendering | 0.031 ms | 0.031 ms | 1000 | 0.048 ms | 120/120 |
| BoxCollider.LateUpdate() | Physics | 0.031 ms | 0.031 ms | 1001 | 0.037 ms | 120/120 |
| Rigidbody.LateUpdate() | Physics | 0.031 ms | 0.031 ms | 1000 | 0.036 ms | 120/120 |
| Rigidbody.Update() | Physics | 0.031 ms | 0.031 ms | 1000 | 0.037 ms | 120/120 |
| BoxCollider.Update() | Physics | 0.031 ms | 0.031 ms | 1001 | 0.036 ms | 120/120 |
| Rigidbody.OnFrame() | Physics | 0.031 ms | 0.031 ms | 1000 | 0.035 ms | 120/120 |
| Audio.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| VoiceChat.Update | Audio | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| IK | Animation | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Navigation Paths | AI | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Skinning | Animation | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Start | Scripts | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.OnFrame() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.Update() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Water.LateUpdate() | Other | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |
| Destroy | Scripts | 0.000 ms | 0.000 ms | 1 | 0.000 ms | 120/120 |

## The 5 slowest frames (main thread call tree, rows over 0.05 ms)

### Frame 121: interval 1.945 ms, CPU 1.277 ms, GPU -

```
Frame  total 1.277 ms, self 0.769 ms
  OnFrame (every component)  total 0.174 ms, self 0.081 ms
  LateUpdate (every component)  total 0.167 ms, self 0.076 ms
  Update (every component)  total 0.167 ms, self 0.076 ms
```

### Frame 185: interval 1.770 ms, CPU 1.308 ms, GPU -

```
Frame  total 1.308 ms, self 0.781 ms
  Update (every component)  total 0.187 ms, self 0.095 ms
  OnFrame (every component)  total 0.171 ms, self 0.079 ms
  LateUpdate (every component)  total 0.169 ms, self 0.077 ms
```

### Frame 227: interval 1.737 ms, CPU 1.286 ms, GPU -

```
Frame  total 1.286 ms, self 0.773 ms
  OnFrame (every component)  total 0.176 ms, self 0.084 ms
  Update (every component)  total 0.169 ms, self 0.077 ms
  LateUpdate (every component)  total 0.168 ms, self 0.076 ms
```

### Frame 147: interval 1.731 ms, CPU 1.292 ms, GPU -

```
Frame  total 1.292 ms, self 0.775 ms
  LateUpdate (every component)  total 0.174 ms, self 0.077 ms
  OnFrame (every component)  total 0.173 ms, self 0.080 ms
  Update (every component)  total 0.170 ms, self 0.077 ms
```

### Frame 201: interval 1.730 ms, CPU 1.288 ms, GPU -

```
Frame  total 1.288 ms, self 0.778 ms
  OnFrame (every component)  total 0.172 ms, self 0.081 ms
  Update (every component)  total 0.170 ms, self 0.078 ms
  LateUpdate (every component)  total 0.168 ms, self 0.076 ms
```

## Counters (first, lowest, average, highest, last)


Counters in bytes are plain byte counts. Memory that grows from first to last without coming down can be a leak.
