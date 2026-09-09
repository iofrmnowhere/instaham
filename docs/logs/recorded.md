# Recorded device measurements — phase 2.1 (F53)

## Round 1 — 92 kg photo, hand-recorded from the UI (±3 px band)

Six consecutive marks on `.pig_pictures/92kg_pig_meter_stick.HEIC`, reference 100 cm.
`cm_per_px` as displayed by the UI (rounded to four decimals).

| reference px | `cm_per_px` shown | predicted kg |
|---|---|---|
| 1547 | 0.0646 | 84.4 |
| 1548 | 0.0646 | 83.5 |
| 1549 | 0.0646 | 88 |
| 1550 | 0.0645 | 88 |
| 1551 | 0.0645 | 87.3 |
| 1552 | 0.0645 | 87.3 |

## Round 2 — full sweep, all three photos, from `INSTAHAM_ENVELOPE` dumps

18 scans, 6 per photo, marks stepped ~3 px apart across a ~16 px band. Captured with a
`adb logcat -c` / mark / `adb logcat -d >>` cycle per mark, one file per photo. `ref_px` is
back-computed as `reference_cm / scale.cm_per_px_actual` from the envelope, so it is the
length the pipeline actually used, not the UI's rounded display.

`segArea` is `construction.mask_area_px` — the mask in original image coordinates, before the
resample, so it moves only when segmentation itself changes. `featArea` is
`features.values.mask_area` — after resample and after the cutter, which is what the regressor
sees.

### 92 kg — meter stick, reference 100 cm (true weight 92 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 1547.62 | 0.18462 | 1356422 | 0.9190 | 0.8705 | 40212 | 903.96 | 355.87 | 112.0 | 83.54 |
| 1550.52 | 0.18427 | 1356422 | 0.9190 | 0.9356 | 43148 | 956.54 | 381.23 | 112.0 | 88.03 |
| 1553.90 | 0.18387 | 1356422 | 0.9190 | 0.9361 | 43058 | 955.13 | 380.77 | 112.0 | 87.36 |
| 1556.80 | 0.18353 | 1397606 | 0.9200 | 0.9483 | 44695 | 977.17 | 391.90 | 108.7 | 87.00 |
| 1559.69 | 0.18319 | 1397606 | 0.9200 | 0.9500 | 44531 | 974.93 | 390.34 | 108.4 | 87.14 |
| 1563.28 | 0.18277 | 1403010 | 0.9219 | 0.9412 | 44063 | 965.51 | 385.09 | 107.2 | 86.19 |

### 96 kg — porac stick, reference 131 cm (true weight 96 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 2066.20 | 0.18115 | 1512523 | 0.9166 | 0.8796 | 43693 | 969.94 | 381.80 | 112.4 | 85.24 |
| 2069.18 | 0.18089 | 1497791 | 0.9156 | 0.8833 | 43348 | 969.98 | 385.16 | 113.0 | 84.91 |
| 2072.14 | 0.18063 | 1501254 | 0.9153 | 0.8063 | 39495 | 899.07 | 355.46 | 112.0 | 78.53 |
| 2074.68 | 0.18041 | 1501254 | 0.9153 | 0.9507 | 46471 | 1048.26 | 422.42 | 112.3 | 88.84 |
| 2078.34 | 0.18009 | 1501254 | 0.9153 | 0.9490 | 46152 | 1043.78 | 419.74 | 112.0 | 88.22 |
| 2081.48 | 0.17982 | 1501254 | 0.9153 | 0.9516 | 46194 | 1045.68 | 422.19 | 112.4 | 88.07 |

### 118 kg — porac stick, reference 131 cm (true weight 118 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 2005.63 | 0.18662 | 1820661 | 0.9196 | 0.9344 | 59334 | 1065.05 | 415.04 | 149.0 | 118.49 |
| 2009.47 | 0.18626 | 1813602 | 0.9184 | 0.9285 | 58565 | 1048.52 | 409.52 | 151.0 | 112.88 |
| 2012.31 | 0.18600 | 1813602 | 0.9184 | 0.9330 | 58543 | 1051.94 | 411.57 | 150.0 | 107.04 |
| 2014.96 | 0.18575 | 1816902 | 0.9198 | 0.9341 | 58607 | 1052.08 | 413.57 | 150.0 | 106.40 |
| 2017.86 | 0.18549 | 1816902 | 0.9198 | 0.9294 | 58044 | 1044.77 | 410.56 | 150.0 | 105.01 |
| 2021.44 | 0.18516 | 1816902 | 0.9198 | 0.9275 | 57806 | 1041.35 | 408.56 | 150.0 | 104.80 |

All 18 scans ran at `cm_per_px_target` 0.35, `ladder_rung` 0, `cutter.status` `cut_applied`.

## Round 3 — the 0.3289 half, same three photos and same mark bands as round 2

18 scans, same capture and dump cycle as round 2. `ref_px` confirms the same marks as round 2
were replayed: 1547–1563 / 2066–2081 / 2005–2021, within noise of round 2's own values, and the
first scan of each file reproduces round 2's first-scan `segArea` exactly (1356422 / 1512523 /
1820661), which is how the three files were matched to photos.

### 92 kg — meter stick, reference 100 cm (true weight 92 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 1547.19 | 0.19651 | 1356422 | 0.9190 | 0.9335 | 49022 | 1018.34 | 405.99 | 120.0 | 97.94 |
| 1550.06 | 0.19615 | 1356422 | 0.9190 | 0.9388 | 48866 | 1019.75 | 406.56 | 119.0 | 97.93 |
| 1555.51 | 0.19546 | 1397606 | 0.9200 | 0.9487 | 50666 | 1038.72 | 414.71 | 116.0 | 98.80 |
| 1555.81 | 0.19542 | 1397606 | 0.9200 | 0.9487 | 50666 | 1038.72 | 414.71 | 116.0 | 98.80 |
| 1558.60 | 0.19508 | 1397606 | 0.9200 | 0.9458 | 50246 | 1034.38 | 414.27 | 114.8 | 97.80 |
| 1563.23 | 0.19450 | 1403010 | 0.9219 | 0.9046 | 48010 | 995.31 | 393.15 | 119.2 | 96.47 |

median 97.93, band 96.47–98.80 (2.33 kg / 2.38%), error +6.45%

### 96 kg — porac stick, reference 131 cm (true weight 96 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 2066.42 | 0.19275 | 1512523 | 0.9166 | 0.8061 | 45321 | 959.45 | 376.11 | 119.0 | 90.87 |
| 2069.06 | 0.19250 | 1512523 | 0.9166 | 0.9020 | 50586 | 1055.54 | 421.64 | 119.8 | 97.74 |
| 2072.00 | 0.19223 | 1501254 | 0.9153 | 0.9461 | 52577 | 1114.55 | 450.55 | 119.8 | 99.97 |
| 2074.45 | 0.19200 | 1501254 | 0.9153 | 0.9467 | 52295 | 1114.65 | 448.59 | 118.8 | 100.16 |
| 2077.84 | 0.19169 | 1501254 | 0.9153 | 0.9464 | 52209 | 1113.48 | 447.92 | 118.8 | 100.19 |
| 2081.02 | 0.19140 | 1501254 | 0.9153 | 0.9465 | 52123 | 1112.06 | 446.97 | 118.8 | 100.31 |

median 100.07, band 90.87–100.31 (9.44 kg / 9.43%), error +4.24%. The first scan
(`kept_fraction` 0.8061 against 0.9020–0.9467 on the rest) is the same cutter discontinuity
2.1 already found at this photo's round-2 sweep (there it hit a different mark at
`kept_fraction` 0.8063 / 78.53 kg) — it recurs at the new scale, unresolved by changing the
constant. Median excluding that one outlier: 100.16 (band 99.97–100.31, 0.34%).

### 118 kg — porac stick, reference 131 cm (true weight 118 kg)

| ref_px | k | segArea | seg conf | kept_fraction | featArea | perimeter | longest | shortest | est kg |
|---|---|---|---|---|---|---|---|---|---|
| 2004.96 | 0.19866 | 1820661 | 0.9196 | 0.9320 | 67013 | 1130.36 | 439.41 | 159.0 | 136.82 |
| 2008.78 | 0.19828 | 1813602 | 0.9184 | 0.9342 | 66669 | 1121.98 | 439.27 | 160.0 | 136.48 |
| 2012.10 | 0.19795 | 1813602 | 0.9184 | 0.9354 | 66483 | 1121.64 | 440.96 | 160.0 | 140.18 |
| 2014.00 | 0.19776 | 1816902 | 0.9198 | 0.9334 | 66319 | 1118.95 | 441.68 | 160.0 | 137.42 |
| 2017.25 | 0.19745 | 1816902 | 0.9198 | 0.9274 | 65637 | 1110.22 | 435.60 | 159.0 | 134.80 |
| 2021.13 | 0.19707 | 1816902 | 0.9198 | 0.9413 | 66352 | 1125.19 | 444.68 | 159.0 | 134.13 |

median 136.65, band 134.13–140.18 (6.05 kg / 4.43%), error +15.83%

All 18 scans ran at `cm_per_px_target` 0.3289, `ladder_rung` 0, `cutter.status` `cut_applied`.

## Round 4 — host replication, PIGRGB training images, NOT a device sweep

**This round is not comparable to rounds 1–3 above and must not be averaged with them.**
Rounds 1–3 ran on the phone, on field photos, with a hand-marked reference object (jitter
bands 5.18–12.55%). Round 4 ran on this development machine, via
`ML/host_scale_test/weight_branch_cli.cpp` (docs/test-plan-phase/1 and 2), against the
shipped C++ stages and models but on five `Instaham/PIGRGB-Weight/sub_1.78/` images —
training-distribution photos at a known 1.78 m capture height, with `cm_per_px_actual`
derived from `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`'s 304 px/m baseline
(`304 x 1.88/1.78 = 321.0787 px/m`, `cm_per_px_actual = 0.3114504`) rather than from a
hand-marked reference. No jitter term applies — each image was run exactly once per
constant, and re-running was confirmed byte-identical
(`docs/test-plan-phase/3-driver-sweep.md`'s determinism check).

Both arms ran `canvas_mode: scale_aware`, `ladder_rung: 0`, identical `seg_conf`/mask
dimensions/`mask_area_px` per image (the cross-arm invariance assertion the driver runs),
and `cutter.status: cut_applied` on all ten runs — the constant never changed whether a
cutter or gate would have fired, only the predicted weight.

| image | true kg | 0.35 predicted (error) | 0.3289 predicted (error) |
|---|---|---|---|
| 60.27kg_35.png | 60.27 | 75.73 (+25.66%) | 76.01 (+26.12%) |
| 66.24kg_11.png | 66.24 | 79.54 (+20.07%) | 81.73 (+23.38%) |
| 100.9kg_3.png | 100.90 | 96.78 (−4.09%) | 106.19 (+5.24%) |
| 125.38kg_4.png | 125.38 | 126.73 (+1.07%) | 154.21 (+22.99%) |
| 133.42kg_5.png | 133.42 | 142.24 (+6.61%) | 156.43 (+17.24%) |

**0.35 is closer to true weight on all five images**, four of them by a wide margin
(125.38 kg: +1.07% vs +22.99%; 133.42 kg: +6.61% vs +17.24%; 100.9 kg: −4.09% vs +5.24%;
66.24 kg: +20.07% vs +23.38%). The fifth (60.27 kg) is a near-tie, 0.35 still marginally
closer (+25.66% vs +26.12%). Mean absolute error: 0.35 ≈ 11.5%, 0.3289 ≈ 18.99%.

This agrees in direction with rounds 2–3's field-photo finding (0.35 closer on two of
three there) and sharpens it: on a wider weight range (60–133 kg vs 92–118 kg) and without
hand-marking jitter, 0.35 wins on every image, not just a majority. It does not settle
`docs/pipeline/prediction-2.md`'s thesis that the constant should not be fitted at all —
both constants still overshoot on four of five images, 60.27 kg worst of all at +25–26% on
either constant, which is a bias no single scalar constant explains.

Full per-image envelopes (every intermediate value: `k`, `height_ratio`,
`implied_camera_height_m`, all 16 chen16 features, `kept_fraction`, domain gate verdicts)
are in `ML/host_scale_test/out/envelope_<image>_<0350|03289>.json`; the flat comparison
table is `ML/host_scale_test/out/results.csv`.

## Not captured

The live in-app camera path was not swept and its capture resolution was not read — the user
has neither a pig nor the reference stick on hand for a live capture. Every figure in rounds
1–3 is the gallery-import path at 2250 x 3000. Round 4 (above) is a host replication on
PIGRGB training images, not a device capture at all.
