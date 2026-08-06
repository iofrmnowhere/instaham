# INSTAHAM Codex Instructions

## Project scope

- The product is the Flutter app in `lib/`.
- `instaham_ui/` is a read-only Next.js visual reference. Do not run, refactor, or add dependencies to it unless the task explicitly targets that folder.
- `.dart_tool/`, `build/`, platform `ephemeral/` folders, and generated files are not sources of product requirements.

## Default working behavior

- Make the smallest coherent change that satisfies the request.
- Inspect only the files needed for the requested slice. Do not inventory the entire repository for routine UI fixes.
- Do not combine unrelated UI, database, ML, navigation, privacy, or backend work unless the request explicitly requires the integration.
- For broad prompts such as “update the UI and add a database,” preserve scope by implementing one clearly defined vertical slice at a time and state what remains.
- Do not rewrite working files merely for formatting, line endings, or style.
- Do not edit generated files manually, including `*.g.dart` and generated plugin registrants.
- Do not modify platform folders unless a dependency or platform capability requires it.

## Validation

Run the narrowest useful checks after editing:

1. `dart format` on changed Dart files.
2. `flutter analyze` for Dart or dependency changes.
3. Targeted `flutter test <path>` for the changed behavior.
4. Run the full test suite only for cross-cutting changes.
5. Run `dart run build_runner build --delete-conflicting-outputs` only when Drift schema/source generation changes.

Report the exact commands run and any checks that could not run. Never claim success without command output.

## Architecture

- Shared infrastructure belongs in `lib/core/` or `lib/services/`.
- Feature code belongs in `lib/features/<feature>/`.
- Features must not import other feature modules directly.
- Prefer presentation → domain/repository → data access. Avoid adding new direct database calls inside widgets.
- Keep UI widgets independent of HTTP clients and ML runtime packages.
- Use the `content_modular_architecture` skill only for new modules, architecture changes, or cross-feature refactors—not for isolated styling or copy changes.

## Database rules

- Drift/SQLite is the local source of truth.
- Schema changes require a `schemaVersion` increment, an explicit migration, regenerated Drift output, and a migration test.
- Keep database queries out of large screen widgets; add focused DAOs/repositories when extending persistence.
- Preserve stable local IDs and separate remote IDs.
- Do not enqueue, upload, or retain research images without explicit consent.
- Do not create speculative backend tables or sync behavior unless requested by an acceptance criterion.

## Critical inference and calibration rules

1. Never hardcode model class indices; load mappings from model metadata.
2. Pass XGBoost features exactly as `RA, LC, BL, BW, E`.
3. Weight estimation requires all eligibility checks to pass.
4. Weight and health branches are independent; a failed weight branch must not block health assessment.
5. Correct EXIF orientation before any model receives the image.
6. Do not resize or rotate after the user marks reference endpoints unless coordinates are transformed exactly.
7. Derive cm/pixel only from the user-confirmed reference object.
8. Never force a prediction after a failed quality or eligibility check.
9. Reference-point coordinates must map to the actual displayed image rectangle, including `BoxFit` letterboxing—not the whole widget bounds.

## UI source of truth

- Use `.agents/skills/content_modular_architecture/references/design_system.md` for established navigation and interaction contracts.
- Port only the explicitly requested screen or component from `instaham_ui/`.
- Preserve accessibility: semantic labels, readable contrast, scalable text, and touch targets of at least 44×44 logical pixels.
- Never display invented model scores, predictions, or completed states.

## Task completion summary

Include:

- Files changed.
- Behavior implemented.
- Validation run.
- Known limitations or intentionally deferred work.
