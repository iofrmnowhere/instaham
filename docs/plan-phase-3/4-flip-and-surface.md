# Phase 4 — flip the default, fixtures and surfacing

Status: not taken — phase 3 recommended against flipping (`docs/plan-phase-3/3-measurement.md`
"Recommendation for phase 4"). `assets/ml/manifest.json` keeps `protocol: "full_frame"`, and
nothing in this phase's steps was executed. Left in place, unedited below, as the record of
what a future flip would have to do if a retrained checkpoint someday justifies it.

## Goal

If and only if phase 3 recommends it, make a region protocol the shipped default and bring
every downstream artefact that records the old default into line.

## Design/Approach

This phase is deliberately separate from phase 1 so that shipping the capability and changing
behaviour are two decisions, not one. If phase 3's recommendation is "do not flip", this phase
closes as not taken and the code stays available behind the manifest.

### What changes when the default flips

- **`assets/ml/manifest.json`** — `capabilities.health.input.protocol` moves from
  `"full_frame"` to the chosen protocol. `supported` already lists both region protocols.
  `probe_status` is still `not_run` and `evidence` still says "not probed"; phase 3's
  measurement is the evidence, so these fields should be updated to point at it rather than
  left stating that nothing was checked.
- **Recorded fixtures.** `test/fixtures/scenarios/*/meta.json` carry
  `input_protocol_applied: "full_frame"`, `input_protocol_requested: "full_frame"` and
  `input_degraded: false` — 01, 02 and 03 also carry `region_source: "mask"`, while 06 and 08
  carry `"none"`. These are recorded expectations, not observations, and they will all need
  regenerating. Their health probabilities will move too, which is the point.
- **`docs/spec.md`** — the model I/O contract changes shape (the health input is no longer the
  whole frame), so `spec-drift` should be run after this phase, per AGENTS.md.
- **`pipeline-docs`** — the health stage's input changes, and the coordinate recovery is an
  architectural seam worth an ADR. Flag it; do not write the ADR here, that skill owns it.

### Surfacing to the user

`input_protocol_applied`, `input_protocol_requested`, `input_degraded` and `region_source` are
already in the envelope but nothing in `lib/` reads them — grep finds them only in fixture
files. Two questions follow, and both are for the user:

1. Should a scan whose health input degraded to full frame say so on the results screen? It is
   a meaningful caveat: the health verdict was made on a different kind of input than the one
   the app intends. AGENTS.md's "never display invented model state" argues for showing it.
2. Should the degraded flag be persisted? The database currently stores no health-input fields.
   Adding one is a schema change — `schemaVersion` increment, explicit migration, regenerated
   Drift output and a migration test — so it is not a free addition and should not be folded in
   without being asked for.

Default position if not asked: do neither. Surface nothing, persist nothing, and leave both as
recorded open questions. Adding UI and schema on the back of an inference change would be
exactly the unrelated-work combination AGENTS.md forbids.

### The `health_only` route

`pipeline.cpp:328` skips segmentation entirely on the `health_only` route, because the region
protocols were stubs and the YOLO pass fed nothing. Once a region protocol is the default, that
route runs full frame while the dorsal route runs masked — the two branches no longer agree on
what the health model eats. Either accept that and document it, or re-enable segmentation on
that route and pay its cost. This phase must state which, explicitly, rather than leaving it
implicit in the code.

## Steps

- [ ] Confirm phase 3's recommendation is a flip. If not, close this phase as not taken and
      record why.
- [ ] Update `assets/ml/manifest.json`'s `protocol`, and its `evidence` / `probe_status` to
      cite phase 3.
- [ ] Regenerate the affected `test/fixtures/scenarios/*/meta.json` envelopes.
- [ ] Decide and document the `health_only` route's behaviour.
- [ ] Run `spec-drift`.
- [ ] Flag `pipeline-docs` for the health-input stage doc and an ADR on the coordinate
      recovery.
- [ ] Ask the user about surfacing and persistence rather than deciding either.

## Verification

- Full `flutter test` — this phase changes recorded fixtures, so it is cross-cutting.
- `flutter analyze` — expect the same 8 pre-existing issues and no new ones.
- `ctest` — expect `test_abi` and `test_scale_normalization` still failing and nothing else.
- Report the exact commands and their output. No success claimed without it.

## Open questions

1. Surfacing the degraded flag in the UI — user's call.
2. Persisting it — user's call, and a schema change if yes.
3. The `health_only` route's divergence — decided in this phase, but worth the user's opinion
   since it trades capture time against consistency.
