# Phase 1 — Harness baseline: does resolution change the jitter band?

Status: done — 2026-09-10. `jitter_sweep.py` extended; three baselines recorded. The
resolution effect is **real but not monotonic**, and the reason is now understood. See
Results.

## Symptom

**F56.** `ML/host_scale_test/jitter_sweep.py` is the only instrument that can measure
reference-marking jitter without a sideload, and every recorded baseline was taken on PIGRGB
images, which are 960×540. F55's mechanism scales with the size of the intermediate
full-resolution raster (`construction.cpp:97`) relative to the 640×640 mask it comes from. On
a 960×540 image that detour is roughly 1.5×; on a real phone capture it is 2× (live camera,
~1280×720) to 4.7× (gallery import, ~3000 px). A baseline taken only at 960×540 could
therefore misrepresent the defect.

## Root cause

Not a code defect. PIGRGB is the training distribution and carries ground-truth weights,
which is the right reason to sweep it — but it fixes the resolution at 960×540, and
resolution is a variable F55 depends on.

## Change made

`ML/host_scale_test/jitter_sweep.py`:

- **`--upscale-long-edge N`** resamples each source image so its long edge is `N` px before
  the sweep, and divides `cm_per_px_actual` by the same factor so the pig lands at the same
  physical scale in the model input. Reproduces a real capture's resolution, and therefore
  its raster-detour magnitude. `--interp` (default `cubic`) and `--native-long-edge` (default
  960) support it.
- Without `--upscale-long-edge` the behavior is byte-identical to the round 6 baselines —
  verified: a no-upscale rerun of `sub_1.78` reproduced `out/jitter_sweep.json`'s worst case
  to 11.93% vs 11.928% recorded.
- Output JSON now carries `source_resolution` and `swept_resolution` per image, plus
  `upscale_long_edge` / `upscale_interp` / `upscale_scale_factor` at the top. The pre-round-7
  `out/*.json` files carry none of this, which is what made this phase necessary.
- `true_kg` parsing is now optional (`try_parse_true_kg`), so a corpus without weights in the
  filenames can still be swept for spread.

New baselines: `out/jitter_sweep_hires1280.json`, `out/jitter_sweep_hires3000.json`. The
round 6 `out/jitter_sweep{,_1.88}.json` were not touched.

## Results

Same five `sub_1.78` images, same `--deltas`, height 1.78 m. Worst-case spread is dominated
by `133.42kg_5.png` in every run.

| corpus | resolution | 640→orig detour | worst spread | median spread |
|---|---|---|---|---|
| native (round 6 baseline) | 960×540 | 1.5× | **11.9%** | 4.4% |
| `--upscale-long-edge 1280` | 1280×720 | 2.0× | **14.7%** | 3.5% |
| `--upscale-long-edge 3000` | 3000×1688 | 4.7× | **10.8%** | 4.8% |

Per image (spread %):

| image | 960 | 1280 | 3000 |
|---|---|---|---|
| 100.9kg_3 | 4.4 | 2.4 | 4.8 |
| 107.54kg_13 | 2.8 | 3.2 | 1.8 |
| 117.9kg_2 | 8.6 | 6.6 | 4.6 |
| 125.38kg_4 | 4.3 | 3.5 | 7.0 |
| 133.42kg_5 | 11.9 | 14.7 | 10.8 |

**At the baseline point (delta 0) resolution barely matters.** Direct CLI comparison on
`133.42kg_5.png`: predicted 142.2 / 141.6 / 142.4 kg at 960 / 1280 / 3000, and the resampled
mask that feeds the cutter is 854×481 / 854×481 / 854×480 in all three. This confirms
`docs/fix-phase-2/2.1`'s finding that `k` scales inversely with resolution and cancels it —
the final mask is ~854 px regardless of input size.

**The jitter amplification is not monotonic in resolution.** 1280 is worse than native; 3000
is better. Two effects combine:

1. Both raster steps are `INTER_NEAREST`, and the second one
   (`scale_mask_to_training_space`) is a *downscale* whose ratio grows with input resolution:
   960→854 is 0.89×, 1280→854 is 0.67×, 3000→854 is 0.28×. A hard nearest downscale
   re-samples onto a coarse grid that partly realigns with the original 640 blocks, washing
   out some of the marking-dependent grid shift. The 1280 case sits in the worst spot — the
   detour is large enough to matter, the second downscale not hard enough to mask it.
2. **Confounder.** Upscaling an already-downscaled 960 px source with cubic interpolation
   blurs it, so YOLO sees a progressively smoother pig at higher `N`. This independently
   reduces mask variability at 3000 and cannot be separated from effect 1 with this method.
   The docstring records this.

**The one real field photo runs but cannot be swept.**
`.pig_pictures/118kg_pig_porac_stick.jpg` (3024×4032, real sensor detail) segments cleanly
(`seg_conf` 0.92) and the cutter runs, but its true `cm_per_px_actual` is unknown — no
recorded capture height, and the marked reference is only on-device. Swept at three guessed
baselines the prediction ranged 149–182 kg, so a spread taken there samples the wrong part of
the response curve and is not comparable to F53's on-device bands. The two other field photos
are HEIC and OpenCV 5.0 here cannot decode them. Full field-photo sweeps stay on-device
work, exactly as `docs/fix-phase-2/2.1`'s deferred F53 items already say.

## Consequence for phase 2

The premise "960×540 understates the defect" **holds for the live-camera resolution** — 1280
gives 14.7% vs 11.9% — which is the path F53's worst on-device band (12.6%) came closest to.
It does **not** hold at gallery-import resolution in this harness, though the blur confounder
plausibly drives that.

Phase 2 proceeds. The composed transform still addresses F55's actual mechanism: the
final mask's grid alignment depending on `k` through two `INTER_NEAREST` resizes. Phase 4
should validate primarily against the **1280 baseline** (`out/jitter_sweep_hires1280.json`),
keep the native 960 baselines as a secondary check, and treat the on-device F53 re-mark as
the real verdict — this phase has shown the harness cannot cleanly model the resolution
dependence.

## Exit condition — met

Written before-baselines at real capture resolution exist (`out/jitter_sweep_hires1280.json`,
`out/jitter_sweep_hires3000.json`), each carrying source and swept resolution, and their
worst-case spreads (14.7%, 10.8%) are recorded here next to the 11.9% native figure. The
"if it is not larger, say so plainly" branch applies to the 3000 case and is addressed above:
it is lower, the reason is a downscale-ratio effect compounded by an upscaling blur
confounder, and it does not contradict F55's mechanism at the baseline point or at 1280.
