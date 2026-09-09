# Phase 3 — Manifest contract and native weight branch rewiring

Status: done (see Results)

## Goal

Make the manifest describe a feature family of arbitrary width instead of five named
features, and make `pipeline.cpp` / `manifest.cpp` / `stages/weight_prediction.cpp` follow
it, so the ONNX graph from phase 1 is fed the 16-vector from phase 2 with the eligibility
gate intact.

## What is hardcoded to five today

| Location | Hardcoded form |
|---|---|
| `manifest.h` `WeightCapability` | five named `FeatureDomain domain_ra/lc/bl/bw/e` members |
| `manifest.cpp` `load_weight()` | asserts `feature_order == {RA,LC,BL,BW,E}` |
| `stages/weight_prediction.cpp` | builds a 5-element vector, shape `{1, 5}` |
| `pipeline.cpp` | five `feature_in_domain(...)` calls, five `feature_extrapolated(...)` calls, `features.values` JSON keyed `RA..E` |
| `ML/export/manifest.schema.json` | the `weight` block's shape |

## Design/Approach

### `WeightCapability` becomes order-driven

Replace the five named `FeatureDomain` members with:

```cpp
std::vector<std::string> feature_order;              // already exists
std::map<std::string, FeatureDomain> feature_domain; // keyed by feature name
std::string feature_family;                          // "baseline5" | "chen16_noheight"
```

`load_weight()` then validates structurally rather than by name: `feature_family` must be a
family the build knows, `feature_order` must equal that family's canonical list exactly
(preserving AGENTS.md rule 2's intent — an order assertion against a single named constant),
and every name in `feature_order` must have a `feature_domain` entry. Keep the existing
hard failures: a weight-available manifest missing `cm_per_px_target` or `training_frame_px`
still fails to load with `INSTAHAM_ML_ERR_CONTRACT`.

Keeping the family list in C++ as well as in the manifest is deliberate: the manifest is an
asset and can be swapped without a rebuild, so the native side must still refuse a vector
whose width does not match the graph it is about to run.

### The domain gate becomes a loop

`pipeline.cpp`'s five `feature_in_domain` calls become one loop over `feature_order`,
looking each name up in `feature_domain`. The `uncertainty` exponent, which today is applied
as `uncertainty * uncertainty` for the area-like `RA`, `uncertainty` for the linear
`LC/BL/BW`, and `1.0` for the dimensionless `E`, generalizes to a per-feature `dimension`
declared in the manifest:

- `area` (exponent 2): `mask_area`, `convex_hull_area`, `difference`
- `linear` (exponent 1): `perimeter`, `longest`, `shortest`
- `dimensionless` (exponent 0): `dif_mask`, `body_curve`, `outline_curve`, `Hu_1`..`Hu_7`

This has to be data, not a compiled-in table, or the manifest stops being able to describe
its own model. Emit it from `export_xgboost.py` alongside each domain entry.

Note `body_curve` is an angle in degrees (144.1–180.0 across the eval set) and `outline_curve`
and `dif_mask` are ratios: none of the three scales with `k`, so exponent 0 is correct for
all of them, not just the Hu moments.

### Hu moments need a different gate shape

`Hu_5` and `Hu_7` straddle zero (`-1.75e-07` to `8.75e-08`, and `-1.92e-07` to `9.95e-08`),
and `Hu_3`/`Hu_4` span five orders of magnitude. A multiplicative widening is meaningless on
a bound that crosses zero — `min * lower_multiplier` moves the bound the wrong way for a
negative `min`. Since every Hu feature is dimensionless and therefore has exponent 0, no
widening is applied to them at all and the problem does not arise in practice. Assert that
explicitly in `load_weight()`: a `dimensionless` feature with any multiplier other than
`1.0` is a contract error, not a silently-ignored field.

### Feature domain values

Derived from all 1821 rows of `fixed_test_predictions.csv` (test split only — see the plan's
open question 2 on widening):

| feature | min | max | dimension |
|---|---|---|---|
| `mask_area` | 36647 | 95247 | area |
| `convex_hull_area` | 39991 | 102853 | area |
| `difference` | 1273 | 10938 | area |
| `dif_mask` | 0.0198217 | 0.186492 | dimensionless |
| `body_curve` | 144.138 | 179.995 | dimensionless |
| `perimeter` | 861.227 | 1446.57 | linear |
| `outline_curve` | 0.0175394 | 0.0888233 | dimensionless |
| `longest` | 332.233 | 598.365 | linear |
| `shortest` | 103.271 | 190.254 | linear |
| `Hu_1` | 0.225771 | 0.336527 | dimensionless |
| `Hu_2` | 0.0246639 | 0.0864436 | dimensionless |
| `Hu_3` | 2.90541e-08 | 0.0023578 | dimensionless |
| `Hu_4` | 9.56505e-09 | 0.000271574 | dimensionless |
| `Hu_5` | -1.74576e-07 | 8.75468e-08 | dimensionless |
| `Hu_6` | -4.88158e-05 | 6.68431e-05 | dimensionless |
| `Hu_7` | -1.91579e-07 | 9.94685e-08 | dimensionless |

All `upper_multiplier` and `lower_multiplier` values are `1.0`. The widened multipliers in
the current manifest exist solely to tolerate the identity stub's uncut mask; with the real
cutter running they are no longer justified and keeping them would silently re-admit exactly
the inputs phase 2 was built to eliminate.

**Do not gate on all sixteen.** Rejecting a photo because `Hu_6` is fractionally out of the
test split's range is not a meaningful eligibility signal, and with 16 independent bounds
the chance of a spurious rejection compounds. Gate on the three `area` and three `linear`
features — the ones `k` actually scales and where "the model has never seen a pig this size"
is the real question — and record the other ten in the manifest as diagnostics only, with an
explicit `gate: false` flag per entry so the choice is visible in the asset rather than
buried in `pipeline.cpp`.

### `stages/weight_prediction.cpp`

Change `predict_weight` to take `const std::vector<float>& features` plus the expected width
from the manifest, run with shape `{1, N}`, and refuse (rather than truncate or pad) when
the incoming width does not match. The `FiveFeatures` overload can stay for the baseline5
rollback path.

### Envelope JSON

`envelope["features"]["values"]` becomes the 16 Chen16 names. Phase 4 consumes this. Also
add `envelope["features"]["family"]` so the Dart side can tell which vector it received
without inferring it from the key set.

### `cutter` telemetry in the envelope

The cutter now does real work and can decline. Add a `cutter` block to the envelope carrying
`status`, `head_removal_applied`, `kept_fraction`, and `removed_fraction`.

**`kept_fraction` is ours, not the vendor's.** `VALIDATION.md` states "The V144 cutter does
not compute or return a kept-area fraction," and `README.md` says the old `<80% kept area`
reviewer flag is deliberately excluded from the package's decision logic and API. Both are
correct and we keep them: this is `pre_cut_area / post_cut_area` computed in the app's own
`stages/cutter.cpp` adapter, **telemetry only, never a gate**. It is worth adding because
`fixed_test_predictions.csv` records `kept_fraction` and `removed_fraction` per training row
(median around 0.95), making it the one cutter output with a directly comparable training
distribution — and therefore the fastest on-device signal that the cutter is cutting the
wrong thing. Nothing in `pipeline.cpp` may branch on it without a decision recorded first,
or we have reintroduced the reviewer statistic the vendor removed on purpose.

Note this also diverges from the vendor's own ABI stance ("The production C ABI does not
expose Chen16 internals, body-curve internals, kept-area statistics"). That divergence is
deliberate and predates this plan: ref_fix F6–F11 added feature-vector persistence precisely
because a domain rejection was undiagnosable from a log. The app's envelope is a diagnostic
channel, and the UI contract — not the ABI — is what keeps model internals off the screen.

### The quality gates get a manifest switch

Per phase 2, both gates are ported but their activation is data. Add
`weight.quality_gates: {"truncation": bool, "posture": bool, "posture_max_bend_deg": 40.0}`.
The threshold is a validated research value (`README_AI_INTEGRATION.md` section 8 classes
changing it as an algorithm change requiring revalidation), so it travels in the manifest to
be *recorded*, not to be casually tuned. Gates follow the vendor's fail-closed convention:
an analysis failure rejects rather than passes the sample through.

## Steps

- [x] Rework `WeightCapability` to `feature_family` + `feature_order` + keyed
      `feature_domain` with `dimension` and `gate` per entry.
- [x] Rewrite `load_weight()`'s validation: family known, order exact, every name has a
      domain, dimensionless features carry no multipliers.
- [x] Update `ML/export/manifest.schema.json` and `export_xgboost.py` to emit the new block.
      (Found already done on entering this phase — see Results.)
- [x] Generalize `predict_weight` to an N-wide vector with a width check.
- [x] Replace the five gate calls in `pipeline.cpp` with a loop over the gated features.
- [x] Select `extract_five_features` vs `extract_chen16_features` on `feature_family`.
- [x] Emit the new `features` and `cutter` envelope blocks.
- [x] Update `src/test/test_feature_domain.cpp` for the keyed domain and the new exponents;
      add a case asserting a dimensionless feature with a multiplier fails to load.
- [x] Run the native ctest suite on the host.
- [x] Not in the original checklist, but explicitly promised by the Design/Approach section
      and by phase 2's `test_body_curve_dual_call.cpp` comment ("wiring the posture gate
      call is phase 3's job"): wire the truncation and posture quality gates into
      `pipeline.cpp` behind `manifest.weight.quality_gates`, on the whole pre-Ji/Duan mask
      in original capture coordinates.

## Results

**Python/schema side was already done.** On entering this phase, `ML/export/common.py`
(`FEATURE_FAMILIES`), `ML/export/export_xgboost.py` (per-family `dimension`/`gate` meta
tables, keyed `feature_domain`, `quality_gates`, `feature_family`), `ML/export/
manifest.schema.json`, and the regenerated `assets/ml/manifest.json`/`assets/ml/weight/*`
already matched this phase's design exactly — a prior session had done that half of the
work. This phase's own work was entirely the C++ side.

**`manifest.h`/`manifest.cpp`.** `WeightCapability` gained `feature_family` and a
`std::map<std::string, FeatureDomain>` `feature_domain` (replacing `domain_ra`..`domain_e`);
`FeatureDomain` gained `dimension` and `gate`. `load_weight()` now validates structurally:
`feature_family` (defaulting to `"baseline5"` when absent, for a pre-phase-3 fragment) must
be a known family, and `feature_order` must equal that family's canonical order — both
orders (`baseline5`, `chen16_noheight`) are kept as compiled-in constants in `manifest.cpp`,
mirroring `ML/export/common.py`'s `FEATURE_FAMILIES`, because the manifest is a swappable
asset and the native side must still refuse a vector whose order doesn't match the graph it
is about to run. A `dimension`/`gate` missing from a legacy manifest fragment falls back to
a per-name default table (`default_dimension_for()`) so an old baseline5 fragment gates
exactly as it always did — RA area, LC/BL/BW linear, E dimensionless, all five gated. A
dimensionless feature declaring a multiplier other than 1.0 now fails to load
(`INSTAHAM_ML_ERR_CONTRACT`) rather than being silently accepted.

**`stages/weight_prediction.{h,cpp}`.** `predict_weight` now takes `const
std::vector<float>&` and shape `{1, N}`; a width the loaded ONNX graph doesn't accept fails
inside `OnnxRunner::run()` rather than being truncated or padded. The old `FiveFeatures`
overload is kept, forwarding to the vector one, for the baseline5 rollback path.

**`pipeline.cpp`.** The five hardcoded `feature_in_domain`/`feature_extrapolated` call sites
became `run_feature_domain_gate()`/`extrapolated_feature_names()`, looping over
`manifest.weight.feature_order` and skipping any feature whose domain entry has `gate:
false` (`classify_domain_violation()` now keys off a violation's `dimension` field being
`"dimensionless"` rather than hardcoding the name `"E"`). Feature extraction now branches on
`feature_family` between `extract_five_features` and `extract_chen16_features`, and
`envelope["features"]` reports whichever `family`/`order`/`values` the manifest declared.
`envelope["cutter"]` now reports the real protocol id
(`v176_..._v144_..._v1`) and `protocol_implemented: true` (both were hardcoded to the old,
never-ported Python protocol string and `false` — a phase-2 leftover this phase's own goal
was to retire), plus new `kept_fraction`/`removed_fraction` telemetry computed in the app's
own adapter (`pre_cut_area / post_cut_area` on the mask actually handed to the cutter,
telemetry only, never a gate — the vendor's `VALIDATION.md` is explicit that the V144 cutter
itself does not compute this). The `weight.available`-gated branch's stale
`"cutter_identity_stub"` reason (now false — see the amended open question above) became
`"weight_pending_field_validation"`.

**Quality gates wired, not just switched.** Added `stages/quality_gates.{h,cpp}`, a thin
adapter over the phase-2-ported `EdgeTruncationDetector`/`PostureGate` in the same style as
`stages/cutter.cpp`'s vendor wrapper. `pipeline.cpp` runs both — gated independently by
`manifest.weight.quality_gates.truncation`/`.posture`, both `false` in the shipped manifest,
so this is inert on-device until a manifest edit turns either on — on the whole YOLO mask in
original capture coordinates, before Ji/Duan and before scale normalization, immediately
after the F16 implausible-mask check. A gate that rejects short-circuits the branch exactly
like the F16 check does, recording which gate (`truncation_gate_rejected` /
`posture_gate_rejected`) under a new `envelope["quality_gates"]` block. The posture gate's
`computeBodyCurve` call here is intentionally a second, independent invocation from the
Chen16 feature's own call on the final cut mask (phase 2, "Two body-curve calls, not one").

**Verification.**
- `test_feature_domain.cpp` gained five cases: a `chen16_noheight` manifest asserting the
  baseline5 order fails to load; an unknown `feature_family` fails to load; a full 16-wide
  chen16 manifest loads with correct keyed `dimension`/`gate`/`quality_gates` values; a
  dimensionless feature with a multiplier != 1.0 fails to load; `quality_gates` absent
  defaults both gates off. All pass, alongside the pre-existing cases (rewritten to the
  keyed `feature_domain.at("RA")` lookup).
- `test_cutter_identity`, `test_body_curve_dual_call`, `test_mask_selection`,
  `test_segmentation_canvas`, and `chen16_feature_gate_cli` (re-run against
  `ML/parity/chen16_feature_port_gate.py`, still 20/20 masks, 0 mismatches) all rebuild
  clean and pass. `test_scale_normalization` still fails at its pre-existing, out-of-scope
  LC-doubling assertion (unchanged from phase 2).
- No host target links `pipeline.cpp` itself (it needs the full `instaham_ml` library, which
  needs ORT, Android-only). Verified it instead by compiling the real
  `assets/ml/manifest.json` through the new `load_weight()` directly (forcing
  `weight.available: true` in a throwaway copy): it loads cleanly, resolves to
  `feature_family: chen16_noheight`, 16 `feature_order` entries, 16 keyed `feature_domain`
  entries with correct per-entry `dimension`/`gate` (e.g. `mask_area` area/gated,
  `body_curve` dimensionless/ungated), and both quality gates parse to their shipped
  `false`. Deleted the throwaway file afterward; nothing under `assets/ml/` was committed
  with `available: true`.
- `flutter build apk --debug --target-platform android-arm64` is green — this is the only
  build that actually compiles `pipeline.cpp`, `stages/quality_gates.cpp`, and the new
  `weight_prediction.cpp`/`manifest.cpp` together.

**Not done, deliberately out of this phase's scope:** touching any Dart file. `lib/features/
inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart` still reads
`features['RA']`/`['LC']`/etc. unconditionally — this plan's own file split assigns "Dart,
persistence, UI surface" to phase 4. Since `weight.available` stays `false` (per the amended
open question above), the chen16 envelope shape is not observed by Dart in practice yet; the
one case that would show through today is the renamed `weight_pending_field_validation`
reason string, which Dart's `_ => 'Weight branch unavailable ($reason).'` fallback already
renders correctly, just less politely than a dedicated phase-4 message would.

## Open questions

- **~~Should `weight.available` stay gated on anything now that the cutter is real?~~ —
  answer unchanged, one stale string fixed.** The recommendation from before this phase
  still holds: keep the flag until phase 5's field measurement, since it is the one switch
  that turns the branch off without a rebuild. What this phase did change is
  `pipeline.cpp`'s hardcoded envelope reason — `"cutter_identity_stub"` was a statement
  about the pipeline's own behaviour, not the manifest's separate (deliberately-kept)
  `unavailable_reason` field, and it became false the moment phase 2 landed a real cutter.
  It now reads `"weight_pending_field_validation"`. See Results.
