# Fix (round 8): the segmenter never sees the physically normalized photograph

Fourth active fix document, opened as **round 8** on 2026-09-18 and **reopened on 2026-09-19**
under a revised instruction from the user.

[`INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md`](../INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md)
(repository root) is the **specification for this round**, not a proposal to be evaluated. It is
implemented as written. [`scaling-rotation-readme-analysis.md`](scaling-rotation-readme-analysis.md)
remains useful as a record of which of its claims were checked, but it no longer has standing to
override it.

Finding numbering continues at **F60** (F59 was the last assigned, in the round-28 scale
sweep).

## Reopening note — read before working any phase

The round was closed on 2026-09-18 with a **REJECT** verdict produced by phase 2, a measurement
gate that this plan itself invented. The user overruled that verdict: the README was designated
as the basis for the work, and a gate empowered to discard the designated basis is a
counter-proposal, not a plan. **The REJECT verdict is void.** Phase 2's numbers survive as
recorded observations and are reproduced in
[`fix-phase-4-2-results.md`](fix-phase-4-2-results.md); they are evidence, not authority.

The user's instruction on 2026-09-19 is to **brute-force the README's scaling and rotation
basis** — implement it, ship it, and raise disagreements as flags rather than as gates. The
three divergences the previous plan declared (the F61 oversize fallback, the retained retry
ladder, the manifest switch defaulting off) are therefore **withdrawn**; see phase 1.1.

## Symptom

Field captures produce segmentation masks with unnatural straight cutoffs, and the weight
estimate derived from them is wrong in a way no choice of `cm_per_px_target` fixes. The pig is
presented to YOLO at a physical scale unrelated to the scale the segmentation model was
trained at.

## Root cause

**F60 — the photograph is never normalized; only the mask is.** `stages/segmentation.cpp`
composes the decoded capture into the 640x640 model canvas at
`content_scale = cm_per_px_actual / input_cm_per_px`, using
`capabilities.segmentation.input_scale.cm_per_px = 1.1` and the retry ladder
`[1.0, 1.32, 1.68, 0.77]` (`stages/canvas_scale.h`, `pipeline.cpp:329-360`). The selected mask
is only afterwards transformed into 0.34 cm/px training space (`pipeline.cpp:675`). The
segmenter therefore sees the pig at roughly 0.85-1.85 cm/px, while the PIGRGB frames behind
both the segmentation and weight models sit at about 0.33 cm/px in 960x540 releases
(`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md:29`).

**F61 — the README's fit invariant fails on captures this project already holds.** README §6
and §17 require `rotatedWidth <= 960` and `rotatedHeight <= 540` after normalization, with no
fallback. `logs/adb_log.md` records `content_scale = 0.05857691168785095` at
`input_cm_per_px_used = 1.1`, implying `cm_per_px_actual ≈ 0.0644`. A 4032x3024 capture
normalized to 0.34 cm/px is 764x573; 573 exceeds 540, and rotation does not help a landscape
frame. **Under the brute-force instruction this now ships as README §6 specifies — a declared
halt.** It is carried as an open flag below, not as a licence to add a fallback.

> **CORRECTION 2026-09-19 (phase 3). F61's derivation above does not hold.** It pairs a
> `cm_per_px_actual` with a capture size the value was not measured on. `cm_per_px_actual` is
> centimetres per pixel *of the image it was measured on*, so it cannot be carried between
> resolutions of the same photo.
>
> The same `adb_log.md` entry settles which resolution its 0.0644 belongs to. It records
> `height_ratio = 0.6643095400323831` at `cm_per_px_target = 0.35`, and `pipeline.cpp`
> computes `height_ratio = k × sqrt(w·h) / sqrt(720·720)` with `k = cm_per_px_actual /
> cm_per_px_target`. Solving for the capture: `sqrt(w·h) = 0.6643 × 720 / 0.18410 = 2598.1`,
> and `sqrt(2250 × 3000) = 2598.1` exactly, against `sqrt(3024 × 4032) = 3491.8`. **The device
> was processing a 2250x3000 image, not a 4032x3024 one.** At 2250 px and 0.0644 cm/px the
> capture covers 145.0 cm of ground on its short side, needing **426 of the 540 px available**
> — it fits, with about 21% headroom.
>
> What the invariant actually bounds is ground coverage, not pixels: at most `960 × 0.34 =
> 326 cm` on the long side and `540 × 0.34 = 184 cm` on the short side. Halving an image's
> pixels doubles its `cm_per_px_actual`, leaving the product unchanged, so resolution cannot
> decide the fit. §6 halts a capture taken from too far back.
>
> Phase 1.1's separate "F61 fired on a real corpus image" result repeats the same error with a
> file instead of a hypothetical, and is retracted in
> [fix-phase-4/1.1-readme-is-the-path.md](fix-phase-4/1.1-readme-is-the-path.md). Both pieces
> of evidence for F61 are invalid; see the downgraded flag below.

**F62 — two disagreeing "training frame" constants.** The weight capture contract declares
`training_frame_px = [720, 720]`, consumed by the mask-diagonal plausibility check at
`pipeline.cpp:508` with `min_mask_diagonal_fraction = 0.35`. The README introduces 960x540 as
the training-like frame without reconciling the two. Phase 3 reconciles them.

**F64 — the app has never run the README's pipeline.**
`packages/instaham_ml_ffi/src/pipeline.cpp` contains no reference to `input_scale_mode` or
`normalize_first`. Phase 1 landed the new composition path in `stages/segmentation.cpp` and
wired it only into `ML/host_scale_test/weight_branch_cli.cpp`. The shipped app path is
unchanged and unaware of it. **Closed 2026-09-19 (phase 4)** — `pipeline.cpp` now calls
`run_segmentation()` once at `cm_per_px_target`, the same composition
`weight_branch_cli.cpp` runs; see [fix-phase-4/4-app-wiring.md](fix-phase-4/4-app-wiring.md)'s
Result section. Device confirmation is still open.

**F65 — README §4's head-direction assumption was enforced nowhere.** §4 assumes a portrait
capture has the pig's head at the top, and forbids inferring head direction at preprocessing
time. Nothing in the app made that true. The user's 2026-09-19 instruction resolves this by
constraining capture instead of inference:

- **Portrait captures require the pig's head facing up.**
- **Landscape captures require the pig's head facing right.**

Both rules land the pig head-right at the segmenter: portrait rotates 90° clockwise per §4 and
the head swings from top to right; landscape is not rotated and the head is already right. The
landscape half is an **addition to the README**, which says only "do not rotate" for landscape
and is silent on its head direction. Phase 6 enforces both at capture time.

## Change made

Nothing yet — this document is a plan. The intended change is the README's pipeline, shipped:
uniform resize to `cm_per_px_target`, 90° clockwise rotation for portrait, centring unresized on
a 960x540 canvas, a single segmentation pass, then the inverse canvas and rotation transforms on
the returned mask — as the app's only segmentation input path, with capture-time orientation
constraints making §4's assumption true.

## Divergences from the README — withdrawn

The previous revision of this plan declared three deliberate divergences. All three are
withdrawn under the brute-force instruction:

| Previous divergence | Now |
|---|---|
| F61 oversize canvas gets a defined fallback | **Withdrawn.** README §6 halts. Flagged below. |
| Retry ladder retained on the new path | **Withdrawn.** README §13 is a single pass. |
| New path behind a manifest switch defaulting off | **Withdrawn.** It becomes the only path. |

The one remaining substantive disagreement — README §3's stated rationale for the canvas, which
does not hold arithmetically — is a **documentation** matter, not a behavioural one. The canvas
still ships; phase 3 records the defensible reason for it (frame-geometry parity with the
960x540 PIGRGB releases) alongside the README's.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Host-side normalize-before-segment path, behind a manifest switch | **done 2026-09-18 — superseded by phase 1.1** — the composition path, rotation pair and inverse transforms were built and build clean; `ctest` 7 of 9, the two failures pre-existing at `06d2ecd`. What it got wrong is structural, not arithmetic: an off-by-default switch, a host-only wiring, a retained ladder and an added fallback. Do not redo the composition code. | [fix-phase-4/1-normalize-before-segment.md](fix-phase-4/1-normalize-before-segment.md) |
| 1.1 | Make the README path the only path | **done 2026-09-19** — mode switch, host-CLI retry ladder and F61 enlargement deleted; README §6's halt ships. `pipeline.cpp`'s own ladder is untouched (phase 4's scope) and now runs the normalize-first arithmetic with stale substitutes — **do not build/sideload an APK before phase 4**. ~~F61 confirmed firing on a real corpus image (581x774 → rotated 774x581 → halts against 540), not just predicted.~~ **That result is retracted (phase 3)** — the smoke test gave a 3024x4032 file the scale measured on its 2250x3000 copy; with the correct scale it fits. Build clean, `ctest` 8/9 (2 pre-existing failures). | [fix-phase-4/1.1-readme-is-the-path.md](fix-phase-4/1.1-readme-is-the-path.md) |
| 2 | Measure it: detection, MAE and jitter against the shipped path | **closed 2026-09-18 — verdict VOID, not repeated** — the measurement ran and its numbers stand as observations; its authority to gate the round does not. Retained for the evidence only. | [fix-phase-4/2-measurement.md](fix-phase-4/2-measurement.md) |
| 3 | Reconcile the frame and scale constants | **done 2026-09-19** — `training_frame_px` and `min_mask_diagonal_fraction` verified unchanged against real corpus A/B images (F62's stated mechanism didn't hold); provenance added for the 960x540 canvas and the 304 px/m doc's standing; `segmentation.input_scale.cm_per_px` renamed to `legacy_ladder_base_cm_per_px` to stop it being misread as the README's scale. **Also retracted F61** — both its evidence pairs a capture size with a `cm_per_px_actual` from another resolution; no §6 ruling is needed before phase 4. `ctest` 8/9 (2 pre-existing failures). See the phase file's Result section. | [fix-phase-4/3-constants.md](fix-phase-4/3-constants.md) |
| 4 | Wire the app and verify on device | **native side done 2026-09-19, device sideload still open** — `pipeline.cpp` now runs the README's single normalize-first pass at `cm_per_px_target` (round-4 retry ladder deleted), surfaces the section 6 halt as a declared failure at every envelope level, fixes `k = 1.0` (F60), and calls `rotate_pig_mask_90_ccw()` on both masks it builds -- a real gap this phase closes, not a re-check. Verified through the real `instaham_ml_run_pipeline_request_json()` entry point against a corpus A image: matches `weight_branch_cli.exe` bit-for-bit (88.9058837890625 kg, same mask dims/areas); a forced-oversize run and a no-reference run both degrade cleanly with health unaffected. Dart confirmed to need no change. The round-4 `input_scale` manifest block is removed (hand-carried, not re-exported -- same call and reasoning as phase 3). Build clean, `ctest` 8/9 (2 pre-existing failures). Device sideload and the phase-2-capture comparison are the user's own next step, not done this session. | [fix-phase-4/4-app-wiring.md](fix-phase-4/4-app-wiring.md) |
| 5 | Stage debug outputs and shipped assertions | **done 2026-09-21** — README §16 scalars in the envelope (`resize_factor`, `normalized_w/h` now set on every run, `x_offset/y_offset`, `rotated_width/height`, `base_mask_w/h`, `final_mask_w/h`); §17's checks shipped via new `stages/invariants.h`, most already enforced by `decide_normalize_first_composition()` and now stated explicitly. One real finding: the vendor cutter's Ji/Duan gap-fill legitimately adds ~0.04% foreground pixels beyond the base mask on the one photo checked, so the "FINAL_MASK ⊆ BASE_MASK" check ships tolerance-gated (1%, `final_mask_added_px`/`removed_px` always recorded) rather than failing every capture. `weight_branch_cli.exe` gained `--dump-stages` for §16's three-image comparison; produced and visually confirmed pixel-aligned for one corpus A and one corpus B image. `ctest` 9/10 (2 pre-existing failures, one test slot added). End-to-end read-back via a scratch FFI harness reproduces phase 4's 88.9058837890625 kg bit-for-bit. Capture orientation/head-attestation fields deferred to phase 6. See the phase file's Result section. | [fix-phase-4/5-debug-and-assertions.md](fix-phase-4/5-debug-and-assertions.md) |
| 6 | Enforce capture orientation (portrait head-up, landscape head-right) | **done 2026-09-22** — closes F65. `CaptureOrientation` enum, tips-list additions, a live in-camera prompt driven by `CameraController.value.deviceOrientation`, an un-pre-ticked confirm checkbox gating "Verify reference," and two new `ScanRecords` columns (schemaVersion 4→5, migration + test) recording the orientation and attestation. No native change. `flutter analyze` clean; `flutter test` on the changed behaviour (12 tests across two files) passes. See the phase file's Result section. | [fix-phase-4/6-capture-orientation.md](fix-phase-4/6-capture-orientation.md) |

Work them in numerical order: 1.1, 3, 4, 5, 6. **No phase in this round is a gate.** A phase may
report that a number moved the wrong way; that is a flag raised to the user, and it does not
authorise skipping the phases after it.

## Verification

**Round reopened 2026-09-19.** The round closes when the README's pipeline is the app's
pipeline: `assets/ml/manifest.json` regenerated (never hand-edited) so the normalize-first
composition is what ships, `pipeline.cpp` running it, README §16 debug fields and §17 assertions
in place, the capture screen enforcing both orientation rules, and a sideloaded APK confirming
the envelope on device against the host numbers.

F49 in [`fix-phase-2/3-normalization-order.md`](fix-phase-2/3-normalization-order.md) is
**reopened** — it was closed as "superseded" on the strength of the void verdict. Its answer is
now the README's order, by instruction.

## Open flags

- **~~F61 halts on ordinary captures.~~ DOWNGRADED 2026-09-19 (phase 3) — it does not.** The
  original flag read: "a 4032x3024 capture at 0.34 cm/px is 764x573; 573 > 540, and README §6
  says halt, so the weight branch declares failure on full-resolution phone photographs." That
  worked example silently assumes a `cm_per_px_actual` under which the photo covers ~1.95 m of
  ground on its short side. **Resolution is not what decides the fit.** `cm_per_px_actual` is
  measured on the image it belongs to, so halving an image's pixels doubles it and the product
  is unchanged; what the invariant actually bounds is how much *ground* the frame covers —
  at most `960 × 0.34 = 326 cm` on the long side and `540 × 0.34 = 184 cm` on the short side.
  Phase 1.1's "F61 fired on a real corpus image" result is **retracted**: it fed a 3024x4032
  file the `cm_per_px_actual` measured on the 2250x3000 copy of the same photo. With that file's
  own scale (0.0486) it fits and predicts 125.49 kg against a true 118 kg. All nine corpus
  images re-run under phase 3 fit, each using 418–432 px of the 540 available. The project's
  field photos cover ~145 cm on the short side, ~20% inside the bound. See
  [fix-phase-4/1.1-readme-is-the-path.md](fix-phase-4/1.1-readme-is-the-path.md)'s retraction
  block for the measurements.
  The original adb-log derivation fails the same way and is corrected in the Root cause section
  above: that log's own `height_ratio` resolves its capture to **2250x3000**, needing 426 of
  540 px. **Neither piece of evidence for F61 survives.**
  **No ruling is needed before phase 4, and the halt ships as written.** §6 halts a capture
  taken from too far back, not a high-resolution one. If a halt does appear on device, the
  first suspect is the app pairing a reference mark and an image from different coordinate
  spaces (AGENTS.md rules 6 and 9) — a real defect to find, not a reason to grow the canvas.
- **The retry ladder's removal is untested for detection regressions.** The ladder was added in
  round 4 (F18/F19) because detection failed without it. Phase 1.1 removes it on the README path
  per §13. The user's 2026-09-21 device run (round 5, `docs/logs/recorded.md`) confirmed
  device-vs-host arithmetic parity on the phase 4 build — all four corpus A photos matched the
  host's `normalize_first` prediction within 2 kg, well inside the 5.18–12.55% jitter bands
  rounds 2–3 measured — but it re-scanned the same four photos already known to detect, using
  gallery import, not fresh captures. It does not answer whether the ladder's removal cost
  anything on a capture the ladder used to rescue.
- **Ji/Duan gap-fill vs README §17's strict FINAL_MASK ⊆ BASE_MASK reading (phase 5).** The
  vendor cutter's preprocessing legitimately adds a small number of foreground pixels beyond the
  base mask (morphological gap-fill, not a coordinate bug) — measured at 0.037% of the base
  mask's area on the one photo checked. Phase 5 ships the check tolerance-gated at 1% rather
  than failing every capture; the 1% figure is a judgment call from one measurement, not a
  swept statistic. See [fix-phase-4/5-debug-and-assertions.md](fix-phase-4/5-debug-and-assertions.md)'s
  Result section.
- **Two documents disagree on the mask's destination coordinate space.**
  [`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md`](../INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md)
  §5.2 requires the mask be mapped back to the original image coordinate system; the README's
  §9 and §12 require 0.34 cm/px and explicitly forbid original full-resolution camera
  coordinates. This round implements the README. Which document governs generally is ADR-worthy
  and belongs to `pipeline-docs`.
- Both weight quality gates ship disabled (`quality_gates.posture = false`,
  `.truncation = false`). This round does not enable them; it preserves their position in the
  order.
- ADR-010's roughly 73 kg training-domain floor is untouched here.
- **README's exact-960x540-fit reading conflicts with its own source document (phase 3).**
  [`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`](INSTAHAM_CAMERA_SCALE_NORMALIZATION.md) lines
  287/685 say a normalized image "does not need to be exactly 960 x 540"; README §6 requires
  an exact fit and halts otherwise. This round ships the README's exact-fit reading (F61
  above is a direct consequence). Not resolved.
- **The `input_scale` manifest block is removed, hand-carried rather than re-exported
  (phase 3, then phase 4).** Phase 3 hand-renamed `cm_per_px` to
  `legacy_ladder_base_cm_per_px` rather than re-running the ONNX export (non-deterministic
  run to run) for a JSON-key-only change. Phase 4 absorbed that field, as phase 3 flagged it
  might, but by deleting the whole block (`legacy_ladder_base_cm_per_px`,
  `ladder_multipliers`, `retry_conf_threshold`) along with the retry ladder in `pipeline.cpp`
  that was its only remaining reader — not by re-exporting. The same non-determinism
  argument applies with more force now: nothing in the manifest needs this block's *value*
  any more, so re-staging a new `segmentation.model.sha256` for its removal would buy
  nothing. A full `export_yolo.py` + `ML.export.build_manifest` rebuild is still open should
  a future session want the manifest's provenance trail to reflect an actual re-export
  rather than a hand edit.
- **ADR needed.** `pipeline-docs` should record: (a) that the stage-order question F49 raised is
  settled by instruction in favour of the README, with phase 2's contrary measurement recorded
  as a known and accepted counter-indication; (b) the capture-orientation contract from phase 6,
  which is a user-facing behavioural constraint, not an implementation detail; (c) that the
  coordinate-space conflict above remains open.

## Plan rating: 8/10

**Pros.** It implements the designated specification instead of adjudicating it, which is what
was asked and removes the failure mode that voided the previous revision. Phase 1's composition
code is reused rather than rewritten, so the reopening costs one narrow revision phase, not a
redo. The three withdrawn divergences are named individually, so nothing is quietly dropped or
quietly kept. Phase 6 turns README §4's weakest point — an assumption enforced nowhere — into a
capture-time contract, which is a stronger guarantee than the README asked for.

**Cons.** ~~Shipping README §6's halt is knowingly shipping a failure on full-resolution phone
captures; the plan flags it but does not fix it, and if the user does not rule on that flag,
phase 4's device run will fail for a reason the plan already predicted.~~ **Withdrawn 2026-09-19
(phase 3):** this con rested on F61, whose two pieces of evidence both paired a capture size
with a `cm_per_px_actual` measured at a different resolution. The device's own telemetry puts
its captures at 2250x3000 / 426 of 540 px, and all nine corpus images fit. The halt is not a
known-broken behaviour the round ships anyway; it bounds how far back the camera may stand.
Removing the retry
ladder discards a fix that was added because detection genuinely failed, and nothing before
phase 4 will catch the regression. Phase 2's measurement is left on the record saying corpus B
got worse, so the round ships a change that its own only evidence mildly argues against —
honest, but uncomfortable. Phase 6 is Dart and UI work bolted onto an otherwise native round;
it is independent enough to be safe, but it makes the round's scope wider than its title.
