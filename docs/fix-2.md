# Fix (round 6): the weight branch freezes the app after "Confirm analysis"

Second active fix document, opened as **round 6**. It is deliberately separate from
`docs/fix.md`, which is still mid-round-5 with its phase 7 open. Round 6's phase 1 has to be
worked before that phase 7 finishes, so appending here would have produced a document whose
phases are not executed in order.

Numbering continues at **F42** — never reuse F1–F41, from either document, or the source
comments citing them start pointing at the wrong thing. `docs/fix.md` and `docs/fix-phase/`
remain the record for rounds 1–5 and are not edited by this document.

Source material: the `docs/plan.md` phases 1–4 changes (the `chen16_noheight` swap and the
V176/V144 cutter port), the first on-device test of that build, and
`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`.

## Symptom

After marking the reference endpoints and pressing **Confirm analysis**, the app hangs for
noticeably longer than a normal scan and then dies. Reported on the first APK built after
`docs/plan.md` phases 1–4 shipped. No result screen, no rejection message.

The crash class is not yet confirmed. An ANR (Android killing an unresponsive foreground
activity) and a native fault produce the same user-visible outcome, and phase 1 separates
them before anything is changed.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | The freeze: unscaled mask into the cutter | closed — F42–F45, F52 | [fix-phase-2/1-cutter-freeze.md](fix-phase-2/1-cutter-freeze.md) |
| 1.1 | The rebuilt manifest lost the segmentation scale ladder | F50 fixed (hand edit); F51 fixed (build_manifest key-loss guard) | [fix-phase-2/1.1-manifest-input-scale-regression.md](fix-phase-2/1.1-manifest-input-scale-regression.md) |
| 2 | The scale target: 0.35 cm/px against the spec's 304 px/m | **closed 2026-09-09** — F46, F49, F38 resolved; 0.35 kept on the host sweep, applied and shipped (ADR-010) | [fix-phase-2/2-scale-target-conflict.md](fix-phase-2/2-scale-target-conflict.md) |
| 2.1 | One pixel of reference marking moves the estimate by 5% | measured — F53, all three photos on device with the shipped cutter (bands 5.2% / 12.0% / 12.6%); fix still open | [fix-phase-2/2.1-reference-length-sensitivity.md](fix-phase-2/2.1-reference-length-sensitivity.md) |
| 3 | Normalization order: resize the image, not the mask | not started | [fix-phase-2/3-normalization-order.md](fix-phase-2/3-normalization-order.md) |

**Work phase 1 first, and it is a hard dependency, not a preference.** Phases 2 and 3 are both
measured against real predictions from the three `.pig_pictures/` field photos, and the app
currently dies before producing any.

**Phase 2.1 was worked before phase 2's measurement, despite its number,** because it
establishes whether phase 2's comparison can be measured at all. Its sweep is now done: the
jitter band from reference marking alone is 5.18%, 12.04% and 12.55% on the three photos,
against the ~13% in predicted weight that separates phase 2's two candidate constants. Phase 2
is therefore unblocked but constrained — it must compare six-mark sweeps by median, never
single predictions, and 2.1 has already collected the 0.35 half of that comparison.

**2.1's own fix is still open and is a separate question from phase 2's constant.** The
dominant amplifiers turned out to be the cutter's discontinuity and the boundary features'
instability, not the segmentation-input term the write-up first suspected. Choosing a value
for `cm_per_px_target` does not address either.

## Root cause

Phase 1's cause is established by reading, not yet confirmed on device:

1. **`assets/ml/manifest.json` has `capabilities.weight.available: false`** (line 171). The
   commit at `HEAD` has `true`. `ML/export/export_xgboost.py:234` only writes `true` when the
   exporter is run with `--enable-for-testing`, so a manifest regeneration without that flag
   turned the weight branch off.
2. **A false `available` flag skips scale derivation**, not just the prediction.
   `pipeline.cpp:479` returns `weight_capability_unavailable` before `k` is ever computed, so
   `scale_ok` stays false. The user's confirmed reference object is measured, persisted, and
   then never used.
3. **The cutter runs anyway, on the raw mask.** Its block is guarded only by
   `is_dorsal && have_mask` (`pipeline.cpp:540`) — not by `scale_ok` and not by the weight
   override. With no scale, `mask_for_cutter` stays pointed at the unscaled `pig_mask`
   (`pipeline.cpp:655`), which is a deliberate fallback "to keep provisional debugging
   features visible when no reference was marked."
4. **That raw mask is at full capture resolution.** `construct_pig_mask` unletterboxes back to
   `seg.orig_w × seg.orig_h` (`construction.cpp:99`) — roughly 3000×4000 on a phone camera.
   The V176 shrinking-ball and medial-axis passes were written for the 720×720 training frame.
   That is about 20× the pixel count they were designed for, and it is the first build in
   which the cutter is real rather than an identity stub, so this path has never been
   exercised before.

Phases 2 and 3 are contract questions rather than defects. **Phase 2 is now closed**: the host
sweep in `ML/host_scale_test/` measured 0.35 against the specification's 0.3289 over five PIGRGB
images with known true weights and 0.35 won on every one, so it is kept, applied and shipped,
and 304 px/m is retracted as a shipped value. Phase 3 remains open — the pipeline normalizes the
mask after segmentation where the specification requires the whole image to be normalized before
it.

## Change made

Phase 2 applied: `cm_per_px_target` restored to 0.35 in `ML/export/export_xgboost.py` with a
`_source` tag naming the sweep, re-exported, `assets/ml/manifest.json` rebuilt, APK rebuilt and
confirmed shipping by the user. Phases 1 and 1.1's changes are recorded in their own files.
Phase 3 and 2.1's fix are not applied.

## Verification

Closed: **F46, F49, F38** (phase 2), plus F42–F45 and F50–F52 in phases 1 and 1.1.
Open: **F53's fix** (phase 2.1) and phase 3. `docs/adr/010-regressor-training-domain-floor.md`
came out of phase 2 and discharges the ADR-005 replacement owed since round 5.

`docs/changelog.md` gets its entry when the whole round closes, not per phase — the contract is
one line per closed-out fix.
