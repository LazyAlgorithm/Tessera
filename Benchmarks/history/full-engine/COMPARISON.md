> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Tessera performance comparison

Updated 2026-10-27 21:24:03 CDT. Performance measurements only.

Builds: Tessera Beef Release/native -O3 (ThinLTO unavailable); Unity 6000.3.27f1 LTS, nondevelopment Mono standalone, Vulkan. Hardware: see per-run environment.json.

Results are medians of per-process medians, in milliseconds. Query samples contain 1,000 queries. Tail columns are the median of each process’s p95. Native rendering differs in image quality; these intervals are not GPU-only times. Missing values mean no complete measurement, not zero.

## Physics

| Workload | Population / batch size | Tessera median ms | Unity median ms | Tessera p95 ms | Unity p95 ms |
|---|---:|---:|---:|---:|---:|
| physics-boxcast | 100 | 0.5574 | 0.3960 | 0.5636 | 0.4022 |
| physics-boxcast | 1000 | 0.7868 | 0.5755 | 0.7914 | 0.5867 |
| physics-capsulecast | 100 | 0.5935 | 0.4133 | 0.6003 | 0.4188 |
| physics-capsulecast | 1000 | 0.8920 | 0.6279 | 0.9001 | 0.6425 |
| physics-ccd | 100 | 0.0549 | 0.2152 | 0.0635 | 0.2813 |
| physics-ccd | 1000 | 0.4729 | 1.3486 | 0.4992 | 1.5440 |
| physics-characters-flat | 100 | 0.0898 | 0.1262 | 0.0989 | 0.1522 |
| physics-characters-flat | 1000 | 0.7899 | 0.8687 | 0.8520 | 0.9955 |
| physics-characters-steps | 100 | 0.0904 | 0.0880 | 0.0966 | 0.1144 |
| physics-characters-steps | 1000 | 0.7878 | 0.8396 | 0.8350 | 0.9905 |
| physics-check-box | 1000 | 1.2974 | — | 1.3161 | — |
| physics-check-capsule | 1000 | 0.6880 | — | 0.7119 | — |
| physics-check-sphere | 1000 | 0.5981 | — | 0.6335 | — |
| physics-discrete | 100 | 0.0294 | 0.0401 | 0.0484 | 0.0516 |
| physics-discrete | 1000 | 0.1850 | 0.2183 | 0.2003 | 0.2614 |
| physics-free | 100 | 0.0224 | 0.0389 | 0.0296 | 0.0519 |
| physics-free | 1000 | 0.1302 | 0.1771 | 0.1446 | 0.2396 |
| physics-joints | 1 | 0.0127 | 0.0252 | 0.0178 | 0.0391 |
| physics-joints | 100 | 0.0768 | 0.0677 | 0.0866 | 0.1072 |
| physics-mesh | 100 | 0.0477 | 0.1151 | 0.0555 | 0.1301 |
| physics-mesh | 1000 | 0.6795 | 0.6315 | 0.7090 | 0.7608 |
| physics-mesh-raycast | 100 | 0.3942 | 0.2951 | 0.3990 | 0.3014 |
| physics-mesh-raycast | 1000 | 0.5409 | 0.4109 | 0.5466 | 0.4252 |
| physics-mixed-shapes | 100 | 0.0449 | 0.0634 | 0.0540 | 0.0769 |
| physics-mixed-shapes | 1000 | 0.5036 | 0.5272 | 0.5998 | 0.6832 |
| physics-overlap-box | 100 | 0.4432 | 0.1929 | 0.4579 | 0.1995 |
| physics-overlap-box | 1000 | 1.3483 | 0.2647 | 1.3675 | 0.2762 |
| physics-overlap-capsule | 100 | 1.1373 | 0.1812 | 1.1622 | 0.1859 |
| physics-overlap-capsule | 1000 | 2.6929 | 0.2882 | 2.7248 | 0.3082 |
| physics-overlap-sphere | 100 | 2.0720 | 0.1977 | 2.1023 | 0.2092 |
| physics-overlap-sphere | 1000 | 6.6828 | 0.4195 | 6.6967 | 0.4250 |
| physics-pile | 100 | 0.0714 | 0.1042 | 0.0776 | 0.1199 |
| physics-pile | 1000 | 0.6953 | 0.5208 | 0.7688 | 0.6657 |
| physics-raycast | 100 | 0.1483 | 0.2375 | 0.1527 | 0.2460 |
| physics-raycast | 1000 | 0.2893 | 0.3535 | 0.2964 | 0.3625 |
| physics-spherecast | 100 | 0.5293 | 0.3826 | 0.5364 | 0.3907 |
| physics-spherecast | 1000 | 0.8204 | 0.5884 | 0.8306 | 0.6190 |

## Rendering

| Workload | Population / batch size | Tessera median ms | Unity median ms | Tessera p95 ms | Unity p95 ms |
|---|---:|---:|---:|---:|---:|
| render-ao | 100 | 0.1422 | 0.2815 | 0.1651 | 0.3553 |
| render-ao | 1000 | 0.3218 | 0.6374 | 0.3318 | 0.7193 |
| render-ao@1920x1080 | 1000 | 0.3237 | 0.6376 | 0.3596 | 0.7341 |
| render-bloom | 100 | 0.1229 | 0.3861 | 0.1408 | 0.4392 |
| render-bloom | 1000 | 0.2676 | 0.8278 | 0.2776 | 0.9520 |
| render-culling | 100 | 0.1105 | 0.1690 | 0.1207 | 0.2408 |
| render-culling | 1000 | 0.1913 | 0.2030 | 0.2343 | 0.2812 |
| render-culling | 10000 | 0.8680 | 0.5362 | 0.9058 | 0.6213 |
| render-dof | 100 | 0.1946 | 0.2671 | 0.2356 | 0.3527 |
| render-dof | 1000 | 0.3089 | 0.5884 | 0.3179 | 0.6684 |
| render-grading | 100 | 0.1224 | 0.2636 | 0.1349 | 0.3441 |
| render-grading | 1000 | 0.2565 | 0.5874 | 0.2654 | 0.6674 |
| render-lights | 100 | 0.1259 | 0.5253 | 0.1489 | 0.6599 |
| render-lights | 1000 | 0.2457 | 1.6490 | 0.2898 | 1.8398 |
| render-lights | 10000 | 1.6104 | 37.0381 | 1.6240 | 38.2935 |
| render-materials | 100 | 0.2460 | 0.2936 | 0.2554 | 0.3723 |
| render-materials | 1000 | 0.2360 | 0.7544 | 0.2591 | 0.8747 |
| render-materials | 10000 | 1.5827 | 4.0636 | 1.7034 | 4.5702 |
| render-motion-blur | 100 | 0.1379 | 0.2763 | 0.1573 | 0.3513 |
| render-motion-blur | 1000 | 0.3058 | 0.5981 | 0.3146 | 0.6750 |
| render-moving | 100 | 0.1277 | 0.2419 | 0.1408 | 0.3065 |
| render-moving | 1000 | 0.3053 | 0.5705 | 0.3144 | 0.6792 |
| render-moving | 10000 | 2.3023 | 3.2189 | 2.3214 | 3.6338 |
| render-particles | 100 | 0.1095 | 0.1951 | 0.1409 | 0.2701 |
| render-particles | 1000 | 0.1907 | 0.4355 | 0.2082 | 0.5317 |
| render-particles | 10000 | 0.9717 | 8.0003 | 0.9934 | 10.2141 |
| render-physics | 100 | 0.1242 | 0.3027 | 0.1357 | 0.3894 |
| render-physics | 1000 | 0.2866 | 1.0042 | 0.3007 | 1.1263 |
| render-physics | 10000 | 2.0550 | 16.4071 | 7.9894 | 18.4187 |
| render-reflections | 100 | 0.1438 | 0.3094 | 0.1681 | 1.0650 |
| render-reflections | 1000 | 0.3914 | 0.6645 | 0.4030 | 1.2992 |
| render-shadows | 100 | 0.1541 | 0.2601 | 0.1869 | 0.3242 |
| render-shadows | 1000 | 0.3712 | 0.8888 | 0.3803 | 0.9904 |
| render-shadows | 10000 | 2.9772 | 5.6319 | 3.0456 | 6.7485 |
| render-shared | 100 | 0.1291 | 0.2209 | 0.1447 | 0.3071 |
| render-shared | 1000 | 0.2363 | 0.5211 | 0.2472 | 0.6141 |
| render-shared | 10000 | 1.5456 | 2.4536 | 1.5615 | 3.1322 |
| render-shared@1920x1080 | 1000 | 0.2634 | 0.5426 | 0.3145 | 0.6161 |
| render-spheres | 100 | 0.1181 | 0.2424 | 0.1286 | 0.2821 |
| render-spheres | 1000 | 0.2575 | 0.6896 | 0.2701 | 0.7696 |
| render-spheres | 10000 | 1.5691 | 5.1944 | 1.5938 | 5.8448 |
| render-transparency | 100 | 0.2397 | 0.3116 | 0.2494 | 0.3780 |
| render-transparency | 1000 | 0.2927 | 0.7828 | 0.3892 | 0.8973 |

## Skinned meshes

| Workload | Population / batch size | Tessera median ms | Unity median ms | Tessera p95 ms | Unity p95 ms |
|---|---:|---:|---:|---:|---:|
| render-skinning-cpu | 1 | 0.2421 | 0.1876 | 0.2522 | 0.2631 |
| render-skinning-cpu | 10 | 1.3314 | 0.2740 | 1.3574 | 0.3788 |
| render-skinning-cpu | 100 | 4.3031 | 0.9944 | 4.5219 | 1.2930 |
| render-skinning-gpu | 1 | 0.1194 | 0.1828 | 0.1322 | 0.2635 |
| render-skinning-gpu | 10 | 0.1828 | 0.2687 | 0.1991 | 0.3558 |
| render-skinning-gpu | 100 | 0.8767 | 0.6225 | 1.2957 | 0.7181 |
| render-skinning-gpu@1920x1080 | 1000 | 10.0112 | 4.1077 | 20.1576 | 4.4529 |

## AI

| Workload | Population / batch size | Tessera median ms | Unity median ms | Tessera p95 ms | Unity p95 ms |
|---|---:|---:|---:|---:|---:|
| ai-behavior-tree | 100 | 0.0245 | — | 0.0274 | — |
| ai-behavior-tree | 1000 | 0.2562 | — | 0.2619 | — |
| ai-nav-bake | 1 | 6.1903 | 2.3639 | 6.2541 | 2.6434 |
| ai-nav-path | 1 | 0.0123 | 0.0015 | 0.0125 | 0.0015 |
| ai-nav-path | 10 | 2.1513 | 0.0111 | 2.1806 | 0.0114 |
| ai-nav-path | 100 | 1.2165 | 0.1075 | 1.2545 | 0.1117 |

## Scene and other subsystems

| Workload | Population / batch size | Tessera median ms | Unity median ms | Tessera p95 ms | Unity p95 ms |
|---|---:|---:|---:|---:|---:|
| animation-ik | 100 | 0.0859 | — | 0.1076 | — |
| animation-ik | 1000 | 0.8777 | — | 0.8924 | — |
| animation-retarget | 1 | 0.6165 | — | 0.6217 | — |
| animation-retarget | 10 | 6.1281 | — | 6.2118 | — |
| animator-clips | 1 | 0.0240 | 0.0104 | 0.0282 | 0.0135 |
| animator-clips | 100 | 0.2855 | 0.7680 | 0.2921 | 0.9146 |
| animator-clips | 1000 | 2.8996 | 10.4848 | 2.9619 | 11.2973 |
| animator-layered | 1 | 0.0447 | 0.0120 | 0.0557 | 0.0176 |
| animator-layered | 100 | 1.4366 | 1.1102 | 1.4584 | 1.3479 |
| animator-layered | 1000 | 14.8452 | 16.3369 | 15.3063 | 18.0047 |
| anti-cheat-guard | 100 | 0.0003 | — | 0.0003 | — |
| anti-cheat-guard | 1000 | 0.0037 | — | 0.0037 | — |
| anti-cheat-process-scan | 1 | 0.0093 | — | 0.0093 | — |
| anti-cheat-process-scan | 10 | 0.0915 | — | 0.0962 | — |
| asset-async-cache | 1 | 1.1822 | — | 1.2656 | — |
| asset-async-cold | 1 | 1.7948 | — | 1.7948 | — |
| asset-image-decode | 1 | 1.0564 | 0.8455 | 1.0678 | 0.9979 |
| asset-image-decode | 100 | 107.3979 | 90.9627 | 108.0774 | 95.2596 |
| asset-model-load | 1 | 1.2360 | — | 1.2580 | — |
| asset-model-load | 10 | 12.4073 | — | 12.4776 | — |
| asset-pack-read | 1 | 0.1099 | — | 0.1168 | — |
| asset-pack-read | 10 | 1.0960 | — | 1.1084 | — |
| audio-hrtf | 1 | 0.1450 | — | 0.1530 | — |
| audio-hrtf | 10 | 1.2064 | — | 1.2229 | — |
| audio-mix | 1 | 0.0407 | 0.0331 | 0.0448 | 0.0431 |
| audio-mix | 10 | 0.1600 | 0.0447 | 0.1664 | 0.0554 |
| audio-mix | 100 | 0.4492 | 0.1588 | 0.4677 | 0.1896 |
| baking-lightmap | 1 | 4.0709 | — | 4.3374 | — |
| baking-lightmap | 10 | 4.4723 | — | 4.8136 | — |
| baking-uv | 1 | 0.0865 | — | 0.0947 | — |
| baking-uv | 10 | 0.8409 | — | 0.8718 | — |
| dialogue-condition | 100 | 0.0183 | — | 0.0197 | — |
| dialogue-condition | 1000 | 0.1835 | — | 0.1935 | — |
| dialogue-parse | 100 | 0.0651 | — | 0.0840 | — |
| dialogue-parse | 1000 | 2.5203 | — | 2.5321 | — |
| editor-api-index | 1 | 22.9440 | — | 23.2578 | — |
| editor-code-completion | 10 | 0.0089 | — | 0.0105 | — |
| editor-code-completion | 100 | 0.0867 | — | 0.0933 | — |
| editor-code-index | 10 | 0.0095 | — | 0.0096 | — |
| editor-code-index | 100 | 0.0963 | — | 0.1001 | — |
| editor-graph-generate | 10 | 0.0026 | — | 0.0027 | — |
| editor-graph-generate | 100 | 0.0293 | — | 0.0301 | — |
| editor-graph-validate | 10 | 0.0004 | — | 0.0004 | — |
| editor-graph-validate | 100 | 0.0091 | — | 0.0093 | — |
| editor-theme-parse | 10 | 0.3462 | — | 0.3636 | — |
| editor-theme-parse | 100 | 3.4785 | — | 3.4909 | — |
| graph-blackboard | 100 | 0.0054 | — | 0.0054 | — |
| graph-blackboard | 1000 | 0.0530 | — | 0.0582 | — |
| http-local | 1 | 0.1033 | 0.1201 | 0.1339 | 0.1608 |
| http-local | 10 | 0.9630 | 1.1636 | 1.1133 | 1.4791 |
| input-parse | 100 | 0.0348 | — | 0.0396 | — |
| input-parse | 1000 | 0.3400 | — | 0.3447 | — |
| model-algorithm-array | 1 | 0.0147 | — | 0.0191 | — |
| model-algorithm-array | 10 | 0.1433 | — | 0.1555 | — |
| model-algorithm-bevel | 1 | 0.0353 | — | 0.0390 | — |
| model-algorithm-bevel | 100 | 3.5429 | — | 3.5549 | — |
| model-algorithm-csg-subtract | 1 | 0.0251 | — | 0.0314 | — |
| model-algorithm-csg-subtract | 10 | 0.2473 | — | 0.2569 | — |
| model-algorithm-cube | 1 | 0.0043 | — | 0.0044 | — |
| model-algorithm-cube | 100 | 0.4229 | — | 0.4306 | — |
| model-algorithm-decimate | 1 | 0.0806 | — | 0.0881 | — |
| model-algorithm-decimate | 10 | 0.7784 | — | 0.7944 | — |
| model-algorithm-extrude | 1 | 0.0173 | — | 0.0178 | — |
| model-algorithm-extrude | 100 | 1.7252 | — | 1.7358 | — |
| model-algorithm-inset | 1 | 0.0197 | — | 0.0204 | — |
| model-algorithm-inset | 10 | 0.1893 | — | 0.1995 | — |
| model-algorithm-large-subdivide | 1 | 73.1569 | — | 74.4139 | — |
| model-algorithm-large-uv-smart | 1 | 19.6030 | — | 19.7319 | — |
| model-algorithm-loopcut | 1 | 0.0232 | — | 0.0254 | — |
| model-algorithm-loopcut | 10 | 0.1872 | — | 0.1980 | — |
| model-algorithm-mirror | 1 | 0.0115 | — | 0.0122 | — |
| model-algorithm-mirror | 10 | 0.1126 | — | 0.1396 | — |
| model-algorithm-poke | 1 | 0.0106 | — | 0.0118 | — |
| model-algorithm-poke | 10 | 0.0948 | — | 0.1181 | — |
| model-algorithm-primitives | 1 | 0.0044 | — | 0.0048 | — |
| model-algorithm-primitives | 10 | 0.3381 | — | 0.3590 | — |
| model-algorithm-primitives | 12 | 0.3955 | — | 0.4148 | — |
| model-algorithm-primitives | 120 | 3.9405 | — | 3.9888 | — |
| model-algorithm-solidify | 1 | 0.0091 | — | 0.0093 | — |
| model-algorithm-solidify | 10 | 0.0899 | — | 0.0948 | — |
| model-algorithm-split-edge | 1 | 0.0051 | — | 0.0052 | — |
| model-algorithm-split-edge | 10 | 0.0470 | — | 0.0507 | — |
| model-algorithm-subdivide | 1 | 0.0183 | — | 0.0192 | — |
| model-algorithm-subdivide | 100 | 1.7653 | — | 1.7712 | — |
| model-algorithm-triangulate | 1 | 0.0079 | — | 0.0089 | — |
| model-algorithm-triangulate | 10 | 0.0646 | — | 0.0688 | — |
| model-algorithm-uv | 1 | 0.0047 | — | 0.0048 | — |
| model-algorithm-uv | 10 | 0.0470 | — | 0.0495 | — |
| model-algorithm-uv-cylinder | 1 | 0.0049 | — | 0.0050 | — |
| model-algorithm-uv-cylinder | 10 | 0.0464 | — | 0.0502 | — |
| model-algorithm-uv-pack | 1 | 0.0151 | — | 0.0164 | — |
| model-algorithm-uv-pack | 10 | 0.1497 | — | 0.1555 | — |
| model-algorithm-uv-planar | 1 | 0.0050 | — | 0.0052 | — |
| model-algorithm-uv-planar | 10 | 0.0484 | — | 0.0523 | — |
| model-algorithm-uv-smart | 1 | 0.0119 | — | 0.0149 | — |
| model-algorithm-uv-smart | 10 | 0.1149 | — | 0.1230 | — |
| model-algorithm-uv-sphere | 1 | 0.0051 | — | 0.0053 | — |
| model-algorithm-uv-sphere | 10 | 0.0491 | — | 0.0551 | — |
| model-algorithm-uv-unwrap | 1 | 0.0128 | — | 0.0135 | — |
| model-algorithm-uv-unwrap | 10 | 0.1265 | — | 0.1580 | — |
| model-algorithm-weld | 1 | 0.0052 | — | 0.0056 | — |
| model-algorithm-weld | 100 | 0.5190 | — | 0.5324 | — |
| model-object-bevel | 1 | 0.0576 | 0.6494 | 0.0618 | 0.7697 |
| model-object-bevel | 100 | 5.6582 | 66.3506 | 5.6898 | 77.6239 |
| model-object-cube | 1 | 0.0117 | 0.0579 | 0.0120 | 0.1611 |
| model-object-cube | 100 | 1.1320 | 8.4450 | 1.1494 | 8.7316 |
| model-object-extrude | 1 | 0.0413 | 0.2424 | 0.0437 | 0.3317 |
| model-object-extrude | 100 | 3.8903 | 25.9415 | 3.9192 | 26.8031 |
| model-object-subdivide | 1 | 0.0383 | 0.7461 | 0.0410 | 0.8652 |
| model-object-subdivide | 100 | 3.7239 | 78.8734 | 3.7511 | 88.8734 |
| model-object-weld | 1 | 0.0127 | 0.0978 | 0.0131 | 0.2200 |
| model-object-weld | 100 | 1.2426 | 13.8069 | 1.2608 | 14.4350 |
| network-compress | 1 | 0.7795 | — | 0.7880 | — |
| network-compress | 10 | 7.8018 | — | 7.8289 | — |
| network-loopback | 1 | 0.0083 | — | 0.0084 | — |
| network-loopback | 10 | 0.0100 | — | 0.0121 | — |
| network-snapshot-pack | 100 | 0.0088 | — | 0.0093 | — |
| network-snapshot-pack | 1000 | 0.0881 | — | 0.1062 | — |
| rig-autoweights | 1 | 22.9156 | — | 23.8039 | — |
| rig-autoweights | 10 | 228.9713 | — | 231.3313 | — |
| rig-pose | 1 | 0.3490 | — | 0.3541 | — |
| rig-pose | 10 | 3.4669 | — | 3.5598 | — |
| rig-weight-brush | 1 | 0.0508 | — | 0.0562 | — |
| rig-weight-brush | 10 | 0.4454 | — | 0.5124 | — |
| save-binary-decode | 100 | 0.0074 | — | 0.0075 | — |
| save-binary-decode | 1000 | 0.0787 | — | 0.0833 | — |
| save-binary-encode | 100 | 0.0049 | — | 0.0049 | — |
| save-binary-encode | 1000 | 0.0503 | — | 0.0537 | — |
| save-json-decode | 1 | 0.0004 | 0.0019 | 0.0004 | 0.0025 |
| save-json-decode | 100 | 0.0257 | 0.0366 | 0.0286 | 0.1267 |
| save-json-encode | 1 | 0.0002 | 0.0012 | 0.0002 | 0.0013 |
| save-json-encode | 100 | 0.0088 | 0.0151 | 0.0110 | 0.1069 |
| scene-churn | 100 | 0.0261 | 0.2021 | 0.0265 | 0.2941 |
| scene-churn | 1000 | 0.5909 | 2.1335 | 0.6099 | 2.2145 |
| scene-empty | 100 | 0.0001 | 0.0002 | 0.0001 | 0.0003 |
| scene-empty | 1000 | 0.0001 | — | 0.0001 | — |
| scene-hierarchy | 100 | 0.0089 | 0.0070 | 0.0092 | 0.0071 |
| scene-hierarchy | 1000 | 0.0907 | 0.0681 | 0.0946 | 0.0726 |
| scene-scripts | 100 | 0.0024 | 0.0037 | 0.0024 | 0.0038 |
| scene-scripts | 1000 | 0.0230 | 0.0355 | 0.0232 | 0.0391 |
| scene-transforms | 100 | 0.0028 | 0.0056 | 0.0028 | 0.0056 |
| scene-transforms | 1000 | 0.0258 | 0.0542 | 0.0265 | 0.0580 |
| sequence-evaluate | 100 | 0.0165 | — | 0.0166 | — |
| sequence-evaluate | 1000 | 0.1591 | — | 0.1631 | — |
| sequence-parse | 100 | 0.0895 | — | 0.0937 | — |
| sequence-parse | 1000 | 0.8891 | — | 0.9168 | — |
| terrain-mesh | 1 | 1.3925 | — | 1.5670 | — |
| terrain-mesh | 10 | 2.7111 | — | 2.8852 | — |
| terrain-noise | 1 | 0.0994 | — | 0.1782 | — |
| terrain-noise | 10 | 1.7391 | — | 1.7683 | — |
| texture-mips-color | 1 | 0.9230 | — | 0.9520 | — |
| texture-mips-color | 10 | 9.1749 | — | 9.3600 | — |
| texture-mips-normal | 1 | 1.5980 | — | 1.6632 | — |
| texture-mips-normal | 10 | 16.0303 | — | 16.2419 | — |
| texture-paint | 1 | 0.5113 | — | 0.5259 | — |
| texture-paint | 10 | 5.1309 | — | 5.1590 | — |
| ui-layout | 100 | 0.0981 | — | 0.1031 | — |
| ui-layout | 1000 | 0.4733 | — | 0.4818 | — |
| ui-parse | 100 | 0.0315 | — | 0.0345 | — |
| ui-parse | 1000 | 0.1465 | — | 0.1773 | — |
| voice-decode | 1 | 0.0086 | — | 0.0086 | — |
| voice-decode | 10 | 0.0824 | — | 0.0965 | — |
| voice-encode | 1 | 0.1327 | — | 0.1708 | — |
| voice-encode | 10 | 1.2601 | — | 1.2907 | — |
| voxel-carve | 1 | 0.6385 | — | 0.6448 | — |
| voxel-carve | 10 | 6.3557 | — | 6.3965 | — |
| voxel-rebuild | 1 | 0.5447 | — | 0.5507 | — |
| voxel-rebuild | 10 | 5.4080 | — | 5.4730 | — |

## Interpretation

Compare the same row, then check its workload definition, correctness observations and memory. No overall engine score is calculated. Solver defaults differ; CCD timings require tunneling counts. Character motors and scene callback dispatch differ. Render-physics advances different numbers of simulation steps per rendered second. Rendering uses native pipeline settings and different sky/lighting/shadow/particle material implementations. Skinning forces all characters to deform every frame; Unity CPU and GPUBatched are separate builds. Navigation uses native grid search versus native polygon NavMesh search; path shapes and quality differ.

## Sources

- `20261027-171400`: [environment](results/20261027-171400/environment.json), [samples](../archives/full-engine-18.tar.gz), [summary](results/20261027-171400/summary.csv), [checks](../archives/full-engine-17.tar.gz), [failures](../archives/full-engine-17.tar.gz)
- `20261027-172540`: [environment](results/20261027-172540/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-172540/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-172744`: [environment](results/20261027-172744/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-172744/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-172834`: [environment](results/20261027-172834/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-172834/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-172844`: [environment](results/20261027-172844/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-172844/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-173929`: [environment](results/20261027-173929/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-173929/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-174441`: [environment](results/20261027-174441/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-174441/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-175018`: [environment](results/20261027-175018/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-175018/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-175307`: [environment](results/20261027-175307/environment.json), [samples](../archives/full-engine-19.tar.gz), [summary](results/20261027-175307/summary.csv), [checks](../archives/full-engine-19.tar.gz), [failures](../archives/full-engine-19.tar.gz)
- `20261027-175313`: [environment](results/20261027-175313/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-175313/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-175317`: [environment](results/20261027-175317/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-175317/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-175513`: [environment](results/20261027-175513/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-175513/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-175559-925240`: [environment](results/20261027-175559-925240/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-175559-925240/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-175654-815908`: [environment](results/20261027-175654-815908/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-175654-815908/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-180334-304828`: [environment](results/20261027-180334-304828/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-180334-304828/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-180627-701204`: [environment](results/20261027-180627-701204/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-180627-701204/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-180635-380731`: [environment](results/20261027-180635-380731/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-180635-380731/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-180939-060530`: [environment](results/20261027-180939-060530/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-180939-060530/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-181715-487508`: [environment](results/20261027-181715-487508/environment.json), [samples](../archives/full-engine-20.tar.gz), [summary](results/20261027-181715-487508/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-181828-386064`: [environment](results/20261027-181828-386064/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-181828-386064/summary.csv), [checks](../archives/full-engine-20.tar.gz), [failures](../archives/full-engine-20.tar.gz)
- `20261027-181856-107631`: [environment](results/20261027-181856-107631/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-181856-107631/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-181915-231119`: [environment](results/20261027-181915-231119/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-181915-231119/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-182022-039876`: [environment](results/20261027-182022-039876/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-182022-039876/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-182036-778104`: [environment](results/20261027-182036-778104/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-182036-778104/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-182040-466499`: [environment](results/20261027-182040-466499/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-182040-466499/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-182109-863971`: [environment](results/20261027-182109-863971/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-182109-863971/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-211927-171666`: [environment](results/20261027-211927-171666/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-211927-171666/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-211957-023441`: [environment](results/20261027-211957-023441/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-211957-023441/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212010-353561`: [environment](results/20261027-212010-353561/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212010-353561/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212012-807264`: [environment](results/20261027-212012-807264/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212012-807264/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212029-103523`: [environment](results/20261027-212029-103523/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212029-103523/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212114-417144`: [environment](results/20261027-212114-417144/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212114-417144/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212156-749957`: [environment](results/20261027-212156-749957/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212156-749957/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212159-761198`: [environment](results/20261027-212159-761198/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212159-761198/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
- `20261027-212343-741144`: [environment](results/20261027-212343-741144/environment.json), [samples](../archives/full-engine-21.tar.gz), [summary](results/20261027-212343-741144/summary.csv), [checks](../archives/full-engine-21.tar.gz), [failures](../archives/full-engine-21.tar.gz)
