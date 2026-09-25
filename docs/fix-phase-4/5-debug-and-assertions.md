# Phase 5 — Stage debug outputs and shipped assertions

Status: done 2026-09-21 (see Result)

Parent: [`../fix-4.md`](../fix-4.md). Unblocked 2026-09-19 — phase 2's gate is void. Work this
after phase 4.

## Symptom

Coordinate bugs on the new path are invisible until they show up as a wrong weight. Round 7's
F55 defect survived several rounds for exactly this reason: nothing in the envelope said which
transform had actually been applied.

## Root cause

Not a defect. README §16 and §17 ask for stage dumps and invariant checks; this phase decides
which of them are worth shipping and which belong in the host harness only.

## Change made

**In the envelope, on every run.** These are cheap scalars and they are what a future session
reads instead of the source:

- `resize_factor`, and the normalized width and height;
- `was_rotated_clockwise`;
- the capture orientation and the user's head-direction attestation from phase 6, so a
  head-left mask can be checked against what was declared;
- whether the README §6 halt fired, and at what normalized dimensions;
- `x_offset`, `y_offset`, `rotated_width`, `rotated_height`;
- base mask dimensions and final mask dimensions;
- `k`, which should be 1.0 on the new path — a value away from 1.0 there means the photograph
  was not actually normalized and is a bug signal in itself.

**In the host harness only.** README §16's image dumps — the EXIF-corrected RGB, the normalized
RGB, the rotated RGB, the canvas, the canvas-coordinate mask, the cropped mask, the base mask
and the final mask. These are large and belong in `ML/host_scale_test/`, not on the device.
The single most useful comparison is the normalized RGB against the base mask against the final
mask; all three must align pixel for pixel.

**As shipped checks.** README §17 lists invariants. Ship all of them:

- `reference_px > 0`, `resize_factor > 0`, normalized dimensions positive — keep;
- base mask dimensions equal normalized RGB dimensions, after any inverse rotation — keep, this
  is the check that would have named a rotation bug immediately;
- final mask dimensions equal base mask dimensions, and the final mask's foreground is a subset
  of the base mask's — keep;
- `width <= 960` and `height <= 540` — **ship it.** Phase 1.1 implements README §6's halt, so
  this is the halt's trigger condition and it must be a declared failure carrying both
  dimensions and the bound. ~~F61 predicts it fires on full-resolution captures; that is the
  specified behaviour this round ships~~ — **corrected by phase 3:** F61's evidence is retracted
  (it paired capture sizes with `cm_per_px_actual` values measured at other resolutions), the
  bound is on ground coverage rather than pixels (184 cm short side, 326 cm long side at
  0.34 cm/px), and every capture on record fits. Expect this assertion to stay quiet; the
  envelope must make each occurrence countable precisely because an occurrence is now a signal,
  most likely of a reference-mark coordinate-space mismatch (AGENTS.md rules 6 and 9) rather
  than of a too-small canvas. Record the `cm_per_px_actual` alongside the dimensions so the two
  can be checked against each other.

Every one of these failing must produce a declared failure with a reason, never a silent extra
resize.

## Verification

- A unit test per shipped invariant, including a negative case that proves the check fires.
- One end-to-end host run whose envelope is read back and checked field by field against the
  values the harness computed independently.
- The three-image visual comparison is produced for at least one corpus A photograph and one
  corpus B image, and stored with the phase 2 results.

## Deferred

Nothing, but this phase no longer closes the round — phase 6 does. The §16 image dumps stay
host-only; §16 is titled "recommended during integration" and is the one README section that
reads as guidance rather than contract, so keeping large per-stage PNGs off the device is a
scoping choice, not a withdrawn divergence. If a device-side coordinate bug ever outlives the
scalar fields above, revisit it.

## Result (2026-09-21)

**Envelope scalars, shipped invariants, and the §16 image dumps are all in place.** Native
only; no Dart/UI change.

- `stages/invariants.h` (new, header-only, OpenCV/ORT-free): the pure scalar/array checks
  behind README §17 — `check_composition_positive`, `check_content_fits_canvas`,
  `check_canvas_exact`, `check_mask_matches_rgb_dimensions`, and
  `check_final_mask_subset_of_base`/`measure_final_mask_against_base`. Two of §17's checks
  (`reference_px`/`resize_factor`/normalized-dimensions positive, and the 960x540 fit) were
  already enforced by `decide_normalize_first_composition()`
  (`stages/canvas_scale.h`) before this phase — the new header states them explicitly
  anyway, for a caller that does not go through that function, rather than duplicating
  behaviour.
- `pipeline.cpp` now checks "cropped mask size equals rotated normalized RGB size" and
  "after inverse rotation: BASE_MASK size equals original normalized RGB size" right where
  `construct_pig_mask()`/`rotate_pig_mask_90_ccw()` run, as declared failures
  (`envelope["segmentation"]["reason"]`) — not expected to fire given the two stages
  already agree by construction, but now checked rather than assumed.
- `envelope["segmentation"]` gained `resize_factor`, `normalized_w`/`h` (now set on every
  run, not only the §6 halt), `x_offset`/`y_offset`, `rotated_width`/`height`, and (on the
  halt path) `cm_per_px_actual` alongside the halt dimensions. `envelope["construction"]`
  gained `base_mask_w`/`h`. `envelope["cutter"]` gained `base_mask_w`/`h`,
  `final_mask_w`/`h`, `final_mask_added_px`, `final_mask_removed_px`. `SegmentationOutput`
  gained `x_offset`/`y_offset` fields (`stages/segmentation.h`).
- **A real finding, not a coordinate bug:** the strict README §17 reading of "FINAL_MASK
  foreground subset of BASE_MASK foreground" fails on every real photograph tested, because
  the vendor cutter's Ji/Duan preprocessing (`vendor/instaham_v176`, frozen per ADR-001's
  successor) runs a morphological CLOSE before the cut, which legitimately fills small gaps
  and adds a handful of foreground pixels the base mask did not have — measured at 17 of
  46043 base px (0.037%) on `corpus_a/75kg_pig_meter_stick.jpg`. This is expected
  denoising, not a displaced region, so `pipeline.cpp` ships the check as a
  **tolerance-gated** declared failure: `kMaxTolerableAddedMaskPxFraction = 0.01` (two
  orders of magnitude above the measurement) — a violation above that fraction still
  withholds weight with reason `final_mask_not_subset_of_base`, but ordinary cutter cleanup
  does not. `final_mask_added_px`/`final_mask_removed_px` are in the envelope regardless of
  which side of the line a run falls on, so this is visible either way without a code read.
- `ML/host_scale_test/weight_branch_cli.cpp` gained an optional `--dump-stages <out_dir>`
  argument writing the §16 three-image comparison (`normalized_rgb.bmp`, `base_mask.bmp`,
  `final_mask.bmp` — BMP, not PNG: this vcpkg OpenCV build has no PNG encoder registered)
  from the same pure `util/image_io.h` functions the app calls, not read back out of
  `stages/segmentation.cpp`. `base_mask.bmp`/`final_mask.bmp` are `mask_for_cutter`/
  `cutter_result` (the masks the cutter actually saw), not the pre-scale `pig_mask`, so the
  three images are pixel-comparable. `ML/host_scale_test/CMakeLists.txt` now also finds
  and links `opencv_imgcodecs` (host-only; the app itself never writes an image file).
  Produced and visually confirmed pixel-aligned for one corpus A image
  (`corpus_a/75kg_pig_meter_stick.jpg`, stored at
  `ML/host_scale_test/out/dumps_corpusA_75kg/`) and one corpus B image
  (`Instaham/PIGRGB-Weight/sub_1.88/74.4kg_9.png`, stored at
  `ML/host_scale_test/out/dumps_corpusB/`) — a 50%-blend overlay of `normalized_rgb.bmp`
  and `base_mask.bmp` traces the pig's outline exactly on both, mask-over-photo, no offset.
- **Verification, end to end.** `test_stage_invariants.cpp` (new, 10 unit tests, one
  positive and one negative case per invariant plus the counted-measurement variant) builds
  and passes unconditionally, like `test_segmentation_canvas.cpp`. Full `ctest`: 9 of 10 —
  `test_abi` and `test_scale_normalization` are the same two pre-existing failures unchanged
  since `06d2ecd` (see the phase 4 handoff); everything else, including the new test,
  passes. A scratch harness (not committed, same pattern as phase 4's) called
  `instaham_ml_run_pipeline_request_json()` against `corpus_a/75kg_pig_meter_stick.jpg` at
  1582 px / 100 cm and read every new field back against hand-computed values: `cm_per_px_
  actual` 0.06321113, `cm_per_px_target` 0.34 → `resize_factor` 0.1859151 → `normalized_w/h`
  418/558 (`round(2250×0.1859151)`/`round(3000×0.1859151)`) → rotated (558>418) →
  `rotated_width/height` 558/418 → `x_offset/y_offset` 201/61
  (`(960−558)/2`/`(540−418)/2`) → `base_mask_w/h` 418/558 (swapped back, matching
  `normalized_w/h` exactly — no dimension-mismatch declared failure) → `final_mask_w/h`
  418/558, `final_mask_added_px` 17 (under the 1% tolerance) → `estimated_kg`
  88.9058837890625, bit-for-bit the same value phase 4's own verification recorded. This
  phase's additions did not move the predicted weight on the one case checked; they made
  every step that produced it visible.

Rebuild/rerun commands, matching the handoff's Build/environment notes: `ninja` then
`ctest --output-on-failure` from `packages/instaham_ml_ffi/src/build/host` under vcvars64;
`cmake . && ninja weight_branch_cli` from `ML/host_scale_test/build` for the dump CLI.

## Known limitations / deferred

- The capture orientation and head-direction attestation fields the phase document
  originally asked for depend on phase 6 (not built yet — Dart/UI), so they are not in the
  envelope this round; phase 6 adds them.
- The `final_mask_not_subset_of_base` tolerance (1%) is a judgment call from one measured
  photograph, not a swept statistic — if a future capture legitimately needs more Ji/Duan
  gap-fill than that, this is the constant to revisit, not the check to remove.
- The image dumps were produced for one corpus A and one corpus B image, per the phase's
  Verification bullet ("at least one"), not the full corpora.
