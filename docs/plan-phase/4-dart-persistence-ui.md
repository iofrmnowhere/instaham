# Phase 4 — Dart, persistence, and UI surface

Status: done

## Goal

Carry the 16-feature vector and the new cutter telemetry from the FFI envelope through the
Dart layer, into Drift, and into the rejection messaging — without widening the schema by
sixteen columns or leaking model internals into widgets.

## What is bound to five today

- `lib/core/database/app_database.dart`: `WeightEstimates` has
  `featureRa/featureLc/featureBl/featureBw/featureE`, `saveWeightResult(...)` takes five
  named `double?` parameters, and the seed helper near line 470 fabricates five random
  values. `schemaVersion` is 3.
- `lib/services/ml/weight_model_service.dart` (~lines 64–72): reads `features['RA'..'E']`.
- `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart`:
  reads the same five keys twice (~lines 240–270), and `const order = ['RA','LC','BL','BW','E']`
  at ~line 464 drives the rejection message rendering added in ref_fix F17.

## Design/Approach

### Persistence: a JSON blob, not sixteen columns

Adding sixteen `RealColumn`s bakes one model's feature family into the schema, and the next
model change repeats this migration. Instead:

- Add `TextColumn get featureVector => text().nullable()()` to `WeightEstimates`, holding the
  envelope's `features` block verbatim (`{"family": "chen16_noheight", "values": {...}}`).
- Add `TextColumn get featureFamily => text().nullable()()` as a queryable discriminator, so
  a later export or analytics query can filter by family without parsing every blob.
- **Keep** `featureRa..featureE` and stop writing them. They hold real field data from
  earlier scans, and dropping them loses the history that
  `docs/fix-phase/6-device-telemetry-findings.md` was built from. Mark them deprecated in a
  comment naming this phase.
- Bump `schemaVersion` to 4 and add `if (from < 4)` to the `onUpgrade` block, adding both new
  columns. Nullable additions, so no backfill.
- Regenerate with `dart run build_runner build --delete-conflicting-outputs` and add a
  migration test covering 3 to 4 (an existing row keeps its `featureRa`, and the new columns
  read null).

Also add the cutter telemetry, which is small, fixed, and directly diagnostic:
`RealColumn get cutterKeptFraction` and `TextColumn get cutterStatus`, both nullable, in the
same migration. `kept_fraction` is the field-comparable number
(`fixed_test_predictions.csv` records it per training row, median around 0.95), and it is the
fastest on-device signal that the cutter is cutting the wrong thing. Per phase 3 it is
computed in the app's cutter adapter — the vendor's V144 cutter deliberately does not return
it — and it is **telemetry only**: nothing in the Dart layer may branch on it either, and it
must not reach the UI.

### `saveWeightResult` signature

Replace the five `ra/lc/bl/bw/e` parameters with `Map<String, double>? features` plus
`String? featureFamily`, `double? cutterKeptFraction`, `String? cutterStatus`. Update the
three call sites (the two in the use case and the seed helper). The seed helper should stop
fabricating feature values entirely and write `null` — inventing sixteen plausible Chen16
values, including signed Hu moments, would be fabricated model output, which the UI contract
forbids surfacing.

### Rejection messaging

The F17 renderer at `run_and_persist_pipeline_use_case.dart:464` lists all five features and
marks the violating ones. Rendering all sixteen would be unreadable, and per phase 3 only six
are gated at all. Change it to render **the gated features only** (`mask_area`,
`convex_hull_area`, `difference`, `perimeter`, `longest`, `shortest`), driven by the
envelope's own `gated` flag rather than a hardcoded Dart list — a second hardcoded order is
exactly the coupling this plan is removing.

The feature names are also now internal jargon in a way `RA/LC/BL/BW/E` at least was not
paired with a user-facing sentence. Map them to plain-language labels in the presentation
layer ("body area", "outline length", "body length", "body width"), keeping the raw name in
the persisted blob for diagnostics. Never show a Hu moment to a user.

New rejection reasons the cutter can now produce (`jiduan_failed`, `no_terminal_balls`,
`break1_unfit`, `shoulder_undecided`) each need a user-facing sentence. They all mean roughly
"the pig's outline could not be resolved well enough to find the shoulder", so one shared
message with the raw status kept in telemetry is acceptable — but it must be a distinct
message from the existing domain-gate rejection, because the corrective action differs
(retake the photo from the side, versus the animal is outside the trained size range).

Phase 2's quality gates add two more, and `README_AI_INTEGRATION.md` section 7 already
prescribes both the outcome names and the corrective action, so follow it rather than
inventing our own vocabulary:

| native outcome | user-facing action |
|---|---|
| `truncated` | stop; ask for a full-body retake |
| `excessiveCurvature` | stop; ask for a straighter-posture retake |
| `nativeAnalysisFailed` | stop safely; controlled error, ask for another image |

Native returns status only — the vendor's rule, and this repo's already. The strings live in
the presentation layer.

### `weight_model_service.dart`

Replace the five hardcoded key reads with a pass-through of the whole `values` map plus
`family`. The service should not know feature names at all.

## Steps

- [x] Add `featureVector`, `featureFamily`, `cutterKeptFraction`, `cutterStatus` to
      `WeightResults` (the table is `WeightResults`, not `WeightEstimates`); deprecate
      `featureRa..featureE` in comments.
- [x] Bump `schemaVersion` to 4; add the `from < 4` migration step.
- [x] `dart run build_runner build --delete-conflicting-outputs`.
- [x] Add the 3 to 4 migration test.
- [x] Change `saveWeightResult`'s signature and its call sites; stop fabricating feature
      values in the seed helper.
- [x] Update `weight_model_service.dart` to pass the map through untouched.
- [x] Rewrite the F17 rejection renderer against the envelope's `gated` list; add
      plain-language labels for the gated features.
- [x] Add user-facing messages for the four new cutter decline statuses.
- [x] `dart format` on changed files, `flutter analyze`, and targeted `flutter test`.

## Open questions

- Does anything downstream (CSV export, analytics DAO, a research-upload payload) read
  `featureRa..featureE` directly? Grep before the signature change; a reader that silently
  starts getting null is worse than a compile error. If one exists, decide whether it reads
  the blob instead or is retired.
- Should `featureVector` be excluded from any research upload? It is derived measurement, not
  an image, so consent rules around research images do not obviously apply — but it is new
  data leaving the device, so confirm against the privacy rules before wiring any upload.

## Results (implemented this session)

### Persistence — `lib/core/database/app_database.dart`
- `WeightResults` gains `featureVector` (TEXT, the family-tagged blob
  `{"family":..,"values":{name:value}}`), `featureFamily` (TEXT discriminator),
  `cutterKeptFraction` (REAL) and `cutterStatus` (TEXT). `featureRa..featureE` are kept but
  marked deprecated in a comment naming this phase — no longer written by any call site.
- `schemaVersion` 3 → 4 with an `if (from < 4)` step that `addColumn`s the four new
  nullable columns. No backfill; existing rows keep their `featureRa..featureE`.
- Drift output regenerated (`dart run build_runner build --delete-conflicting-outputs`,
  exit 0).
- `saveWeightResult`'s five `ra/lc/bl/bw/e` params replaced by `Map<String,double>?
  features` + `String? featureFamily` + `double? cutterKeptFraction` + `String?
  cutterStatus`. `featureVector` is `jsonEncode({'family': featureFamily, 'values':
  features})` when `features != null`, else null.
- `insertSampleRecord()` no longer fabricates a feature vector (inventing sixteen Chen16
  values, signed Hu moments included, would be fabricated model output). `valueKg` stays
  synthetic — it is only the demo record's headline.

### Envelope pass-through — `run_and_persist_pipeline_use_case.dart`
- The two weight `saveWeightResult` calls now pass `features` (converted from
  `envelope['features']['values']` to `Map<String,double>`), `featureFamily`
  (`envelope['features']['family']`), and the cutter telemetry
  (`envelope['cutter']['kept_fraction']` / `['status']`). No Dart code branches on the
  telemetry and it never reaches the UI.
- `_weightFailureMessage` gains cases for `weight_pending_field_validation` (the shipped
  build's real weight-unavailable reason now that the cutter is real and only phase-5 field
  calibration is pending), `truncation_gate_rejected`, `posture_gate_rejected`, and — via a
  new optional `cutterStatus` argument — the four cutter decline statuses
  (`jiduan_failed`, `no_terminal_balls`, `break1_unfit`, `shoulder_undecided`), which map
  to one shared "outline could not be resolved, retake from the side" sentence, distinct
  from the domain-gate "animal outside trained size range" message.
- `_domainFeatureDetail` now renders the gated features only, by plain-language label
  (`_featureLabel`: "body area", "outline length", "body length", "body width", …), driven
  by a new `envelope['features']['gated']` array rather than a hardcoded Dart order. Falls
  back to the `violations`-named features when an older native build omits `gated`.

### Native — `packages/instaham_ml_ffi/src/pipeline.cpp`
- The `features` envelope block gains a `gated` array (feature names where
  `feature_domain[name].gate && max > 0` — the same predicate pipeline.cpp's own domain
  gate uses). This is the only native change; it cannot be host-compiled (no host target
  links `pipeline.cpp` — Android build is the only compile check) so it is verified by
  inspection and by the Dart-side fallback that tolerates its absence.

### Service — `lib/services/ml/weight_model_service.dart`
- `WeightPredictionResult`'s `ra..e` replaced by `Map<String,double>? features` +
  `String? featureFamily`. `predict()` passes the values map through without naming any
  feature; it accepts both the flat `features:{RA:..}` shape the standalone
  `instaham_ml_predict_weight_json` still emits and the nested `features.values` envelope
  shape.

### Open question 1 — downstream readers of `featureRa..featureE`
Grepped `lib/`: only `test/` referenced the five columns. `analytics_dao.dart` and
`records_dao.dart` read whole `weightResults` rows but never those fields. No CSV export or
research-upload payload exists yet. So dropping the writes is safe; no reader silently
starts getting null.

### Validation
- `dart format` on the five changed files.
- `flutter analyze lib/ test/` — no issues.
- `flutter test` on `test/core/database/app_database_test.dart` (incl. the new 3→4
  migration test), `test/features/inference_pipeline/` (incl. the rewired
  `weight_domain_failure_test.dart`), `test/features/analytics/`,
  `test/features/records/`, `test/features/weight_estimation/` — all pass.

### Deferred
- `weight_features.dart` / `weight_result_entity.dart` / `PipelineResultEntity.fromJson`
  are still baseline5-shaped (require all five `RA..E` keys), but they are referenced only
  by `pipeline_result_entity_test.dart` and are not wired into any runtime path, so they
  were left alone rather than widened speculatively.
- Excluding `featureVector` from a research upload — no upload path exists to gate yet;
  revisit when one is built.
