# Phase 4 — docs, ADR and device check

Status: done (2026-09-25)

Parent: [`../fix-6.md`](../fix-6.md) (round 10). Needs phases 1-3.

## Symptom

The contract docs describe round 9's shape: one override, from `reject` only, toward the full
route, with a disclosure banner on the results screen.

## Change made (planned)

1. **`pipeline-docs`**:
   - `docs/ffi-bridge.md`: the `view_route_override` request field and the kept boolean
     alias.
   - `docs/architecture.md`: the "only the `reject` stop is overridable" sentence.
   - `docs/pipeline/README.md`: the exception paragraph about `view_gate_override`.
   - A new ADR superseding the part of ADR-017 that limits overrides to `reject` → full route.
     ADR-017's status line changes to "Partly superseded by ADR-0NN"; its body is not edited.
2. **`spec-drift`**: the envelope's `view` block gains `override_route`.
3. **`docs/app-flow.md`** (no owning skill): the routing section for `health_only` (it now asks
   first), and the result-states table rows for the View card and the **overridden** banner,
   which are removed.
4. **`docs/design-system.md`**: check for any entry describing the view card or the reject
   dialog, and update it if one exists.
5. **Device check.** Build `flutter build apk --release`. The user sideloads it and uses
   gallery photos (no live pig is needed):
   - a photo the app calls `reject` and one it calls `health_only` both show the three-option
     dialog;
   - on each, **Check health only** gives a health result with weight Skipped, and **Check
     weight and health** goes to reference marking and runs the full route;
   - a normal dorsal photo goes straight to reference marking;
   - no results screen shows the photo-check card or the override banner.

   Record the result here as soon as the user reports it. No Firebase Test Lab run is part of
   this phase.
6. **Close-out.** Add the round 10 line to `docs/changelog.md` and mark `docs/fix-6.md` done.

## Verification

- Each owning skill's own check, and the user's device report recorded above.

### Result, step 5 — device check (2026-09-25, user report)

- The user sideloaded a release build of the current tree. A first report of a missing
  loading animation and missing dialog came from an older APK that had not been replaced yet;
  it was withdrawn once the new build was installed.
- On the new build the user reported: "both health only and health + weight option works as
  intended". **Check health only** and **Check weight and health** each run their route.
- Asked about the remaining checklist items (the dialog on both a `reject` and a
  `health_only` photo, a dorsal photo going straight to reference marking, and no photo-check
  card or override banner on any results screen), the user confirmed "yes all good".

### Result, steps 1-4 (2026-09-25)

- **Step 1 (`pipeline-docs`).** `ffi-bridge.md`: the request field is now
  `view_route_override`, with the boolean alias and its precedence (a string key, even an
  invalid one, wins; the boolean is read only when that key is absent or not a string), and
  the `override` / `override_route` marking rule. `architecture.md` and `pipeline/README.md`:
  the view gate is overridable from `reject` to either route and from `health_only` to
  `dorsal_valid`. New [ADR-020](../adr/020-view-route-override-either-route.md); ADR-017's
  status line now reads "Partly superseded by ADR-020", body unchanged.
- **Step 2 (`spec-drift`).** The spec had never recorded round 9's boolean override, so both
  rounds were added to the view classifier's contract, and `envelope["view"]` is now listed
  in "Envelope and ABI". Intentional change, not drift.
- **Step 3 (`app-flow.md`).** The label table, Stage A routing (three-button dialog on both
  verdicts, what each button records), `execute` step 1, and the result-states table (the View
  card and overridden-banner rows removed, weight Skipped defined by the route that ran) with a
  note on `effectiveRoute`.
- **Step 4 (`design-system.md`).** The scan-flow diagram, a note on the dialog's layout, and
  the "view gate renders as its own card" rule, which is now "no card of its own".
- Every claim was checked against the code (`instaham_ml.cpp:445-460`, `pipeline.cpp:292-306`,
  `classifier.cpp:103-110`, `capture_screen.dart:416-487` and `:958-1007`,
  `run_and_persist_pipeline_use_case.dart:70-128`, `results_screen.dart:434,473`). Docs only,
  so no build or test ran.

## Open questions

- Which photos from `.pig_pictures/` or the scenario fixtures reliably get `reject` and
  `health_only` verdicts. Fixture `05_offdorsal_view` and `06_lesion_closeup` are the likely
  candidates. Confirm this from recorded verdicts, not by guessing.
