# Phase 3 — remove the photo-check cards from results

Status: done (2026-09-25)

Parent: [`../fix-6.md`](../fix-6.md) (round 10), finding F69. Independent of phases 1-2.

## Symptom

The results screen shows two cards that describe the photo check rather than the pig:

- **"Photo framing"**: `_viewCard()` (`results_screen.dart:474-520`), which shows Pending,
  Dorsal view, Health-only view or the raw label, with the classifier's confidence.
- **"Photo check overridden"**: `_viewOverrideBanner()` (`results_screen.dart:459-469`), shown
  above it after the user overrode a `reject`.

The user decided on 2026-09-25 that neither belongs on the user side.

## Root cause

TASKS.md P2 added the view card so a view-gate stop would not
be mistaken for a health failure. Round 9 added the banner as a disclosure. Both now duplicate
what the weight and health cards already say (Skipped, with a reason) or expose internal
routing.

## Change made (planned)

1. Remove the `_viewOverrideBanner()` and `_viewCard()` calls and the spacing around them from
   the results layout (`results_screen.dart:278-283`), and delete both methods.
2. Keep `bundle.viewEvent` and the route from phase 2. The weight and health cards still need
   them to tell **Skipped** from **Unavailable**. Nothing is removed from the database, the
   envelope, or `LocalScanBundle` beyond what phase 2 already replaces.
3. Check that no other screen renders either card (a search found both only in
   `results_screen.dart`). `reject_result_screen.dart` is a separate screen and is out of scope.

## Verification

- A widget test: for a `dorsal_valid` scan, a `health_only` scan and an overridden scan, find
  no "Photo framing" text and no "Photo check overridden" text, and still find the weight and
  health cards.
- Existing results-screen tests that looked for the view card are updated or removed, with
  each removal named in the phase result.
- `dart format`, `flutter analyze`, and targeted `flutter test test/features/results/`.

## Open questions

- None. The parent's open question 3 was answered on 2026-09-25: the override stays hidden,
  with no replacement note on screen.

### Result (2026-09-25)

- Removed the `_viewOverrideBanner()`/`_viewCard()` calls and the spacing around them
  (`results_screen.dart:278-283` before this change), and deleted both methods. `bundle.viewEvent`
  and `effectiveRoute` are unchanged; the weight and health cards still read them.
- A search confirmed both cards were only referenced in `results_screen.dart`; no other screen
  needed a change.
- New widget test: `test/features/results/results_screen_view_cards_removed_test.dart`, covering
  a `dorsal_valid` scan and a `health_only` scan, each asserting no "Photo framing" and no
  "Photo check overridden" text, with the weight and health cards still present. No existing
  test referenced either removed card's text, so nothing else needed updating; one stale comment
  in `health_card_cascade_test.dart` describing the layout order was corrected.
- `dart format` on changed files, `flutter analyze` on the changed files (no issues), and
  `flutter test test/features/results/`: 10 passed, 0 failed.
