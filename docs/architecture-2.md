# Architecture, part 2 — Flutter module layout

Continues [architecture.md](architecture.md), which covers the app end to end and the native
boundary. This part covers only the shape of `lib/`: module boundaries, layering, naming, and
the single FFI seam.

## Directory shape

```
lib/
├── main.dart                     # App entry point, bootstraps DI & router
├── app.dart                      # MaterialApp / root widget
│
├── core/                         # App-wide shared code (no feature logic here)
│   ├── theme/                    # ThemeData, color tokens, text styles
│   ├── router/                   # go_router routes, route constants
│   ├── errors/                   # AppFailure sealed class, error handling
│   └── utils/                    # Generic helpers (EXIF fix, image utils, etc.)
│
├── services/                     # Infrastructure / side-effect services
│   └── ml/                       # ML model loaders and runners
│       ├── ml_runtime.dart       # THE dart:ffi seam — stages assets, owns the one
│       │                         # InstahamMlContext. Nothing else in lib/ touches FFI.
│       ├── pipeline_service.dart # Whole-graph call, used by the pipeline use case
│       ├── view_model_service.dart
│       ├── health_model_service.dart
│       ├── segmentation_service.dart
│       └── weight_model_service.dart
│
└── features/                     # Self-contained feature modules
    ├── capture/                  # Camera/gallery intake + capture-time view gate
    ├── inference_pipeline/       # Orchestrates the full image→result pipeline
    ├── view_suitability/         # dorsal_valid / health_only / reject routing
    ├── health_assessment/        # Health classification + uncertainty handling
    ├── segmentation/             # YOLO mask extraction + mask construction
    ├── weight_estimation/        # Reference marking UI, features, XGBoost
    ├── results/                  # Combined results display
    ├── analytics/                # Historical charts, graphs, and aggregate statistics
    └── records/                  # Saved past scans and local device history
```

The native side lives outside `lib/` entirely, in `packages/instaham_ml_ffi/`.

## Feature module layout

Each module under `lib/features/<feature>/` follows the same three layers:

```
features/<feature>/
├── data/          models/ (raw models, JSON parsing) + repositories/ (implementations)
├── domain/        entities/ (pure Dart) + repositories/ (interfaces) + use_cases/
└── presentation/  screens/ (one per route) + widgets/ + bloc/ (or notifier/)
```

| Layer | Naming pattern | Example |
|---|---|---|
| Entity | `<Name>Entity` | `PigMaskEntity` |
| Repository interface | `I<Name>Repository` | `IWeightRegressionRepository` |
| Repository impl | `<Name>RepositoryImpl` | `WeightRegressionRepositoryImpl` |
| Use case | `<Verb><Noun>UseCase` | `ExtractWeightFeaturesUseCase` |
| Screen widget | `<Name>Screen` | `ReferenceMarkingScreen` |
| Bloc/Notifier | `<Name>Bloc` / `<Name>Notifier` | `WeightEstimationBloc` |
| State | `<Name>State` | `WeightEstimationState` |

## Module responsibilities

- **`capture/`** — camera and gallery intake. Bakes EXIF orientation once, here. Runs the
  view gate at capture time and routes on the result; see [app-flow.md](app-flow.md).
- **`inference_pipeline/`** — the app-flow orchestrator. `RunAndPersistPipelineUseCase`
  makes one whole-graph native call through `IPipelineService` and persists every branch
  through `AppDatabase`. Never throws: a native or ORT failure is recorded as a blocked
  result, not raised. Sets `completed` only when the weight branch produced a number.
- **`view_suitability/`** — the GhostNetV3 view model. Three labels, read from
  `classes.json`, routed on argmax with no confidence threshold.
- **`health_assessment/`** — the GhostNetV3 health classifier. Returns
  `HealthResultEntity` with an `uncertain` flag that is display-only below 0.60. Runs on
  both the `dorsal_valid` and `health_only` branches and is never blocked by a weight
  failure. Shows the disclaimer: *"This is not a veterinary diagnosis."*
- **`segmentation/`** — YOLO11s-seg mask extraction, on a scale-aware canvas when a
  confirmed reference exists; details in [pipeline/segmentation.md](pipeline/segmentation.md).
  Serves the weight branch only.
- **`weight_estimation/`** — reference object selection and endpoint marking, mapped to the
  displayed image rect including `BoxFit` letterboxing. Computes and persists
  `cm_per_pixel` from the user-confirmed reference. Features are extracted natively in the
  fixed order `[RA, LC, BL, BW, E]`.
- **`results/`** — the combined scan bundle, and the lazy first-run trigger. Keeps
  **Skipped** (routing outcome) and **Unavailable** (no number) distinct.
- **`analytics/`** — historical trends through `AnalyticsDao`, rendered with `fl_chart`.
- **`records/`** — local scan history through `RecordsDao`, with All / Completed / Needs
  Review filtering.

## Dependency rules

```
presentation → domain → data
presentation → core
domain → core
data → core
services → core

features/X  ─X→  features/Y    (cross-feature imports are FORBIDDEN)
```

Features communicate only through `inference_pipeline/` or shared entities in `core/`.

## The FFI seam

Models run natively in `libinstaham_ml.so`, reached through exactly one `dart:ffi` seam.
Features never import an ML package or touch FFI directly.

```
feature use case  →  lib/services/ml/<capability>_service.dart
                  →  lib/services/ml/ml_runtime.dart      (the ONLY dart:ffi caller)
                  →  package:instaham_ml_ffi bindings
                  →  libinstaham_ml.so
```

```dart
// Good — feature use case calls a service interface
final result = await _viewModelService.classify(image);

// Bad — feature reaches for the runtime, the bindings, or dart:ffi itself
final runtime = await MlRuntime.instance();          // ❌ services/ml only
DynamicLibrary.open('libinstaham_ml.so');            // ❌ ml_runtime.dart only
```

Everything the native layer needs comes from `assets/ml/manifest.json`, normally generated by
`ML/export/build_manifest.py`. Hand edits are the exception, not the rule, and are allowed only
when the exporter cannot be run and the values are pinned constants copied verbatim — the F50
restoration of `capabilities.segmentation.input_scale` is the one on record
(`docs/fix-phase-2/1.1-manifest-input-scale-regression.md`). Prefer a re-export; if you must
hand-edit, record why.

`build_manifest` refuses a rebuild that drops any key the existing manifest had, unless passed
`--allow-key-removal`. That guard exists because the fragments it assembles live in gitignored
`build/ml_export/` and can be arbitrarily stale, so regenerating one capability could silently
revert another — which is exactly how F50 happened. Note that `--check` does **not** cover this:
it re-hashes the `model`/`regressor`/`class_map` files only, and a vanished block changes no
file hash. See [ffi-bridge.md](ffi-bridge.md) for the ABI conventions.

## Design system mapping

The UI contract — tokens, widget mapping, screen structure — is in
[design-system.md](design-system.md).
