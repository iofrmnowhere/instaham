---
name: content_modular_architecture
description: >
  Use for new INSTAHAM feature modules, architecture changes, cross-feature refactors,
  or decisions about lib/ boundaries and layering. Do not use for isolated UI styling,
  copy edits, a single widget bug, a focused database query, or routine generated-code updates.
---

# Content Modular Architecture — INSTAHAM Flutter

## When not to activate this skill

Do not load this architecture workflow for:

- Color, spacing, typography, icon, or copy-only changes.
- A bug confined to one existing widget or method.
- A focused Drift query that does not change schema or layering.
- Generated-code regeneration.
- Test-only changes that do not alter architecture.

For those tasks, follow the root `AGENTS.md` and inspect only the directly relevant files.

---

## Overview

Every significant capability in INSTAHAM is a **self-contained feature module** under `lib/features/`. Modules own their data, domain logic, and presentation — nothing leaks across module boundaries without going through a shared `lib/core/` or `lib/services/` layer.

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

The native side lives outside `lib/` entirely, in `packages/instaham_ml_ffi/`
(`libinstaham_ml.so`: ONNX Runtime + opencv-mobile + the five pipeline stages). See
`references/inference_pipeline_flow.md` for how the Dart and C++ halves divide the work.

---

## Feature Module Layout

Each module under `lib/features/<feature>/` follows the three-layer pattern:

```
features/<feature>/
├── data/
│   ├── models/          # Raw data models, JSON parsing (e.g. from ML output)
│   └── repositories/    # Concrete repository implementations
│
├── domain/
│   ├── entities/        # Pure Dart business objects (no Flutter/framework deps)
│   ├── repositories/    # Abstract repository interfaces
│   └── use_cases/       # Single-responsibility use case classes
│
└── presentation/
    ├── screens/         # Full-page screen widgets (one per route)
    ├── widgets/         # Reusable widgets scoped to this feature
    └── bloc/ (or notifier/)  # State management (Bloc or Riverpod Notifier)
```

### Naming Conventions

| Layer | Naming Pattern | Example |
|---|---|---|
| Entity | `<Name>Entity` | `PigMaskEntity` |
| Repository interface | `I<Name>Repository` | `IWeightRegressionRepository` |
| Repository impl | `<Name>RepositoryImpl` | `WeightRegressionRepositoryImpl` |
| Use case | `<Verb><Noun>UseCase` | `ExtractWeightFeaturesUseCase` |
| Screen widget | `<Name>Screen` | `ReferenceMarkingScreen` |
| Bloc/Notifier | `<Name>Bloc` / `<Name>Notifier` | `WeightEstimationBloc` |
| State | `<Name>State` | `WeightEstimationState` |

---

## Feature Modules — Responsibilities

### `capture/`
- Accesses camera and gallery via `image_picker` or `camera` package.
- Bakes EXIF orientation **once**, here (`AGENTS.md` rule 5). No later stage rotates —
  native code expects an already-normalised RGB image.
- Runs the **view gate at capture time** (`RunAndPersistPipelineUseCase.resolveViewGate`) and
  routes on the result, because the label decides which screen comes next. The label is
  persisted as a `view` `PipelineEvent` so the model never runs a second time.

### `inference_pipeline/`
- The **app-flow orchestrator**: `RunAndPersistPipelineUseCase` sequences view → health →
  segmentation → weight and persists every branch through `AppDatabase`.
- Calls the ML services in `lib/services/ml/`, never a model runtime directly.
- Never throws: a native/ORT failure is recorded as a blocked result, not surfaced as an
  exception, so the user always gets an explanation.
- Sets final scan status: `completed` only when the weight branch produced a number,
  otherwise `blocked` (or `rejected` at the view gate).
- Note the C++ library also has its own whole-graph orchestrator
  (`instaham_ml_run_pipeline_json`), which is **not yet bound in Dart** — stage ordering
  still lives here. See `references/inference_pipeline_flow.md`.

### `view_suitability/`
- Runs the GhostNetV3 view model.
- Returns one of three labels: `dorsal_valid`, `health_only`, `reject`.
- `dorsal_valid` enables both branches; `health_only` runs health and skips weight *and*
  reference marking; `reject` stops with a retake prompt.
- Reads class mapping from `classes.json` — never hardcodes indices (`AGENTS.md` rule 1).
- **Routes on argmax, with no confidence threshold.** The model's recorded metrics were
  measured under argmax; an app-invented cutoff would invalidate them. Do not reintroduce one.

### `health_assessment/`
- Runs the GhostNetV3 health classifier.
- Returns `HealthResultEntity` with `className`, `confidence`, and `uncertain` flag
  (`uncertain` is display-only, below 0.60 — it never changes the label or a route).
- Runs on **both** the `dorsal_valid` and `health_only` branches, and is never blocked by a
  weight-branch failure (`AGENTS.md` rule 4).
- Displays the required disclaimer: *"This is not a veterinary diagnosis."*

### `segmentation/`
- Runs YOLO11s-seg at 640×640 with letterboxing.
- Decodes the 32 mask coefficients against the 160×160 prototype and unletterboxes, so the
  mask lands in **original image coordinates**.
- Serves the weight branch only — skipped entirely for `health_only`, since health runs
  `full_frame` today.

### `weight_estimation/`
- UI for reference object selection and manual endpoint marking. Endpoint coordinates map to
  the displayed image rect **including `BoxFit` letterboxing** (`AGENTS.md` rule 9).
- Computes and persists `cm_per_pixel` from the user-confirmed reference (`AGENTS.md` rule 7).
- **`cm_per_pixel` does not currently scale the features.** The shipped regressor's capture
  contract is `fixed_camera_pixels` and the C++ feature stage runs at `linear_scale = 1.0`.
  The reference is stored for provenance and a future cm-space model. Multiplying features by
  it would silently change the feature space the model was trained in.
- Features are extracted natively in the **fixed order** `[RA, LC, BL, BW, E]`
  (`AGENTS.md` rule 2), re-asserted against the manifest at load time.
- The weight number is gated: see "Weight availability" in
  `references/inference_pipeline_flow.md`.

### `results/`
- Displays the combined scan bundle, and lazily triggers the pipeline the first time a scan
  has an image but no stored health result.
- Keeps **Skipped** (routing outcome) and **Unavailable** (genuinely no number) as distinct
  weight states — collapsing them has regressed twice (`TASKS.md` Cause B/C).
- Never displays an invented score or a completed state for a branch that did not produce one.

### `analytics/`
- Handles querying historical health and weight trends.
- Encapsulates queries in `AnalyticsDao` to isolate from `AppDatabase`.
- Renders `fl_chart` driven UI with independent Weight and Health tabs.

### `records/`
- Manages the local device history of past scans.
- Encapsulates queries in `RecordsDao` and shares core `LocalScanBundle` models.
- Provides list filtering (All, Completed, Needs Review).

---

## Dependency Rules

```
presentation → domain → data
presentation → core
domain → core
data → core
services → core

features/X  ─X→  features/Y    (cross-feature imports are FORBIDDEN)
```

Features communicate only through the `inference_pipeline/` orchestrator or shared entities in `core/`.

---

## Design System Mapping (from UI reference)

| UI Reference (Next.js) | Flutter Equivalent |
|---|---|
| `ScreenContainer` | `AppScaffold` widget in `core/theme/` |
| `HealthStatusLabel` | `HealthStatusCard` widget in `features/results/presentation/widgets/` |
| `StatCard` | `StatCard` widget in `core/theme/widgets/` |
| `Badge` | `StatusBadge` widget in `core/theme/widgets/` |
| `BottomNav` | `AppBottomNav` in `core/router/` |
| `#C2185B` primary | `AppColors.signalPink` in `core/theme/app_colors.dart` |
| IBM Plex Mono | `AppTextStyles.numeric` in `core/theme/app_text_styles.dart` |
| `status-success` / `status-uncertain` / `status-blocked` | `AppColors.success` / `.uncertain` / `.blocked` |

---

## ML Model Integration

Models run natively in `libinstaham_ml.so` (ONNX Runtime + opencv-mobile), reached through a
single `dart:ffi` seam. Features never import an ML package or touch FFI directly.

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

Everything the native layer needs — model paths, sha256, input sizes, mean/std, class-map
paths, feature order, protocol versions, per-capability `available` flags — comes from
`assets/ml/manifest.json`, generated by `ML/export/build_manifest.py` and **never
hand-edited**. Nothing is hardcoded in C++ or Dart (`AGENTS.md` rules 1, 2, 7). A capability
with `available: false` is still a valid, shippable manifest; every call into it returns
`ERR_UNAVAILABLE`.
