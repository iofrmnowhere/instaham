# Session handoff — weight branch "unavailable" bug

**State:** root cause found and fixed in code. **Not yet verified** — no C++ toolchain in this
environment, so the native changes have never been compiled or run. Everything is uncommitted
on branch `initial_health` (last commit `9684b0f`).

**Next action:** `flutter build apk`, sideload, re-run the three photos in `.pig_pictures/`.
Native deps (opencv-mobile, onnxruntime) are already fetched under
`packages/instaham_ml_ffi/src/third_party/`, so no `scripts/fetch_deps.sh` run is needed.

---

## The diagnosis

Three real scans (`ref_log.md`, photos in `.pig_pictures/`, all iPhone 11, all seen by the
pipeline at 2250×3000 after `ImageService`'s 3000px cap):

| photo | app scale | result | BL reported | implied body length | BL expected | shrink |
| --- | --- | --- | --- | --- | --- | --- |
| 92 kg, meter stick | 0.0648 cm/px | rejected | 64.0 | **16.6 cm** | ~532 | 8.3× |
| 118 kg, porac stick | 0.0653 cm/px | rejected | 14.0 | **3.6 cm** | ~636 | 45.4× |
| 96 kg, porac stick | 0.0634 cm/px | **141.1 kg** (true 96) | passed | — | ~642 | 1.0× |

A 118 kg pig whose mask measures 3.6 cm end to end is not a scale error — the masks were
garbage (a 64×39 blob and a 14×3 sliver). All three photos are good dorsal shots; measuring
the sticks off the images independently reproduces the user's pixel lengths within ~2%.

**Root cause (F12), `stages/segmentation.cpp`:** `mask_area()` ranked NMS candidates by their
*uncropped* prototype response over the whole 160×160 proto plane. The Python reference
(`ML/pipeline/segmentation.py::_largest_mask_index`) reads `result.masks.data`, which
ultralytics has **already cropped to each instance's box**. So selection scored a global
response blob while `construct_pig_mask` then built the mask from that winner's own small box.
Image-dependent, which is why 1 of 3 worked; only bites when >1 detection survives NMS (the
96 kg pig hangs against a clean wall, the two failures have feet, footwear, a hose, a grate).

**This exonerates:** the reference object and the user's marking, `cm_per_px_target = 0.26`,
`k`, the height-ratio bound, and the feature-domain gate. The gate correctly refused to
predict on a 3.6 cm pig (AGENTS.md rule 8).

**The +47% on the scan that worked** (141.1 vs 96) is the identity-stub cutter: head/neck stay
in the mask, so expected BL ~642 sits above the trained head-removed max of 638. Expected and
documented — do not fudge it.

---

## Shipped this session

Round 2 (F6–F11) and round 3 (F12–F17) are both in the working tree. `ref_fix.md` holds the
full round-3 plan and rationale; numbering is continuous and cited from source comments, so
**never reuse F1–F17**.

### Round 3 — the actual fix

- **F12** — new `packages/instaham_ml_ffi/src/stages/mask_geometry.h`: `proto_box_bounds()` +
  `cropped_mask_area()`, pure array math (no OpenCV/ORT), shared by `segmentation.cpp`'s
  selection and `construction.cpp`'s mask building so the two can't diverge again.
- **F13** — segmentation output channel layout derives `nc` instead of hardcoding 1.
- **F14** — `construct_pig_mask` consumes the carried `letterbox_pad_left/top` instead of
  recomputing them, honouring `segmentation.h`'s own stated contract.
- **F15** — `envelope["segmentation"]` now carries `candidates_kept`, selected/runner-up proto
  mask areas, the selected box in original pixels, and its frame fraction. `candidates_kept`
  is the key number: F12 only bites when it is > 1.
- **F16** — mask-plausibility gate before the cutter/feature/domain stages. Rejects a mask
  whose bbox diagonal is under `min_mask_diagonal_fraction` (manifest-tunable, default 0.15)
  with a dedicated `mask_implausibly_small` reason. Needed because `E` (eccentricity) cannot
  catch a degenerate mask — a thin sliver scores *high* on eccentricity.
- **F17** — `classify_domain_violation` routes **any** `E` violation to
  `mask_shape_out_of_domain` (round 2 required E to violate alone, which misrouted the 118 kg
  sample to the reference-object message); the Dart failure message now always renders all
  five RA/LC/BL/BW/E values with violators starred, not only the violating ones.

### Round 2 — made it diagnosable (this is what produced the numbers above)

F6 persists the feature vector and a `features` pipeline event on every run, success or
failure. F7 split the domain-gate reason three ways. F8 replaced guessed `upper_multiplier`
values with ones measured from `whole_mask_area_px` in the eval CSV and added
`lower_multiplier`. F9 added `cm_per_px_target_uncertainty` (1.15) which widens size bounds
only. F10 (scale-invariant shape checks) was deliberately **deferred**. F11 replaced the
endpoint crosshair with an auto-oriented caliper-jaw rectangle in
`reference_marking_screen.dart`.

---

## Files touched (all uncommitted)

Native: `stages/mask_geometry.h` (new), `stages/segmentation.{h,cpp}`,
`stages/construction.cpp`, `pipeline.cpp`, `manifest.{h,cpp}`, `test/CMakeLists.txt`,
`test/test_mask_selection.cpp` (new), `test/test_feature_domain.cpp` (new).

Dart: `run_and_persist_pipeline_use_case.dart`, `reference_marking_screen.dart`,
`test/features/inference_pipeline/weight_domain_failure_test.dart` (new),
`test/features/weight_estimation/reference_marker_geometry_test.dart` (new).

ML/assets: `ML/export/export_xgboost.py`, `ML/export/manifest.schema.json`,
`assets/ml/manifest.json`.

No Drift schema change — no `schemaVersion` bump, no migration, no `build_runner`.

---

## Verification status

**Done:** `dart format` and `flutter analyze` clean (one pre-existing unrelated `unused_field`
warning in generated FFI bindings). 54/54 Dart tests pass across
`test/features/inference_pipeline/` and `test/features/weight_estimation/`.

**Not done — the gap:** the native C++ has never been compiled. No compiler exists in this
environment (checked `cl.exe`, `g++`, `clang++` — none). `test_mask_selection.cpp` is written
and wired into ctest but unrun; its arithmetic was verified only by porting the identical
logic to Python and executing that. `assets/ml/manifest.json` was hand-edited to match what
`export_xgboost.py` now emits, because `xgboost`/`onnxmltools`/`onnxruntime` are not installed
here — regenerate it properly when the ML toolchain is available.

**Acceptance for F12:** the two failing photos should produce `BL` in the 500–650 range rather
than 64 and 14, and both should predict a weight. The 96 kg photo must still pass and still
predict ~141 kg (it had a single dominant detection; F12 doesn't change that path). Expect the
two recovered scans to overestimate by roughly the same +47% — that is the correct outcome
here; the cutter is out of scope.

If they still fail, the next suspect is detection quality itself (the model may not fire well
on extreme close-ups). `candidates_kept` in the new `segmentation` pipeline event tells you
which world you're in.

---

## Standing limitations (unchanged, both out of scope)

1. The cutter is a permanent identity stub, so every prediction reads ~47% heavy.
2. `cm_per_px_target = 0.26` is still the uncalibrated seed. The 96 kg scan suggests it is
   roughly right — reassurance, not calibration. Replace it with the median of several 1.88 m
   calibration captures and set `cm_per_px_target_uncertainty` to 1.0 at the same time.
