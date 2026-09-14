> **Superseded.** This document measured the pre-F55 double-rasterisation path
> (`construct_pig_mask` → `scale_mask_to_training_space`, `INTER_NEAREST`, grid-snapped and
> dependent on the swept `k`) over the now-retired `sub_1.78/` corpus, and both are gone: F55
> replaced the scale step with a single composed transform, and the corpus was retired in favour
> of `sub_1.88/` (no 1.78→1.88 m rescaling assumption). Its numbers describe code and images that
> no longer exist. Superseded by
> [`scale-constant-sweep-results-2.md`](scale-constant-sweep-results-2.md), which re-ran the same
> comparison on the current pipeline against `sub_1.88/` and `.pig_pictures/`. The body below is
> kept as the historical record of the pre-F55 measurement; do not quote its MAE or bias figures
> against the current pipeline.

# `cm_per_px_target` sweep — host results (2026-09-09)

Measured on the **current pipeline, with the real V176/V144 cutter running** — not the
identity stub ADR-001 shipped, and not the Python reference cutter. `cutter_status` was
`cut_applied` on every run in this document, with `kept_fraction` 0.80–0.93, so the head and
neck were genuinely being removed before features were measured.

## What was run

| what | path |
|---|---|
| harness source | `ML/host_scale_test/weight_branch_cli.cpp` |
| built binary | `ML/host_scale_test/build/weight_branch_cli.exe` |
| sweep driver | `ML/host_scale_test/sweep_constants.py` |
| two-arm driver | `ML/host_scale_test/run_sweep.py` |
| build + setup notes | `ML/host_scale_test/README.md` |
| test images | `Instaham/PIGRGB-Weight/sub_1.78/` (5 PNGs, 960×540, weight in filename) |
| raw sweep output | `ML/host_scale_test/out/constant_sweep.json` |
| two-arm output | `ML/host_scale_test/out/results.csv` + `out/envelope_*.json` |

To re-run (needs a `vcvars64.bat` shell only for rebuilding, not for running):

```
python ML/host_scale_test/sweep_constants.py     # N-constant sweep
python ML/host_scale_test/run_sweep.py           # 0.35 vs 0.3289, writes results.csv
```

The harness links the app's own `stages/*.cpp` plus `vendor/instaham_v176/` and runs the
shipped `assets/ml/` models. It patches temporary manifest copies (`manifest.test_*.json`,
gitignored, deleted after each run) — `assets/ml/manifest.json` is never written.

`cm_per_px_actual = 0.3114504`, from `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`'s
304 px/m at 1.88 m, rescaled to these images' 1.78 m capture height
(`304 × 1.88/1.78 = 321.0787 px/m`). Held identical across every row below.

## Results

Columns are the five pigs, lightest to heaviest. Values are signed error %.

| target | 60.27 | 66.24 | 100.90 | 125.38 | 133.42 | MAE | bias | spread |
|---|---|---|---|---|---|---|---|---|
| 0.2800 | +33.9 | +55.9 | +50.9 | +41.6 | +40.6 | 44.6 | +44.6 | 21.9 |
| 0.3000 | +25.8 | +37.6 | +26.5 | +31.6 | +36.6 | 31.6 | +31.6 | **11.8** |
| 0.3289 *(spec)* | +26.1 | +23.4 | +5.2 | +23.0 | +17.2 | 19.0 | +19.0 | 20.9 |
| **0.3500** *(fitted)* | +25.7 | +20.1 | −4.1 | +1.1 | +6.6 | **11.5** | +9.9 | 29.7 |
| 0.3800 | +25.9 | +16.2 | −16.1 | −16.4 | −14.8 | 17.9 | **−1.0** | 42.3 |
| 0.4200 | +24.4 | +10.8 | −26.7 | −29.3 | −30.7 | 24.4 | −10.3 | 55.0 |
| 0.4600 | +24.7 | +10.1 | −26.9 | −41.6 | −37.2 | 28.1 | −14.2 | 66.4 |
| 0.5000 | +23.4 | +14.4 | −26.1 | −41.7 | −38.8 | 28.9 | −13.8 | 65.0 |

**0.35 wins on MAE (11.5% vs 19.0%).** It was also closer than 0.3289 on all five images
individually in the two-arm run.

## Why the fitted 0.35 beat the theoretical 0.3289

Not because 0.35 is correct. Three reasons, in order of importance:

1. **304 px/m was never measured either.** `INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` §24 states
   it is a *theoretical* floor-plane baseline derived from the reported rig geometry and camera
   field of view, and says to replace it if empirical calibration from the released PIGRGB
   images is ever obtained. No pig in a released image was measured to produce it. So this is
   a fitted value against an unvalidated derived value — not measurement against theory.
2. **Neither is right; 0.35 is just nearer.** Min MAE is at 0.35, min |bias| at 0.38, min
   spread at 0.30. Three criteria, three different optima — no single scalar satisfies them,
   which is what you would expect if the constant is not the live error term.
3. **0.35's provenance is still contaminated.** `docs/fix.md` round 4's F21 moved it 0.26 → 0.35
   while the cutter was an identity stub, i.e. to compensate for head-and-neck area that should
   not have been in the mask. That head is now actually being cut, and 0.35 still wins — which
   is evidence the head was never what 0.35 was really absorbing.

## The finding that matters more than the constant

**The 60.27 kg column barely moves.** Across a 79% change in the constant (0.28 → 0.50) its
error goes +25.8 → +23.4. Per-image prediction ranges over the whole sweep:

| true kg | min pred | max pred | swing |
|---|---|---|---|
| 60.27 | 74.34 | 80.72 | **6.4 kg** |
| 66.24 | 72.93 | 103.24 | 30.3 kg |
| 100.90 | 73.78 | 152.24 | 78.5 kg |
| 125.38 | 73.12 | 177.50 | 104.4 kg |
| 133.42 | 81.60 | 187.56 | 106.0 kg |

Every image bottoms out near **73 kg**. The regressor cannot emit a number below that.

Mechanism, checked against `capabilities.weight.feature_domain`'s **raw trained range**
(unwidened by `lower_multiplier` or `cm_per_px_target_uncertainty`):

```
60.27kg: mask_area 25425 < 36647   perimeter 733 < 861   longest 290 < 332   shortest 90 < 103
66.24kg: mask_area 32202 < 36647   perimeter 811 < 861   longest 325 < 332
100.9kg, 125.38kg: no excursions
```

Both light pigs sit below the trained minimum on every gated size feature. The model has never
seen a pig that small and answers from its floor leaf — `pipeline.cpp`'s F22 `extrapolated`
condition. Scaling cannot recover a vector that is outside the trained domain, which is why no
value of `cm_per_px_target` moves those rows. At the extreme constants the *heavy* pigs get
shrunk below the floor too and collapse onto the same ~73 kg, confirming this is a property of
the regressor rather than of any one photograph.

The two in-domain pigs (100.90, 125.38) predict well at 0.35 — −4.1% and +1.1% — so the
geometry chain (segmentation, cutter, resample, features) is sound. The failure is the
regressor's training coverage at the low end.

## Caveats

- Five images, all PIGRGB — the regressor's own training distribution. Good agreement here is
  partly memorization and does not predict field-photo accuracy.
- The 1.78 m capture height comes from the folder's description, not from a repository
  document. Everything scales with it: a 5% height error is a 5% error in `cm_per_px_actual`.
- Host ONNX Runtime is 1.29.0; the device links the Android `.so`. Same graphs, not
  bit-identical.
- `weight_branch_cli.cpp` does not yet record the `extrapolated` / `extrapolated_features`
  fields the app emits — the excursion table above was computed after the fact from the
  envelopes. Worth adding before the next sweep.
