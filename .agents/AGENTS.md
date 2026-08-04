# INSTAHAM Workspace Rules

## Critical Rules for Inference & Flow
The following rules are non-negotiable for the INSTAHAM app:

1. **Never hardcode class indices** — always load mapping from the model metadata.
2. **Fixed Feature Order for XGBoost**: You must extract and pass features exactly in this order: `RA, LC, BL, BW, E`.
3. **Weight Eligibility**: Weight estimation requires ALL 9 checks to pass (1 pig, no truncation, no occlusion, valid posture, valid reference, etc.). If any check fails, do not estimate weight.
4. **Independence**: Health assessment and weight estimation are independent branches. A failed weight branch must NEVER block the health assessment if the image is usable.
5. **EXIF Correction**: EXIF orientation must be corrected before passing images to any model.
6. **No Silent Resizing**: Do not silently resize or rotate images after the reference endpoints have been selected by the user.
7. **Reference Scale Only**: The cm/pixel scale must come from the user-marked reference object. Never derive scale from the pig's own body dimensions.
8. **No Forced Predictions**: On any failure, do not show a forced or low-quality prediction. Explicitly show what failed and ask the user for another image.

## Architecture
This project uses a **Content Modular Architecture (CMA)**. Each capability lives in its own self-contained module under `lib/features/<feature>/` (e.g., `capture`, `inference_pipeline`, `segmentation`, `weight_estimation`). 
- Features do not import from other features.
- All ML models are wrapped in interfaces inside `lib/services/ml/`.

## Implementation Plan Guidelines
When creating an implementation plan in this workspace, follow these rigorous guidelines:
1. **Grounded in Source**: Trace plans directly from reference files (e.g., Next.js TSX files, design systems). Document exact props, state machines, icons, and layout specifics rather than guessing.
2. **Structured Phasing**: Break the work down into logical phases (e.g., Phase 0: Dependencies, Phase 1: Core Theme, Phase 2: Shared Widgets, etc.).
3. **Precise File Mapping**: Use `[NEW]`, `[MODIFY]`, and `[DELETE]` tags with exact file paths. Provide highly detailed per-file descriptions of what will be built or changed.
4. **Explicit Module Boundaries Verification**: Include a table verifying that no cross-feature imports are introduced for each modified CMA feature (`lib/features/...`).
5. **Asset & Dependency Tracking**: Explicitly list `pubspec.yaml` changes, document icon stand-ins with mapping tables, and highlight missing or unused assets.
6. **ML Services & Data Flow**: Outline data flow (adhering to Fixed Feature Order). Keep ML runtime decisions abstract behind `lib/services/ml/` interfaces without baking engine logic into the UI.
7. **Verification Plan**: Include concrete steps for automated testing and manual verification, ensuring edge cases (like failed weight checks not blocking health assessments) are explicitly covered.

## Tech Stack
- **Mobile Application**: Flutter & Dart

**Note**: `instaham_ui` exists only as a visual/component reference for porting into Flutter. Never scaffold it as a separate project or runtime.
