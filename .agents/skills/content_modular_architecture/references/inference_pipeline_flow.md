# Inference Pipeline Flow Reference

The end-to-end flow as actually implemented, from camera shutter to the results cards.

Two things dominate this document and are easy to get wrong:

1. **Orchestration is split across two layers.** Dart sequences the *app* flow (capture →
   routing → persistence); C++ sequences the *model* graph. They are different orchestrators
   with different entry points, and Dart currently calls the per-capability C++ entrypoints
   rather than the single whole-graph one.
2. **The view gate runs at capture time, not at analysis time.** It decides which screen the
   user sees next, so it cannot wait until the results screen.

Source of truth: `lib/features/capture/presentation/screens/capture_screen.dart`,
`lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`,
`packages/instaham_ml_ffi/src/pipeline.cpp`, and `ML/ML_implementation_plan.md` revision 7.

---

## The view model has three labels

`dorsal_valid`, `health_only`, `reject` — read by name from `view/classes.json`, never by
index (`AGENTS.md` rule 1).

The label is always the model's **argmax**. There is no confidence threshold anywhere in the
routing path: the model's recorded metrics were measured under argmax, so overriding it with
an app-invented cutoff would invalidate them. Confidence is displayed, and drives a
*display-only* `uncertain` flag on the health card below `kHealthUncertainBelow` (0.60), but
it never changes a route or a label.

| Label | Weight branch | Health branch | Reference marking |
|---|---|---|---|
| `dorsal_valid` | runs | runs | shown (Reference mode) |
| `health_only` | skipped | runs | skipped |
| `reject` | stopped | stopped | n/a — retake dialog |

---

## Stage A — capture-time routing

```
CaptureScreen._usePhoto()
    │
    ├─ ImageService.processRawBytes()   # EXIF baked in ONCE, here (AGENTS.md rule 5).
    │                                   # No later stage rotates: native expects an
    │                                   # already-normalised RGB image.
    ├─ db.createScan(...)  →  status: captured
    │
    ▼
RunAndPersistPipelineUseCase.resolveViewGate(db, scanId, imagePath)
    │  Runs the view classifier and persists the label as a 'view' PipelineEvent
    │  (status = label, message = confidence). Reused later — the model never runs twice.
    │
    ├── 'reject'      →  status: rejected  →  "Photo not usable" dialog  →  retake
    │
    ├── 'health_only' →  status: analyzing →  push /analysis
    │                    (reference marking skipped: it exists only to scale a weight)
    │
    └── 'dorsal_valid' (or gate failure → null, which routes as dorsal)
          │
          ├─ MeasurementMode.referenceObject → status: reference_review → push /reference-marking
          └─ MeasurementMode.fixedHeight     → status: analyzing        → push /analysis
```

A view-gate *failure* (native throw) falls through to unfiltered routing rather than blocking
the user — `AGENTS.md` rule 4 applied to the gate itself.

### Reference marking (`/reference-marking`, dorsal + Reference mode only)

`ReferenceMarkingScreen` collects a reference object and two endpoints, computes
`cm_per_pixel = lengthCm / originalPixelLength`, and persists it. Endpoint coordinates are
mapped to the **displayed image rectangle including `BoxFit` letterboxing**, not raw widget
bounds (`AGENTS.md` rule 9), then converted to original-image pixels.

> **Currently collected but not consumed by the regressor.** The shipped XGBoost model's
> capture contract is `feature_space: "fixed_camera_pixels"` with
> `camera_height_is_xgboost_feature: false`, and the C++ feature stage is called with
> `linear_scale = 1.0`. The reference is stored for provenance and for the eventual
> cm-space model; it does **not** currently scale the features. Do not "fix" the C++ to
> multiply by `cm_per_pixel` — that would silently change the feature space the model was
> trained in.

---

## Stage B — analysis (`/analysis` → `ResultsScreen`)

`ResultsScreen` lazily runs the pipeline the first time a scan has an image but no stored
health result, then reloads the bundle and renders. A retake, or a scan with no image, just
renders stored state.

```
RunAndPersistPipelineUseCase.execute(db, scanId, imagePath)
    │
    ├─ resolveViewGate()            # reads the persisted capture-time event; no re-run
    │
    ├─ 'reject' → health + weight saved ineligible, status: rejected, return
    │
    ├─ HealthModelService.classify()          → instaham_ml_classify_health_json
    │     saved ALWAYS, independent of weight (AGENTS.md rule 4)
    │     `uncertain` = confidence < 0.60 (display flag only, label stays argmax)
    │
    ├─ if dorsal: SegmentationService.segment() → instaham_ml_segment_json
    │     persists a 'segmentation' PipelineEvent with pig_count + confidence.
    │     Skipped entirely for health_only — the ~40 MB YOLO pass serves weight only.
    │
    ├─ weight branch
    │     ├─ not dorsal        → ineligible, "skipped: not a dorsal view"
    │     ├─ pig_count == 0    → ineligible, "no pig detected"
    │     └─ else WeightModelService.predict() → instaham_ml_predict_weight_json
    │             ├─ eligible  → valueKg + RA/LC/BL/BW/E persisted
    │             └─ otherwise → ineligible with the native `reason`
    │
    └─ status: completed if the weight branch produced a number, else blocked
```

Never throws. A native/ORT failure is caught and recorded as blocked results, because
surfacing an exception to the UI would leave the user with no explanation.

---

## Stage C — the C++ model graph

Dart calls the **per-capability** entrypoints above. The library also exports a single
whole-graph call, `instaham_ml_run_pipeline_json` (`pipeline.cpp`), which returns the
complete section-9 envelope in one FFI hop.

> **Not currently bound in Dart.** `instaham_ml_bindings_generated.dart` exposes
> `classifyView`, `classifyHealth`, `segment`, `predictWeight`, and
> `extractFeaturesProvisional`, but not `runPipeline`. Stage ordering therefore still lives
> in Dart. Moving to the single call is the intended direction — it removes the duplicated
> segmentation pass that `segment()` and `predictWeight()` currently each perform.

```
instaham_ml_run_pipeline_json
    │
    ├─ (0) view classifier ────────────── reject → stop, envelope closed
    │
    ├─ (1) segmentation      stages/segmentation.cpp     YOLO11s-seg @640, letterboxed
    ├─ (2) construction      stages/construction.cpp     32 mask coefficients × 160×160
    │                                                    prototype → unletterbox → mask in
    │                                                    ORIGINAL image coordinates
    │
    ├─ health classifier ─── runs on BOTH branches, degrades its input rather than failing
    │
    ├─ (3) cutter            stages/cutter.cpp           IDENTITY DUMMY — see below
    ├─ (4) feature calc      stages/feature_calculation.cpp  → RA, LC, BL, BW, E
    └─ (5) weight prediction stages/weight_prediction.cpp    → XGBoost ONNX [1,5] → [1]
```

Feature order is fixed at `[RA, LC, BL, BW, E]` (`AGENTS.md` rule 2) and re-asserted against
the manifest at load time in `manifest.cpp` — a mismatch is `INSTAHAM_ML_ERR_CONTRACT`, not a
silent reorder.

### The cutter is a permanent identity stub

Stage 3 returns the input mask unchanged (`ML_implementation_plan.md` revision 7, §3.4). The
real `ji_duan` head/neck removal is ~9,900 lines of SciPy/scikit-image geometry that was
neither ported to C++ nor shipped as on-device Python.

Consequences that must propagate, never be hidden:

- `head_removal_applied` is always `false`; `protocol_implemented` is always `false`.
- Features are measured on an **uncut** mask, so they include the head and neck.
- Any weight derived from them **overestimates** the research protocol's number.

### Weight availability

`weight.available` is `false` in every manifest built for shipping, so `predictWeight`
returns `ERR_UNAVAILABLE` with `reason: "cutter_identity_stub"` and the card reads
"Unavailable". That is the stated contract, not a bug (`AGENTS.md` rule 8).

Building with `python -m ML.export.export_xgboost --enable-for-testing` flips
`weight.available` to `true`, and the full C++ chain then returns a real kg number. It is a
**developer-only override for verifying the native stage end-to-end** — the value it produces
is genuine inference, but biased high by the uncut mask, and every envelope carries a `note`
saying so. Never ship a manifest built with that flag.

---

## Result states the UI must distinguish

Collapsing these into one "Unavailable" is a regression that has already happened twice
(`TASKS.md` Cause B/C); each card splits them deliberately.

| Card | State | Meaning |
|---|---|---|
| View | `dorsal_valid` / `health_only` / `reject` | the routing decision itself, shown as its own card |
| Health | ok | label + confidence; `uncertain` badge below 0.60 |
| Health | Unavailable | classifier failed — never blocked by the weight branch |
| Weight | **Skipped** | routing outcome: not a dorsal photo. Not a failure. |
| Weight | **Unavailable** | genuinely no number: no pig detected, segmentation failed, or the cutter stub gates it |
| Weight | ok | a kg value — only reachable under the test override today |

Never display an invented score, and never show a completed state for a branch that did not
produce one.
