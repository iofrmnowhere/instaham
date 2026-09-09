# Test plan: host-side replication of the weight branch to settle `cm_per_px_target`

## Goal

Build a Windows host harness that runs the **actual shipped C++ pipeline stages** —
segmentation, construction, the k-resample, the vendor V176/V144 cutter, the Chen16 feature
extractor, and the XGBoost ONNX regressor — against the **current exported models** in
`assets/ml/`, and use it to decide between `cm_per_px_target = 0.35` and
`cm_per_px_target = 0.3289` on five PIGRGB images with known true weights.

This replaces the device-sweep method used in rounds 2 and 3. Those rounds needed 18
sideloaded scans per constant, and each scan carried hand-marking jitter of 5–13% because
the reference endpoints were placed by hand. The five PIGRGB images have their scale fixed
by acquisition geometry instead, so the jitter term disappears and the constant's effect is
measured directly.

The harness must be a **replication, not a reimplementation**. The existing Python reference
under `ML/pipeline/` is not acceptable for this test: `ML/pipeline/cutter.py` implements
protocol `ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`, while the app runs the
vendor chain declared in the manifest as
`v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1`. Since the
cutter has been identified as the dominant amplifier of prediction error, a Python-only run
would measure a stage the phone does not execute.

## Inputs

`Instaham/PIGRGB-Weight/sub_1.78/`, five 960×540 RGB PNGs captured at **1.78 m**:

| file | true kg |
|---|---|
| `60.27kg_35.png` | 60.27 |
| `66.24kg_11.png` | 66.24 |
| `100.9kg_3.png` | 100.90 |
| `125.38kg_4.png` | 125.38 |
| `133.42kg_5.png` | 133.42 |

Weight range 60–133 kg, wider than the 92–118 kg field set used in rounds 2 and 3.

## Design/Approach

### Where the scale comes from

`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` fixes the PIGRGB baseline at **304 px/m** on
the floor plane for a **1.88 m** capture at 960×540. Pixels per metre scale inversely with
camera height at fixed field of view and fixed image width, so for these 1.78 m images:

```
ppm_1.78      = 304 x (1.88 / 1.78) = 321.0787 px/m
cm_per_px_actual = 100 / 321.0787   = 0.3114504 cm/px
```

`0.3114504` is what the harness passes where the app passes the user-confirmed reference
object's measurement. It is **not** a free parameter and must not be tuned — see phase 4's
"What would invalidate this test".

### What is swept, and what is held fixed

Only `capabilities.weight.capture_contract.cm_per_px_target` is swept, over `{0.35,
0.3289}`. Everything else — the images, `cm_per_px_actual`, the segmentation canvas mode,
the models, every other manifest field — is held identical between the two arms. The
constant enters the pipeline at exactly one place, `pipeline.cpp:500`:

```
k = cm_per_px_actual / manifest.weight.cm_per_px_target
```

and `k` is then the resample factor for `scale_mask_to_training_space`. Nothing upstream of
that line reads `cm_per_px_target`, which is why the segmentation canvas decision can be
held fixed without confounding the comparison.

Derived values, precomputed here so the implementer can sanity-check the harness on its
first run:

| target | k | scaled mask dims | height_ratio | implied camera height |
|---|---|---|---|---|
| 0.35 | 0.889858 | 854 x 480 | 0.889858 | 1.673 m |
| 0.3289 | 0.946946 | 909 x 511 | 0.946946 | 1.780 m |

`height_ratio` equals `k` exactly here because `sqrt(960 x 540) = 720` and the training
frame is `720 x 720`, so the resolution term in `pipeline.cpp`'s height check cancels. Both
values sit inside the `[0.25, 4.0]` gate, so neither arm is rejected before it reaches the
regressor.

Note that the implied camera height at 0.3289 lands at 1.780 m, matching the images' actual
1.78 m capture height. **This is arithmetic, not evidence.** It is the geometry chain being
self-consistent — 0.3289 was derived from the same 304 px/m figure the harness uses to
compute `cm_per_px_actual`. It says nothing about which constant produces better weights,
and must not be reported as if it did.

### Structure

Everything for this test lives in one folder, `ML/host_scale_test/`, per the requirement
that the local test be self-contained:

```
ML/host_scale_test/
  README.md              how to build and run, written during phase 1
  CMakeLists.txt         standalone host build of the CLI
  weight_branch_cli.cpp  the harness binary's source
  run_sweep.py           driver: patches the constant, invokes the CLI, collects rows
  third_party/           generated onnxruntime.lib + copied onnxruntime.dll
  out/                   results.csv, per-image envelope JSON, build log
```

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Host toolchain and ONNX Runtime import library | done | `docs/test-plan-phase/1-host-toolchain.md` |
| 2 | The replication CLI | done | `docs/test-plan-phase/2-host-cli.md` |
| 3 | Driver and the two-arm sweep | done | `docs/test-plan-phase/3-driver-sweep.md` |
| 4 | Analysis, reporting, and what invalidates the result | not started | `docs/test-plan-phase/4-analysis.md` |

Work them in numerical order. Phase 2 cannot start until phase 1's build produces a linking
binary; phase 3 cannot start until phase 2's CLI produces a correct envelope for at least
one image.

## Phase 1 result — a real finding for later phases

Phase 1 built clean: all 39 translation units (app stages + vendor V176/V144 cutter + Chen16
features) compiled and linked under MSVC, and the resulting binary loaded the real
`assets/ml/manifest.json` and a real `xgboost.onnx` session through the generated import
library. Full detail in `ML/host_scale_test/README.md`.

One discovery changes how phase 2/3 must invoke their binary: **this machine has a
system-wide `C:\Windows\System32\onnxruntime.dll`** (from an unrelated installed
application) that only supports ORT API versions 1–10, against this project's version-17
headers. Windows' DLL search order tries the executable's own directory first, so the
correctly-built binary with its own 1.29.0 copy alongside it is unaffected — but if that
local copy is ever missing, the process does not fail cleanly. It silently loads the
System32 copy and segfaults inside `OrtGetApiBase`'s version dispatch, printing `The given
version [17] is not supported, only version 1 to 10 is supported in this build.` This
reproduced deterministically on the first attempt, not as a hypothetical. Phase 2's CLI and
phase 3's driver must always run from a directory where `onnxruntime.dll` sits next to the
`.exe`, and should recognize that specific message as this failure mode rather than a
pipeline bug if it recurs.

## Open questions

These are for the implementer to resolve during the phase that hits them, and to record in
that phase file rather than deciding silently.

1. **Segmentation canvas mode.** The app composes the 640×640 model canvas scale-aware,
   using `manifest.segmentation.input_scale.cm_per_px = 1.1`. For these images that gives
   `content_scale = 0.3114504 / 1.1 = 0.2831`, placing 960×540 as 272×153 inside the canvas
   — the pig may be too small to detect, and the ladder multipliers `[1.0, 1.32, 1.68,
   0.77]` mostly shrink it further. Plain letterbox (pass `cm_per_px_actual = 0` to
   `run_segmentation`) fits 960×540 as 640×360 instead, which is what the segmenter saw at
   training time. Phase 2 must try scale-aware first, fall back to letterbox if detection
   fails, and **record which mode was used**. Either is valid for this test as long as it is
   identical across both arms, because the canvas mode does not read `cm_per_px_target`.
2. **Host vs device ONNX Runtime version.** The host will link ORT 1.29.0 (the pip build
   already on disk); the device links whatever `third_party/onnxruntime/lib/android/
   arm64-v8a/libonnxruntime.so` is. Same graphs and same ops, but not bit-identical by
   construction. Phase 4 should state the host version in the report rather than claim
   device equivalence.
3. **Whether ground-truth masks exist for these five images.** `Instaham/PIGRGB-Weight/
   MASK_3394/` holds 51 masks, but its naming (`100.9_14`) does not match `sub_1.78`'s
   (`100.9kg_3`), so they are probably different captures. If a match is found, phase 4 can
   add an optional arm that feeds the ground-truth mask directly, separating segmentation
   error from scale error. Do not block on this.
4. **Five images is a small sample.** The result will be a direction, not a calibration. If
   both constants read high or both read low on all five, the finding is about the pipeline,
   not about the constant — say so rather than picking the closer one.

## Plan rating: 7/10

**Pros.** The test isolates a single variable at the one line where it enters the pipeline,
and it runs the shipped C++ rather than a Python stand-in, so a result transfers to the
device modulo the ORT version. It removes the 5–13% hand-marking jitter that made rounds 2
and 3 expensive to interpret, replaces an 18-scan sideload cycle with a host command, and
widens the weight range from 60–133 kg against the field set's 92–118 kg. Every host
dependency but one is already installed and verified. The harness is reusable: once built,
any future constant or cutter change can be swept the same way for the cost of one command.

**Cons.** Five images is a thin sample and cannot calibrate a constant, only rank two of
them. The standalone `CMakeLists.txt` duplicates source lists that live in
`packages/instaham_ml_ffi/src/CMakeLists.txt` and will drift; phase 1 adds a guard, but a
guard is not the same as a single source of truth. The ONNX Runtime import library is
generated from a pip DLL rather than an official SDK drop, which is sound but unusual enough
to need documenting. The PIGRGB images are the regressor's own training distribution, so
good agreement is weaker evidence than it looks — it partly measures memorization. And the
open question about segmentation canvas mode may force a deviation from the app's real path
on the very first run, which weakens the "identical to device" claim in a way phase 4 has to
report honestly rather than gloss.
