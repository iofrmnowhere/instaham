# ADR-007: The weight feature family is manifest data, on both sides of the FFI seam

Status: Accepted

## Context

The weight regressor was swapped from a 5-feature `baseline5` XGBoost model
(`RA, LC, BL, BW, E`) to a 16-feature `chen16_noheight` model. The 5-feature contract was
written into the code and the schema in five separate places: `WeightCapability`'s five named
`domain_ra`…`domain_e` members, five hardcoded call sites in `pipeline.cpp`'s domain gate,
`predict_weight()`'s fixed-width signature, five `feature_*` columns in the Drift
`WeightResults` table, and a hardcoded `['RA','LC','BL','BW','E']` order in the Dart rejection
renderer.

Reproducing that pattern at width 16 would mean sixteen named members, sixteen columns, a
sixteen-entry Dart list, and a schema migration on the next model change — while also putting
seven signed Hu moments into a user-facing rejection message and into the database as named
columns. AGENTS.md rule 1 already forbids hardcoding class indices for the classifiers; the
same argument applies to feature identity.

## Decision

The feature contract is data, declared once in `assets/ml/manifest.json` and carried through
every layer without being re-stated:

- **Native.** `WeightCapability` holds `feature_family` (`baseline5` | `chen16_noheight`), an
  arbitrary-width `feature_order`, and `feature_domain` as a `map<string, FeatureDomain>`.
  Each entry carries `min`/`max`, the widening multipliers, a `dimension`
  (`area` | `linear` | `dimensionless`, which is the exponent on the calibration-uncertainty
  widening) and a `gate` flag (eligibility check vs. diagnostic-only bound). `pipeline.cpp`'s
  gate and extrapolation loops walk `feature_order`; `predict_weight()` takes a
  `std::vector<float>` and refuses a width the loaded ONNX graph disagrees with.
  `classify_domain_violation()` reads each violation's `dimension`, never a feature name.
- **Envelope.** `envelope["features"]` carries `family`, `order`, `values`, `measured_on`, and
  a `gated` array naming the subset the gate enforces.
- **Dart/Drift.** The vector is persisted as a family-tagged JSON blob
  (`weight_results.feature_vector` = `{"family":…,"values":{…}}`) plus a queryable
  `feature_family` discriminator, not as per-feature columns. The rejection renderer maps the
  envelope's own `gated` list to plain-language labels rather than keeping a second hardcoded
  order.

Only two things stay compiled in, deliberately: a per-family canonical order that
`load_manifest()` checks `feature_order` against, and a per-family branch selecting which
extractor runs. The manifest is a swappable asset, so the binary must still be able to refuse
a vector whose width or order does not match the graph it is about to run
(`INSTAHAM_ML_ERR_CONTRACT`).

## Consequences

- A future feature-family change is an export + manifest change plus one extractor, with no
  Drift migration, no schema churn, and no Dart edit.
- The five `feature_ra`…`feature_e` columns are kept but deprecated and no longer written.
  They hold real field measurements from scans taken before `schemaVersion` 4 — the data
  `docs/fix-phase/6-device-telemetry-findings.md` was built from — and dropping them would
  lose that history. Anything reading them gets pre-phase-4 rows only.
- Feature values are no longer queryable in SQL without JSON extraction. Accepted: nothing in
  the app queries by feature value, and `feature_family` covers the one filter that was
  plausible.
- Only the six features the scale actually moves (`mask_area`, `convex_hull_area`,
  `difference`, `perimeter`, `longest`, `shortest`) are gated. Every dimensionless feature,
  including all seven Hu moments, is recorded and never enforced — a Hu-moment rejection is
  not something a user can act on. A side effect is that `mask_shape_out_of_domain`, which
  fires on a dimensionless violation, is unreachable under `chen16_noheight`; the
  mask-plausibility check (`min_mask_diagonal_fraction`) and the posture quality gate are what
  catch a degenerate mask now.
- The domain bounds are derived from a 1821-row held-out test split, so they are slightly
  stricter than the model's true competence. Widening them is plan phase 5's open question 2.
