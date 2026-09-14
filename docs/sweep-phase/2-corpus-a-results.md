# Phase 2 results — corpus A (`.pig_pictures/`), Route 2

## Route taken and why

`adb devices` reported no attached device (empty list), so Route 1 (device-side, `adb pull` of
the app's own `instaham_cap_*.jpg`) was unavailable. Route 2 (host-side fallback) was used
instead, per the phase 2 doc's own fallback condition ("only if the device is unavailable").
**Route 1 remains preferred if the phone becomes available later** — this round is a documented
approximation, not a replacement for it.

## Conversion

`ML/host_scale_test/convert_corpus_a.py`, decoder versions: `pillow_heif` 1.6.0 (wrapping
`libheif` 1.23.2), `Pillow` 12.3.0. Mirrors `image_service.dart`'s five steps: decode → resize
to long edge ≤ 3000 px → JPEG q92 → decode → bake orientation → JPEG q92. All three source HEIC
files decode to already-upright 3024×4032 pixels (libheif applies the container-level `irot` on
decode) carrying a stale `Orientation=6` EXIF tag; that tag was deliberately **not** carried
into the intermediate JPEG, since baking it on top of already-upright pixels would rotate a
correctly-oriented image. This is confirmed correct by the output: all four files land at
2250×3000 portrait, unrotated, matching `docs/logs/recorded.md`'s device-observed dimensions —
had the stale tag been honored, the output would have come out landscape.

Output: `ML/host_scale_test/corpus_a/{75,92,96,118}kg_*.jpg`, all four **2250×3000** — dimension
gate passed, no rescaling of reference pixel lengths needed.

## `cm_per_px_actual` per file (unchanged from `docs/sweep.md`'s table, dimension gate confirms these apply as-is)

| file | reference cm | ref px | `cm_per_px_actual` |
|---|---|---|---|
| 75 kg | 100 | 1582 | 0.06321113 |
| 92 kg | 100 | 1547.62 | 0.06461534 |
| 96 kg | 131 | 2066.20 | 0.06340625 |
| 118 kg | 131 | 2005.63 | 0.06531661 |

## Cross-check against `docs/logs/recorded.md` round 2 (`cm_per_px_target = 0.35`)

| file | metric | recorded (round 2, row 1 / band) | this conversion | verdict |
|---|---|---|---|---|
| 92 kg | `k` | 0.18462 | 0.184615 | match |
| 92 kg | segArea (`mask_area_px`) | 1356422 | 1356133 (−0.02%) | match |
| 92 kg | `kept_fraction` | 0.8705 | 0.8697 | match |
| 92 kg | `predicted_kg` | 83.54 | 83.02 (−0.6%) | match, within jitter |
| 96 kg | `k` | 0.18115 (row 1) | 0.18116 | match |
| 96 kg | segArea | 1512523 (row 1) | 1513442 (+0.06%) | match |
| 96 kg | `kept_fraction` | 0.806–0.9516 (band) | 0.9059 | within band |
| 96 kg | `predicted_kg` | 78.53–88.84 (band) | 87.36 | within band |
| 118 kg | `k` | 0.18662 (row 1) | 0.186619 | match |
| 118 kg | segArea | 1820661 (row 1) | 1820644 (−0.001%) | match |
| 118 kg | `kept_fraction` | 0.9275–0.9344 (band) | 0.9292 | within band |
| 118 kg | `predicted_kg` | 104.80–118.49 (band) | 113.86 | within band |

`k` and segArea agree to within noise on all three cross-checked files — the strongest possible
signal that the host-side conversion is reproducing the same pixel content the device produced,
since `k` depends only on `cm_per_px_actual` (independently computed from the reference marks)
and `cm_per_px_target`, and segArea depends only on segmentation of the converted pixels.
**Route 2 is validated for this corpus.**

## 75 kg (floor row, no device recording exists to cross-check)

Segmentation succeeded (`segmentation_status: ok`, `cutter_status: cut_applied`,
`extrapolated: false`), `predicted_kg = 89.94` at `cm_per_px_target = 0.35`. Per the phase 2
doc, this file has no recorded device row and cannot be cross-checked; it is excluded from
phase 4 aggregates as a floor row regardless (see
`docs/adr/010-regressor-training-domain-floor.md`).

## Verification checklist

- [x] Four files exist, all readable by the harness (`segmentation_status: ok` on all four),
      all at the recorded 2250×3000.
- [x] 92 kg cross-check within jitter band.
- [x] 96 kg cross-check within jitter band.
- [x] 118 kg cross-check within jitter band.
- [x] 75 kg has no recorded device row; noted, excluded from aggregates.

## Known hazards carried forward

- The reference pixel lengths used are round 2's *first* mark of a six-mark band that moved
  the 92/96/118 kg predictions by 5.18–12.55%. Phase 4 must report these three field rows with
  that band attached, not as point estimates — this conversion's numbers sit inside those bands,
  they do not collapse them.
- This is a conversion check against round 2's pre-F55 device build, not a baseline. Phase 4
  must not compare its own predictions to round 2's numbers as if they measured the same code.
