| Run | Adapter / renderer | Viewport | Overall P50 / P95 / P99 / max ms | Mission P95 (idle / walk / tablet / pause) ms | >33.3 ms frames | Engine video MiB | WS peak MiB | GPU dedicated / shared peak MiB |
|---|---|---|---|---|---|---|---|---|
| amd_fplus_1080_r2 | AMD Radeon(TM) RX Vega 10 Graphics / forward_plus (vsync off) | 1920x1080 | 5.456 / 7.294 / 10.639 / 2201.786 | 9.007 / 9.592 / 10.075 / 7.274 | 12 | 131.1 | 506.6 | 189.2 / 140.4 |
| amd_gl_1080_r2 | AMD Radeon(TM) RX Vega 10 Graphics / gl_compatibility (vsync off) | 1920x1080 | 2.175 / 3.356 / 6.506 / 708.806 | 3.312 / 3.159 / 3.723 / 3.049 | 9 | 32.6 | 377.7 | 212.9 / 122.2 |
| amd_gl_1080_vsync | AMD Radeon(TM) RX Vega 10 Graphics / gl_compatibility (vsync on) | 1920x1080 | 8.275 / 10.975 / 12.515 / 687.473 | 11.272 / 11.091 / 11.792 / 10.193 | 12 | 28.5 | 377.9 | 196.8 / 122.2 |
| amd_gl_1080_warm_r2 | AMD Radeon(TM) RX Vega 10 Graphics / gl_compatibility (vsync off) | 1920x1080 | 1.942 / 3.211 / 6.217 / 228.426 | 3.198 / 2.552 / 3.603 / 2.997 | 7 | 34.6 | 370.6 | 220.9 / 122.2 |
| amd_gl_720 | AMD Radeon(TM) RX Vega 10 Graphics / gl_compatibility (vsync off) | 1280x720 | 1.729 / 2.717 / 5.58 / 671.924 | 2.881 / 2.513 / 2.97 / 2.56 | 7 | 25.3 | 388.6 | 137.8 / 122.2 |
| amd_mobile_1080_r2 | AMD Radeon(TM) RX Vega 10 Graphics / mobile (vsync off) | 1920x1080 | 3.102 / 4.179 / 7.394 / 1548.894 | 4.078 / 4.208 / 4.383 / 4.122 | 7 | 100.4 | 553.9 | 189.0 / 139.1 |
| intel_fplus_1080 | Intel(R) RaptorLake-S Mobile Graphics Controller / forward_plus (vsync off) | 2560x1600 | 10.448 / 12.843 / 13.927 / 1246.022 | 11.024 / 13.804 / 12.726 / 12.309 | 3 | 186.8 | 832.2 | 0.3 / 645.4 |
| intel_gl_1080 | Intel(R) RaptorLake-S Mobile Graphics Controller / gl_compatibility (vsync off) | 2560x1600 | 4.972 / 7.797 / 16.673 / 44.803 | 7.799 / 7.361 / 8.266 / 6.906 | 2 | 55.1 | 491.5 | 0.0 / 342.9 |
| intel_mobile_1080 | Intel(R) RaptorLake-S Mobile Graphics Controller / mobile (vsync off) | 2560x1600 | 4.955 / 7.076 / 7.987 / 822.939 | 6.677 / 6.972 / 7.374 / 7.02 | 2 | 126.3 | 644.0 | 0.3 / 479.5 |
| nv_fplus_1080 | NVIDIA GeForce GTX 1650 / forward_plus (vsync off) | 1920x1080 | 1.726 / 3.427 / 5.506 / 4480.616 | 3.453 / 3.567 / 3.434 / 3.406 | 7 | 137.6 | 747.7 | 277.2 / 241.7 |
| nv_gl_1080_r2 | NVIDIA GeForce GTX 1650 / gl_compatibility (vsync off) | 1920x1080 | 2.62 / 3.913 / 5.894 / 295.202 | 3.883 / 3.847 / 3.998 / 3.803 | 6 | 28.5 | 268.7 | 132.1 / 86.2 |
| nv_gl_1080_vsync_r2 | NVIDIA GeForce GTX 1650 / gl_compatibility (vsync on) | 1920x1080 | 8.322 / 11.625 / 12.265 / 289.132 | 11.882 / 12.146 / 11.447 / 9.114 | 13 | 28.5 | 268.3 | 132.2 / 86.2 |
| nv_gl_1080_warm | NVIDIA GeForce GTX 1650 / gl_compatibility (vsync off) | 1920x1080 | 2.677 / 4.0 / 5.852 / 219.682 | 3.847 / 3.735 / 4.46 / 3.579 | 6 | 28.5 | 263.6 | 137.5 / 86.2 |
| nv_gl_720 | NVIDIA GeForce GTX 1650 / gl_compatibility (vsync off) | 1280x720 | 2.259 / 3.03 / 5.558 / 290.335 | 3.044 / 2.63 / 3.358 / 2.838 | 6 | 19.3 | 239.4 | 74.5 / 57.7 |
| nv_mobile_1080 | NVIDIA GeForce GTX 1650 / mobile (vsync off) | 1920x1080 | 1.667 / 3.117 / 5.308 / 517.125 | 3.021 / 3.108 / 3.216 / 3.221 | 7 | 97.5 | 601.1 | 282.7 / 240.5 |
| release_gate | ? / ? (vsync off) | ?x? | 8.326 / 8.446 / 8.649 / 8.777 | ? / ? / ? / ? | 0 | 0.0 | 197.1 | 68.3 / 51.7 |

Segments: 0 = menu_idle, 1 = mission_idle, 2 = walk_look, 3 = tablet_toggle, 4 = pause_toggle, 5 = final_idle. First 5 s of each run excluded.
