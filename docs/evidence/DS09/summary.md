| Run | Adapter / renderer | Viewport | Overall P50 / P95 / P99 / max ms | Mission P95 (idle / walk / tablet / pause) ms | >33.3 ms frames | Engine video MiB | WS peak MiB | GPU dedicated / shared peak MiB |
|---|---|---|---|---|---|---|---|---|
| intel_gl_ds09_cold | Intel(R) RaptorLake-S Mobile Graphics Controller / gl_compatibility (vsync off) | 2560x1600 | 7.478 / 33.299 / 36.082 / 839.364 | 33.299 / 33.368 / 35.691 / 31.885 | 804 | 93.6 | 706.9 | 0.0 / 461.6 |
| intel_gl_ds09_warm | Intel(R) RaptorLake-S Mobile Graphics Controller / gl_compatibility (vsync off) | 2560x1600 | 7.761 / 33.898 / 38.088 / 131.049 | 37.758 / 33.848 / 36.083 / 32.677 | 902 | 95.4 | 699.3 | 0.0 / 527.6 |
| rtx5090_gl_ds09_sanity | NVIDIA GeForce RTX 5090 Laptop GPU / gl_compatibility (vsync off) | 2560x1600 | 0.833 / 2.576 / 7.082 / 471.261 | 4.244 / 1.435 / 3.257 / 3.157 | 5 | 79.2 | 396.4 | 252.4 / 137.7 |

Segments: 0 = menu_idle, 1 = mission_idle, 2 = walk_look, 3 = tablet_toggle, 4 = pause_toggle, 5 = final_idle. First 5 s of each run excluded.
