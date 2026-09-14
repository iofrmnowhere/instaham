# Phase 2 — build corpus A through the app's own decode path

Status: done — see `docs/sweep-phase/2-corpus-a-results.md` for full results, cross-checks, and
the route-2 justification (no device was attached: `adb devices` returned empty).

## Goal

Turn the four `.pig_pictures/` photographs into files the host harness can read, such that what
the harness sees is what the app's native pipeline would have seen. Three of the four are HEIC.

This is a correctness requirement, not a convenience one: the conversion is part of the
measurement. A cleaner input than the device produces would make the harness score a pipeline
that does not ship.

## What the app actually does

`lib/core/utils/image_service.dart` is the whole path, and it is not a plain decode. In order:

1. `ImagePicker.pickImage(source: gallery, maxWidth: 3000, maxHeight: 3000, imageQuality: 92)`.
   The resize and the first JPEG encode happen **on the Android plugin side**, not in Dart. This
   is also where HEIC becomes JPEG — Android transcodes it for the requesting app.
2. `img.decodeImage(rawBytes)` — `package:image` ^4.3.0.
3. `img.bakeOrientation(decoded)` — EXIF orientation baked in, satisfying AGENTS.md rule 5.
4. `img.encodeJpg(oriented, quality: 92)` — a **second** JPEG encode at quality 92.
5. Written to the temp directory as `instaham_cap_<ms>.jpg`. That path is what reaches FFI.

So the native pipeline receives a doubly-JPEG-compressed, ≤3000 px, orientation-baked JPEG.
`docs/logs/recorded.md` confirms the resulting dimensions for these photographs: **2250 × 3000**,
gallery-import path.

Converting the HEIC files to PNG with an arbitrary tool would skip both JPEG encodes and the
3000 px cap. That is not the same input.

## Two routes

### Route 1 — device-side, recommended (not used this round: no device attached)

Run the four photographs through the installed app's own import path and pull the temp JPEGs off
the phone with `adb`. Exact by construction: every step above is the real one, including the
Android-side HEIC transcode that the host cannot reproduce.

Costs a sideload and some `adb` work. Spends **no** Firebase Test Lab quota — this is the user's
own physical phone, which is how native and ML changes are tested on this project anyway.

- [ ] Import each of the four photographs through the app's gallery picker.
- [ ] `adb pull` the resulting `instaham_cap_*.jpg` from the app's temp directory.
- [ ] Store them under `ML/host_scale_test/corpus_a/` with names that preserve the true weight,
      matching the `parse_true_kg` convention the existing drivers use.

### Route 2 — host-side fallback (used this round)

Only if the device is unavailable. Reproduces steps 2–4 faithfully and approximates step 1.

- [x] Decode HEIC with a named, version-recorded decoder — `pillow_heif` 1.6.0 (`libheif`
      1.23.2). `package:image` cannot decode HEIC, so Dart alone will not do it.
- [x] Downscale so the long edge is ≤ 3000 px, matching the observed 2250 × 3000.
- [x] JPEG-encode at quality 92, decode, bake orientation, JPEG-encode at quality 92 again — the
      double encode is deliberate and was preserved. See
      `docs/sweep-phase/2-corpus-a-results.md` for the stale-EXIF-orientation finding.
- [x] Record the decoder and its version in phase 4's results header as a stated deviation.
      (`pillow_heif` 1.6.0 / `libheif` 1.23.2 / `Pillow` 12.3.0 — see results doc.)

`118kg_pig_porac_stick.jpg` is already JPEG, so it passes through both routes without the HEIC
step. If both routes are run, it is the natural control: a large disagreement on that one file
means route 2's approximation is not faithful, and the field rows must be labelled accordingly.

## The dimension gate

This is a hard gate on phase 4 and the most likely silent failure in the whole plan.

`cm_per_px_actual` is resolution-dependent. The reference pixel lengths in `docs/sweep.md` were
marked in the app's post-resize 2250 × 3000 space. If phase 2's output has different dimensions,
every one of those lengths is wrong by the dimension ratio, and the four field rows are wrong
without looking wrong.

- [x] Assert each converted file is 2250 × 3000 (or record the actual dimensions and rescale
      every reference pixel length by the exact ratio before phase 4 runs). **All four landed at
      2250 × 3000** — no rescaling needed.
- [x] Recompute and record `cm_per_px_actual` per file from the reference length actually used:

| file | reference cm | ref px | `cm_per_px_actual` |
|---|---|---|---|
| 75 kg | 100 | 1582 | 0.06321113 |
| 92 kg | 100 | 1547.62 | 0.06461534 |
| 96 kg | 131 | 2066.20 | 0.06340625 |
| 118 kg | 131 | 2005.63 | 0.06531661 |

## Verification

- [x] Four files exist, all readable by the harness, all with recorded dimensions.
- [x] The 92 kg file, run at `cm_per_px_target = 0.35`, reproduces `docs/logs/recorded.md`
      round 2's first row within the jitter band — `k` ≈ 0.18462, `segArea` ≈ 1356422,
      `kept_fraction` ≈ 0.87, prediction ≈ 83.5 kg. This is the single best available check that
      the conversion is faithful, because that row was measured on the device through the real
      path. Treat a large disagreement as a conversion failure, not as a finding about the
      pipeline. **Matched: see `docs/sweep-phase/2-corpus-a-results.md`.**
- [x] Cross-check the same way on 96 kg and 118 kg, whose round 2 rows are also recorded.
      **Both within their recorded jitter bands.**
- [x] The 75 kg photograph has no recorded device row and cannot be cross-checked. Noted; it is
      a floor row anyway and is excluded from aggregates.

## Known hazards

- The reference pixel lengths for 92, 96 and 118 kg are the *first* row of a six-mark band, not a
  single truth. `docs/logs/recorded.md` shows those bands moving the prediction by 5.18–12.55 %.
  Phase 4 must report the field rows with that band attached, not as point estimates.
- Round 2's numbers were taken at `cm_per_px_target = 0.35` on the pre-F55 device build. They are
  a conversion check, not a baseline to beat. Do not compare phase 4's predictions to them as if
  they measured the same code.
