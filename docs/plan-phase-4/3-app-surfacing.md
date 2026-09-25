# Phase 3 — persist and show the stage in the app

Status: done

## Goal

Store which stage produced the health result, and make the results screen say so truthfully
when the second pass ran, without presenting it as a confirmed diagnosis.

## Design/Approach

### Persistence, no schema change

`run_and_persist_pipeline_use_case.dart:159-180` already saves the top-level `label` and
`confidence`. After phase 1, those are the final stage's values, so the label and confidence
columns need no change.

Add one value: `preprocessingVersion`, an existing nullable `HealthResults` column that nothing
writes today (`app_database.dart:131`). It gets:

- `cascade_v1:full_frame` when the final answer came from the whole photo,
- `cascade_v1:segmentation_masked` when it came from the second pass,
- left null when the envelope has no `cascade` key (cascade off), so old and new rows can be
  told apart.

The value is read from `envelope['health']['cascade']['final_stage']`, never inferred from the
label. Using an existing column means no `schemaVersion` bump and no migration. If the user
wants the first-stage label stored too, that is a schema change and a separate decision (plan
open question 2).

The `uncertain` flag keeps its current rule (`confidence < kHealthUncertainBelow`, 0.60) and
applies to the final stage's confidence.

### Results screen health card

`results_screen.dart:522-560` (`_healthCard`) keeps its title ("Possible visual indicator") and
value (the final label). Only the message line changes, and only when
`preprocessingVersion == 'cascade_v1:segmentation_masked'`:

> "{confidence} · Flagged on the whole photo, then re-checked on the pig alone. This is a
> possible indicator, not a confirmed diagnosis."

Constraints:

- Never use "confirmed", "verified" or similar words for the second pass.
- If the result is also `uncertain`, keep the existing "Review or retake recommended." advice.
- For results from the whole photo, and for older rows, the card reads exactly as it does today.
- The existing disclaimer at `results_screen.dart:378` stays.

The screen reads the value from the stored `HealthResult` row, not from the live envelope, so
reopening a scan later shows the same wording.

## Steps

- [x] Use case: `run_and_persist_pipeline_use_case.dart` now reads
      `envelope['health']['cascade']['final_stage']` and writes
      `preprocessingVersion: 'cascade_v1:$finalStage'`, or leaves it null when the envelope
      carries no `cascade` key.
- [x] `_healthCard`: the second-pass message line, exactly as designed --
      `preprocessingVersion == 'cascade_v1:segmentation_masked'` triggers "Flagged on the whole
      photo, then re-checked on the pig alone. This is a possible indicator, not a confirmed
      diagnosis.", with the existing "Review or retake recommended." appended when also
      `uncertain`. Every other case (full-frame final stage, or no stored stage at all) renders
      byte-for-byte what it did before this plan.
- [x] Tests:
      - `test/features/inference_pipeline/health_cascade_persistence_test.dart` — the three
        `preprocessingVersion` outcomes (full frame, second pass, no `cascade` key at all),
        using the same stub-pipeline-service pattern as `reference_scale_forwarding_test.dart`.
      - `test/features/results/health_card_cascade_test.dart` — four widget tests: the
        second-pass wording (and that "confirmed" only ever appears negated), the
        also-uncertain case keeping the review/retake line, a full-frame-final result reading
        unchanged, and a row with no stored stage reading unchanged. Needed a taller test
        surface (`tester.view.physicalSize`) -- the health card sits below the photo preview,
        pig-assignment card, view card and weight card, past flutter_test's default surface
        plus cacheExtent, so its own widgets are never built without it; this is a test-harness
        sizing detail, not app behaviour, and is called out in the test's own comment.
- [x] `dart format` on the four changed/added files: no diff on the two production files, the
      persistence test reformatted once (its own line-wrapping), the widget test unchanged.
      `flutter analyze`: clean on every touched file (a stray unused `dart:io` import in the
      widget test was the only new issue, fixed). Targeted `flutter test` on the two new files:
      7/7 passed. Full `flutter test`: 133 passed, 39 skipped (was 126 passed, 39 skipped per
      round 2's own count, i.e. +7 -- exactly this phase's new tests, no regressions).

## Open questions

- Plan open question 2 (show the first-stage label as well) is not done here unless the user
  asks for it.
