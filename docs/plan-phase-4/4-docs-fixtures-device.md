# Phase 4 — contract docs, fixtures and device check

Status: done

## Goal

Bring the recorded contract and fixtures into line with the cascade, and hand the user an APK
to check on their own phone.

## Design/Approach

- **`spec-drift`.** `assets/ml/manifest.json` changed (new `health.cascade` block), and the
  health envelope gained a `cascade` object. AGENTS.md requires `spec-drift` after a manifest
  change.
- **`pipeline-docs`.** The health stage can now run the model twice, and its output shape grew.
  That is a stage-order and envelope change, so `pipeline-docs` is run for
  `docs/pipeline/*`, `docs/architecture.md` and `docs/ffi-bridge.md`. Flag whether it deserves
  an ADR ("the whole photo decides healthy; the isolated pig gives the second reading of a
  condition"). The ADR itself belongs to `pipeline-docs`, not this plan.
  `docs/ffi-bridge.md` should also record that `instaham_ml_classify_health_json` stays
  single-stage because it has no region.
- **Scenario fixtures.** `test/fixtures/scenarios/*/meta.json` hold recorded expectations for
  the health envelope. For 01, 02 and 03 the top-level values must not move (phase 2, check 1),
  so only the new `cascade` fields are added, with `second_stage: "not_needed_healthy"`. For 06,
  add `second_stage: "no_region"`. These are expectations, and each one must be set from
  phase 2's observed output, not guessed. If any top-level health value in 01-03 would have to
  change, stop: that contradicts phase 2.
- **`docs/app-flow.md`.** One line in the health step describing the two stages.
- **Device check.** Build a release APK. The user sideloads it onto their own phone and scans the
  existing pig photos from the gallery. Expected: healthy pigs show the same result as before.
  Because no live pig is available, the second-pass wording is checked on host only (phase 2,
  check 2, plus phase 3's widget test), unless the user has a gallery photo that the whole photo
  flags. No Firebase Test Lab run is part of this phase.

## Steps

- [x] Run `spec-drift` and resolve what it reports. (2026-09-25: no unintended drift. The
      health section of `docs/spec.md` was stale from rounds 3 and 4 and has been updated in
      place.)
- [x] Run `pipeline-docs`, and flag the ADR question to the user. (2026-09-25: new
      `docs/pipeline/health.md` with a redirect-table row; `docs/architecture.md` and
      `docs/ffi-bridge.md` updated. ADR-019 approved by the user and written:
      `docs/adr/019-whole-photo-decides-healthy-masked-pig-rechecks.md`.)
- [x] Update the 01, 02, 03 and 06 fixture `meta.json` files from phase 2's observed output.
      (2026-09-25: added `expected_outcome.health_branch.cascade` with `second_stage`,
      `final_stage`, `final_label` and `source`, taken from the `cascade_natural` column. 01-03
      are `not_needed_healthy` / `Healthy`; 06 is `no_region` / `Infected_Environmental_Sunburn`.
      No existing value changed, and `observed_phase4` was left alone. No test asserts the new
      field yet. `generate_fixtures.py` was not updated; it already overwrites
      `observed_phase4`, so a regeneration would drop these fields too.)
- [x] Add the one-line note to `docs/app-flow.md`. (2026-09-25: a "Health | ok, re-checked" row
      in the result-states table.)
- [x] Build the APK and hand it to the user with the checks above. Record their result here.

## Device result (2026-09-25)

The user built `flutter build apk --release`, sideloaded it onto their own phone, and scanned
existing pig photos from the gallery. Reported result, in the user's words: "all working great
... it detects healthy as healthy and the disease one gets reanalyzed for further clarity."

- Photos the whole-photo pass calls `Healthy` stayed `Healthy`, with no re-check wording.
- A photo the whole-photo pass flagged as a condition went through the masked second pass and
  showed the re-check wording.

This is the user's summary, not a per-photo log. The final disease labels shown on the phone
were not reported, and there is still no ground truth for whether a disease label is correct.
- [x] Close out: add the round 4 line to `docs/changelog.md` and mark `docs/plan-4.md` done.
      Close round 3 (`docs/plan-3.md`) at the same time, since its only open question was this
      cascade.

## Open questions

- None beyond the plan's own. `docs/logs/phase3-mask-dumps/` (about 53 MB of BMPs) still has to
  be deleted or gitignored before any commit. That is a round 3 leftover, raised again here so
  it is not forgotten.
