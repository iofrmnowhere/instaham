# Phase 1 — native cascade and manifest switch

Status: done

## Goal

Make the native pipeline run the health classifier in two stages when the manifest says so:
`full_frame` first, then `segmentation_masked` only when the first result is not the healthy
class, with the second result reported as the final one. With the manifest switch off, the
output must be byte-for-byte what it is today.

## Design/Approach

### Manifest: `capabilities.health.cascade`

New block in `assets/ml/manifest.json`, next to `input`:

```json
"cascade": {
  "enabled": true,
  "healthy_label": "Healthy",
  "second_stage_protocol": "segmentation_masked",
  "evidence": "docs/logs/phase3-health-protocol-measurement.md; docs/plan-4.md"
}
```

- Parsed in `manifest.cpp` beside the existing `input` fields (`manifest.cpp:141-147`) into
  new `ClassifierCapability` fields (`manifest.h`, health-only, like
  `health_bbox_padding_ratio`): `health_cascade_enabled`, `health_healthy_label`,
  `health_second_stage_protocol`.
- Absent block, `enabled: false`, or an unknown `second_stage_protocol`: cascade off.
- `healthy_label` is checked against `class_names` after `load_class_names()`
  (`manifest.cpp:176`). If it is not in the class map, the cascade is turned off and the
  reason is kept for the envelope (`cascade.disabled_reason`). A missing label must not fail
  the manifest load (AGENTS.md rule 4).
- The first stage keeps using `input.protocol` (`full_frame`), so the existing switch is not
  overloaded with a second meaning.
- `ML/export/build_manifest.py:111-113` copies `health.input` from a fragment when it
  rebuilds the manifest. Add the same pass-through for `health.cascade`, so a rebuild does
  not silently drop the block.

### The decision, as a pure function

In `health_input.{h,cpp}`, beside `pig_region_from_base_mask()`:

```cpp
enum class HealthSecondStage { kNotNeededHealthy, kRun, kDisabled, kNoRegion };
HealthSecondStage decide_health_second_stage(bool cascade_enabled,
                                             const std::string& first_label,
                                             const std::string& healthy_label,
                                             const PigRegion* region);
```

No ORT, no image, so `test_health_input.cpp` can cover every branch directly. `kNoRegion`
covers a null region, an invalid box, and `has_mask == false`: the masked protocol needs a mask,
and falling back to full frame would just repeat the first pass.

### The cascade, one function for every caller

In `classifier.{h,cpp}`, beside `run_classifier()`:

```cpp
bool run_health_cascade(OnnxRunner* runner, const ClassifierCapability& cap,
                        const std::string& image_path, const PigRegion* region,
                        std::string* out_json, int* error_code_out);
```

1. Run `run_classifier()` with `HealthInputOptions{parse(cap.input_protocol), region}`, which is
   exactly today's call. If it fails, return its error envelope unchanged, as today.
2. Ask `decide_health_second_stage()`. Anything but `kRun`: final = first.
3. `kRun`: run `run_classifier()` again with the second-stage protocol and the same region.
   - Success, and `input_degraded == false`: final = second.
   - Success but `input_degraded == true` (the mask turned out empty, so it quietly ran full
     frame): final = first, reason `second_stage_degraded`.
   - Failure: final = first, reason `second_stage_failed`, second error message kept. The
     health result is never lost because the second pass broke.
4. Output: the final stage's envelope at the top level (so `label`, `confidence`,
   `probabilities`, `input_protocol_*` and `region_source` stay where Dart and the fixtures read
   them), plus:

```json
"cascade": {
  "version": "cascade_v1",
  "enabled": true,
  "second_stage": "not_needed_healthy | ran | no_region | second_stage_degraded | second_stage_failed | disabled",
  "final_stage": "full_frame | segmentation_masked",
  "first": { "label": "...", "confidence": 0.0, "probabilities": { } },
  "disabled_reason": "only when the cascade is off because of the manifest"
}
```

With the cascade off, `run_health_cascade()` returns exactly `run_classifier()`'s output with
**no** `cascade` key, so turning the switch off really restores today's bytes.

### Call sites

- `pipeline.cpp:496-518`: replace the single `run_classifier()` call with
  `run_health_cascade()`, passing the region it already builds. Nothing else in the block moves.
- `instaham_ml_classify_health_json` (`instaham_ml.cpp:174-178`) has no segmentation and never
  builds a region. It is not the app's path (the results screen runs the full pipeline), so it
  stays single-stage and is not changed. This is noted in `docs/ffi-bridge.md` in phase 4.

### Timing

Measure the extra time on the host for one image (decode plus one GhostNet pass), and write it
down in this file. A second decode is accepted unless it turns out to be a noticeable share of
the scan. In that case, open subphase 1.1 for a `run_classifier()` overload that takes the
decoded image, rather than folding the refactor into this phase.

## Steps

- [x] Add `health_cascade_*` fields to `ClassifierCapability` and parse `health.cascade` in
      `manifest.cpp`, including the `healthy_label` class-map check.
- [x] Add `decide_health_second_stage()` to `health_input.{h,cpp}`.
- [x] Add `run_health_cascade()` to `classifier.{h,cpp}`.
- [x] Switch `pipeline.cpp`'s health block to `run_health_cascade()`.
- [x] Add the `cascade` block to `assets/ml/manifest.json`, and the pass-through to
      `ML/export/build_manifest.py` (also added a `cascade` entry to
      `ML/export/manifest.schema.json`, matching the existing `input` block's pattern).
- [x] `test_health_input.cpp`: new group 7 for `decide_health_second_stage()`, covering all
      four outcomes, a label that is only a case-variant of the healthy one (must not match),
      an empty healthy label, a bbox-only region (no mask), and an invalid box.
- [x] Manifest test: new `test_health_cascade_manifest.cpp` (synthetic fixture, same pattern as
      `test_feature_domain.cpp`) covering block absent, explicitly disabled, valid, an unknown
      `second_stage_protocol`, and a `healthy_label` missing from the class map -- all load
      successfully with the cascade off in the last two cases. Also pinned the shipped
      values (`health_cascade_enabled == true`, `healthy_label == "Healthy"`,
      `second_stage_protocol == "segmentation_masked"`) onto `test_shipped_manifest.cpp`,
      matching that file's existing pattern for the weight capability.
- [x] Build `packages/instaham_ml_ffi/src/build/host` with `ninja` (full rebuild, no errors).
      `ctest -E test_abi --timeout 400`: 10/11 passing. The one failure is
      `test_scale_normalization`, the same pre-existing failure recorded in every prior
      session's handoff -- no new failure. `python -m pytest ML/parity/test_health_input.py`:
      13 passed, unchanged. Manifest schema re-validated with `jsonschema` against the live
      `assets/ml/manifest.json`: OK.
- [x] Record the second-pass timing here: measured `assets/ml/health/model.onnx` directly with
      `onnxruntime` (CPU, host) on `test/fixtures/scenarios/01_valid_dorsal_100cm_reference/
      image.jpg` -- JPEG decode ~22 ms/run (10 runs), GhostNetV3 inference ~10 ms/run (20 runs,
      after warmup). A forced second pass therefore adds on the order of 30-40 ms to a scan
      that (per `docs/logs/recorded.md`) already takes seconds end to end for segmentation and
      the weight branch. Not a noticeable share; the second decode (open question 3 below,
      and plan open question 3) does not need a refactor.

## Open questions

- Should `second_stage_protocol` accept `segmentation_crop` too? The parser can allow it,
  because both are implemented. The shipped value is `segmentation_masked`, as the user asked.
- Resolved: the second decode's cost (~22 ms) is not worth a `run_classifier()` overload that
  takes an already-decoded image. Revisit only if a slower device build shows otherwise.
