---
name: content_modular_architecture
description: >
  Defines the Content Modular Architecture (CMA) for the INSTAHAM Flutter app.
  Triggers when implementing any feature, adding a new screen, creating a new
  service, or structuring lib/ folders. Use this to ensure consistent module
  boundaries, layering, naming conventions, and dependency rules across the project.
---

# Content Modular Architecture — INSTAHAM Flutter

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
│       ├── view_model_service.dart
│       ├── health_model_service.dart
│       ├── segmentation_service.dart
│       └── weight_regression_service.dart
│
└── features/                     # Self-contained feature modules
    ├── capture/                  # Camera/gallery image intake
    ├── inference_pipeline/       # Orchestrates the full image→result pipeline
    ├── view_suitability/         # dorsal_valid / health_only / reject routing
    ├── health_assessment/        # Health classification + uncertainty handling
    ├── segmentation/             # YOLO mask extraction + eligibility checks
    ├── weight_estimation/        # Reference UI, feature extraction, XGBoost
    └── results/                  # Combined results display
```

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
- Corrects EXIF orientation before any downstream use.
- Outputs a validated `CapturedImageEntity` (path + metadata).

### `inference_pipeline/`
- The **single orchestrator**. It wires view → health → segmentation → weight in sequence.
- Calls use cases from each feature module in order.
- Produces a `PipelineResultEntity` matching the result schema in Section 13 of the requirements.

### `view_suitability/`
- Runs the MobileNetV4 view model.
- Returns one of: `dorsal_valid`, `health_only`, `reject`.
- Reads class mapping from `classes.json` — never hardcodes indices.
- Routes the pipeline based on confidence thresholds from `thresholds.json`.

### `health_assessment/`
- Runs the health classifier (MobileNetV4-Conv-Small / ShuffleNetV2 / GhostNetV3).
- Returns `HealthResultEntity` with `className`, `confidence`, and `uncertain` flag.
- Displays the required disclaimer: *"This is not a veterinary diagnosis."*

### `segmentation/`
- Runs the YOLO model at 640×640 with letterboxing.
- Maps the mask back to original image coordinates.
- Runs all 9 weight-eligibility checks. If **any** fail → sets `eligible = false` with a specific `failureReason`.

### `weight_estimation/`
- UI for reference object selection and manual endpoint marking.
- Computes `cm_per_pixel` from the reference endpoints.
- Extracts features in the **fixed order** `[RA, LC, BL, BW, E]`.
- Runs the XGBoost model (physical-centimeter feature space only).
- Uses the mask cleanup logic identical to training.

### `results/`
- Displays the combined `PipelineResultEntity`.
- Shows weight (if eligible) and health classification.
- Handles all blocked, uncertain, and retake states with specific messages.

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

All ML models are loaded and run through `lib/services/ml/`. Features never import ML packages directly.

```dart
// Good — feature use case calls a service interface
final result = await _viewModelService.classify(image);

// Bad — feature directly loads a TFLite model
final interpreter = Interpreter.fromAsset('...');  // ❌
```
