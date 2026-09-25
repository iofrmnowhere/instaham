# Fix (round 10): let the user choose the route when the photo check flags a photo — closed 2026-09-25

Sixth fix document, opened as **round 10** on 2026-09-25. It builds on
[`fix-5.md`](fix-5.md) (round 9), whose phase 2 added the single "Analyze anyway" override for
a `reject` verdict. This round widens that override; it is not a phase of round 9.

Finding numbering continues at **F68** (F67 was the last assigned, in round 9).

## Symptom

Requested by the user on 2026-09-25, as chosen product behaviour:

1. **The photo check (view classifier) can be wrong in both directions it stops a photo.**
   - On `reject`, the dialog offers only **Retake** or **Analyze anyway**, and "anyway" always
     means the full weight-and-health route. There is no way to ask for a health check alone.
   - On `health_only`, there is no dialog at all. The app goes straight to a health-only check,
     so a dorsal photo the classifier misread can never get a weight estimate.
2. **The results screen shows the user the photo check's own output.** The "Photo framing" card
   (Dorsal view / Health-only view / Not usable, with a confidence) and, after an override, the
   "Photo check overridden" banner are internal routing details, not results the user needs.

## Root cause

**F68 — the override can only be granted from `reject`, and only toward one route.** Every
layer hardcodes that shape:

- `capture_screen.dart:416-458` shows the dialog only when `viewLabel == 'reject'`, with two
  buttons, and a `health_only` verdict falls through to `skipReference` at line 465 unasked.
- `RunAndPersistPipelineUseCase.execute` computes `overridden` only when
  `view.label == 'reject'` (`run_and_persist_pipeline_use_case.dart:84-85`).
- The `view_override` event records *that* an override happened, not *which route* was chosen
  (`recordViewGateOverride`, status always `'override'`).
- The native request carries a boolean `view_gate_override`, and `pipeline.cpp:291-312` turns
  it into exactly one outcome: an overridden `reject` is routed as `dorsal_valid`.

**F69 — the results screen presents the photo check as a result.** `results_screen.dart:278-282`
always renders `_viewCard()` and, when overridden, `_viewOverrideBanner()`. Round 9 added the
banner as a disclosure. The user has now decided both are irrelevant on the user side.

**F70 — the weight card misreads an overridden scan (found while tracing F68).**
`_weightCard` labels any unusable weight result as **Skipped** whenever the stored verdict is not
`dorsal_valid` (`results_screen.dart:433-434`). An overridden `reject` whose weight checks then
fail is shown as "Skipped" rather than "Unavailable" today. Once a `health_only` verdict can be
overridden to the full route, this becomes the common case. The health card has the matching
check against `reject` (`results_screen.dart:537`). Both must read the route that actually ran,
not the verdict.

## Change made

All four phases are done; the round was closed on 2026-09-25 after the user's device check. The fix is split into phases, in order:

| # | Name | Status | File |
|---|---|---|---|
| 1 | Native route override | done | docs/fix-phase-6/1-native-route-override.md |
| 2 | Three-option dialog and Dart routing | done (F70 test substituted, see phase file) | docs/fix-phase-6/2-dialog-and-routing.md |
| 3 | Remove the photo-check cards from results | done | docs/fix-phase-6/3-remove-view-cards.md |
| 4 | Docs, ADR and device check | done | docs/fix-phase-6/4-docs-and-device.md |

Phases run in numerical order. Phase 3 has no dependency on 1-2 and could be done first if the
user wants a quick visible change, but it is kept third to keep the order the user gave.

### The chosen behaviour in one table

| Photo check says | Dialog? | Retake photo | Check health only | Check weight and health |
|---|---|---|---|---|
| `dorsal_valid` | no, unchanged | – | – | – |
| `health_only` | **yes (new)** | back to camera | today's health-only route, no override recorded | override to the full route |
| `reject` | yes | back to camera (unchanged) | **override to the health-only route (new)** | override to the full route (today's "Analyze anyway") |
| unresolved (gate failed) | no, unchanged | – | – | – |

The stored verdict is never rewritten. The chosen route is a separate, image-keyed fact, as in
round 9. Only the view gate is bypassed; every other gate (scale, truncation, posture, feature
domain, cutter) stays live.

## Verification

The round closes when:

- A `reject` photo and a `health_only` photo each show the three-option dialog, and each of the
  five non-retake choices runs the route in the table above. This is checked on host by Dart
  tests and on the user's phone with gallery photos.
- A `dorsal_valid` photo still goes straight to reference marking with no dialog.
- The results screen shows no "Photo framing" card and no "Photo check overridden" banner for
  any scan, old or new.
- A weight branch that fails on an overridden full-route scan reads **Unavailable**, not
  Skipped (F70).
- The native routing decision is covered by a model-free ctest, and `flutter analyze` and the
  full `flutter test` suite pass with no regressions.

## Open questions

1. **Dialog wording.** *Answered 2026-09-25: use phase 2's proposed titles, body text and
   button labels as written.*
2. **Retake on a `health_only` photo.** *Answered 2026-09-25: mark the scan `rejected` and go
   back to the camera, the same as the existing Retake on `reject`.* This is only the scan's
   status. No override or route is recorded for a Retake.
3. **Should the override stay visible anywhere?** With the banner gone, the override is kept
   only in the database and the envelope. The records list and any export would not show it.
   *Answered 2026-09-25: keep it hidden. Nothing on screen shows it.*

## Plan rating: 8/10

**Pros.** The behaviour is fully specified by the user and fits in a five-cell table. Round 9
already built the hard parts: the image-keyed override event, the request field, the native
routing hook and its tests, so this round widens an existing mechanism rather than inventing
one. No schema change and no ABI change: the route rides in the existing request JSON and the
existing event row. The native decision becomes a pure function that ctest can cover without
models. F70 is caught before it becomes the common case.

**Cons.** It widens a user override that AGENTS.md rules 3 and 8 are wary of: the user can
now also force a full weight run on a photo the classifier called health-only. The protection
is the same as round 9's (every other gate stays live), but it needs a new ADR superseding part
of ADR-017. Removing the disclosure banner means an overridden result looks the same as a
clean one on screen. That is the user's explicit choice, but it is a real loss of provenance for
anyone reading a result later. A three-button dialog is tight on small phones and has to stack
vertically to keep 44 px targets.

**Why not higher.** The classifier's unreliability (F67) is still unaddressed. This round gives
the user more ways around it, not a better classifier.

**Why not lower.** Every change is small, grounded in code already read, reversible, and has a
concrete host check. The device check needs only gallery photos.
