# Phase 2 — Port the V176/V144 cutter and the Chen16 feature stack

Status: done — body_curve parity patch applied, feature-port gate green 20/20 (see Results)

## Goal

Replace `stages/cutter.cpp` (the identity stub) with the real V176 shoulder selector plus
V144 circle cut, and add a 16-feature Chen16 extractor alongside the existing
`extract_five_features`, both inside `packages/instaham_ml_ffi`, with no new third-party
dependency and no change to how `pipeline.cpp` obtains its mask.

This is the phase that reverses [ADR-001](../adr/001-cutter-identity-stub.md) and resolves
the root cause `docs/fix.md` round 5 is open on. It needs its own ADR (see phase 5).

## What changes the ADR-001 conclusion

There is also a reason ADR-001's approach could never have worked, independent of effort:
`ML/pipeline/cutter.py` implements protocol
`ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`, not the
`v176_…_v144_…_v1` the Chen16 model was trained against. Porting it faithfully would have
produced a faithful port of the wrong cutter. Note this when phase 5 writes the ADR
superseding ADR-001.

ADR-001 declined the port because `ML/pipeline/cutter.py` is ~11 000 lines coupled to
`scipy.signal.find_peaks`, `scipy.ndimage.gaussian_filter1d`, and
`skimage.morphology.skeletonize`. That reasoning was about porting the Python. It no longer
applies: `model_and_cutter/instaham_cpp_weight_runtime_v176_chen16/` is an existing C++
implementation of the same protocol, and it is small — **351 lines** of core sources total,
written in a dense style, with every SciPy/skimage dependency already replaced by an OpenCV
or hand-rolled equivalent (for example `BodyCurve.cpp` carries its own Zhang-Suen
`skeletonize` with a one-pixel zero border, explicitly documented as matching
`skimage.morphology.skeletonize`'s treatment of the crop edge).

## Design/Approach

### Dependencies: nothing new

The vendor `CMakeLists.txt` wants OpenCV (`core`, `imgproc`), ONNX Runtime, and
nlohmann/json. `packages/instaham_ml_ffi/src/third_party/` already vendors all three
(`opencv`, `onnxruntime`, `nlohmann_json`), and `src/CMakeLists.txt` already links
opencv-mobile via its `OpenCVConfig.cmake` for `stages/construction.cpp` and
`stages/feature_calculation.cpp`. Only `instaham_core` is needed — the vendor's
`YoloOnnx.cpp`, `XGBoostJsonPredictor.cpp`, `WeightPipelineOrchestrator.cpp`, and
`ffi/` layer are all **not** ported, because the app already has its own segmentation stage,
ONNX regressor path, pipeline order, and C ABI. Taking the orchestrator would duplicate
`pipeline.cpp`, which AGENTS.md forbids and the vendor README itself calls the one file that
owns execution order.

### Files to bring in

Copy under `packages/instaham_ml_ffi/src/vendor/instaham_v176/`, preserving the vendor's
`include/instaham/...` layout so the sources compile unmodified:

- `MaskUtils.cpp`, `preprocess/JiDuan.cpp`
- `features/`: `MaskArea`, `ConvexHullArea`, `Difference`, `DifMask`, `BodyCurve`,
  `Perimeter`, `OutlineCurve`, `CenterCrossingAxesWork`, `Longest`, `Shortest`,
  `HuMomentsWork`, `Hu1`–`Hu7`, `Chen16Vector` (20 files)
- `cutter/`: `OutlineBuilder`, `ShrinkingBall`, `SelleFilter`, `TerminalGeometry`,
  `Break1Fit`, `ShoulderSelectorV176`, `CircleCutterV144` (7 files)
- the matching headers under `include/instaham/`

Record the drop's sha256 per file in a `VENDOR.md` next to them, and keep edits to the
absolute minimum needed to compile, each one logged in that file with its reason. A silently
hand-edited file cannot be re-diffed against a future vendor update, and phase 5's parity
work depends on knowing exactly where we diverged from what they shipped.

**Expect edits.** `VALIDATION.md` states plainly: "A complete native build was not possible
in the artifact environment because OpenCV C++ development headers and ONNX Runtime C++
libraries are not installed there," and the only build check they ran was "CMake
configure/generate syntax check passes with runtime disabled." **This code has never been
compiled.** Every contract item in `VALIDATION.md` was verified by reading, not by running.
Budget for compile errors as the normal case, not as a surprise, and treat "it builds" as a
phase milestone in its own right rather than a formality before the real work.

Explicitly **not** copied: `inference/`, `model/`, `orchestrator/`, `ffi/`, `flutter/`,
`tests/`.

### `quality_gates/` is a parity dependency, not an optional extra

The plan's open question 4 understated this. `VALIDATION.md` lists "Whole-mask truncation and
body-curve/posture gates occur before Ji/Duan" as a **package contract check**, and
`tests/README.md` makes truncation (step 2) and pre-Ji/Duan posture (step 3) two of the seven
prescribed parity steps — before the cutter is even reached. The training data was produced
with both gates in the loop, so a native pipeline without them will accept photos the
training protocol rejected, and phase 5 cannot claim protocol parity on a ladder it skipped
the first two rungs of.

The gates are also cheap: `EdgeTruncationDetector.cpp` is 538 lines and `PostureGate.cpp` is
28, and posture is a pure decision over an already-computed `body_curve` angle
(`bend = 180 - body_curve`, reject above 40 degrees).

Decision for this phase: **port both core detectors** (`EdgeTruncationDetector.{hpp,cpp}`,
`PostureGate.{hpp,cpp}`) into the vendor tree, but not their `*_ffi.{h,cpp,dart}` layers —
the app has one consolidated native library and one C ABI, and `README_AI_INTEGRATION.md`
section 9 explicitly permits folding the sources into an existing native target so long as
module boundaries hold. Whether the gates are *enabled* in `pipeline.cpp` stays a phase-3
manifest switch, so they can ship dark and be turned on once phase 5 has measured their
rejection rate on real captures. That respects the vendor's "a gate must be possible to
disable without rewriting the pipeline" rule while keeping the parity ladder runnable.

Two constraints from `README_AI_INTEGRATION.md` that bind the port:

- The truncation gate must receive the mask **in original capture coordinates, not the
  640x640 letterboxed model frame**. The app restores masks via `unletterbox_native_mask`
  already, so feed it the restored mask, before `scale_mask_to_training_space`.
- Gates must not call each other, and must return status only, never user-facing strings.
  `pipeline.cpp` owns sequencing; phase 4 owns the messages.

### Two body-curve calls, not one

`README.md` and `VALIDATION.md` both insist on this and it is easy to get wrong when folding
the gates in: `postureBodyCurve` runs on the **whole YOLO mask before Ji/Duan** and feeds the
posture gate only; the Chen16 `body_curve` feature is **recomputed on the final cut mask**.
Same algorithm, two separate invocations, and the numeric result must never be cached and
reused across them. Add a native test asserting the two differ on a mask where a cut actually
happened — a shared-value regression would otherwise be invisible and would quietly corrupt
feature 5 of 16.

### Seam into the app's stages

The app's stages speak `std::vector<uint8_t>` masks plus width/height; the vendor speaks
`cv::Mat`. Do not rewrite either side. Add a thin adapter and keep the existing stage
signatures:

- `stages/cutter.h` keeps `MaskView` / `CutterResult` and the `cut_body_mask(const MaskView&)`
  signature. Its body becomes: wrap the mask in a `cv::Mat`, run
  JiDuan → OutlineBuilder → ShrinkingBall → SelleFilter → TerminalGeometry → Break1Fit →
  ShoulderSelectorV176 → CircleCutterV144, and return the final cut mask.
  `head_removal_applied` becomes true. `status` gains real values — at minimum
  `cut_applied`, `cut_not_required`, and one distinct value per stage that can decline
  (`jiduan_failed`, `no_terminal_balls`, `break1_unfit`, `shoulder_undecided`), because
  phase 4 has to tell the user *which* stage rejected the photo, and phase 5 has to
  attribute parity failures to a stage.
- `stages/feature_calculation.h` gains `struct Chen16Features { std::array<double,16> values;
  bool valid; }` and `std::optional<Chen16Features> extract_chen16_features(const
  std::vector<uint8_t>& mask, int w, int h)`. `extract_five_features` stays untouched —
  phase 3 selects between them on the manifest's declared `feature_family`, which is what
  makes the rollback in phase 5 a manifest edit.
- No RA-style frame normalization applies to Chen16. `mask_area` is a raw pixel count, and
  the training frame enters only through `scale_mask_to_training_space` upstream. Do not add
  an `ra_frame_w/h`-style parameter here; there is nothing for it to divide by.

### Build wiring

Add the 27 vendor sources to `INSTAHAM_ML_SOURCES` in
`packages/instaham_ml_ffi/src/CMakeLists.txt` behind the existing
`INSTAHAM_ML_WITH_OPENCV` guard — they are unconditionally OpenCV-dependent, and the host
ctest build currently compiles `stages/cutter.cpp` *because* it was header-only. That is no
longer true, so `src/test/CMakeLists.txt`'s gate-D target must either link OpenCV on the
host or drop the cutter test; prefer linking OpenCV, since phase 5's parity harness wants to
run natively on the host anyway.

`src/test/test_cutter_identity.cpp` asserts the stub's pass-through behavior and will fail
by design. Replace it rather than delete it: same file name, now asserting that a mask with
a known head region comes back smaller, and that an invalid mask still yields
`invalid_input`.

## Steps

- [x] Copy the 27 core sources plus headers, and the two quality-gate detectors, into
      `src/vendor/instaham_v176/`; write `VENDOR.md` with per-file sha256 and the vendor
      `PACKAGE_MANIFEST.json` verbatim.
- [x] Get it to compile — this code has never been built (`VALIDATION.md`). Add the sources
      to `INSTAHAM_ML_SOURCES` under the OpenCV guard and drive an Android `arm64-v8a`
      build to green, logging every source edit in `VENDOR.md`.
- [x] Wire `postureBodyCurve` (whole mask, pre-Ji/Duan) separately from the Chen16
      `body_curve` (final cut mask); add the test asserting they are computed twice.
- [x] Make the host ctest build link OpenCV so the cutter and parity tests can run there.
- [x] Rewrite `stages/cutter.cpp` over the vendor pipeline; extend `CutterResult::status`
      with the per-stage decline values; keep the header's public shape.
- [x] Add `extract_chen16_features` to `stages/feature_calculation.{h,cpp}` as an adapter
      over `assembleChen16`.
- [x] Replace `src/test/test_cutter_identity.cpp` with a real cut assertion.
- [x] Add the feature-port gate test: run the C++ `extract_chen16_features` and Python
      `ML/pipeline/feature_calculation.py::extract_chen16_features` over the **same** masks
      from `Instaham/PIGRGB-Weight/MASK_3394/` and require agreement at the tolerances below.
      Start with 20 masks spanning several weight groups; widen to the full 3394 in phase 5.
      This gates the rest of the phase — do not move on to the cutter seam until it is green.
- [x] Apply the vendor `BODYCURVE_FIXED` patch to `vendor/instaham_v176/src/features/BodyCurve.cpp`
      (skeletonizer only), add `body_curve_skeleton_protocol` to the vendored
      `PACKAGE_MANIFEST.json`, refresh the `BodyCurve.cpp` sha256 in `VENDOR.md`, rebuild
      host + Android arm64, and re-run the feature-port gate to green. Do **not** take the
      patch's `ShoulderSelectorV176.cpp` — see Results.

## Results

**Build.** `VENDOR.md` records one required edit: `ShoulderSelectorV176.cpp` line 14 had
`auto cr=crosses(d),all=maxima(b);` — a single `auto` declaration whose two declarators
deduce different types (`std::vector<Cross>` vs `std::vector<double>`), which is ill-formed
C++ and fails under any conforming compiler. Split into two statements; no behavior change.
This is the only edit found — everything else compiled unmodified, confirming
`VALIDATION.md`'s "never been compiled" claim was accurate but that the vendor sources are
otherwise sound.

Android `arm64-v8a` build is green (`flutter build apk --debug --target-platform
android-arm64`). Host ctest build is also green, but required installing a full toolchain
that did not exist on this machine: VS Build Tools 2022 (C++ workload) + vcpkg + `opencv4`
for `x64-windows` (opencv-mobile, already vendored, ships no desktop libs). `cmake
--build` targets were built in Debug config specifically — a first Release-config run
passed every test only because `/DNDEBUG` had silently compiled out every `assert()`;
re-running in Debug caught two real problems (below).

**Tests.** `test_cutter_identity.cpp` and `test_body_curve_dual_call.cpp` (both new/rewritten
this phase) pass for real, on a deliberately bent synthetic mask — a straight dumbbell shape
gives `computeBodyCurve` an identical, degenerate 180° on both the whole mask and the cut
mask, which would have passed the dual-call test for the wrong reason (masking a real
caching bug had one existed). `test_scale_normalization.cpp` (pre-existing, unrelated to
this phase, never previously run because host OpenCV never existed before this session) had
a real test-helper bug of its own — `make_disc_mask()` never set `PigMask.area_px`, so an
assertion compared a real pixel count against a default-initialized `0` — fixed as a
one-line incidental fix. After that fix it still fails, now at a *different*, deeper
assertion (LC doubling tolerance under nearest-neighbor resize) that is about the pre-existing
baseline5 pipeline, not the Chen16/cutter port; left failing and out of this phase's scope.

**Feature-port gate (the phase's own gating test), 20 masks from `MASK_3394/` spanning
several weight groups:** 15 of 16 features — `mask_area`, `convex_hull_area`, `difference`,
`dif_mask` (exact), `perimeter`, `longest`, `shortest`, `outline_curve` (rel 1e-3), and all
7 Hu moments (rel 1e-6) — match on every mask, zero mismatches. `body_curve` mismatches on
17 of 20 masks, relative error ~0.16%–8.6% (most under 2%; four masks 4–8.6%).

**body_curve root cause found; vendor patch verified, not yet applied.** The divergence is
in the thinning itself, and the handoff's leading suspect — the 1px zero-border
pad-before-thin — was **not** the bug. The pad is correct.

Static review confirmed the vendor's `thinningIteration()` matches the canonical 1984
Zhang-Suen A/B/m1/m2 conditions and 8-neighbor ordering exactly, and that endpoint detection
and farthest-pair selection are semantically identical between `BodyCurve.cpp` and
`ML/pipeline/feature_calculation.py::_skeleton_body_curve` (Python's
`neighborhood_count == 2` from a 3x3 sum including the center pixel equals C++'s `nb == 1`
excluding it). What the review could not reach was
`skimage.morphology.skeletonize()`'s actual implementation: a compiled Cython lookup table
(`_fast_skeletonize` in `_skeletonize_various_cy`, a `.pyd`). That LUT is where the two
differ. It is *not* the textbook algebraic conditions — it is a 256-entry neighborhood
classification table whose deletion classes do not reduce to the A/B/m1/m2 form, so a
faithful textbook Zhang-Suen and skimage's `method='zhang'` produce different skeletons on
real masks even though both are called Zhang-Suen.

The vendor shipped a fix for exactly this, in
`model_and_cutter/instaham_weight_runtime_BODYCURVE_FIXED/` (see its
`PATCH_NOTES_BODY_CURVE.md`). It replaces the algebraic conditions in
`src/features/BodyCurve.cpp` with skimage 0.26.0's 256-entry LUT, bit order
`NW,N,NE,E,SE,S,SW,W = 1,2,4,8,16,32,64,128`, pass 1 deleting classes 1 and 3, pass 2
deleting classes 2 and 3, each subpass reading the pre-subpass skeleton and committing
deletions only after a complete scan. Everything downstream of skeleton generation is
unchanged, and no tolerance or threshold was widened. The vendored `PACKAGE_MANIFEST.json`
gains `"body_curve_skeleton_protocol": "skimage_0.26.0_zhang_exact_lut_v1"`.

**Verification of the patch, on this project's own data.** The vendor's own check was 200
synthetic blob/ellipse masks. That was reproduced here against the real corpus instead: the
patch's LUT was parsed directly out of its `.cpp` and its two-subpass loop transcribed to
Python, then run over the same 20 `MASK_3394` masks the feature-port gate uses, bbox-cropped
the way `computeBodyCurve` crops. Result: **zero XOR pixels against
`skimage.morphology.skeletonize` on all 20 masks, and 0.000000% `body_curve` relative error**
— against 17 of 20 mismatched at 0.16%–8.6% before. This validates the algorithm on real
data without a device build; it does **not** yet validate the C++ transcription of it, which
is what the re-run of `ML/parity/chen16_feature_port_gate.py` against a rebuilt
`chen16_feature_gate_cli` still has to establish.

**Patch applied and gate re-run — closed.** `BodyCurve.cpp` swapped in
(`vendor/instaham_v176/`, sha256 refreshed in `VENDOR.md`, pre-/post-patch hashes both
recorded there), `PACKAGE_MANIFEST.json` gained `body_curve_skeleton_protocol`.
`ShoulderSelectorV176.cpp` was left untouched, per the trap noted below. Host
`chen16_feature_gate_cli`, `test_cutter_identity`, and `test_body_curve_dual_call` rebuilt
clean (Debug config) and all pass. `flutter build apk --debug --target-platform
android-arm64` is green. Re-running `python -m ML.parity.chen16_feature_port_gate` against
the rebuilt CLI:

```
checked 20/20 masks (0 mismatches)
```

All 16 Chen16 features, including `body_curve`, now agree with the Python oracle at their
assigned tolerances on every gate mask — 0 mismatches, versus 17/20 before this patch. This
was the phase's own gating test; it is green, and phase 2 has no remaining open findings.
Widening to the full 3394-mask corpus stays phase 5's job, unchanged from the original plan.

**Trap when applying the patch.** Three files differ between the `BODYCURVE_FIXED` drop and
the vendored copy: `src/features/BodyCurve.cpp` and `PACKAGE_MANIFEST.json` (both wanted),
and `src/cutter/ShoulderSelectorV176.cpp` (**not** wanted). The third is not a fix — it is
the vendor's original line 14, `auto cr=crosses(d),all=maxima(b);`, the ill-formed
declaration logged in `VENDOR.md`. Copying that file wholesale would re-break the build.

**Not attempted:** widening the feature-port gate from 20 masks to the full 3394 — the plan
assigns that to phase 5.

## Open questions

- **~~Do the vendor's cached final masks ship with the CSV?~~ — resolved: no, and they are
  not needed.** `final_mask_path` points at `/instaham/artifacts/…`, outside this repo, and
  the PNGs were not part of the dataset drop. They also cannot be regenerated here: the
  fallback this question proposed — "regenerate a handful with the Python cutter" — does not
  work, because `ML/pipeline/cutter.py` declares
  `PROTOCOL_VERSION = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"` and contains no
  V176 / V144 / ShrinkingBall / SelleFilter / Break1 code. It is a different cut protocol
  from the `v176_…_v144_…_v1` every CSV row was produced with, so masks it generates would not
  be the masks the training features came from.

  This turned out not to matter, because the fixture was solving the wrong problem. The point
  of it was to test the **feature port** in isolation from the cutter port, and
  `extract_chen16_features` is a pure function of whatever binary mask it receives — it does
  not care whether that mask was ever cut. Handing the same mask to the C++ port and to the
  version-matched Python function (`chen16_noheight_centerchord_v2`, identical to the CSV's
  `extended_feature_protocol_version`) is a complete test of the port. The 3394 ground-truth
  masks in `Instaham/PIGRGB-Weight/MASK_3394/` are a better input than a cached final mask
  would have been, because they also take the app's YOLO out of the loop.

- **The cutter port cannot be unit-tested in isolation, and this phase should not pretend
  otherwise.** With no reference implementation of V176/V144 outside the vendor sources,
  there is nothing to diff a single cut against. Phase 2's job for the cutter ends at "it
  compiles, it runs, it returns a smaller mask with a plausible `status`". Correctness is
  established in phase 5 against the CSV's per-row cutter telemetry
  (`final_mask_area_px`, `kept_fraction`, `shoulder_selected_x`, `circle_center_x/y`,
  `final_circle_radius_px`, `peak_route_type`, `selection_reason` — all populated on all 1821
  rows). Do not block phase 2 waiting for a cutter parity number that only phase 5 can produce.

- **Tolerances for the C++/Python feature comparison** (proposal, finalized in phase 5):
  exact for `mask_area`, `convex_hull_area`, `difference` (integer pixel counts) and hence
  `dif_mask`; relative `1e-3` for `perimeter`, `longest`, `shortest`, `outline_curve`;
  relative `1e-6` for `Hu_1`..`Hu_7`; `body_curve` relative `1e-3` but any mismatch is a
  Zhang-Suen-vs-skimage thinning bug to fix, never a tolerance to widen.
