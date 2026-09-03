# TASKS.md — Wiring the reference object into the weight pipeline

**Goal.** Turn the reference-object marking screen from a dummy that computes a number nobody
reads into the scale source for the weight branch, so that XGBoost receives `RA, LC, BL, BW, E`
expressed in the pixel space the regressor was trained on, regardless of the height the phone was
held at.

**Status of the code this plan touches:** verified against the working tree on branch
`initial_health` (commit `8c98aac`).

---

## 1. What exists today

### 1.1 The reference tool (works, but nothing consumes it)

`lib/features/weight_estimation/presentation/screens/reference_marking_screen.dart` lets the user
place two pins, drag them, and pick a preset (`meter_stick` 100 cm, `porac_stick` 131 cm) or a
custom length. It computes the pixel distance in **original image pixels**
(`_originalPixelLength`, lines 67–77) using `args.imageWidthPx` / `args.imageHeightPx`, divides
`lengthCm` by it (line 206), and persists the result:

```dart
await database.saveReferenceAnnotation(
  scanId: sessionId, reference: _reference,
  startX: ..., startY: ..., endX: ..., endY: ...,
  pixelLength: pixelLength, cmPerPixel: cmPerPixel, ...);
```

`ReferenceAnnotations` (`lib/core/database/app_database.dart:50`) already stores
`pixelLength` and `cmPerPixel`. Nothing ever reads them back — there is no
`getReferenceAnnotation` query anywhere in `lib/`, and the only other references to that table are
the insert at line 303 and the wipe at line 587.

`ComputeScaleUseCase` (`lib/features/weight_estimation/domain/use_cases/compute_scale_use_case.dart`)
implements exactly this division with proper validation, and is **dead code**: its only caller is
its own test. The screen re-implements the same division inline instead of using it. Same story for
`WeightEligibilityChecker` — 9 checks, fully tested, checks 5–8 are all about the reference object,
and no production code path calls it.

### 1.2 The pipeline (one native call, no scale input)

`RunAndPersistPipelineUseCase.execute(db, scanId, imagePath)`
(`lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`) makes a
single call `pipelineService.run(imagePath)` →
`MlRuntime.runPipeline(imagePath)` → `instaham_ml_run_pipeline_json(ctx, image_path, out_json)`.
The image path is the **only** input. There is no parameter through which a scale could travel, at
any layer: not the Dart use case, not `IPipelineService`, not `MlRuntime`, not the generated
bindings (`_InferDart` is `(ctx, imagePath) -> json`), not the C ABI.

Inside `packages/instaham_ml_ffi/src/pipeline.cpp` the weight branch calls:

```cpp
auto feats = stages::extract_five_features(cutter_result.mask, cutter_result.width,
                                           cutter_result.height, 1.0,
                                           /*preserve_processed_mask=*/true);
```

`1.0` is the `linear_scale` argument. Every shipped path hardcodes it — `ML/weight_runtime.py:499`,
`ML/parity/run_reference.py:70`, and the manifest's own
`weight.feature_extractor.linear_scale: 1.0` (`ML/export/export_xgboost.py:118`).

### 1.3 The regressor's capture contract

`assets/ml/manifest.json` → `capabilities.weight.capture_contract`:

```json
{ "feature_space": "fixed_camera_pixels",
  "training_camera_height_m": 1.88,
  "camera_height_is_xgboost_feature": false }
```

Parsed into `WeightCapability` at `packages/instaham_ml_ffi/src/manifest.cpp:206-211`. The contract
is *recorded* and *reported* in the envelope; it is never *enforced*. A photo taken at 2.5 m runs
through the identical code path as one taken at 1.88 m and produces a confident, wrong number.

Note that in this working tree `capabilities.weight.available` is **true** — this is an
`export_xgboost.py --enable-for-testing` bundle — so the weight branch is live and testable right
now, uncut mask and all.

---

## 2. Three defects that must be fixed before cm/px means anything

These are ordered by how badly they corrupt the number. Fixing #1 is a prerequisite for the whole
plan; a scale computed from bad pin coordinates is worse than no scale at all.

### D1 — Pin coordinates are normalized against the widget, not the displayed image rect

`AGENTS.md` critical rule 9 says reference-point coordinates must map to the actual displayed image
rectangle including `BoxFit` letterboxing. The screen does the opposite:

- `_ReferencePhoto` renders with `fit: BoxFit.contain` (lines 501 and 504).
- `_placePin` (line 42) divides the tap position by the **`LayoutBuilder` constraints**, i.e. the
  full widget box, and `_movePin` (line 55) does the same for drag deltas.
- `_originalPixelLength` then multiplies those fractions by `imageWidthPx` / `imageHeightPx`.

With `BoxFit.contain` the image occupies only part of the widget in one axis. A 4:3 photo in a
3:4 widget box leaves ~44 % of the height as empty letterbox. A pin the user places at the visual
midpoint of the stick maps to a normalized coordinate that is wrong in that axis by the letterbox
ratio, and the error is **anisotropic** — it distorts diagonal reference placements more than
axis-aligned ones. The resulting cm/px can be off by tens of percent, and the error is invisible
because the on-screen line still looks right.

**Fix:** compute the displayed image rect from the image's aspect ratio and the widget
constraints, hit-test against that rect, and normalize against it. Reject taps outside it rather
than clamping them to the edge (clamping silently fabricates an endpoint). This requires knowing
the image aspect ratio at layout time — `args.imageWidthPx`/`imageHeightPx` already carry it, and
the screen should refuse to accept pins at all when they are null, instead of the current behaviour
of accepting pins and then quietly producing `cmPerPixel: null` at save time (line 204).

### D2 — `cmPerPixel` is persisted but unreachable from the pipeline

`RunAndPersistPipelineUseCase.execute` takes `(db, scanId, imagePath)` and never queries
`referenceAnnotations`. Even a perfect cm/px value cannot reach the native layer.

### D3 — There is no ABI through which a scale can be passed

`instaham_ml_run_pipeline_json` takes `(ctx, image_path, out_json)`. `instaham_ml.h`'s own contract
states `ABI_VERSION` bumps only on a breaking signature change, so this needs either a new
entrypoint or an ABI bump. See §5.3.

---

## 3. The math — what "normalize to the training space" actually requires

The instruction gives:

> `k = cm_per_px_actual / cm_per_px_target`

That is correct for the **length-dimensioned** features, and it is not sufficient for the whole
feature vector. Working through all five:

| Feature | Definition (`ML/pipeline/feature_calculation.py:44-52`) | Dimension | Behaviour under a k-resize |
|---|---|---|---|
| `RA` | `area_pixels / (height * width)` | dimensionless *ratio of areas* | **invariant** — both numerator and denominator scale by k² |
| `LC` | `cv2.arcLength(contour) * linear_scale` | length | scales by k ✔ |
| `BL` | `max(minAreaRect side) * linear_scale` | length | scales by k ✔ |
| `BW` | `min(minAreaRect side) * linear_scale` | length | scales by k ✔ |
| `E` | eccentricity from `fitEllipse` axis ratio | dimensionless *ratio of lengths* | **invariant** ✔ (correctly so) |

`LC`, `BL`, `BW` are handled by `linear_scale = k`; `E` is genuinely scale-free and needs nothing.
`RA` is the problem. It is invariant to a resize, but it is **not invariant to camera height** —
a pig photographed from 2.5 m fills less of the frame, so its `RA` is smaller by (1.88/2.5)². A
naive whole-image resize by `k` scales the pig **and the canvas**, so `RA` comes out unchanged and
therefore still wrong. `RA` is the one feature that encodes "how much of the frame the animal
occupies", which is exactly the thing camera height changes.

The correct transform keeps the numerator in normalized pixels and pins the denominator to the
**training frame**:

```
RA_normalized = (area_px_actual * k²) / (W_train * H_train)
```

### 3.1 `W_train × H_train` is recoverable from the repo — it is 720 × 720

`ML/weight_prediction/fixed_test_predictions_POSTHOC.csv` carries both `RA` and
`body_mask_area_px` per row. Dividing them recovers the denominator the training features were
computed against. Across **all 2014 rows** the quotient is exactly **518400 = 720 × 720**, with no
second value:

```
row 1:  49757 / 0.0959818672839506 = 518400
row 2:  49004 / 0.0945293209876543 = 518400
```

Every row also has `camera_height_m = 1.88` and `feature_space = fixed_camera_pixels`, confirming
the contract is uniform across the training set. So the training frame constant is not a guess —
it is a measured property of the shipped model's own evaluation artefact.

### 3.2 `cm_per_px_target` is *not* recoverable from the repo

Nothing in `ML/` records a physical length. The dataset (`PIGRGB-Weight`, subset `RGB_9579`)
gives pixel geometry and kilograms, never centimetres. So `cm_per_px_target` must be **measured**,
and it is the one genuinely new constant this work introduces. §4 covers how.

An order-of-magnitude seed is available for sanity-checking whatever measurement comes back.
Training `BL` (post-head-removal trunk length) has median 426.6 px over a 87–192 kg weight range,
median 108 kg. A 108 kg market pig's trunk is roughly 105–115 cm, giving
`cm_per_px_target ≈ 110/426.6 ≈ 0.26 cm/px`. That implies a 720 px frame spans ~186 cm at 1.88 m,
i.e. a horizontal field of view of ~53° — an entirely ordinary camera. **A measured value outside
roughly 0.15–0.40 cm/px should be treated as a measurement error, not accepted.**

### 3.3 Where to apply `k` in the flow

The instruction's flow is:

```
Original RGB -> aspect-preserving resize -> letterbox -> 640x640 -> YOLO seg
Remove padding / recover original coordinates -> Mask H x W -> Ji/Duan + body-masking
  -> features -> RA, LC, BL, BW, E -> XGBoost
```

The letterbox resize in the first line is YOLO's own preprocessing and already exists
(`SegmentationOutput` carries `letterbox_scale` / `letterbox_pad_left` / `letterbox_pad_top`
verbatim, and `construct_pig_mask` unletterboxes back to `orig_w × orig_h` — this is already
correct and parity-gated, do not touch it). The `k` scaling is a **separate** step, and there are
two defensible places for it:

**Option A — analytical (no resampling).** Leave the mask at original dimensions. Pass
`linear_scale = k` into `extract_five_features`, and additionally override the `RA` denominator to
`W_train * H_train` with the numerator multiplied by k². Exact, zero resampling error, ~4 lines of
change.

**Option B — resample the mask (recommended).** Between construction and the cutter, resample the
binary mask by `k` (INTER_NEAREST or area) into normalized-training pixel space, then run the
cutter and feature extraction on that mask with `linear_scale = 1.0`, with the `RA` denominator
taken from the manifest's training frame.

Option B is recommended even though Option A is cheaper and exactly equivalent *today*, because the
Ji/Duan cutter is a pixel-space algorithm. `cutter.cpp` is currently an identity stub, but the
protocol it will implement (`ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`) has thresholds
and structuring elements calibrated in training pixels. Under Option A the real cutter would
operate on unnormalized pixels and its thresholds would silently mean different physical sizes per
photo. Option B makes the instruction's "Mask H × W (this is what goes downstream)" literally true
and keeps the cutter correct by construction when it lands. The cost is one nearest-neighbour
resample of a binary mask — negligible next to a 640×640 YOLO pass.

Placing the resample **after** construction also keeps the existing parity gates valid:
gate B compares `construct_pig_mask`'s output against the Python reference, and that output is
unchanged.

---

## 4. Establishing `cm_per_px_target`

Two paths. Do W1 first; W1b is an optional refinement that should not block the rest of the plan.

**W1 — single calibration capture (the instruction's own suggestion).**
Mount or hold the phone so the sensor is exactly 1.88 m above the floor, place a 1 m stick flat on
the floor plane, capture through the app's normal capture path (so EXIF baking and JPEG encoding
match production exactly), mark both endpoints in the existing reference screen, and read the
resulting `cmPerPixel` from `ReferenceAnnotations`. Repeat 3–5 times with the stick in different
positions and orientations in frame and take the median; the spread across repeats is the honest
error bar on the constant and should be recorded next to it.

**Caveat that must be written down with the number:** this measures the cm/px of *this* phone's
camera at 1.88 m, not the research rig's. They coincide only if the two cameras share a horizontal
field of view and the training images were not cropped from a wider frame. The 720×720 training
frame is square, which strongly suggests a crop or resize of a non-square original — so the
constant recovered this way is an approximation whose residual error shows up as a systematic bias
in predicted kilograms. That bias is acceptable to ship behind the "provisional" labelling the
weight branch already carries; it is not acceptable to present as calibrated.

**W1b — refinement by sweep (optional, only if weighed pigs are already on hand).**
If any scans exist with both a reference marking and a scale-verified true weight, sweep
`cm_per_px_target` over 0.15–0.40 in 0.005 steps, recompute the five features per candidate,
run the regressor, and pick the value minimizing MAE. This estimates the constant *in the units the
model actually cares about* and absorbs the FOV mismatch above. It needs no new data collection
beyond what a normal validation session produces. Do not gate W2–W6 on this.

**Storage.** The constant goes in the manifest, never in Dart or C++ source — `AGENTS.md` rule 1's
principle (mappings and model-space constants come from model metadata) applies directly.
Extend `export_xgboost.py`'s `capture_contract` block:

```python
"capture_contract": {
    "feature_space": "fixed_camera_pixels",
    "training_camera_height_m": 1.88,
    "camera_height_is_xgboost_feature": False,
    "cm_per_px_target": <measured>,          # NEW
    "cm_per_px_target_source": "calibration_capture_1p88m_median_of_5",  # NEW, provenance
    "training_frame_px": [720, 720],         # NEW, measured in §3.1
},
```

and parse the three new fields into `WeightCapability` alongside the existing two
(`manifest.cpp:206-211`). A manifest whose `weight.available` is true but which lacks
`cm_per_px_target` or `training_frame_px` must **fail to load** with
`INSTAHAM_ML_ERR_CONTRACT` — the same bundle-level assertion style the plan already uses for
`weight.available ⇒ cutter.protocol_implemented`. Silently defaulting to 1.0 is exactly the
failure mode `AGENTS.md` rule 8 exists to prevent.

---

## 5. Work plan

### W0 — Fix D1: pin coordinates against the displayed image rect

**Files:** `lib/features/weight_estimation/presentation/screens/reference_marking_screen.dart`

- Add a helper that, given widget constraints and the image's `(widthPx, heightPx)`, returns the
  `Rect` `BoxFit.contain` actually paints into.
- `_placePin` / `_movePin` normalize against that rect; taps outside it are ignored (no pin
  placed, no clamp).
- The pin overlay and `_ReferenceLinePainter` position from the same rect, so what the user sees
  and what is stored cannot diverge.
- When `imageWidthPx`/`imageHeightPx` are null, disable pin placement and show why, instead of
  accepting pins and saving `cmPerPixel: null`.
- Replace the inline `_reference.lengthCm / pixelLength` divisions (lines 206 and ~233) with the
  already-tested `ComputeScaleUseCase`, deleting the duplicate logic rather than keeping two.

**Acceptance:** a widget test that lays the screen out at an aspect ratio deliberately mismatched
to the image, taps two points a known number of logical pixels apart along the letterboxed axis,
and asserts the stored `pixelLength` equals the geometrically correct value. This test fails
against today's code — that is the point.

### W1 — Establish and ship `cm_per_px_target`

Per §4. Deliverables: the measured constant with its spread, the three new manifest fields, the
`manifest.cpp` parse, and the contract assertion that refuses a weight-available manifest missing
them. Ships independently of W2–W6.

### W2 — Read the reference annotation back

**Files:** `lib/core/database/app_database.dart`, or a new focused DAO under
`lib/features/weight_estimation/data/` (preferred — `AGENTS.md`'s database rules ask for focused
DAOs rather than growing the god-object, and `custom_references_dao.dart` is the existing
precedent).

- `Future<ReferenceAnnotation?> getReferenceAnnotation(String scanId)`.
- No schema change is needed anywhere in this plan. `WeightResults` already has nullable
  `referenceLengthCm`, `referencePixelLength` and `cmPerPixel` columns
  (`app_database.dart:77-79`) that `saveWeightResult` currently never populates; `k` is derived on
  read as `cmPerPixel / manifest.cm_per_px_target`. **`schemaVersion` stays 3.**

### W3 — Thread the scale through Dart

**Files:** `lib/services/ml/pipeline_service.dart`, `lib/services/ml/ml_runtime.dart`,
`packages/instaham_ml_ffi/lib/instaham_ml_bindings_generated.dart`,
`lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`

- `IPipelineService.run(String imagePath, {double? cmPerPixel})`.
- `MlRuntime.runPipeline(String imagePath, {double? cmPerPixel})`.
- `execute()` fetches the annotation via W2's DAO before calling `run`, and passes
  `cmPerPixel` only when `userConfirmed && sameFloorPlaneConfirmed` are both true — an unconfirmed
  or non-coplanar reference is not a scale (`AGENTS.md` rule 7: derive cm/pixel only from the
  user-confirmed reference object).

### W4 — Extend the C ABI (D3)

**Files:** `packages/instaham_ml_ffi/src/include/instaham_ml.h`,
`packages/instaham_ml_ffi/src/instaham_ml.cpp`, `packages/instaham_ml_ffi/src/instaham_ml.map`

Add **one new entrypoint** rather than changing the existing signature, keeping `ABI_VERSION` at 1
per the header's own stated contract:

```c
/* Request-shaped variant of instaham_ml_run_pipeline_json. request_json:
 *   {"image_path":<str>, "cm_per_px":<num|null>}
 * Unknown keys are ignored, so later inputs (ROI, capture metadata) are additive. */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_run_pipeline_request_json(
    InstahamMlContext* ctx, const char* request_json, char** out_json);
```

`instaham_ml_run_pipeline_json` stays, implemented as a thin call into the new one with
`cm_per_px: null` — so every existing native test keeps compiling and passing unchanged. Export the
new symbol in `instaham_ml.map`.

The request-JSON shape is preferred over a bare `double` parameter because the next three things
this pipeline will want to receive (a user-confirmed ROI, capture metadata, an EXIF assertion) are
then additive rather than another entrypoint each.

### W5 — Normalize in native (the core change)

**Files:** `packages/instaham_ml_ffi/src/pipeline.cpp`,
`packages/instaham_ml_ffi/src/stages/construction.{h,cpp}`,
`packages/instaham_ml_ffi/src/stages/feature_calculation.{h,cpp}`,
`packages/instaham_ml_ffi/src/manifest.{h,cpp}`

1. `WeightCapability` gains `double cm_per_px_target`, `int training_frame_w`,
   `int training_frame_h`, parsed in W1.
2. New function in `construction` (it is stage 2's job — it already owns coordinate-space
   transforms, and stage-order enforcement forbids a stage importing a later one):
   ```cpp
   // Resamples a pig mask from capture pixels into training pixels.
   // k = cm_per_px_actual / cm_per_px_target. Returns an empty mask for a
   // non-finite or non-positive k -- never silently falls back to k = 1.
   PigMask scale_mask_to_training_space(const PigMask& mask, double k);
   ```
3. `extract_five_features` gains an optional explicit `RA` denominator
   (`int ra_frame_w = 0, int ra_frame_h = 0`, 0 meaning "use the mask's own dimensions" so the
   existing parity callers are untouched). `pipeline.cpp` passes the manifest's training frame.
4. `pipeline.cpp`'s weight branch becomes:
   - `cm_per_px` absent/invalid → `envelope["weight"] = {"status":"unavailable",
     "reason":"scale_unavailable", "user_message_key":"weight_needs_reference_object"}`;
     `features` reported as `provisional` with `"measured_on":"uncut_mask_unnormalized"` so the
     numbers stay visible for debugging but can never be mistaken for model input.
   - `cm_per_px` present → compute `k`, resample, run cutter, extract features with the training
     frame denominator, predict.
   - `k` outside a sanity band (proposed `[0.25, 4.0]`, i.e. roughly 0.47 m–7.5 m of camera
     height) → `{"status":"unavailable","reason":"scale_out_of_range"}`. A pig photographed from
     7 m is not a photo this model has any claim on.
5. New envelope block, so the whole chain is auditable from the app:
   ```json
   "scale": { "status": "ok",
              "cm_per_px_actual": 0.41, "cm_per_px_target": 0.26,
              "k": 1.577, "training_frame_px": [720, 720],
              "source": "user_confirmed_reference" }
   ```
   with `{"status":"unavailable","reason":...}` in the failure cases.

**Health is untouched by all of this.** `AGENTS.md` rule 4: the branches are independent, and the
health branch runs before the weight branch in `pipeline.cpp` already. A missing reference object
must never degrade a health result.

### W6 — Persist and surface

**Files:** `run_and_persist_pipeline_use_case.dart`, the results screens

- On a successful weight result, populate the three reference columns that already exist
  (`referenceLengthCm`, `referencePixelLength`, `cmPerPixel`) alongside the features, so a stored
  scan can be re-derived later.
- On `scale_unavailable`, route to the existing `weight_blocked_screen.dart` /
  `skip_weight_screen.dart` path with a message that names the actual cause ("mark a reference
  object to estimate weight"), not the generic failure text.
- Wire `WeightEligibilityChecker` — currently dead — into this path so checks 5–8 (reference
  present, positive length, endpoints far enough apart, coplanar) run in one place instead of being
  re-implemented ad hoc across the screen and the use case.
- The features shown in the UI must be the **normalized** ones when a scale was applied, and must
  be labelled as raw when one was not. Two different numbers under one label is how a debugging
  session gets lost.

---

## 6. Rule compliance

| `AGENTS.md` rule | How this plan satisfies it |
|---|---|
| 1 — no hardcoded model constants | `cm_per_px_target` and `training_frame_px` live in the manifest, parsed like every other capability field; a weight-available manifest missing them fails to load |
| 2 — features exactly `RA, LC, BL, BW, E` | unchanged; only their values are normalized, and `manifest.cpp:200` already refuses any other order |
| 3 — weight needs all eligibility checks | W6 wires `WeightEligibilityChecker` in; a missing scale is itself a failed check |
| 4 — branches independent | health runs before, and regardless of, the whole scale path; `scale_unavailable` never touches `envelope["health"]` |
| 5 — EXIF corrected before any model | already true — `ImageService.processRawBytes` bakes orientation (`image_service.dart:29`) and reports `widthPx`/`heightPx` from the *oriented* image, which is also the file the native side decodes |
| 6 — no resize/rotate after marking without exact transform | the `k` resample happens on the **mask**, after construction has already returned to original coordinates, and the reference pins are never re-transformed |
| 7 — cm/pixel only from the confirmed reference | W3 passes `cmPerPixel` only when `userConfirmed && sameFloorPlaneConfirmed` |
| 8 — never force a prediction after a failed check | every failure path emits `unavailable` with a named reason; there is no `k = 1.0` fallback anywhere |
| 9 — coordinates map to the displayed image rect | W0, the first task in the plan |

---

## 7. Validation

Narrowest-useful checks, per `AGENTS.md`:

1. `dart format` on every changed Dart file.
2. `flutter analyze`.
3. `flutter test test/features/weight_estimation/` — extended with W0's letterbox widget test and a
   `ComputeScaleUseCase` round-trip.
4. `flutter test test/features/inference_pipeline/` — a fake `IPipelineService` asserting that
   `cmPerPixel` is forwarded when the annotation is confirmed and withheld when it is not.
5. Native unit tests under `packages/instaham_ml_ffi/src/test/`:
   - `scale_mask_to_training_space` with `k = 1.0` is the identity;
   - `k = 2.0` doubles `BL`/`BW`/`LC` to within resampling tolerance and leaves `E` unchanged;
   - `RA` with an explicit 720×720 denominator reproduces the CSV relationship
     `RA == area_px / 518400` on a synthetic mask;
   - a non-finite / zero / negative `k` returns an empty mask, and the envelope reports
     `scale_unavailable`, never a number.
6. A regression fixture asserting `instaham_ml_run_pipeline_json` (the old entrypoint) still
   produces a byte-identical envelope for a no-scale run.
7. No `dart run build_runner build` needed — §W2 explicitly avoids a schema change.

**Every one of these must be reported with its actual command output.** In particular, the native
tests need the Android build to succeed, and this environment cannot run the app on a device — the
end-to-end confirmation is a sideloaded APK on the physical phone.

---

## 8. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | `cm_per_px_target` measured on this phone ≠ the research rig's, because the 720×720 training frame is a crop/resize of a non-square original | **high** | a systematic multiplicative bias in every kilogram shown | W1b's sweep absorbs it; the number stays behind the existing "provisional / uncut mask" labelling until it is validated against scale weights |
| 2 | Users mark the reference on a surface that is not the pig's floor plane | medium | scale wrong by the plane offset, silently | `sameFloorPlaneConfirmed` is already collected and is now load-bearing rather than decorative (W3) |
| 3 | The identity-stub cutter dominates the error budget | certain | `BL`/`LC` include the head; predictions overestimate | already labelled in three places in the envelope; this plan does not claim to fix it, and normalization is orthogonal to it |
| 4 | Training weight range is 87–192 kg (median 108); smaller pigs are out of distribution | high in the field | confident extrapolation on young stock | out of scope here, but worth an explicit range check before the weight number is ever presented as calibrated |
| 5 | Binary-mask resampling changes the contour enough to move features by >1 % | low | parity drift | resample happens after the parity-gated construction output, so gates A/B are unaffected; W5's test bounds the drift directly |
| 6 | Two entrypoints (`..._json` and `..._request_json`) drift apart | low | inconsistent behaviour between debug and production paths | the old one is implemented as a call into the new one, not a copy; §7.6 pins that |

---

## 9. What this plan deliberately does not do

- **Implement the Ji/Duan cutter.** Out of scope by standing instruction. Normalization is
  independent of it and lands first; Option B in §3.3 is chosen specifically so the cutter is
  correct-by-construction when it does land.
- **Retrain the regressor to remove the fixed-height dependence.** That is the real fix for the
  whole class of problem this plan works around, and it is not a code task.
- **Automatic reference detection.** The screen already supports a `suggestion` path; this plan
  only makes the manual, user-confirmed path load-bearing.
- **Any schema change.** The three columns needed already exist and are unused.

---

## 10. Plan rating

**8 / 10.**

**Pros**

- **It fixes a real, invisible correctness bug first.** D1 (pins normalized against the widget
  rather than the `BoxFit.contain` rect) corrupts cm/px by the letterbox ratio in one axis, is a
  direct violation of `AGENTS.md` rule 9, and would have quietly poisoned every downstream number
  this plan wires up. Doing the scale work without fixing it would have produced a system that
  looks calibrated and is not.
- **It found the `RA` gap.** The instruction's single `k` is correct for `LC`/`BL`/`BW` and silently
  wrong for `RA`, which is a ratio against the frame and therefore invariant to exactly the resize
  meant to correct it. Two of the five features would have stayed uncorrected under a literal
  reading, and the failure would have been a plausible-looking bias, not an error.
- **One of the two new constants is measured, not assumed.** `training_frame_px = 720 × 720` is
  recovered from the shipped model's own evaluation CSV and holds exactly across all 2014 rows —
  no calibration session, no guesswork.
- **It costs no migration.** `WeightResults` already carries the three reference columns unused, so
  `schemaVersion` stays 3 and there is no Drift regeneration, no migration test, no schema risk.
- **Every failure path is `unavailable` with a named reason.** There is no `k = 1.0` fallback
  anywhere in it, which is the specific dishonest failure `AGENTS.md` rule 8 targets.
- **The ABI change is additive.** `ABI_VERSION` stays 1, existing native tests keep passing
  unchanged, and the request-JSON shape means the next input this pipeline needs is a field, not
  another entrypoint.

**Cons**

- **The headline constant is the weakest link in the whole chain.** `cm_per_px_target` cannot be
  recovered from anything in this repo, and the single-calibration-photo method measures *this
  phone's* camera at 1.88 m, not the research rig's. The square 720×720 training frame is
  circumstantial evidence of a crop the calibration cannot see through. W1b's sweep is the honest
  fix and it depends on scale-weighed pigs that may not be at hand.
- **It improves the input to a model whose output is still not trustworthy.** The cutter is an
  identity stub, so `BL` and `LC` include the head and the predictions overestimate. Perfectly
  normalized features into a mis-specified mask is a better wrong answer, not a right one.
- **`RA` normalization assumes the capture and training framings are comparable in kind.** Pinning
  the denominator to 720×720 is right for camera height; it does nothing about a different aspect
  ratio or a different crop convention, and there is no artefact in the repo that says what the
  training crop was.
- **The sanity bands are engineering judgement, not measurements.** `k ∈ [0.25, 4.0]` and
  `cm_per_px_target ∈ [0.15, 0.40]` are defensible and round; neither is derived from data, and
  both will need revisiting once real captures exist.
- **W0 is a UI change on a screen with no existing widget-test coverage**, so the letterbox test
  has to be written from scratch against a screen that also depends on `DatabaseScope` and
  `go_router` — the most fiddly task in the plan is the one that has to land first.
- **Six work items across Dart, the C ABI, native stages, and the manifest exporter** is a wide
  blast radius for what is conceptually one multiplication, and only W1 and W0 deliver anything
  observable on their own.

---

## 11. Execution status (2026-09-02)

W0 through W6 are implemented. What follows is what actually shipped, one deliberate deviation,
one pre-existing bug found (not fixed — out of scope), and the exact validation run.

### Shipped

- **W0** — `reference_marking_screen.dart`: pin placement/drag now normalize against
  `computeContainedImageRect()` (a new pure top-level function, extracted specifically so the
  letterbox math is unit-testable), not the raw widget box. A tap outside that rect is ignored,
  not clamped. Pin placement is refused (with an on-screen reason) when image dimensions are
  unknown. The two inline `lengthCm / pixelLength` divisions are replaced by
  `ComputeScaleUseCase`, which is no longer dead code.
- **W1** — `WeightCapability` gained `cm_per_px_target`, `training_frame_w/h`.
  `training_frame_px: [720, 720]` is the measured constant from §3.1. `cm_per_px_target` ships as
  **0.26, explicitly labelled `UNCALIBRATED_seed_estimate_pending_1p88m_calibration_capture`** —
  see Deviation below. `manifest.cpp`'s `load_weight()` now refuses to load a weight-available
  manifest missing either field (`INSTAHAM_ML_ERR_CONTRACT`).
- **W2** — `lib/core/database/reference_annotation_dao.dart` (`ReferenceAnnotationDao`) reads back
  `ReferenceAnnotations` by `scanId`. Placed in `core/database/`, not
  `weight_estimation/data/` as originally sketched — its caller is the `inference_pipeline`
  feature, and AGENTS.md bars cross-feature imports. No schema change; `schemaVersion` is still 3.
- **W3** — `IPipelineService.run()` / `MlRuntime.runPipeline()` gained an optional `cmPerPixel`.
  `RunAndPersistPipelineUseCase.execute()` fetches the annotation and forwards it only when
  `userConfirmed && sameFloorPlaneConfirmed && cmPerPixel > 0`.
- **W4** — New additive entrypoint `instaham_ml_run_pipeline_request_json` (request JSON:
  `{"image_path", "cm_per_px"}`). `instaham_ml_run_pipeline_json` is now a thin call into it with
  `cm_per_px` omitted — same behaviour, same tests. `ABI_VERSION` unchanged;
  `instaham_ml.map`'s `instaham_ml_*` wildcard needed no edit.
- **W5** — `construction::scale_mask_to_training_space(mask, k)` (nearest-neighbour resample, empty
  output for non-finite/non-positive `k` — never an implicit `k = 1.0`).
  `extract_five_features()` gained an optional explicit `RA` denominator (0 = old behaviour,
  every existing caller unaffected). `pipeline.cpp`'s weight branch now: resamples into training
  space and predicts when a valid, in-range (`k ∈ [0.25, 4.0]`) scale exists; degrades to
  `{"status":"unavailable","reason":"scale_unavailable"|"scale_out_of_range"|
  "scale_resample_failed"}` otherwise. A new `"scale"` envelope block reports which. Health is
  untouched by all of this.
- **W6** — a successful weight result now also persists `referenceLengthCm`,
  `referencePixelLength`, `cmPerPixel` (columns that existed, unused, since before this feature).
  `_weightFailureMessage()` gained cases for the three new scale reasons; `results_screen.dart`
  already renders `failureReason` dynamically, so no screen edit was needed for the messaging to
  reach the user. **`WeightEligibilityChecker` was NOT wired in** — see Deferred below.

### Deviation: `cm_per_px_target` ships unmeasured

§4's W1 calibration capture requires a phone held at exactly 1.88 m — a physical measurement this
environment cannot perform. Rather than block the rest of the plan on it, `cm_per_px_target` ships
as the §3.2 seed estimate (0.26), with its provenance field spelling out in capital letters that it
is not calibrated. **This must not be read as "done."** The weight branch will now run and produce
numbers, but they carry whatever bias the seed estimate has, on top of the already-known cutter
bias (Risk 3). Before this is trusted: capture 3–5 photos at exactly 1.88 m with a 1-meter stick per
W1's procedure, read the resulting `cmPerPixel` values from `ReferenceAnnotations`, take the
median, and replace `0.26` in both `assets/ml/manifest.json` and
`ML/export/export_xgboost.py`.

### Deferred: `WeightEligibilityChecker` wiring

The plan's W6 asked for this fully tested but currently-dead 9-check class to be wired into
`execute()`. It was not, on inspection: checks 1–4 and 9 duplicate logic the native `pipeline.cpp`
envelope already enforces (pig count, mask boundary, segmentation confidence, posture, feature
sanity) via its own `status`/`reason` fields, and running both independently risks the two
disagreeing — a native `status: "ok"` next to a Dart-computed `ineligible` (or vice versa) with no
single source of truth for which one wins. Checks 5–8 (the reference-object ones) are now enforced
structurally instead: W3's confirmation gate (§ rule 7) plus the native `scale`/`weight` envelope
reasons cover the same ground without a second, potentially-diverging implementation. Wiring the
checker properly would mean first deciding whether it becomes the single source of truth (and
deleting the native duplicate logic) or a pure-Dart pre-flight short-circuit before the native call
— a design decision, not a mechanical wiring task, and out of this pass's scope.

### Bug found, not fixed (pre-existing, out of scope)

`RunAndPersistPipelineUseCase.execute()` calls `resolveViewGate(db, scanId, imagePath)` without
forwarding `this.viewModelService` — the injected fake/alternate service is silently ignored
whenever no `view` `PipelineEvent` already exists for the scan, and the real `ViewModelServiceImpl`
(which touches native ORT) runs instead. This predates this change; it was worked around in the new
W3 test by pre-seeding a `view` event via `recordViewGate()` rather than fixed, since fixing it is
unrelated to reference-object scaling.

### Validation run

```
dart format <every changed .dart file>          → 0 changes needed after first pass
flutter analyze                                   → 1 pre-existing warning (unused_field,
                                                     instaham_ml_bindings_generated.dart:59,
                                                     confirmed present on unmodified tree too)
flutter test                                       → 70 passed, 21 skipped (native/device/
                                                     parity tests that were already skipped
                                                     pre-existing), 0 failed
flutter test test/features/weight_estimation/      → all pass, including the new
                                                     computeContainedImageRect unit tests and
                                                     the new pin-placement widget test
flutter test test/features/inference_pipeline/     → all pass, including the new
                                                     reference_scale_forwarding_test.dart
                                                     (4 cases: confirmed, unconfirmed,
                                                     non-coplanar, no-annotation)
```

**Not run — no C/C++ toolchain in this environment** (no `g++`/`cl`/`clang++`, no Android NDK):
- `test_scale_normalization.cpp` (new, under `packages/instaham_ml_ffi/src/test/`, gated behind
  `INSTAHAM_ML_WITH_OPENCV` in CMakeLists.txt) — written per §7.5 but unbuilt and unrun.
- The Android native build itself (`instaham_ml.cpp`/`pipeline.cpp`/`manifest.cpp`/
  `construction.cpp`/`feature_calculation.cpp`). Reviewed by hand (brace-balance checked file by
  file; every new call site cross-checked against its declaration), but a hand review is not a
  compiler. Per the existing project convention (see `~/.claude` android-testing-workflow memory),
  the real check is a locally built APK sideloaded onto a physical phone — needed before this
  merges, not optional.
- `dart run build_runner build` — not needed; W2 confirmed no schema/generated-source change.
