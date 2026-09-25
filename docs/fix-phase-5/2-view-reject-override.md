# Phase 2 — Let the user override a view-gate rejection and analyze the photo anyway

Status: implemented, host-verified (Dart) and device-verified (2026-09-22) — Retake, Analyze
anyway, and the no-leak check all confirmed; native ctest fixture and widget test still owed

Parent: [`../fix-5.md`](../fix-5.md) (round 9). This phase is the user's answer to **F67** (the
view classifier's unreliability on landscape input), supplied on 2026-09-22 and recorded here
as chosen product behaviour, not as an approach proposed by this document.

## Symptom

F67, restated from the user's seat: a landscape photograph of a pig that is perfectly usable is
classified `reject` by `assets/ml/view/model.onnx`, and the app then refuses to analyze it at
all. The rejection dialog in `capture_screen.dart:403-418` offers exactly one action, `Retake`,
so a correct photo the model dislikes is a dead end — retaking it in the same orientation
reproduces the same verdict (host measurements in `fix-5.md`'s F67 table show `reject` at 0.46
and verdict flips between rotation directions on the same image).

## Chosen behaviour

On a `reject` verdict the app shows a dialog stating the photo was detected as not usable, with
**two** choices:

- **Retake** — current behaviour, unchanged: the scan is marked `rejected` and the capture
  screen returns to the camera.
- **Analyze anyway** — the scan proceeds through the normal flow and the photo is analyzed in
  full, whatever the outcome turns out to be. The result is shown as-is, including a failure or
  a low-quality outcome; the override buys the user an analysis, not a good one.

The override is per-photograph and expires with the photograph. It is not a session setting, not
a preference, and it never applies to a different image (see "Tying the override to an image").

## Why the change is not just a second dialog button

Four separate layers stop a `reject` today. All four have to be told about the override or the
button will appear to do nothing.

1. **`capture_screen.dart:399-420`** — writes `ScanStatuses.rejected`, shows the one-action
   dialog, drops back to the camera, and `return`s before any routing decision.
2. **`RunAndPersistPipelineUseCase.execute`
   (`run_and_persist_pipeline_use_case.dart:76-95`)** — on `view.label == 'reject'` it writes an
   ineligible health result and an ineligible weight result, sets the scan `rejected`, and
   returns without ever calling the native pipeline.
3. **`run_pipeline` (`packages/instaham_ml_ffi/src/pipeline.cpp:293-295`)** — on
   `view_label == "reject"` it returns `stopped_envelope(view_json, "view_rejected")`, an
   envelope with `status: "stopped"` and no other branch in it.
4. **`execute` again (`run_and_persist_pipeline_use_case.dart:119-125`)** — throws `StateError`
   when the envelope's status is `stopped`, which lands in the catch-all failure path.

Layer 3 also matters for routing, not just for stopping: past the stop, the downstream branches
are gated on `is_dorsal` / `is_health_only` (`pipeline.cpp:298-309`), and a `reject` label is
neither, so it falls into the `view_unresolved` block that skips segmentation, construction,
cutter, features, weight **and** health. Removing only the early return would therefore produce
an envelope in which every branch is `skipped` — an "analysis" that computes nothing. The
override has to state what an overridden `reject` is treated *as*.

## Design

### Treatment of an overridden reject

An overridden `reject` is routed exactly as `dorsal_valid`: reference marking is offered,
segmentation, construction, cutter, features, health and weight all run. That is the reading of
"the photo gets analyzed no matter what the result would be" — the user is overriding the view
classifier's opinion that this is not a dorsal pig photo, and the only useful thing to do with
that override is to run the branches a dorsal photo would get.

The label itself is **not** rewritten to `dorsal_valid` anywhere — in the envelope, in
`pipeline_events`, or in the database. The stored verdict stays `reject`, and the override is a
separate, explicitly recorded fact beside it. Nothing downstream should be able to read this
scan and conclude the view model accepted the photo.

### Tying the override to an image

The override must be keyed to the image it was granted for, for exactly the reason phase 1
exists: `_sessionId` in `capture_screen.dart` never rotates, so anything keyed to the scan alone
leaks onto every later photograph in the same capture-screen session. An override that leaked
this way would silently disable the view gate for the rest of the session — a strictly worse
version of F66.

`pipeline_events` already carries `imageIdentity` (phase 1), so the override is recorded as a
row on that table: stage **`'view_override'`** (deliberately not `'view'`), status
`'override'`, `imageIdentity` = the same `imageIdentityOf(imagePath)` sha256 phase 1 added,
`message` = the overridden label and confidence. The stage must differ from `'view'` because
both `resolveViewGate`'s cache lookup and `RecordsDao.loadLatestEvent(scanId, 'view')` (used by
the results screen's view/weight/health cards) select the latest row of stage `'view'` with no
status filter — an override row filed under that stage would be read back as a corrupted
verdict (label `'override'`) by every existing reader. Reading the override back is an
identity-matched lookup of the same shape `resolveViewGate` already performs, and no schema
change, no `schemaVersion` increment and no migration are needed. A `ScanRecords` column was
considered and rejected on those grounds: it would be scan-scoped (the F66 shape) and would
cost a 6 → 7 migration to store something narrower.

### Native plumbing

`instaham_ml_run_pipeline_request_json` already takes a JSON request
(`packages/instaham_ml_ffi/src/instaham_ml.cpp:414-458`), so the flag rides in that request and
**no exported FFI symbol changes signature**:

- Request gains an optional `"view_gate_override": true`. Absent, null or non-boolean means
  false — the current behaviour, bit for bit.
- `run_pipeline` gains a corresponding parameter (`pipeline.h:39`). When set and the label is
  `reject`, it does not build the stopped envelope; it proceeds with the dorsal-valid routing
  above.
- The envelope's `view` block gains `"override": true` on any run that used it, so a stored
  envelope is self-describing and a later reader cannot mistake the run for a clean one.
- `instaham_ml_run_pipeline_json` (the no-request entrypoint) keeps passing no override.
- `MlRuntime.runPipeline` (`lib/services/ml/ml_runtime.dart:151-169`) currently routes to the
  plain entrypoint whenever `cmPerPixel == null`. It gains a `viewGateOverride` parameter and
  must use the request entrypoint when **either** value is present, not only for `cmPerPixel`.
  `PipelineService.run` forwards it.

### What the override does *not* bypass

Only the view gate. Every other eligibility and quality check stays live and can still decline
to produce a number: the truncation gate, the posture gate, the reference-scale checks
(`scale_...` reasons), and the feature-domain check. AGENTS.md rule 3 ("weight estimation
requires all eligibility checks to pass") and rule 8 ("never force a prediction after a failed
quality or eligibility check") are the live tension here, and the position this phase takes is:
the user's explicit, per-photograph, recorded consent replaces the view classifier's verdict as
the eligibility input for that one photograph, and no other check is touched or weakened. This
is a deliberate narrowing, and it is the thing to re-read if the behaviour is ever questioned.

If the user overrides and then skips reference marking, the weight branch degrades to
unavailable exactly as it does today; health still runs. That is acceptable and needs no special
handling.

### Surfacing it

Anything showing a result from an overridden scan states that the photo failed the view check
and was analyzed at the user's request, and that its numbers are not backed by a passed view
check. That is a plain factual banner on the results screen, not a score and not a completed
state — AGENTS.md's UI rule forbids inventing scores, not disclosing provenance. Wording is
implementation-time work; the requirement is that an overridden result is never presented as
indistinguishable from a normal one.

## Steps

- [x] **2a — capture screen dialog.** Reject dialog now has two actions, `Retake` and
      `Analyze anyway`. `updateScanStatus(id, ScanStatuses.rejected)` moved to fire only on
      `Retake`; `Analyze anyway` records the override and falls through to the same routing a
      `dorsal_valid` verdict gets.
- [x] **2b — record the override.** `recordViewGateOverride`/`hasViewGateOverride` added
      beside `recordViewGate`/`resolveViewGate` in `run_and_persist_pipeline_use_case.dart`,
      ordered by `id` per phase 1.1. **Correction from the plan above:** the event is stage
      `'view_override'`, not stage `'view'`. Filing it under `'view'` would have made it the
      "latest view event" `resolveViewGate`'s own cache lookup and
      `RecordsDao.loadLatestEvent(scanId, 'view')` (the results screen's view/weight/health
      cards) both select — both filter by stage only, with no status filter — so an override
      row there would have been read back as a corrupted verdict (label `'override'`). A
      distinct stage keeps every existing `'view'` reader untouched. `recordViewGateOverride`
      takes plain `overriddenLabel`/`overriddenConfidence` strings/doubles rather than a
      `ViewClassificationResult`, so `capture_screen.dart` does not need to import
      `services/ml/view_model_service.dart` (AGENTS.md: UI widgets stay independent of ML
      runtime packages).
- [x] **2c — `execute()`.** Consults `hasViewGateOverride` before the `viewRejected` early
      return; on a match, skips the two ineligible-result writes and the `rejected` status, and
      forwards the flag to `pipelineService.run`. Envelope-disagreement degradation is
      untouched for every non-overridden case.
- [x] **2d — native.** `view_gate_override` parsed in `instaham_ml_run_pipeline_request_json`,
      new trailing `bool view_gate_override = false` parameter on `run_pipeline` (default
      keeps every existing call site, including the plain `instaham_ml_run_pipeline_json`
      path, unchanged), reject-stop skipped and dorsal routing taken when set,
      `view.override = true` written into the envelope's `view` block on that run.
- [x] **2e — Dart FFI wrapper.** `viewGateOverride` threaded through `IPipelineService.run`,
      `PipelineServiceImpl.run`, and `MlRuntime.runPipeline` (which now uses the request-shaped
      entrypoint when *either* `cmPerPixel` or `viewGateOverride` is present, not only
      `cmPerPixel` — the gap the plan flagged above). Three existing test doubles
      (`reference_scale_forwarding_test.dart`, `weight_domain_failure_test.dart`,
      `functional_scenarios_test.dart`) implement `IPipelineService.run` and needed the new
      named parameter added to keep compiling; behaviour unchanged since none of them set it.
- [x] **2f — results surfacing.** `LocalScanBundle` gained a `viewOverridden` bool, computed
      by `ResultsScreen._loadAndRunPipelineIfNeeded` via `hasViewGateOverride` (identity-matched
      against the scan's current image) rather than by `RecordsDao`, since that DAO lives in a
      different feature and must not import the inference-pipeline use case (AGENTS.md:
      features must not import other feature modules directly). A plain-text banner
      (`_viewOverrideBanner`, `ResultStatus.uncertain`) renders above `_viewCard` when true.
- [x] **2g — docs.** `pipeline-docs` run 2026-09-22. Updated `ffi-bridge.md` (the request
      contract now carries `view_gate_override`, and the entrypoint-selection rule), the view-gate
      bullet in `architecture.md`'s "Boundaries that matter", the exception note in
      `pipeline/README.md`, and `app-flow.md` (label table, Stage A routing, Stage B step 1,
      result-states table — a plain doc with no owning skill, edited directly per AGENTS.md).
      The ADR it flagged was written: [ADR-017](../adr/017-user-consent-view-gate-override.md),
      which states the F67 evidence, the four bounds on the override, and the accepted tension
      with AGENTS.md rules 3 and 8.

## Verification

Host, before any device work:

- [x] `flutter test` on new Dart tests (`test/features/inference_pipeline/view_gate_override_test.dart`):
      `hasViewGateOverride` is false with nothing recorded; true for the exact image an
      override was recorded for; false for a different image in the same scan (the F66-class
      regression this design exists to avoid); and a `'view_override'` event never satisfies
      `resolveViewGate`'s own `'view'`-stage cache lookup. Full suite: **119 passed, 39
      skipped** (was 115/39 before this phase's 4 new tests; every skip is pre-existing and
      deliberate, none added by this phase).
- [ ] Widget test that the reject dialog exposes both actions and that `Retake` still marks the
      scan `rejected`. **Not written** — no existing widget-test scaffolding for
      `capture_screen.dart` (camera controller, `DatabaseScope`, routing) to build on, and
      standing one up was judged out of proportion to a two-button dialog change at this
      session's effort level. Left as owed rather than skipped silently.
- [ ] Native: a `ctest` case that a request with `view_gate_override: true` on an image the view
      model rejects returns a non-`stopped` envelope carrying `view.override == true` and
      non-skipped downstream blocks. **Not written** — every existing `ctest` target that
      exercises `run_pipeline()` needs real ORT runners loaded from `assets/ml/manifest.json`
      (`test_shipped_manifest`) or is pure-JSON (`test_feature_domain`); none stub the view
      runner, so a fixture that actually reaches the `"reject"` branch needs a real rejecting
      image plus loaded models, the shape flagged as possibly Tier-B-gated in the plan above.
      Confirmed instead: `ninja` builds clean with the new `pipeline.h`/`pipeline.cpp`/
      `instaham_ml.cpp` signatures, and `ctest` shows the pre-existing suite unaffected —
      **8/10 passing, `test_abi` and `test_scale_normalization` fail, both on files this
      phase never touched** (verified via `git status` before the run) and both failing for
      reasons unrelated to this change (`test_abi` asserts `instaham_ml_create` succeeds on a
      nonexistent manifest path, stale since real manifest parsing landed; `test_scale_normalization`
      fails an `lc` feature-scaling tolerance). Neither is new.
- [x] `flutter analyze`, `dart format` on changed Dart files — 0 errors (one pre-existing-style
      `use_null_aware_elements` info on `ml_runtime.dart`'s conditional map entries, matching
      the same `if (x != null) 'key': x` pattern used throughout `app_database.g.dart` and
      every `*_entity.dart` `toJson()` in this codebase).

Device, the user's work and the thing that actually closes F67:

- [x] A landscape photo the model rejects: take **Retake** once and confirm the old path is
      intact, then take **Analyze anyway** and confirm an analysis runs to a result and the
      result is labelled as overridden. **Confirmed on device 2026-09-22: both Retake and
      Analyze anyway worked as designed.**
- [x] In the same app session, after an override, feed a genuinely bad photo and confirm it is
      still rejected — i.e. the override did not leak to the next photograph. **Confirmed on
      device 2026-09-22:** the second bad photo triggered the same Retake/Analyze-anyway
      dialog again rather than being silently waved through, so the override does not carry
      over to a different image.

## Open questions

- **Does an overridden scan's result belong in history/trends the same way a clean one does?**
  This phase does not exclude it and does not aggregate it differently; it only labels it. If
  overridden weights should be held out of any trend or export, that is a separate decision and
  a separate phase.
- **Retry ordering on device is worth watching.** Phase 1's device confirmation is still owed,
  and this phase adds a second per-image fact to the same table. Confirming phase 1 first keeps
  the two diagnoses separable.

## Plan rating: 7/10

**Pros.** All four blocking layers are identified from source with line references before
anything is written, so the phase cannot ship a button that silently does nothing — which is the
obvious failure mode of this change. Keying the override to `imageIdentity` reuses phase 1's own
mechanism and makes the session-leak bug structurally impossible rather than merely tested
against, and it avoids a `schemaVersion` bump for one boolean. Riding the existing request-JSON
entrypoint means no exported FFI signature changes. The tension with AGENTS.md rules 3 and 8 is
stated plainly with its narrowing, rather than being left for a reviewer to discover.

**Cons.** It is a four-layer change (Dart UI, Dart use case, Dart FFI wrapper, C++) for one
button, and that span is real risk — the native half needs a rebuild and a fixture that actually
rejects, which the host test suite does not currently guarantee. Treating an overridden `reject`
as `dorsal_valid` is a judgement call with no better alternative but no evidence behind it
either: nothing is known about how the segmenter behaves on the photos this model rejects, so
the override may frequently buy the user an analysis that fails one stage later for an unrelated
reason. And the underlying F67 defect — a view model that was not trained on landscape dorsal
frames — is not fixed by this phase and is not made less true by it; this is a usable escape
hatch layered over a model gap, and it should not be read as closing the gap.
