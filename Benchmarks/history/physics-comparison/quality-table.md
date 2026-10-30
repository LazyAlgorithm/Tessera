> Historical standalone backend benchmark; no Tessera runtime. Full source/data bundle: [physics-engine-results.zip](physics-engine-results.zip).

| Engine | Native count | Mean center height (m) | Bodies with centers below 0.6 m | RMS linear speed (m/s) |
|---|---:|---:|---:|---:|
| Jolt | 1 | 7.7578 | 256 / 4,000 | 0.702319 |
| Jolt | 4 | 7.8180 | 256 / 4,000 | 0.033282 |
| Box3D | 1 | 7.1195 | 256 / 4,000 | 0.213138 |
| Box3D | 4 | 7.7781 | 256 / 4,000 | 0.001420 |
| Rapier | 1 | 4.1441 | 715 / 4,000 | 1.292996 |
| Rapier | 4 | 7.7781 | 256 / 4,000 | 0.002321 |
| Bullet | 1 | 6.9587 | 320 / 4,000 | 3.550195 |
| Bullet | 4 | 7.8188 | 256 / 4,000 | 0.011214 |
