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

**F62 — two disagreeing "training frame" constants.** The weight capture contract declares
`training_frame_px = [720, 720]`, consumed by the mask-diagonal plausibility check at
`pipeline.cpp:508` with `min_mask_diagonal_fraction = 0.35`. The README introduces 960x540 as
the training-like frame without reconciling the two. Phase 3 reconciles them.

**F64 — the app has never run the README's pipeline.**
`packages/instaham_ml_ffi/src/pipeline.cpp` contains no reference to `input_scale_mode` or
`normalize_first`. Phase 1 landed the new composition path in `stages/segmentation.cpp` and
wired it only into `ML/host_scale_test/weight_branch_cli.cpp`. The shipped app path is
unchanged and unaware of it. Phases 1.1 and 4 close this.

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
| 1.1 | Make the README path the only path | **not started** — delete the mode switch, the retry ladder on this path and the F61 fallback; ship README §6's halt. | [fix-phase-4/1.1-readme-is-the-path.md](fix-phase-4/1.1-readme-is-the-path.md) |
| 2 | Measure it: detection, MAE and jitter against the shipped path | **closed 2026-09-18 — verdict VOID, not repeated** — the measurement ran and its numbers stand as observations; its authority to gate the round does not. Retained for the evidence only. | [fix-phase-4/2-measurement.md](fix-phase-4/2-measurement.md) |
| 3 | Reconcile the frame and scale constants | **not started** | [fix-phase-4/3-constants.md](fix-phase-4/3-constants.md) |
| 4 | Wire the app and verify on device | **not started** | [fix-phase-4/4-app-wiring.md](fix-phase-4/4-app-wiring.md) |
| 5 | Stage debug outputs and shipped assertions | **not started** | [fix-phase-4/5-debug-and-assertions.md](fix-phase-4/5-debug-and-assertions.md) |
| 6 | Enforce capture orientation (portrait head-up, landscape head-right) | **not started** — new, from the user's 2026-09-19 instruction; closes F65. | [fix-phase-4/6-capture-orientation.md](fix-phase-4/6-capture-orientation.md) |

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

- **F61 halts on ordinary captures.** A 4032x3024 capture at 0.34 cm/px is 764x573; 573 > 540,
  and README §6 says halt. Shipping §6 as written means the weight branch declares failure on
  full-resolution phone photographs. Phase 1.1 implements the halt and phase 5 makes it visible
  in the envelope; whether the capture pipeline should downscale before normalization, or the
  canvas should grow, is a decision for the user and is not taken inside this round.
- **The retry ladder's removal is untested.** The ladder was added in round 4 (F18/F19) because
  detection failed without it. Phase 1.1 removes it on the README path per §13. Phase 4's device
  run is the first place a detection regression would show.
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

**Cons.** Shipping README §6's halt is knowingly shipping a failure on full-resolution phone
captures; the plan flags it but does not fix it, and if the user does not rule on that flag,
phase 4's device run will fail for a reason the plan already predicted. Removing the retry
ladder discards a fix that was added because detection genuinely failed, and nothing before
phase 4 will catch the regression. Phase 2's measurement is left on the record saying corpus B
got worse, so the round ships a change that its own only evidence mildly argues against —
honest, but uncomfortable. Phase 6 is Dart and UI work bolted onto an otherwise native round;
it is independent enough to be safe, but it makes the round's scope wider than its title.
