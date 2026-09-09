# Cutter, part 2 — quality gates, wiring state, and build implications

Continues [cutter.md](cutter.md). That file covers what the stage runs, its `status` values,
and why there is no reference implementation to diff a single cut against.

## Two body-curve calls, never one

`computeBodyCurve()` is invoked twice per capture, on two different masks, and the numeric
result must never be cached and reused across them:

1. **Posture gate** — on the whole mask, *before* Ji/Duan. Feeds the posture decision only
   (`bend = 180 - body_curve`, reject above 40°).
2. **Chen16 feature 5 of 16** — recomputed on the **final cut mask**, in
   `extract_chen16_features()`.

A shared-value regression here would be invisible and would quietly corrupt one of the
sixteen regressor inputs, so `src/test/test_body_curve_dual_call.cpp` asserts the two differ
on a mask where a cut actually happened. That test needs a deliberately non-collinear mask: a
straight silhouette yields a degenerate 180° from both calls, which would pass the assertion
for the wrong reason.

## Quality gates: wired, shipping dark

`EdgeTruncationDetector` and `PostureGate` are ported into the vendor tree because the
training protocol ran both *before* Ji/Duan — a pipeline without them accepts photos the
training protocol rejected. Their `*_ffi` layers are deliberately not taken; this library has
one consolidated C ABI.

`src/stages/quality_gates.{h,cpp}` is the app's adapter over them, and `pipeline.cpp` now runs
both — on the **whole mask in original capture coordinates**, after `unletterbox_native_mask`
and before both Ji/Duan and `scale_mask_to_training_space`. Each is switched by its own
manifest flag under `weight.quality_gates`:

| Manifest flag | Shipped value | Rejection reason |
|---|---|---|
| `weight.quality_gates.truncation` | `false` | `truncation_gate_rejected` |
| `weight.quality_gates.posture` | `false` | `posture_gate_rejected` |
| `weight.quality_gates.posture_max_bend_deg` | `40.0` | — |

Both are `false` in `assets/ml/manifest.json`, so they measure nothing on device today. That
is deliberate: switching them on is a manifest edit, not a rebuild, and their real on-device
rejection rate has not been measured yet (plan phase 5). When either flag is on the gate
result is reported under `envelope["quality_gates"]` whether or not it rejected, so the
rejection rate is observable before the gate is trusted. Truncation is evaluated first and
names the reason when both reject — an ordering artefact, not a precedence rule.

Gates never call each other and never return user-facing strings: `pipeline.cpp` owns
sequencing, the Dart layer owns messages (`run_and_persist_pipeline_use_case.dart` maps both
reasons to their own retake instruction).

## Wired into the weight branch; still not the source of a shipped number

Since plan phase 3 the weight branch runs this cutter for real. `pipeline.cpp` writes the true
protocol id and `protocol_implemented: true`:

```json
"cutter": {
  "status": "cut_applied",
  "head_removal_applied": true,
  "protocol_version": "v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1",
  "protocol_implemented": true,
  "kept_fraction": 0.94,
  "removed_fraction": 0.06
}
```

`kept_fraction` is `post_cut_area / pre_cut_area`, computed in **this app's adapter**, not by
the vendor code — `VALIDATION.md` records that the V144 cutter deliberately does not return a
kept-area fraction, and that omission is preserved. Both fractions are **telemetry only**:
nothing in C++ or Dart branches on them, and they never reach the UI. The pre-cut area is the
same mask handed to the cutter (scaled or unscaled), so the number is comparable across runs.
Dart persists it to `weight_results.cutter_kept_fraction`; the training CSV records the same
quantity per row (median ≈ 0.95), which makes it the fastest signal that the cutter is cutting
the wrong thing.

Two things still are **not** true, and neither is a cutter defect:

- The calibration is still unvalidated, so a shipped estimate is provisional. `weight.available`
  was `false` for this reason; it is now `true` under the `--enable-for-testing` re-export
  (F42) for on-device work, which makes `weight_pending_field_validation` unreachable rather
  than resolved. `cm_per_px_target` was fitted with the identity stub in the loop, the
  specification's alternative measured worse (F46, [prediction-2.md](prediction-2.md)), and
  phase 5 still owes a re-derivation from post-cut field masks.
- The standalone `instaham_ml_predict_weight_json` entrypoint (`src/instaham_ml.cpp`) was
  **not** rewired. It calls `cut_body_mask()` but still reports `qc.cutter: "identity_stub"`,
  `cutter_protocol_implemented: false`, the old `ji_duan_…_v26` protocol string, and a
  `baseline5` feature block. It is a debug-only path; `pipeline.cpp` is the shipped one. Do
  not read its payload as a statement about the pipeline.

[ADR-001](../adr/001-cutter-identity-stub.md) is now `Superseded by
`[009](../adr/009-cutter-ported-after-all.md). This reverses an earlier deferral recorded here,
which held the superseding ADR back until cut parity was proven against the CSV telemetry above,
on the grounds that "an ADR claiming a verified port before the verification exists would be the
wrong record." That concern is met by scoping ADR-009 to what is verifiable: it records **that
the port shipped and runs**, which is checkable in `pipeline.cpp` today, and states explicitly
that its field effect is unverified and that no accuracy claim may cite it until a device run
exists. The deferral's reasoning was sound; leaving ADR-001 asserting the stub is "permanent,
not a placeholder awaiting a port" while shipped code contradicts it was the larger error.

Cut parity against the CSV telemetry remains unproven and is still owed. The +16.6% uncut-mask
bias in [prediction-2.md](prediction-2.md) and
[ADR-005](../adr/005-identity-cutter-is-the-dominant-error.md) describes the **last measured**
field behaviour, taken before this rewiring; it has not been re-measured since.

## Build implications

Every vendor source is unconditionally OpenCV-dependent, so they compile only under
`INSTAHAM_ML_WITH_OPENCV`. That option now defaults **on for every platform**, not just
Android: `stages/cutter.cpp` used to be header-only and let the host `ctest` build skip
OpenCV, and it no longer is. The host build links a desktop OpenCV (vcpkg) rather than the
Android-only opencv-mobile prebuilt, which ships no desktop libraries — see
[../architecture.md](../architecture.md) for where the vendor tree sits in the native library.
