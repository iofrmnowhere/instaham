# Phase 2 — host verification on real captures

Status: done

## Goal

Show, using the shipped `run_health_cascade()` and the real models, that the cascade behaves as
designed on every real capture the repo has, including the branch that never triggers by itself
on today's photos.

## Design/Approach

Extend `packages/instaham_ml_ffi/src/test/health_protocol_measure_cli.cpp` (round 3's
measurement CLI) with a `cascade` mode. It builds the region with the same
`run_segmentation` → `construct_pig_mask` → `pig_region_from_base_mask()` chain it already uses,
then calls `run_health_cascade()`. It must not re-implement the decision logic.

Three checks:

1. **Natural run.** Fixtures `01_valid_dorsal_100cm_reference`, `02_valid_dorsal_131cm_porac_reference`
   and `03_valid_dorsal_custom_reference` with the shipped manifest. Expected: all three are
   `Healthy` under full frame, so `second_stage: "not_needed_healthy"`, and the top-level
   label, confidence and probabilities are identical to the cascade-off output
   (92 kg Healthy 0.68, 96 kg Healthy 0.97, 75 kg Healthy 0.91). This checks that healthy
   results are unchanged.
2. **Forced second stage.** The same three fixtures, with the CLI's own copy of the capability
   given a `healthy_label` that matches no pig result (the same copy-the-capability trick round 3
   used for black fill, so `manifest.json` is untouched). Expected: `second_stage: "ran"`,
   `final_stage: "segmentation_masked"`, and final labels and probabilities matching round 3's
   recorded mask + crop rows exactly: 92 kg Sunburn, 96 kg Erysipelas, 75 kg Sunburn
   (`docs/logs/phase3-health-protocol-measurement.md`). A mismatch means the cascade is feeding
   the second pass a different region or protocol than round 3 measured, so stop and diagnose.
   Do not loosen the check.
3. **No-region route.** `06_lesion_closeup` through the pipeline's `health_only` route (no
   segmentation, no region). Expected: `second_stage: "no_region"`, final = first stage.
   Whatever label the first stage gives is recorded as observed, not judged.

Also record, per image: whether the second pass ran, and the extra wall-clock time it added.

Each run gets its own `dump_dir` (every fixture is named `image.jpg`). JSON is taken from the
CLI's last line (`tail -1`), because OpenCV prints an `[ INFO ]` line to stdout first.

## Steps

- [x] Add the `cascade` mode (and the forced-healthy-label option) to
      `health_protocol_measure_cli.cpp`: three new envelope keys, `cascade_natural` (the
      manifest as shipped), `cascade_forced` (a capability copy with an unmatchable
      `healthy_label`, forcing the second stage whenever a region is available), and
      `cascade_forced_no_region` (the same forced capability with `region` passed as
      `nullptr`, matching `pipeline.cpp`'s `health_only` route exactly). All three call the
      shipped `run_health_cascade()` directly.
- [x] Rebuilt the target (`ninja health_protocol_measure_cli`) — clean build, no ORT/OpenCV
      warnings.
- [x] Ran checks 1-3 on fixtures 01, 02, 03 and 06 and wrote the raw rows to
      `docs/logs/phase4-health-cascade-host.md`, every value labelled observed.
- [x] All three checks pass:
      - **Check 1 (natural, healthy unchanged):** 01/02/03 all report
        `not_needed_healthy` / `Healthy`, identical to the pre-cascade `full_frame` result.
      - **Check 2 (forced second stage matches round 3):** 01/02/03's forced final labels
        (Sunburn / Erysipelas / Sunburn) match round 3's recorded mask + crop rows exactly.
      - **Check 3 (no-region route):** 06 (no segmentation detection on this photo) reports
        `no_region` on all three cascade variants, including the explicit null-region call,
        and falls back to the first pass's own label.
      See `docs/logs/phase4-health-cascade-host.md` for the full table.

## Open questions

- None about the method. The known gap is that no whole-pig disease photo exists, so no check
  here measures whether the final disease label is *correct*. It only shows that the cascade
  produces the label round 3's masked pass produces. This stays stated as a limitation, not
  papered over.
