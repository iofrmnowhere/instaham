# ML Model Integration — INSTAHAM Flutter App (Native C++ / `dart:ffi` Plan)

> This supersedes the previous Chaquopy / `MethodChannel` plan. No Python runtime ships in the
> app. The Python files in `ML/` stay as permanent reference implementations. Work is phased so
> the one hard piece — the 10,701-line `body_mask.py` fixed-06Q geometry pipeline — is deferred
> behind a manifest capability flag until the research models are frozen.

## What changed from the previous plan

| Previous (Chaquopy) | Now (native C++) |
|---|---|
| Ship PyTorch + Ultralytics + XGBoost + OpenCV + SciPy + scikit-image inside the APK | Ship only ONNX Runtime Mobile + opencv-mobile (core/imgproc/imgcodecs) + exported models |
| Kotlin `MethodChannel` bridge, Android only | `dart:ffi` to a stable C ABI, Android **and** iOS |
| ~150 MB+ APK, Chaquopy commercial licence | ~15–30 MB delta, no licence |
| Runs the frozen `.py` unchanged on device | Frozen `.py` become a **reference**; an export toolchain converts checkpoints to ONNX |
| Hard gate: do custom LDConv/ACmix operators load under Chaquopy PyTorch | Softer gate: YOLO export has a documented fallback ladder; view/health/provisional-weight ship regardless |

### Decisions locked

| Decision | Choice |
|---|---|
| Native inference runtime | **ONNX Runtime Mobile** — one engine for classifiers + XGBoost + (later) YOLO |
| Platform scope | **Android + iOS** — build glue lives once in an FFI plugin package |
| Scope of this iteration | Slices 0–5 (below). Defer only `body_mask.py`. |

---

## Architecture

```
Flutter UI
  -> RunInferencePipelineUseCase
       -> IViewModelService / IHealthModelService / IWeightPipelineService / ISegmentationService
            (Dart FFI impls in lib/services/ml/impl/)
              -> MlRuntime  (top-level singleton + one long-lived inference isolate)
                   -> dart:ffi  (ffigen bindings, committed)
                        -> libinstaham_ml.so / instaham_ml.xcframework
                             |  stable C ABI: packages/instaham_ml_ffi/src/include/instaham_ml.h
                             |
      +----------------------+----------------------+---------------------------+
      v                      v                      v                           v
 ONNX Runtime           ONNX Runtime           ONNX Runtime               OpenCV-mobile C++
 (view classifier)      (health classifier)    (XGBoost; YOLO later)      (mask cleanup, 5 features,
                                                                          ji_duan core, unletterbox)
```

Everything the native layer needs — file paths, sha256, architecture name, input size, mean/std,
class-map path, feature order, protocol versions, and a per-capability `available` flag — comes from
an on-device `manifest.json`. **Nothing is hardcoded** in C++ or Dart (satisfies `AGENTS.md`
rules 1, 2, 7).

**The seam that makes the full port cheap:** the C ABI and the manifest schema are frozen in this
iteration. Finishing `body_mask.py` later = a new `cv/body_mask.cpp` + flipping
`"weight": { "available": true }` — no ABI change, no Dart change, no build change. The JSON result
envelope (not C structs) is the payload contract, so adding fields later never breaks the ABI.

---

## New directory structure

### Native — Flutter FFI plugin package (`packages/instaham_ml_ffi/`)

Created with `flutter create --template=plugin_ffi packages/instaham_ml_ffi`. A plugin package keeps
edits to the app's `android/app` and `ios/Runner` folders minimal.

```
packages/instaham_ml_ffi/
├── pubspec.yaml                      # ffiPlugin: true
├── ffigen.yaml
├── lib/
│   ├── instaham_ml_ffi.dart          # DynamicLibrary loader + re-export
│   └── instaham_ml_bindings_generated.dart   # ffigen output (committed)
├── android/build.gradle              # externalNativeBuild.cmake -> ../src/CMakeLists.txt
├── ios/instaham_ml_ffi.podspec       # compiles src/*.cpp, links ORT xcframework + opencv-mobile
├── scripts/fetch_deps.sh             # pinned URLs + sha256 for ORT + opencv-mobile prebuilts
└── src/
    ├── CMakeLists.txt
    ├── include/instaham_ml.h         # THE STABLE C ABI
    ├── instaham_ml.map               # ELF version script: export only instaham_ml_*
    ├── instaham_ml.cpp               # C ABI impl (thin; delegates)
    ├── context.{hpp,cpp}             # manifest load, model registry, capability flags
    ├── manifest.{hpp,cpp}            # nlohmann/json parse + schema_version check
    ├── onnx_runner.{hpp,cpp}         # Ort::Session wrappers, tensor marshalling
    ├── classifier.{hpp,cpp}          # shared view/health: preprocess + softmax + label map
    ├── xgboost_runner.{hpp,cpp}      # XGBoost ONNX inference
    ├── weight_pipeline.{hpp,cpp}     # yolo -> mask -> features -> xgb; honours available flag
    ├── cv/
    │   ├── mask_cleanup.{hpp,cpp}    # port: clean_binary_mask, _largest_component_fill, largest_contour
    │   ├── dorsal_core.{hpp,cpp}     # port: isolate_dorsal_core_ji_duan (+ _rolling_median, _odd_window)
    │   ├── five_features.{hpp,cpp}   # port: extract_five_features (RA, LC, BL, BW, E)
    │   ├── letterbox.{hpp,cpp}       # port: _unletterbox_native_mask + polygon rasterization
    │   └── body_mask_stub.{hpp,cpp}  # returns ERR_UNAVAILABLE while weight.available == false
    ├── util/
    │   ├── image_io.{hpp,cpp}        # decode JPEG/PNG (opencv imgcodecs); NO exif rotation here
    │   ├── sha256.{hpp,cpp}
    │   ├── json_out.{hpp,cpp}        # builds the section-13 result envelope
    │   └── errors.{hpp,cpp}          # thread-local last-error string
    ├── third_party/                  # nlohmann_json (vendored), onnxruntime (prebuilt), opencv (prebuilt)
    └── test/                         # ctest: test_manifest, test_five_features, test_classifier_golden, test_letterbox
```

### Flutter app side

```
lib/services/ml/
├── view_model_service.dart           # interface UNCHANGED
├── health_model_service.dart         # interface UNCHANGED
├── segmentation_service.dart         # interface UNCHANGED (mask still TODO)
├── weight_pipeline_service.dart      # NEW — replaces weight_regression_service.dart
├── ml_runtime.dart                   # NEW — singleton, inference isolate, init from manifest
├── ml_exceptions.dart                # NEW — MlInitException, MlInferenceException, MlUnavailableException
└── impl/                             # NEW dir
    ├── view_model_service_impl.dart
    ├── health_model_service_impl.dart
    ├── segmentation_service_impl.dart
    └── weight_pipeline_service_impl.dart

lib/features/weight_estimation/domain/entities/
└── capture_contract.dart             # NEW — {featureSpace, trainingCameraHeightM, cameraHeightIsXgboostFeature}
```

### Python export & parity toolchain (next to the frozen reference `.py`)

```
ML/export/
├── common.py               # sha256_file, RESIZE_RATIO=1.14, IMAGENET_MEAN/STD, fragment helpers
├── export_classifier.py    # timm ckpt -> ONNX + preprocessing.json + classes.json + fragment + sha256
├── export_xgboost.py       # model.json -> ONNX (onnxmltools); emits feature_order.json + meta
├── export_yolo.py          # Ultralytics modified ckpt -> ONNX (imports ML/yolo_modifications.py); fallback ladder
├── build_manifest.py       # assembles assets/ml/manifest.json; --check re-export determinism
├── ort_op_config.py        # emits the ORT reduced-build op allowlist for the exported graphs
└── requirements-export.txt # torch, timm, ultralytics, onnx, onnxruntime, onnxmltools (DEV ONLY, never ships)

ML/parity/
├── run_reference.py        # runs frozen pipeline over test/fixtures/parity/* -> expected.json
└── compare.py              # tolerance helper reused by the Dart parity test via golden json
```

### Model assets

```
assets/ml/
├── manifest.json
├── view/          model.onnx  classes.json  preprocessing.json
├── health/        model.onnx  classes.json  preprocessing.json
├── weight/        xgboost.onnx  feature_order.json  xgboost.meta.json
└── segmentation/  yolo.onnx  classes.json          # large -> Play Asset Delivery on Android
```

---

## The stable C ABI — `packages/instaham_ml_ffi/src/include/instaham_ml.h`

Design choices: **opaque handle** (not a global singleton — hot-restart safety, a separate test
manifest, clean teardown); **error model** = `int` status enum + out-params, heap JSON strings
freed by the caller, thread-local `instaham_ml_last_error()`; **threading** = synchronous
ORT-`Run`-safe entrypoints that Dart serializes on one inference isolate.

Key entrypoints (full header committed at that path):

- `instaham_ml_create(const char* manifest_path, InstahamMlContext** out)` — verifies every
  referenced file's sha256 before creating any ORT session.
- `instaham_ml_destroy`, `instaham_ml_abi_version`, `instaham_ml_build_info`, `instaham_ml_last_error`.
- `instaham_ml_string_free(char*)` — every `*_json` return is a heap UTF-8 string the caller frees.
- `instaham_ml_capability_available(ctx, "view"|"health"|"segmentation"|"weight")`.
- `instaham_ml_classify_view_json` / `instaham_ml_classify_health_json` —
  `{"status":"ok","label","confidence","probabilities":{...},"class_map_sha256","protocol_version"}`.
- `instaham_ml_predict_weight_json` — mirrors `weight_runtime.py predict()` (section 13). Returns
  `ERR_UNAVAILABLE` + `{"status":"unavailable","reason":"body_mask_port_incomplete"}` while the
  flag is false.
- `instaham_ml_extract_features_provisional_json` — five features from the raw YOLO mask (no
  ji_duan / body_mask), for parity bring-up and the "provisional" UI state.

`image_path` is always an **already-EXIF-normalised** RGB image. Native performs no rotation
(`AGENTS.md` rule 5 is enforced once, Dart-side, in `MlRuntime.exifNormalize`).

---

## Manifest schema — `assets/ml/manifest.json`

```jsonc
{
  "schema_version": 1,
  "bundle_id": "instaham-ml-2026.08",
  "reference_commit": "<git SHA of the ML/ snapshot exported from>",
  "runtime": { "engine": "onnxruntime", "min_abi_version": 1 },

  "capabilities": {
    "view": {
      "available": true,
      "model": { "path": "view/model.onnx", "sha256": "…",
                 "architecture": "mobilenetv4_conv_small.e2400_r224_in1k", "opset": 17,
                 "input": { "name": "input", "layout": "NCHW", "size": [224,224], "channels": "rgb" } },
      "preprocessing": { "exif": "expect_normalized", "resize_shorter_side": 255, "center_crop": 224,
                         "scale": 0.00392156862745098,
                         "mean": [0.485,0.456,0.406], "std": [0.229,0.224,0.225], "interpolation": "bilinear" },
      "class_map": { "path": "view/classes.json", "sha256": "…" },
      "protocol_version": "view_suitability_v1",
      "expected_labels": ["dorsal_valid","health_only","reject"]
    },

    "health": {
      "available": true,
      "model": { "path": "health/model.onnx", "sha256": "…", "architecture": "ghostnetv3_100", "opset": 17,
                 "input": { "name": "input", "layout": "NCHW", "size": [224,224], "channels": "rgb" } },
      "preprocessing": { "exif": "expect_normalized", "resize_shorter_side": 255, "center_crop": 224,
                         "scale": 0.00392156862745098,
                         "mean": [0.485,0.456,0.406], "std": [0.229,0.224,0.225], "interpolation": "bilinear" },
      "class_map": { "path": "health/classes.json", "sha256": "…" },
      "protocol_version": "health_cvsafe_v3"
    },

    "segmentation": {
      "available": false,
      "unavailable_reason": "yolo_export_pending",
      "model": { "path": "segmentation/yolo.onnx", "sha256": "…",
                 "architecture": "yolo11s-seg-ldconv-acmix", "opset": 17,
                 "input": { "name": "images", "layout": "NCHW", "size": [640,640], "channels": "rgb" },
                 "letterbox": { "color": [114,114,114], "stride": 32, "scaleup": false } },
      "postprocess": { "conf": 0.25, "iou": 0.7, "single_largest_instance": true,
                       "mask_protocol": "original_coordinate_polygon_v1" },
      "class_map": { "path": "segmentation/classes.json", "sha256": "…" },
      "export_mode": "onnx_native",
      "protocol_version": "yolo11s_ldconv_acmix_fixed_seed42"
    },

    "weight": {
      "available": false,
      "unavailable_reason": "body_mask_port_incomplete",
      "regressor": { "format": "onnx", "path": "weight/xgboost.onnx", "sha256": "…",
                     "meta_path": "weight/xgboost.meta.json", "meta_sha256": "…",
                     "feature_order_path": "weight/feature_order.json", "feature_order_sha256": "…",
                     "feature_family": "baseline5", "n_estimators": 300, "objective": "reg:squarederror" },
      "feature_extractor": { "protocol_version": "baseline5_v1",
                             "names": ["RA","LC","BL","BW","E"], "linear_scale": 1.0 },
      "body_mask": { "stage": "provisional",
                     "protocol_version": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26",
                     "ported_functions": ["clean_binary_mask","isolate_dorsal_core_ji_duan",
                                          "extract_five_features","unletterbox_native_mask"] },
      "capture_contract": { "feature_space": "fixed_camera_pixels",
                            "training_camera_height_m": 1.88, "camera_height_is_xgboost_feature": false }
    }
  }
}
```

On load the native layer asserts: `feature_extractor.names == ["RA","LC","BL","BW","E"]`;
`feature_order.json` matches; XGBoost `meta.json.feature_names` matches → else
`INSTAHAM_ML_ERR_CONTRACT`. Labels are always resolved through `classes.json` (name→idx), never by
position in code.

---

## Neural runtime: ONNX Runtime Mobile

One engine covers the timm classifiers, XGBoost (`onnxmltools` → ONNX, same session), and later the
YOLO. Reduced build ≈ 3–6 MB per arm64; op-allowlist emitted by `ML/export/ort_op_config.py` next
to the manifest. Pin **ORT 1.17.x**.

**YOLO custom-op fallback ladder** (`export_yolo.py` docstring + `manifest.segmentation.export_mode`):

1. `onnx_native` — `torch.onnx.export` with `ML/yolo_modifications.py` importable, static 640×640,
   opset 17.
2. `ort_customop` — register `LDConv` / `ACmix` gather as an ORT custom op in `src/onnx_runner.cpp`.
3. `unavailable` — ship view + health + provisional weight; `segmentation.available=false`. A
   manifest flip later, no code churn.

---

## C++ classical-CV port: now vs deferred

### Ported NOW (Slice 4) — 1:1 with OpenCV C++ `core` / `imgproc`

| Python (`ML/`) | OpenCV C++ equivalent |
|---|---|
| `mask_features.extract_five_features` | `contourArea`/`moments` (RA = area/(H*W)), `arcLength` (LC), `minAreaRect` (BL = max side, BW = min side), `fitEllipse` → `E = sqrt(1-(minor/major)^2)`; replicate the `>=5 points` guard |
| `mask_features.clean_binary_mask`, `_largest_component_fill`, `largest_contour` | `connectedComponentsWithStats`, `findContours`, `morphologyEx` (exact kernel shapes from source) |
| `mask_features.isolate_dorsal_core_ji_duan` (+ `_rolling_median`, `_odd_window`, `ji_duan_adaptive_kernel_sizes`) | double `morphologyEx(MORPH_OPEN)` + small median filter |
| `yolo_inference._unletterbox_native_mask`, `_polygon_mask_in_original_coordinates` | `fillPoly` + crop arithmetic; `mask_protocol = "original_coordinate_polygon_v1"`; one-pixel odd-padding handling |

Golden-tested against `ML/parity/run_reference.py` on fixture masks at **±0.5 % relative**.

### DEFERRED to Phase 2 — behind `weight.available = false`

| Python | Gap | Phase-2 fill |
|---|---|---|
| `body_mask.isolate_body_only_mask` (10,701 lines, ~90 helpers, `_v9/_v14/_v26` head-fit) | no OpenCV equivalent | direct port, helper-by-helper, each with a golden fixture |
| `scipy.ndimage.gaussian_filter1d` | — | separable 1-D Gaussian, reflect padding |
| `scipy.signal.find_peaks` | — | port prominence/width/distance logic |
| `skimage.morphology.skeletonize` | — | Zhang-Suen (skimage's 2-D default) |
| `extended_mask_features.extract_chen16_features` | partial | only if a chen16 model is selected |

`body_mask_stub.cpp` returns `ERR_UNAVAILABLE` while the flag is false; `weight_pipeline.cpp` reads
`body_mask.stage` and calls the stub or (Phase 2) the real port.

---

## Existing files modified (pattern-level)

| File | Change |
|---|---|
| `lib/main.dart` | after `ensureInitialized()`: `await MlRuntime.instance.init(await getApplicationSupportDirectory());` in try/catch — init failure logs and the app still runs. |
| `lib/services/ml/weight_regression_service.dart` | **delete**; replace with `weight_pipeline_service.dart`: `abstract interface class IWeightPipelineService { Future<void> loadModel(); Future<WeightResultEntity> predictFromImage(String imagePath); }`. |
| `lib/features/inference_pipeline/domain/use_cases/run_inference_pipeline_use_case.dart` | (a) 3-way view branch: `reject` → stop; `health_only` → health only, `weight: null`; `dorsal_valid` → both. (b) delete the hardcoded `WeightFeatures(ra: 0.21, …)` placeholder + the `segment → eligibility → computeScale → predict` sequence. (c) weight branch = `await weightPipelineService.predictFromImage(input.imagePath)` in its own try/catch (health untouched on failure — `AGENTS.md` rule 4). (d) build `SegmentationResultEntity` from the weight result's `qc` + `segmentation_confidence`. (e) keep `WeightEligibilityChecker` and `ComputeScaleUseCase` for `cmPerPixel` **display only** (`camera_height_is_xgboost_feature == false`). (f) surface `capture_contract`. |
| `lib/features/weight_estimation/domain/entities/weight_result_entity.dart` | add `final CaptureContract? captureContract;` + `capture_contract` in `toJson`/`fromJson`. |
| `lib/features/results/presentation/screens/results_screen.dart` + weight card | render a "Research / fixed-camera (1.88 m) — provisional" badge when `captureContract.featureSpace == 'fixed_camera_pixels'`; render "Weight unavailable — model not finalized" when the failure reason indicates unavailable. Never display invented values. |
| `test/helpers/mock_ml_services.dart` | replace `MockWeightRegressionService` with `MockWeightPipelineService`; add a `health_only` preset to `MockViewModelService`. |
| `test/features/inference_pipeline/run_inference_pipeline_use_case_test.dart` | update ctor param name; add a `health_only` routing test; drive weight failure via `MockWeightPipelineService`. |
| `test/parity/parity_test.dart` | un-skip view + health + feature-extraction; load `test/fixtures/parity/expected.json`; run concrete impls against a **test manifest**; assert view/health prob ≤ 0.01, features ±0.5 % rel. Weight e2e stays skipped until Phase 2. |
| `pubspec.yaml` | add `ffi: ^2.1`, `crypto: ^3.0`, `instaham_ml_ffi: { path: packages/instaham_ml_ffi }`; dev dep `ffigen: ^13`; uncomment `assets:` + add `- assets/ml/` (exclude the large `segmentation/yolo.onnx` → Play Asset Delivery). |
| `.gitignore` | add `!assets/ml/**/*.onnx` (or adopt Git LFS for `assets/ml/**`). |
| `android/app/build.gradle.kts` | `defaultConfig { ndk { abiFilters += listOf("arm64-v8a", "x86_64") } }`; `packagingOptions { jniLibs { pickFirsts += "**/libc++_shared.so" } }`. |
| `ios/Podfile` | picks up the podspec; bump `platform :ios, '13.0'` (ORT min). |

The 3 unchanged interfaces and their inline result types stay as-is — only `impl/` classes are
added.

---

## Ordering — independently shippable vertical slices

| Slice | Contents | User-visible outcome | Depends on |
|---|---|---|---|
| **0 — Toolchain skeleton** | `packages/instaham_ml_ffi` created; `instaham_ml.h` + stub `.cpp` (all entrypoints return `ERR_UNAVAILABLE`); ffigen wired; `MlFfiLoader`; native builds green on Android + iOS; smoke test `instaham_ml_abi_version() == 1`. | none (proves toolchain) | — |
| **1 — Export + manifest** | `ML/export/*`; produce `assets/ml/{view,health,weight}` + assembled `manifest.json`; `.gitignore`/LFS; CI `build_manifest --check`. | none | — |
| **2 — View classifier E2E** | native `classifier.cpp` + `onnx_runner.cpp` + `manifest.cpp` + `context.cpp`; `instaham_ml_classify_view_json`; `MlRuntime` singleton + inference isolate; `ViewModelServiceImpl`; asset copy-on-first-launch + sha256 verify; `MlRuntime.init()` in `main.dart`; un-skip view parity. | real view classification on device | 0, 1 |
| **3 — Health classifier + `health_only`** | `instaham_ml_classify_health_json`; `HealthModelServiceImpl` (reuses `classifier.cpp`, arch from manifest); re-add `health_only` branch; un-skip health parity. | real health assessment; `health_only` photos route correctly | 2 |
| **4 — XGBoost + provisional feature path** | `xgboost_runner.cpp`; `cv/mask_cleanup` + `cv/five_features` + `cv/dorsal_core` + `cv/letterbox`; `instaham_ml_extract_features_provisional_json`; `instaham_ml_predict_weight_json` (returns `unavailable` per flag); `IWeightPipelineService` + impl; `CaptureContract` entity + field; swap use case; `SegmentationServiceImpl` from qc; native golden tests for five-features vs Python. | weight card shows "provisional / fixed-camera" badge; features computed natively | 3 |
| **5 — YOLO segmentation** | `export_yolo.py`; native YOLO runner + letterbox + mask rasterization; feed real mask into the provisional feature path; flip `segmentation.available=true`. If LDConv/ACmix export fails → `export_mode: "unavailable"`, documented fallback, weight stays provisional. | real masks; provisional weight from real segmentation | 4 |
| **6 — Phase 2 (outline only, NOT this iteration)** | bit-accurate `body_mask.py` port + `gaussian_filter1d` + `find_peaks` + `skeletonize`; flip `weight.body_mask.stage="exact"` + `weight.available=true`; full section-14 parity gate; un-skip `functional_scenarios` + `device_benchmarks`. | validated weight estimation | 5 + frozen models |

### DI & threading (locked)

- **DI: plain top-level singleton `MlRuntime.instance`**, initialized in `main.dart` — not an
  InheritedWidget. Services stay constructor-injected at the interface level, so
  `test/helpers/mock_ml_services.dart` keeps working and `MlRuntime` never appears in use-case
  tests.
- **Threading: one long-lived inference isolate** spawned in `MlRuntime.init()`. It opens the
  `DynamicLibrary`, calls `instaham_ml_create`, holds the context pointer; the main isolate sends
  `{op, path}` over a `SendPort`. `Isolate.run`-per-call is rejected — it re-creates the ORT
  session per call.

---

## Verification

**Native (`ctest`, Slice 2+):**

- `test_manifest` — schema-version accept/reject; hash mismatch → `ERR_HASH_MISMATCH`;
  `available:false` → `ERR_UNAVAILABLE`; permuted `feature_order.json` → `ERR_CONTRACT`.
- `test_classifier_golden` — ONNX logits vs committed reference logits < 1e-3; permuted
  `classes.json` → label names follow the map (no positional hardcoding).
- `test_five_features` — vs `ML/parity/run_reference.py` fixture output, ±0.5 % relative.
- `test_letterbox` — mask unletterbox round-trip IoU ≥ 0.99 on synthetic polygons.

**Python:**

- `python -m ML.export.build_manifest --check` — deterministic re-export, stable sha256.
- `python -m ML.parity.run_reference --fixtures test/fixtures/parity --out test/fixtures/parity/expected.json`.

**Flutter (`AGENTS.md` validation order):**

1. `dart format` on changed files.
2. `flutter analyze`.
3. `flutter test test/features/inference_pipeline/run_inference_pipeline_use_case_test.dart`.
4. `flutter test test/parity/parity_test.dart` — view/health prob ≤ 0.01, features ±0.5 % rel.
5. `flutter test` full suite.
6. Manual device smoke — APK size delta recorded; first-launch asset copy + sha256 verify.

**`AGENTS.md`-specific gates:**

- EXIF: a rotated-EXIF fixture must yield identical output to its pre-rotated twin.
- XGBoost feature order asserted in native (`ERR_CONTRACT` otherwise) + existing
  `test/features/weight_estimation/weight_features_order_test.dart` retained.
- Weight-branch-failure test proves `health` is untouched.

---

## Section 13 — internal result contract (unchanged from requirements doc)

The `instaham_ml_predict_weight_json` envelope mirrors `weight_runtime.py predict()`:

```json
{
  "status": "ok",
  "estimated_kg": 82.4,
  "segmentation_confidence": 0.94,
  "feature_family": "baseline5",
  "feature_order": ["RA","LC","BL","BW","E"],
  "features": { "RA": 0.21, "LC": 246.8, "BL": 121.3, "BW": 44.1, "E": 0.87 },
  "qc": { "pair_valid": true, "head_removal_applied": true, "...": "..." },
  "protocols": { "mask_coordinate_protocol": "original_coordinate_polygon_v1", "...": "..." },
  "capture_contract": {
    "feature_space": "fixed_camera_pixels",
    "training_camera_height_m": 1.88,
    "camera_height_is_xgboost_feature": false
  },
  "artifacts": { "xgboost_model": "...", "feature_order": "...", "yolo_checkpoint": "..." }
}
```

When `weight.available == false`:

```json
{ "status": "unavailable", "reason": "body_mask_port_incomplete",
  "capture_contract": { "feature_space": "fixed_camera_pixels", "training_camera_height_m": 1.88 } }
```

---

## Section 14 — parity tolerances (gate before any weight release, Phase 2)

| Output | Tolerance |
|---|---|
| View label (top-1) | exact match |
| View probability vector | ≤ 0.005 per class |
| Health label (top-1) | exact match |
| Health probability vector | ≤ 0.01 per class |
| YOLO selected mask | IoU ≥ 0.95 vs reference |
| Body-mask QC fields (`pair_valid`, `head_removal_applied`) | exact match |
| Feature vector (RA, LC, BL, BW, E) | ≤ 1 % relative error |
| XGBoost `estimated_kg` | ≤ 0.1 kg absolute |

Test the exact ORT / opencv-mobile builds that will ship.

---

## Plan rating: 7 / 10

### Pros

- Stable C ABI + manifest seam: the 10k-line `body_mask.py` port becomes an isolated Phase-2 module
  plus a one-line manifest flip — no ABI, Dart, or build churn.
- Single ONNX Runtime engine for classifiers + XGBoost + (later) YOLO → smallest native footprint,
  zero Python shipped, directly serving the "save space / speed up" goal.
- Export toolchain in `ML/export/` never touches the frozen reference `.py`; an unfinalized
  checkpoint becomes a re-run, not a re-port.
- Phased slices each ship a real capability (view → health → provisional weight → real masks)
  without waiting on frozen models.
- Classical-CV parity is testable now against the real Python via fixture masks, at tolerances
  already committed in the repo.
- The FFI plugin package encapsulates all Android/iOS build glue → minimal edits to the app's
  platform folders, matching `AGENTS.md`.
- Every `AGENTS.md` inference rule maps to a checkable point (class-map from JSON, feature order
  asserted in native, EXIF normalised once, weight/health independence preserved, scale
  display-only per the capture contract).

### Cons

- LDConv/ACmix ONNX export is genuinely uncertain; may force an ORT custom-op detour or leave
  segmentation/weight unavailable longer than hoped.
- Introduces a C++/CMake/NDK/ORT/opencv-mobile toolchain to a codebase with zero native code today —
  real ramp-up and CI cost.
- APK size still grows meaningfully (ORT reduced build + opencv-mobile + models ≈ 15–30 MB); the
  40 MB YOLO needs Play Asset Delivery, with no iOS equivalent story yet.
- Two feature-extraction paths (provisional now, exact later) can diverge; the parity harness must
  cover both permanently.
- iOS ORT + opencv build and codesigning is a second platform surface, largely unvalidated until
  attempted.
- Phase 2's `find_peaks` / `gaussian_filter1d` / `skeletonize` bit-exactness is still the core risk —
  this plan defers it cleanly but does not shrink it.
- The manifest becomes a critical single point of failure needing its own schema-version discipline
  and tests.
