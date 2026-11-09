| Run | Adapter / renderer | Viewport | Overall P50 / P95 / P99 / max ms | Mission P95 (idle / walk / tablet / pause) ms | >33.3 ms frames | Engine video MiB | WS peak MiB | GPU dedicated / shared peak MiB |
|---|---|---|---|---|---|---|---|---|
| intel_gl_ds08_cold | Intel(R) RaptorLake-S Mobile Graphics Controller / gl_compatibility (vsync off) | 2560x1600 | 3.114 / 42.477 / 45.835 / 3352.792 | 42.078 / 42.373 / 45.727 / 42.995 | 2156 | 104.6 | 730.1 | 0.0 / 540.9 |
| intel_gl_ds08_warm | Intel(R) RaptorLake-S Mobile Graphics Controller / gl_compatibility (vsync off) | 2560x1600 | 3.134 / 41.859 / 45.108 / 212.797 | 41.708 / 42.336 / 45.032 / 41.86 | 2227 | 104.6 | 709.0 | 0.0 / 540.9 |
| rtx5090_gl_ds08_sanity | NVIDIA GeForce RTX 5090 Laptop GPU / gl_compatibility (vsync off) | 2560x1600 | 1.452 / 2.159 / 3.057 / 4730.804 | 2.17 / 1.878 / 2.181 / 2.267 | 6 | 96.9 | None | None / None |

Segments: 0 = menu_idle, 1 = mission_idle, 2 = walk_look, 3 = tablet_toggle, 4 = pause_toggle, 5 = final_idle. First 5 s of each run excluded.
