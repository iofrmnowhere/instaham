# Phase 3 raw measurement log — health protocol comparison

Raw output of `health_protocol_measure_cli` (`packages/instaham_ml_ffi/src/test/`), run
2026-09-24 on the host build at `packages/instaham_ml_ffi/src/build/host`, against the real
shipped `assets/ml/manifest.json` (health checkpoint `health/model.onnx`, `health_v1`,
`fusion_max_abs_diff` 4.23e-06) via the actual `stages::run_segmentation` /
`stages::construct_pig_mask` / `pig_region_from_base_mask()` / `classifier.cpp::run_classifier`
call chain — the same code `pipeline.cpp` runs, not a Python reimplementation, per phase 3's
own instruction.

Command: `health_protocol_measure_cli.exe assets/ml/manifest.json <image> <cm_per_px_actual>`.

## Corpus

Three images — the same three the phase 2 parity gate used
(`docs/plan-phase-3/2-parity-gate-and-tests.md`), each a `valid_dorsal` scenario fixture with
a known `cm_per_px` from a real user-marked reference object
(`test/fixtures/scenarios/*/meta.json`). All three are `.pig_pictures/` originals, re-encoded.

| id | fixture | source | cm_per_px |
|---|---|---|---|
| 01 | `01_valid_dorsal_100cm_reference` | `.pig_pictures/92kg_pig_meter_stick.HEIC` | 0.12120232708468004 |
| 02 | `02_valid_dorsal_131cm_porac_reference` | `.pig_pictures/96kg_pig_porac_stick.HEIC` | 0.11888915779283642 |
| 03 | `03_valid_dorsal_custom_reference` | `.pig_pictures/75kg_pig_meter_stick.HEIC` | 0.11852085967130215 |

**This is the entire corpus with a segmentation mask available.** The fourth `.pig_pictures/`
file (`118kg_pig_porac_stick.jpg`) has no scenario fixture / recorded `cm_per_px` and was not
run. `06_lesion_closeup` was run separately below as a sanity check, not as corpus (it is
`health_only`, no mask is ever produced for it).

**No disease ground truth exists for any of the three.** All three are healthy pigs recorded
by their owner for weight measurement; none carries a condition label. This means phase 3 can
report the healthy-pig case and the label-change rate (both of which have a right answer here
— "stays Healthy" — even without a labelled corpus), but it cannot report per-class accuracy.
Corpus size: **n=3**, stated per the phase 3 doc's own requirement.

## Per-capture results

### 01 — 92 kg, meter-stick reference

`mask_fill_ratio` 0.743 (mask covers 74% of its own bounding box).

| protocol | label | confidence | P(Healthy) |
|---|---|---|---|
| full_frame | **Healthy** | 0.6758 | 0.6758 |
| segmentation_crop | Infected_Environmental_Sunburn | 0.5323 | 0.0084 |
| segmentation_masked | Infected_Environmental_Sunburn | 0.5243 | 0.0031 |

### 02 — 96 kg, porac-stick reference

`mask_fill_ratio` 0.589.

| protocol | label | confidence | P(Healthy) |
|---|---|---|---|
| full_frame | **Healthy** | 0.9724 | 0.9724 |
| segmentation_crop | Infected_Fungal_Ringworm | 0.8046 | 0.0098 |
| segmentation_masked | Infected_Bacterial_Erysipelas | 0.6879 | 0.0044 |

### 03 — 75 kg, meter-stick reference (near the weight-regressor floor; unrelated to health)

`mask_fill_ratio` 0.487.

| protocol | label | confidence | P(Healthy) |
|---|---|---|---|
| full_frame | **Healthy** | 0.9068 | 0.9068 |
| segmentation_crop | Infected_Environmental_Sunburn | 0.9910 | 0.0084 |
| segmentation_masked | Infected_Environmental_Sunburn | 0.9733 | 0.0016 |

### 06 — lesion close-up (sanity check, not corpus: `health_only`, no mask)

Confirms the degradation path fires correctly when there is no mask: all three protocols
collapse to the identical full-frame result (`protocol_applied: "full_frame"`,
`region_source: "none"`, `degraded: true` on the two region protocols requested).

| protocol requested | protocol applied | degraded | label | confidence |
|---|---|---|---|---|
| full_frame | full_frame | false | Infected_Environmental_Sunburn | 0.6252 |
| segmentation_crop | full_frame | true | Infected_Environmental_Sunburn | 0.6252 |
| segmentation_masked | full_frame | true | Infected_Environmental_Sunburn | 0.6252 |

## Follow-up: does the fill colour matter? (black vs. imagenet_mean)

User question, 2026-09-24: is the wrong-direction result specific to the `imagenet_mean` fill
colour the manifest specifies, or does any masking hurt regardless of fill? Tested by adding a
fourth run per image, `segmentation_masked_black` — the same `segmentation_masked` path with
`background_fill` set to `"black"` instead of `"imagenet_mean"` (`health_input.cpp`'s
`crop_to_bbox()` already defaults `fill_rgb` to `{0,0,0}` for any non-`"imagenet_mean"` string,
so this exercises the real code, not a new branch).

| | full_frame | segmentation_masked (imagenet_mean) | segmentation_masked (black) |
|---|---|---|---|
| 01 | Healthy 0.68 | Sunburn 0.52 | Ringworm 0.76 |
| 02 | Healthy 0.97 | Erysipelas 0.69 | Erysipelas 0.72 |
| 03 | Healthy 0.91 | Sunburn 0.97 | Sunburn 0.98 |

Black fill is not better — still 3/3 wrong, and confidence in the wrong label is flat or
slightly higher than with `imagenet_mean` on all three images. The fill colour is not the
cause; masking itself is. This is consistent with the earlier read: the checkpoint was trained
on close-up condition photos, never on an image with a large flat-coloured region (any colour)
standing in for removed background, so any fill introduces an out-of-distribution artefact.

## Follow-up: background removed, but NOT cropped (user question, 2026-09-24)

Isolates the two things `segmentation_masked` does together: does removing the background
alone help, independent of also cropping tight to the pig's box? Hand-assembled in the CLI
(`run_masked_no_crop()`) from the same exported pieces `prepare_health_input()` uses, since no
shipped protocol does this — the mask is resampled to the FULL captured frame's own
dimensions (not the padded pig box), background painted `imagenet_mean`, and the model's usual
resize-shorter-then-crop runs over that full masked frame, same as `full_frame` does over an
unmasked one.

| | full_frame | segmentation_masked (crop+mask) | mask only, no crop |
|---|---|---|---|
| 01 | Healthy 0.68 | Sunburn 0.52 | Dermatitis 0.72 |
| 02 | Healthy 0.97 | Erysipelas 0.69 | Sunburn 0.38 (P(Healthy) 0.19) |
| 03 | Healthy 0.91 | Sunburn 0.97 | Sunburn 0.87 |

Still 3/3 wrong. Image 02 is notably less confidently wrong (`P(Healthy)` 0.19 instead of
0.004-0.01 elsewhere), but no image flips back to the correct label. Removing the background
without cropping does not rescue the result either — consistent with the black-fill follow-up
above: the failure is not specific to one combination of crop + fill, it is masking itself
(any large flat-fill region) that the checkpoint has never seen in training.

## A real bug found and fixed while building this measurement

The CLI's first draft held the recovered `PigRegion`'s mask pointer (`region.mask`) pointing
into a `stages::PigMask` local variable that went out of scope before the three
`run_classifier()` calls that read it — a dangling pointer. The first run under that bug
produced `segmentation_crop` and `segmentation_masked` results that were bit-identical to
full float32 precision on all three images, which does not happen with a real, non-rectangular
mask (fill ratios above are 0.49-0.74, i.e. a quarter to half of each bounding box is
background). Moving the `PigMask` to the function's outer scope
(`packages/instaham_ml_ffi/src/test/health_protocol_measure_cli.cpp`) fixed it; the numbers
in this log are from the corrected build. This is a bug in the new measurement CLI only —
`pipeline.cpp` keeps `pig_mask` alive for its entire request and was never affected.
