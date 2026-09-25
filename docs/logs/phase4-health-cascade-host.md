# Round 4 phase 2 — host cascade verification, raw rows

`docs/plan-phase-4/2-host-verification.md`. `health_protocol_measure_cli.exe` (extended with
`cascade_natural` / `cascade_forced` / `cascade_forced_no_region`, driving the shipped
`run_health_cascade()` — no re-derivation of its decision logic) run against
`assets/ml/manifest.json` and the same four fixtures round 3 used. All values below are
observed CLI output, not predicted.

| fixture | mask_available | full_frame label (P(Healthy)) | segmentation_masked label (P(Healthy)) | cascade_natural (second_stage / final label) | cascade_forced (second_stage / final label) | cascade_forced_no_region (second_stage / final label) |
|---|---|---|---|---|---|---|
| 01 (92 kg) | true | Healthy (0.676) | Infected_Environmental_Sunburn (0.0031) | not_needed_healthy / Healthy | ran / Infected_Environmental_Sunburn | no_region / Healthy |
| 02 (96 kg) | true | Healthy (0.972) | Infected_Bacterial_Erysipelas (0.0044) | not_needed_healthy / Healthy | ran / Infected_Bacterial_Erysipelas | no_region / Healthy |
| 03 (75 kg) | true | Healthy (0.907) | Infected_Environmental_Sunburn (0.0016) | not_needed_healthy / Healthy | ran / Infected_Environmental_Sunburn | no_region / Healthy |
| 06 (lesion closeup) | false | Infected_Environmental_Sunburn (0.164) | Infected_Environmental_Sunburn (0.164, degraded to full frame — no mask) | no_region / Infected_Environmental_Sunburn | no_region / Infected_Environmental_Sunburn | no_region / Infected_Environmental_Sunburn |

`cascade_natural` uses the manifest exactly as shipped (`healthy_label: "Healthy"`).
`cascade_forced`/`cascade_forced_no_region` use a capability copy whose `healthy_label` is
`"__no_such_class__"`, so the cascade always tries to run its second stage when a region is
available — the same copy-the-capability trick round 3 used for the black-fill follow-up, no
`health_input.cpp`/`classifier.cpp` change needed to force it.

## Check 1 — natural run, healthy results unchanged

01/02/03: `cascade_natural`'s label is `Healthy` in every case, `second_stage` is
`not_needed_healthy`, and `final_stage` is `full_frame` — identical to `results.full_frame`
above. Healthy results are unaffected by the cascade being enabled. **Pass.**

## Check 2 — forced second stage reproduces round 3's masked measurement

01/02/03: `cascade_forced`'s final label under `ran` is exactly `results.segmentation_masked`'s
own label in the same row (Sunburn / Erysipelas / Sunburn), matching round 3's recorded rows
(`docs/logs/phase3-health-protocol-measurement.md`) exactly. **Pass** — the cascade is feeding
the second pass the same region and protocol round 3 measured, not a different one.

## Check 3 — no-region route

06 has no segmentation detection on this photo (`mask_available: false`), so both
`cascade_natural` and `cascade_forced` already report `no_region` without needing the explicit
null-region call; `cascade_forced_no_region` (region forced to `nullptr`, matching exactly what
`pipeline.cpp`'s `health_only` route passes) confirms the same `no_region` decision
independent of whatever segmentation happened to find on this particular photo. All three
report `second_stage: "no_region"` and fall back to the first pass's own label. **Pass.**

## Timing

A full CLI run (two ONNX Runtime session loads, one segmentation pass, five protocol
comparisons, three cascade calls) on fixture 01: ~8.8 s wall clock, in line with phase 1's own
timing note (dominated by model loading, not by the extra classifier pass). No stderr
diagnostics on any of the four runs.

## Known gap, unchanged from round 3

No whole-pig disease photograph exists in this repo, so nothing here measures whether the
cascade's final label is the *correct* disease — only that it reproduces round 3's own
mask + crop measurement exactly. That gap stays open.
