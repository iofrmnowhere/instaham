# ML Inference Integration — INSTAHAM Flutter App (Native C++ / `dart:ffi`)

> **Revision 7 (2026-08-30).** Revision 6 organised the Python by *runtime* — one file for the
> code that would be ported to C++, one for the code that would not. That was the right axis when
> the cutter was expected to ship as on-device Python. It is the wrong axis now.
>
> **(1) The Python is reorganised by PROCESS, not by runtime.** `ML/refactor_plan.md` states the
> pipeline as a chain of stages and asks for five source files, one per process:
>
> ```
> picture -> yolo segmentation -> construct pig mask -> cutter pig mask
>         -> calculate 5 features / 16 features -> weight prediction
> ```
>
> Revision 6's two files do not line up with those stages: `ML/pig_geometry.py` contains stages 1,
> 2 and 4 plus the chen16 variant in one 944-line module, and the C++ target was a single
> translation unit covering the same mixture. Revision 7 replaces both with
> `ML/pipeline/{segmentation,construction,cutter,feature_calculation,weight_prediction}.py`, merged
> **from the originals in `.old_py_files/`** rather than re-split out of the consolidated files —
> because a merge from the originals is auditable against them function by function, and a re-split
> of a previous merge is only auditable against the merge.
>
> **(2) The cutter becomes a C++ identity dummy. The Chaquopy programme is deleted.** Revision 6
> deferred a three-way choice (on-device Python / server-side / defer weight) and carried the
> machinery for all three: a suspended pipeline, three extra ABI entrypoints, a handle table with a
> TTL, a Kotlin MethodChannel, a Gradle copy task, a device parity gate, and 65–85 MB of APK per
> ABI. `ML/refactor_plan.md` settles it: *"the only exception is the cutter file, you'll have to
> create a dummy file for it, whenever it gets called it would just return the same image."*
> One C++ call, one code path, both platforms identical, no Python on device. Revision 6's sections
> 3.4 and 3.5, gate C, `pipeline/cutter_gap`, and the three suspension entrypoints are **deleted**.
>
> **(3) The dummy cutter has a price, and this plan states it rather than hiding it.** The XGBoost
> regressor was fitted on features measured from a **head-and-neck-removed** mask. An identity
> cutter returns the whole-pig mask, so the features it would feed the regressor are not the
> features the regressor was trained on, and the kilogram number would be wrong. `AGENTS.md` rule 8
> forbids forcing a prediction after a check that did not pass. Therefore **`weight.available`
> stays `false` while the cutter is the identity dummy**, and the weight branch reports
> `unavailable / cutter_identity_stub`. What the dummy *does* buy is real: stages 1, 2 and 4 run
> end to end on device and can be measured on real photos through
> `instaham_ml_extract_features_provisional_json`, which is labelled `provisional` and never
> renders as a weight.
>
> **(4) The app wiring is part of this plan, not a follow-up.** `TASKS.md` recorded four defects
> from the first on-device run. Two are still live in code, and one of them —
> `RunInferencePipelineUseCase` returning `health: null` for a `health_only` photo — contradicts
> both `AGENTS.md` rule 4 and the `no -> use base segmentation mask for health cnn` line of
> `ML/refactor_plan.md`. Section 12 fixes the wiring as part of this refactor.
>
> Carried forward from revisions 4–6: consolidation is *subtractive* — the originals do not survive
> in the working tree as a second implementation (section 5.6); the `_vN` prefixes are provenance,
> not dead versions (section 5.3(a)); the two override-by-redefinition functions must be resolved
> statically (section 5.3(b)); and every gate keeps its tolerances (section 10).
>
> Supersedes revisions 1–6.

---

## 1. The pipeline

From `ML/refactor_plan.md`:

```
pig -> view type -> segment -> dorsal? -> yes or no
yes -> use py cut off helpers to predict weight -> use base segmentation mask for health cnn
no  ->                                            use base segmentation mask for health cnn

picture -> feed to yolo segmentation -> construct pig mask -> cutter pig mask
        -> calculate 5 features / 16 features -> weight prediction
```

Resolved against what the checkpoints actually accept, and named by the five processes this
revision organises the code around:

```
EXIF-normalised RGB photo
  │
  ├─► [view]  GhostNetV3 1.0x, 3 classes, raw full photo
  │      ├── reject       ──► STOP. No segment, no health, no weight.
  │      ├── health_only  ──┐
  │      └── dorsal_valid ──┤
  │                         │
  ▼                         ▼
 (1) SEGMENTATION   YOLO11s-seg (LDConv+ACmix), 640 letterbox
        │           raw boxes + 32 mask coefficients + 160x160 prototype
        ▼
 (2) CONSTRUCTION   coefficients x prototype -> instance mask -> unletterbox ->
        │           original image coordinates -> largest component -> clean binary mask
        │
        ├──────────────────────────────┬──────────────────────────────────────┐
        │ both branches                │                    dorsal_valid ONLY │
        ▼                              │                                      ▼
   health input (manifest protocol)    │                       (3) CUTTER  head/neck removal
        └──► [health] GhostNetV3,      │                             │     ** IDENTITY DUMMY **
             10 classes                │                             │     returns mask unchanged
                                       │                             ▼
                                       │              (4) FEATURE CALCULATION  RA,LC,BL,BW,E
                                       │                             │        (or chen16)
                                       │                             ▼
                                       │              (5) WEIGHT PREDICTION  XGBoost -> kg
                                       │                             │
                                       └─────────────────────────────┘
                    weight.status = "unavailable" while (3) is the dummy — section 3.4
```

Every box is C++. Nothing runs Python on device. The view classifier is not one of the five
processes: it is a classifier with no geometry, it shares its entire implementation with the health
classifier (section 2.1), and it gates the graph rather than participating in it.

### 1.1 Five consequences that change the design

**(a) View runs on the raw photo, before segmentation.** Evidence:
`ML/view_model/test_predictions.csv` draws from five sources —
`pigrgb_rgb` (2208), `health` (2859), `piglife` (431), `pigrgb_masked` (389), `porac` (11).
Mostly unmasked. The view model is a source-agnostic gate, so it cannot require a mask, and
`refactor_plan.md`'s `view type -> segment` order holds as written.

**(b) Segmentation is on the critical path for health, not just weight.** `refactor_plan.md` sends
*both* branches through "use base segmentation mask for health cnn". That collides with
`AGENTS.md` rule 4 (weight and health branches independent) unless health can still answer when
segmentation fails. Resolved by making the health input protocol manifest-declared with an explicit
fallback — see (c) — and recording which protocol actually ran in the envelope. Segmentation
failure **degrades** the health input; it never blocks health.

**(c) ⚠ The shipped health checkpoint was trained on plain photos, not segmentation masks.**
`ML/health_cnn/test_predictions.csv` is 100 % `health::train|valid/<class>/<file>.rf.<hash>.jpg` —
a Roboflow disease dataset of skin-lesion close-ups. No masked or segmented source appears.
Feeding it a segmentation-masked crop is train/serve skew and will silently degrade accuracy below
the recorded 0.9285.

This does **not** block the work. The design asked for is delivered, made switchable:

| `health.input.protocol` | Meaning |
|---|---|
| `full_frame` | resize-shorter-side 255 + center-crop 224 of the EXIF-normalised photo. Matches the shipped checkpoint's training distribution. |
| `segmentation_crop` | crop to the constructed mask's bounding box (with padding ratio), background **retained**, then the same resize/crop. |
| `segmentation_masked` | crop to that bounding box, background zeroed or mean-filled, then the same resize/crop. |
| `abnormality_crop` | the `TASKS.md` P5 addendum's classical proposer, gated behind a healthy-first check. |

All four are stage-2 geometry plus `health_input`; the manifest picks one; there is no rebuild, no
ABI change, and no Dart change to switch. `on_segmentation_failure` selects `full_frame` or `abort`
per `AGENTS.md` rule 8. Only `full_frame` is implemented today —
`packages/instaham_ml_ffi/src/health_input.h` documents the stub and reports `protocol_applied`
honestly — and the other three become implementable the moment stage 2 lands, because they need a
mask and until now there has been no mask.

**Decisive verification, still blocked on data.** `ML/export/probe_health_input.py` re-runs the
checkpoint over `test_predictions.csv`'s samples under each protocol; the protocol that reproduces
the recorded probabilities *is* the training protocol. It currently reports
`probe_status: "not_run"`, because the 2812 images are not in the repository (section 11.3). The
manifest default stays `full_frame` with the evidence field saying exactly that, rather than
asserting a probe that did not happen.

**(d) The five features are only valid on a cut mask, and the dummy does not cut.**
`ML/weight_prediction/model.metadata.json` records `features [RA, LC, BL, BW, E]`, fitted on masks
that went through `isolate_body_only_mask` — head and neck removed, with `pair_valid` and
`head_removal_applied` both asserted. `ML/weight_runtime.py`'s `predict()` fails closed on both
flags today. An identity cutter cannot set either, so the honest state is `weight: unavailable`,
and that is what section 3.4 specifies. This is not a regression: `weight.available` is already
`false` in every manifest this build ships
(`build/ml_export/assets*/manifest.json`, `unavailable_reason: "body_mask_port_incomplete"`); only
the reason string changes, to one that is true.

**(e) There is no platform asymmetry any more.** Revision 6 built `weight.available: false` on iOS
and a Chaquopy path on Android. With a C++ dummy the two platforms run identical code and produce
identical envelopes. The `unavailable` vocabulary is kept — it now describes *the cutter being a
dummy* rather than *the platform lacking a runtime* — so nothing in the UI or the envelope changes
shape, and the flag would become true on both platforms simultaneously if the cutter were ever
really implemented.

---

## 2. Research artifacts on disk

Folders are named by purpose. Checkpoints are `.gitignore`d (`*.pt`, `*.onnx`), so weights are
local-only export inputs; provenance travels as `source_run.checkpoint_sha256` in the manifest.

| Folder | Capability | Weights | Classes | Status |
|---|---|---|---|---|
| `ML/view_model/` | view type | `best.pt` 28.6 MB, `last.pt` 84.2 MB | `{dorsal_valid:0, health_only:1, reject:2}` | **complete** |
| `ML/segmentation/` | segment | `weights/best.pt` 80.7 MB, `weights/best_eval_fp32.pt` 40.5 MB | `{0: pig}` | **complete** |
| `ML/health_cnn/` | health cnn | `best.pt` 28.6 MB, `last.pt` 84.3 MB | 10 disease classes | **complete** |
| `ML/weight_prediction/` | weight | `model.json`, `model.metadata.json` | features `[RA, LC, BL, BW, E]` | **complete, treated as temporary** |

Note the naming collision this revision has to work around: `ML/segmentation/` and
`ML/weight_prediction/` are already **directories** holding training runs. The five process modules
therefore live in `ML/pipeline/`, not at `ML/` top level, so that `ML/pipeline/segmentation.py` and
`ML/segmentation/` can coexist without a module shadowing a data folder.

### 2.1 View and health are the same architecture

Both checkpoints are **GhostNetV3 1.0x**: `conv_stem.weight` `[16,3,3,3]`, `conv_head.bias`
`[1280]`, 3404 re-parameterisation (`rpr`) key hits each. Only the classifier head differs —
`[3,1280]` for view, `[10,1280]` for health. One vendored architecture file and one C++
`classifier` unit serve both; the head size comes from `classes.json`.

| | view | health |
|---|---|---|
| best epoch | 2 (early-stopped at 14, patience 12) | recorded in checkpoint |
| optimizer | `adamw`, lr 1e-4, wd 1e-4 | `adam`, lr 1e-4, wd 1e-4 |
| scheduler | factor 0.5, patience 5 | factor 0.5, patience 20 |
| seed / batch / AMP | 42 / 32 / on | 42 / 32 / on |
| test accuracy | 0.9727 (macro-F1 0.9498, ROC-AUC ovr 0.9987) | 0.9285 (macro-F1 0.9290) |

Recorded view-gate safety, carried into the manifest as **recorded metrics, never runtime
thresholds**: false-weight-accept 5/3299 (0.15 %), false-weight-reject 75/2599 (2.9 %). Section 12
is where the shipped code is made to honour that sentence.

### 2.2 Segmentation checkpoint facts that constrain stages 1 and 2

Read from `ML/segmentation/weights/best_eval_fp32.pt` and `args.yaml`:

- `ultralytics` **8.4.121** — pin it; `SegmentationModel` is pickled, so the loader must match.
- Weights live in `ema`; top-level `model` is `None`. Use `best_eval_fp32.pt` (40.5 MB), not `best.pt`.
- Epoch 147, `instaham_checkpoint_precision: fp32`.
- **Custom modules are pickled under the module path `src.yolo_modifications`** —
  `LDConv`, `ACmix`, `ACmixLDConvDownsample`. `ML/compat/src_alias.py` is what makes `torch.load`
  resolve them; `ML/yolo_modifications.py` must not be deleted or renamed.
- `instaham_neck_modification`: `first_neck_index 17`, `second_neck_index 20`,
  `ldconv_num_param 5`, `acmix_kernel_att 7`, `acmix_heads 4`, `acmix_kernel_conv 3`.
- `imgsz 640`, `rect false`, `nc 1` (`names {0: "pig"}`), `mask_ratio 4` → mask prototypes are
  **160×160** with 32 coefficients; `overlap_mask true` is training-only; `retina_masks false`;
  `conf 0.25`, `iou 0.7`.

`ML/export/export_yolo.py` already exports both outputs and records the verification numbers:
torch-vs-ORT max abs diff **1.2e-3** on the box/mask head and **6.7e-6** on the prototype. The 32
coefficients and the prototype are therefore already reaching the device. Stage 2 is a missing
*consumer*, not a missing export — `packages/instaham_ml_ffi/src/segmenter.cpp` reads
`outputs[0]` for boxes and ignores `outputs[1]` entirely.

### 2.3 `ML/weight_prediction/` is temporary

`model.metadata.json`: `features [RA, LC, BL, BW, E]`, `n_estimators 300`, `max_depth 5`,
`learning_rate 0.05`, `subsample 0.8`, `colsample_bytree 1.0`, `reg_alpha 0.1`, `reg_lambda 1.0`,
target `weight_kg`; `capture_contract.feature_space: fixed_camera_pixels` at
`training_camera_height_m: 1.88`.

Two things follow. First, the weight capability is built to be **replaced by re-running one export
script**: feature order, estimator count, and objective travel from `model.metadata.json` into the
manifest, and stage 5 reads its contract from the manifest — so swapping the model is an export
plus a sha256 change, with no C++ edit, no ABI change, and no Dart change. The native layer refuses
to run if the new model's feature names are not exactly `RA, LC, BL, BW, E` (`AGENTS.md` rule 2).
Second, the fixed ~1.88 m camera height is a research constraint, not a handheld-phone product;
that is an independent reason the weight branch is not the near-term deliverable, and it does not
go away when the cutter is implemented.

---

## 3. Architecture — five stages, one direction

`refactor_plan.md` and `TASKS.md` between them set four hard constraints:

1. Models and helpers must not affect each other.
2. Inference-running code must be separate from model and helper code.
3. There must be a clear entry point.
4. **One source file per process**, and the same five processes on both sides of the language
   boundary.

Constraint 4 is new in this revision and it is the organising principle. The layered
`core / models / geometry / capabilities / pipeline` directory scheme of revision 6 is
**withdrawn**: it was never built (the shipped tree is flat — `manifest.cpp`, `onnx_runner.cpp`,
`classifier.cpp`, `segmenter.cpp`, `health_input.cpp`, `cutter.cpp`, `util/`), and a five-layer
scheme cutting across a five-stage pipeline gives every stage two homes. The shape is now:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │  instaham_ml.cpp        the C ABI. Thin. Marshals only.          │  entry point
  └───────────────────────────┬──────────────────────────────────────┘
                              │ includes pipeline.h only
  ┌───────────────────────────▼──────────────────────────────────────┐
  │  pipeline.{h,cpp}       THE FLOW. Section 1's graph lives here    │  orchestration
  │                         and nowhere else.                         │
  └───────────────────────────┬──────────────────────────────────────┘
                              │ includes stages/ + classifier + health_input
  ┌───────────────────────────▼──────────────────────────────────────┐
  │  stages/    (1) segmentation  (2) construction  (3) cutter        │  the five processes
  │             (4) feature_calculation  (5) weight_prediction        │
  │             each stage includes ONLY earlier stages + core        │
  └──────────────┬─────────────────────────────┬─────────────────────┘
                 │                             │
  ┌──────────────▼─────────────┐ ┌─────────────▼─────────────────────┐
  │  classifier.{h,cpp}        │ │  health_input.{h,cpp}             │
  │  GhostNetV3, view + health │ │  the four input protocols         │
  └──────────────┬─────────────┘ └─────────────┬─────────────────────┘
                 │                             │
  ┌──────────────▼─────────────────────────────▼─────────────────────┐
  │  manifest · onnx_runner · util/{image_io,sha256} · json          │  infrastructure
  └──────────────────────────────────────────────────────────────────┘
```

### 3.1 The dependency rule, stated exactly

| Unit | May include | Must never include |
|---|---|---|
| `manifest`, `onnx_runner`, `util/` | standard library, OpenCV, ORT, nlohmann/json | any stage, `pipeline`, `classifier` |
| `stages/segmentation` | infrastructure, ORT | any other stage, `pipeline`, `classifier` |
| `stages/construction` | infrastructure, OpenCV | ORT, any other stage, `pipeline` |
| `stages/cutter` | infrastructure only | OpenCV, ORT, any other stage, `pipeline` |
| `stages/feature_calculation` | infrastructure, OpenCV, `stages/construction` | ORT, `cutter`, `weight_prediction`, `pipeline` |
| `stages/weight_prediction` | infrastructure, ORT | OpenCV, any other stage, `pipeline` |
| `classifier`, `health_input` | infrastructure, ORT/OpenCV | any stage except `construction` (health_input needs the mask), `pipeline` |
| `pipeline` | infrastructure, all stages, `classifier`, `health_input` | nothing forbidden — it is the top |
| `instaham_ml.cpp` | infrastructure, `pipeline` | every stage directly |

Two properties are worth naming because they are the constraints, not conventions:

- **No stage may include a later stage.** The arrow runs 1 → 2 → 3 → 4 → 5 and nothing runs back.
  `feature_calculation` including `construction` is the one backwards-looking include, and it is
  legal because it goes backwards; it exists because `extract_five_features` genuinely calls
  `clean_binary_mask` / `_largest_component_fill` / `largest_contour` (verified in
  `.old_py_files/mask_features.py:315`).
- **`pipeline.cpp` is the only file that knows the order of operations.** That is constraints 2
  and 3, mechanically.

Enforced two ways, both cheap:

- CMake `OBJECT` libraries per group with `target_include_directories(... PRIVATE)`, so a forbidden
  include is a compile error rather than a convention.
- `scripts/check_layering.sh` greps every `#include "` against the table above and fails the build
  on a violation. Runs in under a second and needs no toolchain.

### 3.2 The five-file rule (replaces revision 6's one-file-per-runtime rule)

`refactor_plan.md`: *"we would need 5 python files for each process which are segmentation,
construction, cutter, feature calculation and weight prediction."* The rule as it now stands:

| Stage | Python (reference) | C++ (ships) |
|---|---|---|
| 1 segmentation | `ML/pipeline/segmentation.py` | `stages/segmentation.{h,cpp}` |
| 2 construction | `ML/pipeline/construction.py` | `stages/construction.{h,cpp}` |
| 3 cutter | `ML/pipeline/cutter.py` | `stages/cutter.{h,cpp}` — **dummy, no port** |
| 4 feature calculation | `ML/pipeline/feature_calculation.py` | `stages/feature_calculation.{h,cpp}` |
| 5 weight prediction | `ML/pipeline/weight_prediction.py` | `stages/weight_prediction.{h,cpp}` |

Exactly five Python modules under `ML/pipeline/` and exactly five `.cpp` files under
`stages/`. `scripts/check_five_stages.sh` asserts both sets and fails on a sixth file in either —
that is what stops the count from creeping back up the way revision 3's did.

Two files are deliberately **outside** this rule and must not be folded into it:

- `health_input.{h,cpp}` — new code with no Python-helper ancestor (the four input protocols were
  never research code) and not one of the five processes. Its Python reference is
  `ML/parity/reference_health_input.py`.
- `classifier.{h,cpp}` — the shared GhostNetV3 runner for view and health, which is a model, not a
  process.

### 3.3 Why by process and not by layer

A layer split is what forces the coupling `TASKS.md` prohibits and what revision 6 tripped over in
practice: `pig_geometry.py` ended up holding YOLO inference (`predict_largest_mask`, line 564),
mask construction, five-feature extraction, and chen16 — four processes in one file, which is
precisely the "helpers affect each other" state constraint 1 forbids. It also made the C++ target a
single ~1,200-line translation unit that no reviewer can diff against any one thing.

By process, each swap is local by construction:

- New XGBoost model → `stages/weight_prediction.cpp` unchanged, manifest changes.
- New mask-cleanup heuristic → `stages/construction.cpp` only; no model file recompiles.
- Real cutter one day → `stages/cutter.cpp` only; stages 2 and 4 do not move.
- New pipeline order → `pipeline.cpp` only; no stage changes.

And the gate structure falls out of it: gate B is five file-to-file comparisons instead of one
file-to-blob comparison, so a failure names the stage that broke.

### 3.4 The cutter is an identity dummy — and what that costs

`stages/cutter.{h,cpp}` already exists in the tree and already behaves exactly as
`refactor_plan.md` asks: `cut_body_mask()` copies the input mask through unchanged, sets
`head_removal_applied = false`, and reports `status = "identity_stub"`. Nothing about that changes
in this revision; what changes is that it stops being described as a placeholder for a Chaquopy hop
and becomes the specified behaviour.

**The consequence, stated plainly.** The research protocol is
`ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`: Ji/Duan adaptive opening, residual lateral
appendage cleanup, neck refinement, body-circle pair validation, outward circle closure. The
regressor's `RA, LC, BL, BW, E` were measured *after* all of that. Feed it the five features of an
uncut whole-pig mask and every one of them is wrong in the same direction — larger area, longer
perimeter, longer major axis — so the model does not degrade gracefully, it extrapolates off the
end of its training distribution and returns a confident number.

Three rules follow, and they are not negotiable:

1. **`weight.available` is `false` while the cutter is the dummy.** `unavailable_reason` is
   `"cutter_identity_stub"`. `instaham_ml_predict_weight_json` returns
   `INSTAHAM_ML_ERR_UNAVAILABLE`.
2. **`head_removal_applied: false` and `pair_valid: false` propagate into every envelope** that
   carries features. A caller cannot see features without also seeing that they came from an uncut
   mask.
3. **The provisional feature path is the dummy's actual product.**
   `instaham_ml_extract_features_provisional_json` returns
   `{"status":"provisional", "features":{RA,LC,BL,BW,E}, "qc":{"head_removal_applied":false,
   "pair_valid":false, "cutter":"identity_stub"}}` — real numbers from a real mask, correctly
   labelled as not a weight. That is what makes stages 1, 2 and 4 testable on a real phone without
   ever printing a kilogram.

**What the dummy is worth.** It converts the weight branch from "blocked behind ~9,900 lines of
SciPy-coupled geometry" into "blocked behind one function with a defined signature". Stages 1, 2,
4 and 5 can all be built, ported, gated, and shipped against it, and the day a real cutter arrives
— ported, re-derived, or replaced by a differently-trained regressor that does not need one — it
drops in behind an unchanged signature and `weight.available` flips in the manifest.

**What this revision deletes with it.** Revision 6 section 3.4 (the suspended pipeline), section
3.5 (options A/B/C), `pipeline/cutter_gap.{hpp,cpp}`, `instaham_ml_cutter_input`,
`instaham_ml_finish_weight_json`, `instaham_ml_abandon_cutter`, `android/app/src/main/python/`,
`CutterChannel.kt`, the Gradle copy task, the `runtime.python` manifest block, the device parity
gate, spikes S1 and S2, and gate C. None of it has a job any more. `ML/parity/gate_c.py` is deleted
outright rather than demoted, because after section 5 there is only one copy of each primitive.
---

## 4. Directory structure

Legend: **[has]** on disk · **[new]** to create · **[move]** rename/relocate · **[del]** delete.

### 4.1 Python — `ML/`

```
ML/
├── pipeline/                            # [new] THE FIVE PROCESSES, one file each
│   ├── __init__.py                      # [new] empty; no re-exports, so the import graph
│   │                                    #       stays visible at every call site
│   ├── segmentation.py                  # [new] (1) load + run YOLO, select the largest
│   │                                    #       instance, return raw coefficients/proto/box
│   │                                    #       + letterbox params. ~180 lines.
│   ├── construction.py                  # [new] (2) coefficients x proto -> mask -> unletterbox
│   │                                    #       -> original coordinates -> largest component
│   │                                    #       -> clean binary mask. ~300 lines.
│   ├── cutter.py                        # [new] (3) head/neck removal. ~10,300 lines.
│   │                                    #       NOT PORTED — C++ ships an identity dummy.
│   │                                    #       Owns scipy + skimage. Reference only.
│   ├── feature_calculation.py           # [new] (4) RA,LC,BL,BW,E and the chen16 variant.
│   │                                    #       ~450 lines.
│   └── weight_prediction.py             # [new] (5) XGBoost load, feature-order contract,
│                                        #       features -> kg. ~200 lines.
│
├── pig_cutter.py                        # [has] [del] superseded by pipeline/cutter.py
├── pig_geometry.py                      # [has] [del] superseded by pipeline/{segmentation,
│                                        #       construction,feature_calculation}.py
├── weight_runtime.py                    # [has] KEPT as the reference ORCHESTRATOR — it mirrors
│                                        #       C++ pipeline.cpp + manifest.cpp, not any stage.
│                                        #       [new] repointed at ML.pipeline.* (section 5.7).
├── yolo_modifications.py                # [has] KEPT. LDConv / ACmix / ACmixLDConvDownsample are
│                                        #       pickled INTO best_eval_fp32.pt under
│                                        #       src.yolo_modifications; deleting it makes the
│                                        #       checkpoint unloadable (section 2.2).
│
├── models/ghostnetv3.py                 # [new] vendored, read-only. Serves view AND health.
├── compat/src_alias.py                  # [has] the `src.` shim. [new] narrowed to
│                                        #       src.yolo_modifications only (section 5.7).
│
├── tools/
│   ├── consolidate_helpers.py           # [has] [new] rewritten: 4 originals -> 5 stage files
│   │                                    #       (was: 4 originals -> 2 runtime files)
│   └── ...
│
├── export/                              # unchanged in shape; three edits in section 8
│   ├── common.py  export_classifier.py  export_yolo.py  export_xgboost.py
│   ├── fuse_reparam.py  probe_health_input.py  build_manifest.py
│   ├── manifest.schema.json  ort_op_config.py  requirements-export.txt
│
└── parity/
    ├── run_reference.py                 # [has] [new] runs all five stages, not just features
    ├── reference_yolo.py                # [has] [del] its two jobs split: model running goes to
    │                                    #       pipeline/segmentation.py, the re-exports go away
    ├── reference_health_input.py        # [has] KEPT — health_input has no stage ancestor
    ├── gate_a.py                        # [has] [new] 5 stage files vs the pinned originals
    ├── gate_c.py                        # [has] [del] no duplicated primitives remain
    ├── test_consolidation.py            # [has] [new] asserts the five-file rule, not two
    ├── test_health_input.py             # [has] unchanged
    └── compare.py                       # [has] unchanged

.old_py_files/                           # [has] [del] after gate A — see section 5.1
```

### 4.2 Native — `packages/instaham_ml_ffi/src/`

The tree here is **flat today** and the revision-6 document described a five-directory layout that
was never built. This is the actual target, and it is a small delta from what exists:

```
src/
├── CMakeLists.txt                       # [has] [new] add stages/, turn OpenCV ON (section 11)
├── include/instaham_ml.h                # [has] [new] one added entrypoint (section 7)
├── instaham_ml.map                       # [has] exports only instaham_ml_*
├── instaham_ml.cpp                      # [has] [new] delegates to pipeline.cpp
│
├── manifest.{h,cpp}                     # [has] [new] stage/cutter fields (section 8)
├── onnx_runner.{h,cpp}                  # [has] unchanged
├── classifier.{h,cpp}                   # [has] view + health GhostNetV3
├── health_input.{h,cpp}                 # [has] [new] the three region protocols, now that a
│                                        #       mask exists to crop against
├── pipeline.{h,cpp}                     # [new] THE FLOW. Section 1's graph, and nothing else.
│
├── stages/                              # [new] exactly five .cpp files, enforced in CI
│   ├── segmentation.{h,cpp}             # [move] from segmenter.{h,cpp}; [new] emit the 32
│   │                                    #        coefficients + proto instead of dropping them
│   ├── construction.{h,cpp}             # [new] port of ML/pipeline/construction.py
│   ├── cutter.{h,cpp}                   # [move] from cutter.{h,cpp} at src/ root. DUMMY.
│   │                                    #        No Python port, by design (section 3.4).
│   ├── feature_calculation.{h,cpp}      # [new] port of ML/pipeline/feature_calculation.py,
│   │                                    #        baseline5 only (chen16: section 5.5)
│   └── weight_prediction.{h,cpp}        # [new] XGBoost ONNX float[1,5] -> float[1]
│
├── util/{image_io,sha256}.{h,cpp}       # [has]
├── third_party/                         # [has] nlohmann_json, ORT; [new] opencv-mobile
└── test/
    ├── test_abi.cpp                     # [has]
    ├── test_layering.cpp                # [new] include-fence + five-stage assertions
    ├── test_manifest.cpp                # [new] schema, hashes, contracts, capability gating
    ├── test_construction.cpp            # [new] proto+coeff -> mask, unletterbox round-trip
    ├── test_cutter_identity.cpp         # [new] output == input, bit for bit, and the QC flags
    ├── test_feature_calculation.cpp     # [new] RA,LC,BL,BW,E vs the ML/parity fixtures
    ├── test_health_input.cpp            # [new] all four protocols on a fixture mask
    └── test_pipeline_routing.cpp        # [new] reject / health_only / dorsal_valid graphs
```

The stage files map 1:1 onto `ML/pipeline/*.py` by name. That is what makes gate B five
file-to-file comparisons (section 10) and what lets `check_five_stages.sh` be a two-line script.

### 4.3 Flutter app side

```
lib/services/ml/
├── ml_runtime.dart                      # [has] singleton + asset staging; [new] add the
│                                        #       pipeline entrypoint and an inference isolate
├── view_model_service.dart              # [has]
├── health_model_service.dart            # [has]
├── segmentation_service.dart            # [has] [new] surface mask area / bbox, not just a count
├── weight_regression_service.dart       # [has] [del] replaced by the pipeline service
├── inference_pipeline_service.dart      # [new] ONE call for the whole section-1 graph
└── ml_exceptions.dart                   # [new]

lib/features/inference_pipeline/domain/use_cases/
├── run_and_persist_pipeline_use_case.dart   # [has] [new] section 12 fixes
└── run_inference_pipeline_use_case.dart     # [has] [new] section 12 fixes — currently
                                             #       unreferenced by the app and still carries
                                             #       the invented thresholds

lib/features/capture/presentation/screens/capture_screen.dart   # [has] view gate already moved
                                                                #       ahead of routing (P0)
lib/features/results/presentation/screens/results_screen.dart   # [has] [new] a view card, and
                                                                #       stage-accurate failure text
```

### 4.4 Assets

```
assets/ml/                               # generated by ML/export/build_manifest.py, never hand-edited
├── manifest.json
├── view/          model.onnx  classes.json
├── segmentation/  yolo.onnx   classes.json      # ~40 MB -> Play Asset Delivery / ODR
├── health/        model.onnx  classes.json
└── weight/        xgboost.onnx  feature_order.json  xgboost.meta.json
```

All four are buildable today — every checkpoint exists, and `build/ml_export/` already holds a
complete set from a previous run.

---

## 5. The refactor — merging `.old_py_files/` into five process files

`refactor_plan.md`: *"Use the files in `.old_py_files` folder to merge them properly this time
based on the 5 processes."*

### 5.1 The merge inputs, and why they are trustworthy

`.old_py_files/` holds the six pre-consolidation modules. Verified before planning any of this:
each one is **byte-identical** to `git show 5bd99ce:ML/<name>.py`, the pinned revision that
`ML/parity/gate_a.py` and `ML/tools/consolidate_helpers.py` already use as their reference point:

| File | Lines | Defs | sha256 vs `5bd99ce` |
|---|---:|---:|---|
| `body_mask.py` | 10,701 | 73 | match |
| `mask_features.py` | 349 | 9 | match |
| `extended_mask_features.py` | 309 | 7 | match |
| `yolo_inference.py` | 276 | 4 | match |
| `weight_runtime.py` | 589 | 13 | match |
| `yolo_modifications.py` | 444 | — | match |

Two things follow. First, the merge can be driven from the working tree, which is far easier to
review in a diff than `git show` output. Second, **`.old_py_files/` is deleted once gate A is
green**: it carries no information git does not, and a second copy of the originals in the working
tree is exactly the "two implementations, one tested" state revision 4 was wrong about and
revisions 5–6 corrected. Gate A keeps reading `5bd99ce`, so it stays re-runnable forever.

`yolo_modifications.py` is **not** a merge input. It is already live at `ML/yolo_modifications.py`
and must stay exactly where it is (section 2.2).

### 5.2 The allocation — every definition to exactly one stage

This is the whole refactor in one table. Nothing is dropped, nothing is duplicated, and the
"Leave" column is as load-bearing as the others.

**(1) `ML/pipeline/segmentation.py`** — *load the checkpoint, run it, pick the instance*

| From | Take |
|---|---|
| `yolo_inference.py` | `_largest_mask_index` (line 14); the model-loading and `model.predict(...)` half of `predict_largest_mask` (line 195) |
| — | **[new]** `SegmentationOutput` — the stage-1 → stage-2 contract: `mask_coeffs`, `proto`, `box`, `conf`, `letterbox` `(scale, pad_left, pad_top)`, `native_mask` when ultralytics already produced one, `orig_hw` |

Imports: `ultralytics`, `numpy`, and `ML.compat.src_alias` for the checkpoint unpickle. **No
project-local geometry import** — that is what stops stage 1 from reaching forward into stage 2.

**(2) `ML/pipeline/construction.py`** — *turn model output into a clean pig mask in original coordinates*

| From | Take |
|---|---|
| `yolo_inference.py` | `MASK_COORDINATE_PROTOCOL` (11), `_polygon_mask_in_original_coordinates` (33), `_unletterbox_native_mask` (100) |
| `mask_features.py` | `_largest_component_fill` (7), `clean_binary_mask` (19), `largest_contour` (35) |
| — | **[new]** `construct_pig_mask(seg_output) -> np.ndarray` — the public entry, being the mask-building tail of the original `predict_largest_mask` (section 5.4) |

Imports: `cv2`, `numpy`. Nothing project-local.

**(3) `ML/pipeline/cutter.py`** — *head/neck removal. Not ported.*

| From | Take |
|---|---|
| `body_mask.py` | all of it — 73 defs, entry `isolate_body_only_mask` (10,611, delegating to `_isolate_body_only_mask_fixed06q` at 10,016), `BODY_MASK_PROTOCOL_VERSION` / `BODY_MASK_METHOD` (43–44) and the ~30 tuning constants at 50–120 |
| `mask_features.py` | `_odd_window` (44), `_rolling_median` (49), `ji_duan_adaptive_kernel_sizes` (63), `isolate_dorsal_core_ji_duan` (91), `isolate_dorsal_core` (140) |

Imports: `cv2`, `numpy`, `math`, `scipy.ndimage.gaussian_filter1d`, `scipy.signal.find_peaks`,
`skimage.morphology.skeletonize`, and — replacing `body_mask.py:40`'s
`from src.mask_features import clean_binary_mask, isolate_dorsal_core_ji_duan` —
`from ML.pipeline.construction import clean_binary_mask, _largest_component_fill`.

That one import line is the entire seam between stages 2 and 3, and it is the same seam the
original code already had. Note what it replaces: revision 6 required `pig_cutter.py` to inline its
own copies of six primitives so it could ship standalone under Chaquopy, which created the
duplicate set that gate C existed to police. **With no Chaquopy there is no reason to duplicate
anything**, so the copies go and gate C goes with them.

Why the dorsal-core functions land here rather than in construction: `isolate_dorsal_core_ji_duan`
is the *first step of the cut* (Ji/Duan adaptive opening), not a step of building the mask —
`body_mask.py` calls it internally, and the protocol string
`ji_duan_residual_06q_v9_headfit_exact_twotangent_v26` names it as part of the cutter's contract.
`isolate_dorsal_core` is the alternative INSTAHAM PCA/torso-envelope heuristic compared against it
in the research notebooks; same stage, same reason.

**(4) `ML/pipeline/feature_calculation.py`** — *mask to feature vector*

| From | Take |
|---|---|
| `mask_features.py` | `extract_five_features` (315) |
| `extended_mask_features.py` | `BASELINE5`, `CHEN16_NOHEIGHT`, `EXTENDED_FEATURE_PROTOCOL_VERSION` (19–40), `_largest_external_contour` (42), `_center_crossing_axes` (55), `_skeleton_body_curve` (150), `_resample_closed_contour` (206), `_maximum_outline_curvature` (232), `extract_extended_shape_features` (261), `extract_chen16_features` (307) |

Imports: `cv2`, `numpy`, `skimage.morphology.skeletonize` (chen16 only), and
`from ML.pipeline.construction import clean_binary_mask, _largest_component_fill, largest_contour`
— a real dependency, not a convenience: `extract_five_features` calls all three
(`.old_py_files/mask_features.py:325-327`).

`_largest_external_contour` and `largest_contour` are near-duplicates that end up in different
files. **They are not merged.** Section 5.3(a)'s rule — never dedupe on similarity — applies here
too: they differ in retrieval mode and in what they return on an empty mask, and the chen16 path
was measured with its own.

**(5) `ML/pipeline/weight_prediction.py`** — *feature vector to kilograms*

| From | Take | Leave |
|---|---|---|
| `weight_runtime.py` | the XGBoost load, `feature_order` handling, `_verify_feature_contract` (294), `_verify_loaded_xgb_feature_contract` (372), and the `EXPECTED_*` protocol constants (27–31) | everything else — `WeightEstimator.__init__`'s project-root/YAML machinery, `_find_project_root`, `_sha256_file`, `_resolve_recorded_project_path`, `_load_json`, `_verify_artifact_hashes`, `_verify_runtime_source_hashes`, `_verify_runtime_protocols`, `_verify_candidate_protocol_binding`, `_failure`, and `predict`'s chaining |

Imports: `numpy`, `xgboost`. Nothing project-local — stage 5 takes an ordered float vector and a
model path, and knows nothing about masks.

**What stays in `ML/weight_runtime.py`.** Everything in the "Leave" column above. It becomes what
revision 5 already called it and what its docstring already claims: the reference **orchestrator**,
mirroring C++ `pipeline.cpp` + `manifest.cpp`. It chains the five stages, verifies artifact hashes
and protocol bindings, and assembles the envelope. It is not a sixth process file and it is not
ported as one — `pipeline.cpp` is its C++ counterpart.

### 5.3 Three corrections that must survive the merge

**(a) `_vN` is provenance, not a version switch.** The `_vN` prefixes in `body_mask.py`
(`_v9`×5, `_v14`×6, `_v15`×4, `_v16`×1, `_v26`×1 definitions) look like abandoned versions. **They
are not.** Every one has at least one live call site (`_v14`: 8 calls, `_v15`: 9, `_v9`: 6,
`_v26`: 2, `_v16`: 1). The prefix is a provenance tag on a live sub-step. Any reduction must come
from a measured reachability pass, never from the naming — and the same rule forbids merging
`_largest_external_contour` into `largest_contour` in stage 4.

**(b) `body_mask.py` overrides two of its own functions by redefinition, and the merge can break
that silently.** Two names are defined twice in the same module:

| Name | First `def` | Alias capture | Second `def` (wins) |
|---|---|---|---|
| `choose_body_circle_pair` | 5882 | `_choose_body_circle_pair_fixed06q = choose_body_circle_pair` at **10184** | 10392, calls the alias at 10396 |
| `isolate_body_only_mask` | 10016 | `_isolate_body_only_mask_fixed06q = isolate_body_only_mask` at **10185** | 10611, calls the alias at 10618 |

The module's own comment at 10167 states the intent: *"are intentionally unchanged. Only
`choose_body_circle_pair()` is overridden."* This is a deliberate monkey-patch-by-redefinition
layer and it is **order-dependent late binding**: the call at line 9177 reads
`choose_body_circle_pair(...)` but resolves at runtime to the **10392 override**. The alias
captures the original only because it is bound *between* the two `def`s.

Three rules follow, and they are not optional:

1. **Never dedupe on name.** Removing "the duplicate `def`" silently swaps which implementation runs.
2. **Never reorder across an alias-capture line.** Moving `_choose_body_circle_pair_fixed06q =`
   above the first `def` makes it capture nothing; moving it below the second makes it capture the
   override and recurse forever.
3. **Resolve the override statically during the merge.** In `ML/pipeline/cutter.py` the two
   originals are renamed to their captured alias names (`_choose_body_circle_pair_fixed06q`,
   `_isolate_body_only_mask_fixed06q`), the overrides keep the public names, and the alias
   assignments are deleted. Behaviour-preserving; gate A proves it.

This already landed once in `ML/pig_cutter.py` and must land again identically here. The merge is
not a fresh attempt at the problem — `ML/tools/consolidate_helpers.py` performed exactly this
transform, and its rewrite (section 5.6) keeps the same code path for it.

**(c) 380 lines in `body_mask.py` are dead and are deleted in this merge.** From the revision-6
reachability pass (AST call-graph, BFS from `isolate_body_only_mask`): 9,911 of 10,855 lines live
across 72 functions, 380 dead across 7 —
`_v14_fit_head_closure_circle` (179), `_v14_choose_head_side` (112), `_ordered_terminal_indices`
(27), `_v14_disk_mask_occupancy` (23), `make_circle_defined_structure_overlay` (19), a stale
`_rolling_median` (12), `_v14_candidate_from_geometry` (8).

Note this is the one place (a) does not apply: these have no live call site from the entry point,
which is what makes them safe. The stale `_rolling_median` disappears naturally in this merge
anyway — stage 3 now takes the live one from `mask_features.py` (section 5.2(3)). Deletion is
still gated on gate A.

Seven live functions totalling **1,985 lines** call `scipy.gaussian_filter1d`,
`scipy.find_peaks`, or `skimage.skeletonize` directly. That measurement is why stage 3 is not
ported and why the C++ dummy of section 3.4 is the specified behaviour rather than a temporary one.

### 5.4 The one function that splits across two stages

`predict_largest_mask` (`.old_py_files/yolo_inference.py:195`) does two jobs in one call: it runs
the model, and it builds the mask. The process split cuts it in half:

```
predict_largest_mask(model, image_path, imgsz, conf, device)
        │
        ├── load + predict + _largest_mask_index  ──► ML/pipeline/segmentation.py
        │        returns SegmentationOutput
        │
        └── _polygon_mask_in_original_coordinates / _unletterbox_native_mask
            + _largest_component_fill + clean_binary_mask   ──► ML/pipeline/construction.py
                     construct_pig_mask(SegmentationOutput) -> mask
```

This is the only definition in the whole merge that does not move as a unit, so it is the only one
that can change behaviour by accident. Three constraints on the split:

1. **`SegmentationOutput` carries the letterbox parameters verbatim** — `scale`, `pad_left`,
   `pad_top`, `orig_hw` — because `_unletterbox_native_mask` needs exactly those and recomputing
   them on the stage-2 side would be a second implementation of the same arithmetic
   (`AGENTS.md` rule 9: coordinates must map to the actual displayed rectangle, not a re-derived one).
2. **Both the polygon path and the native-mask path survive.** The original chooses between them;
   stage 2 keeps that choice, and `MASK_COORDINATE_PROTOCOL` still names the result.
3. **Gate A compares `construct_pig_mask(segment(img))` against `predict_largest_mask(img)`**,
   end to end, at IoU ≥ 0.999. The split is an internal detail; what must not change is the mask.

`ML/parity/reference_yolo.py`, which revision 5 created solely to hold `predict_largest_mask` away
from the geometry file, is **deleted**: stage 1 is now the right home for model loading, so the
file has no remaining job.

### 5.5 chen16 is Python-reference-only, and that is a decision

`extract_chen16_features` needs `skimage.morphology.skeletonize` (via `_skeleton_body_curve`). The
shipped regressor is `feature_family: baseline5` with `features [RA, LC, BL, BW, E]`, so chen16 is
not on any shipping path today.

Therefore: **`stages/feature_calculation.cpp` ports the baseline5 path only.** The chen16 functions
live in `ML/pipeline/feature_calculation.py` as reference and gate against nothing until a chen16
model is actually selected, at which point porting them means solving `skeletonize` in C++ — the
same problem stage 3 has, at 1/50th the scale. `manifest.weight.feature_extractor.protocol_version`
is what selects the family, and native returns `ERR_CONTRACT` if it is asked for `chen16` while
only baseline5 is compiled in. That is an honest refusal, not a silent fallback.

### 5.6 Deleting the predecessors

The refactor is not done when the five files exist. It is done when they are the **only** stage
files. Deleted in the same commit, gated:

**Deletion preconditions, all required:**

1. Gate A is green on the fixture corpus at section 10 tolerances, for all five stages and for the
   end-to-end chain.
2. Gate A's expected outputs are committed under `test/fixtures/parity/` — the corpus, not the
   source, becomes the behavioural record.
3. `ML/parity/gate_a.py` still reconstructs the originals from `5bd99ce`, so gate A remains
   re-runnable after the working tree loses them.
4. No importer of a deleted name remains (section 5.7).

**Deleted:** `ML/pig_cutter.py`, `ML/pig_geometry.py`, `ML/parity/reference_yolo.py`,
`ML/parity/gate_c.py`, `.old_py_files/`.

**Explicitly kept:** `ML/yolo_modifications.py` (the checkpoint unpickles through it),
`ML/weight_runtime.py` (the orchestrator), `ML/parity/reference_health_input.py` (health_input has
no stage ancestor), `ML/compat/src_alias.py` (narrowed, section 5.7).

`ML/tools/consolidate_helpers.py` is **rewritten, not deleted**: it stays the reviewable, rerunnable
record of the transform, retargeted from "4 originals → 2 runtime files" to "4 originals → 5 stage
files", keeping its override-resolution code path (section 5.3(b)) unchanged.

### 5.7 The repoint work the deletion forces

Deletion is not a `git rm`; every one of these breaks. This is real work and is part of the same
slice:

| Site | Current | After |
|---|---|---|
| `ML/weight_runtime.py:145-152` | `from ML.parity.reference_yolo import MASK_COORDINATE_PROTOCOL, predict_largest_mask`; `from ML.pig_cutter import (BODY_MASK_PROTOCOL_VERSION, BODY_MASK_METHOD, isolate_body_only_mask)`; `from ML.pig_geometry import extract_five_features, BASELINE5, CHEN16_NOHEIGHT, EXTENDED_FEATURE_PROTOCOL_VERSION, extract_chen16_features` | five imports, one per stage: `ML.pipeline.segmentation`, `ML.pipeline.construction`, `ML.pipeline.cutter`, `ML.pipeline.feature_calculation`, `ML.pipeline.weight_prediction` |
| `ML/weight_runtime.py:356-359` | hashes one consolidated source file in its provenance record | hashes the five stage files, recorded as `stage_sha256: {segmentation, construction, cutter, feature_calculation, weight_prediction}` — matching `manifest.pipeline.stages[*].source_sha256` (section 8) |
| `ML/weight_runtime.py:275-281` | `_verify_runtime_protocols` compares `BODY_MASK_PROTOCOL_VERSION` / `BODY_MASK_METHOD` from `pig_cutter` | same constants from `ML.pipeline.cutter`. The protocol string `ji_duan_residual_06q_v9_headfit_exact_twotangent_v26` must **not** change — it is asserted in the manifest and echoed in the section-9 envelope |
| `ML/weight_runtime.py`'s `predict()` | one call to `predict_largest_mask`, then cutter, then features | five explicit calls in order, so the reference orchestrator reads like `pipeline.cpp` and a stage failure names itself |
| `ML/parity/run_reference.py:65` | `from ML.pig_geometry import extract_five_features` | `from ML.pipeline.feature_calculation import extract_five_features`; and the runner gains stage-1/2 coverage |
| `ML/parity/gate_a.py:137-141` | imports `isolate_body_only_mask`, the two aliases from `ML.pig_cutter` | same names from `ML.pipeline.cutter`; and four more per-stage comparisons (section 10) |
| `ML/parity/test_consolidation.py` | asserts two helper files and the six shared primitives | asserts the five-stage rule, the stage dependency direction, and that no stage imports a later stage |
| `ML/compat/src_alias.py:27` | comments still reference `src.body_mask` / `src.yolo_inference` as legacy roots | keeps `src.yolo_modifications` (needed to unpickle); the stale comments go |
| `scripts/check_one_helper.sh` | asserts exactly `pig_cutter.py` + `pig_geometry.py` | **[del]** replaced by `scripts/check_five_stages.sh` |
| `scripts/check_cutter_purity.sh` | asserts `pig_cutter.py` has zero project-local imports (a Chaquopy requirement) | **[new]** rewritten: stage 3 may import stage 2 and nothing else; still no file IO, no model runtime, no manifest |
| `ML/export/export_xgboost.py:79` | writes `unavailable_reason: "body_mask_port_incomplete"` | `"cutter_identity_stub"` — the port is not incomplete, it is deliberately absent (section 3.4) |

The provenance hash goes from one file to five. That is a manifest-visible change and it is the
point: a bundle built before this refactor and one built after are distinguishable.

---

## 6. Reconstructing the models from `best.pt`

`TASKS.md`: *"The best.pt weights will be used for the reconstruction of the trained yolo and
ghostnet models."* Each has a distinct obstacle. Nothing in this section changes from revision 6 —
it is reproduced because it is still the export contract.

### 6.1 GhostNetV3 ×2 — view and health

1. **Not a `timm` builtin.** `create_model("ghostnetv3_100")` fails on stock timm. The training
   definition is vendored read-only as `ML/models/ghostnetv3.py` and resolved through one
   `build_arch()` registry point; genuine timm names still fall through to timm. Its sha256 goes in
   the manifest (`model.arch_source`), so a silently edited architecture file invalidates the
   bundle exactly like a swapped weight would.
2. **The checkpoint is re-parameterised and not fused.** `model_state` carries
   `blocks.*.ghost1.cheap_rpr_conv.{0,1,2}.*`, `dw_rpr_conv`, `dw_rpr_scale` — the multi-branch
   training form. Exporting as-is ships every training branch. `ML/export/fuse_reparam.py` folds
   them and asserts fused-vs-trained logits agree to < 1e-5 before any ONNX write.

Once fused, GhostNetV3 is ordinary Conv / BatchNorm / ReLU / HardSigmoid / Add / Concat / Split /
GlobalAveragePool / Gemm — all core ORT, no custom kernels.

Export contract checks, all fatal: `classes.json` == the checkpoint's `class_to_idx`;
`classifier.weight.shape[0]` == `len(classes.json)` (3 and 10); fused vs trained logits < 1e-5;
fused torch vs ORT < 1e-4.

### 6.2 YOLO11s-seg

Load `best_eval_fp32.pt`, take the `ema` branch, install `ML/compat/src_alias.py` before
`torch.load`. Export is already working (`onnx_native`, opset 17, static 640×640) with the
verification numbers in section 2.2. `manifest.segmentation.export_mode` records the rung reached.

Post-processing constants, all manifest-driven, none hardcoded: 640 letterbox with `color
[114,114,114]`, `stride 32`, `scaleup false`; 32 mask coefficients against a `[1,32,160,160]`
prototype (`mask_ratio 4`); `conf 0.25`, `iou 0.7`; single largest instance; `nc 1`,
`names {0: pig}`; `retina_masks false`. `overlap_mask true` is training-only and must not be
replicated at inference.

**The one change in this revision:** `stages/segmentation.cpp` must stop discarding `outputs[1]`.
The prototype tensor is exported, verified to 6.7e-6, and currently unread; stage 2 cannot exist
until stage 1 hands it over.

---

## 7. The C ABI — the clear entry point

`packages/instaham_ml_ffi/src/include/instaham_ml.h` is committed and its shape is unchanged:
opaque handle, `int` status enum plus out-params, heap JSON strings freed by the caller,
thread-local `instaham_ml_last_error()`, synchronous entrypoints Dart serialises on one isolate.

**Revision 7 adds exactly one entrypoint and deletes three that revision 6 proposed.**

```c
/* Runs the whole section-1 graph in one call: view -> segmentation -> construction ->
   (health | cutter -> features -> weight). Returns the COMPLETE section-9 envelope,
   always. There is no suspended state and no second call: the cutter is a C++ dummy
   (section 3.4), so nothing crosses a runtime boundary mid-pipeline. */
INSTAHAM_ML_API InstahamMlStatus instaham_ml_run_pipeline_json(
    InstahamMlContext* ctx, const char* image_path, char** out_json);
```

**Deleted before they were written** (revision 6 section 3.4): `instaham_ml_cutter_input`,
`instaham_ml_finish_weight_json`, `instaham_ml_abandon_cutter`. With no Python hop there is no
suspension, no handle table, no TTL, and no `test_cutter_gap.cpp`. `INSTAHAM_ML_ABI_VERSION` stays
at **1**: the addition above is additive, and the ABI contract in the header already states that
only a breaking signature change bumps it.

The existing per-capability entrypoints stay for tests, parity runs, and isolated debugging:
`instaham_ml_classify_view_json`, `instaham_ml_classify_health_json`, `instaham_ml_segment_json`,
`instaham_ml_predict_weight_json`, `instaham_ml_extract_features_provisional_json`,
`instaham_ml_capability_available`.

Two of those change behaviour in this revision, and both changes are the dummy cutter made visible:

- `instaham_ml_segment_json` gains `mask_area_px`, `bbox`, and `mask_protocol` now that stage 2
  produces a mask. `mask_available` stops meaning "a detection survived" and starts meaning what it
  says.
- `instaham_ml_extract_features_provisional_json` stops returning `ERR_UNAVAILABLE` and starts
  returning real features with `"status":"provisional"` and
  `qc: {head_removal_applied:false, pair_valid:false, cutter:"identity_stub"}`. This is the one
  place uncut features are exposed, it is labelled at every level, and section 12 forbids the UI
  from rendering it as a weight.

`instaham_ml_predict_weight_json` continues to return `ERR_UNAVAILABLE` with
`reason: "cutter_identity_stub"` — section 3.4, `AGENTS.md` rule 8.

`image_path` is always an **already-EXIF-normalised** RGB image. Native performs no rotation;
`AGENTS.md` rule 5 is enforced once, Dart-side. Existing error codes are unchanged. The pipeline
never returns a partial-success error code: a branch that fails is reported *inside* the envelope
with its own status, so a failed weight branch cannot mask a successful health branch
(`AGENTS.md` rule 4).
---

## 8. Manifest

`assets/ml/manifest.json` is generated by `ML/export/build_manifest.py` and never hand-edited.
Everything the native layer needs — paths, sha256, architecture, input size, mean/std, class-map
path, feature order, protocol versions, the stage graph, and per-capability `available` flags —
comes from it. **Nothing is hardcoded** in C++ or Dart (`AGENTS.md` rules 1, 2, 7).

Revision 7 changes three things and leaves the rest alone: the `pipeline` block is now stated as
the five stages, the `runtime.python` block is **deleted**, and the weight capability records the
cutter implementation explicitly.

```jsonc
{
  "schema_version": 4,                   // 3 -> 4: stages block, cutter block, no python block
  "bundle_id": "instaham-ml-<git-sha>",
  "reference_commit": "<git SHA of the ML/ snapshot exported from>",
  "platform": "android",                 // or "ios" — identical content under revision 7
  "runtime": { "engine": "onnxruntime", "min_abi_version": 1 },
  //          ^ no "python" block. There is no on-device Python (section 3.4).

  // The section-1 graph, declared. pipeline.cpp reads it; it does not embed it.
  "pipeline": {
    "protocol_version": "instaham_pipeline_v4",
    "view_routing": {
      "reject":       { "stop": true },
      "health_only":  { "segment": true, "weight": false, "health": true },
      "dorsal_valid": { "segment": true, "weight": true,  "health": true }
    },
    "weight_requires": ["segmentation", "construction", "cutter", "feature_calculation"],
    "health_requires": ["segmentation", "construction"],   // subject to on_segmentation_failure
    "stages": [
      { "name": "segmentation",        "runtime": "cpp",
        "source": "ML/pipeline/segmentation.py",        "source_sha256": "…" },
      { "name": "construction",        "runtime": "cpp",
        "source": "ML/pipeline/construction.py",        "source_sha256": "…",
        "mask_protocol": "original_coordinate_polygon_v1" },
      { "name": "cutter",              "runtime": "cpp",
        "implementation": "identity_stub",              // <- the section-3.4 decision, declared
        "source": "ML/pipeline/cutter.py",              "source_sha256": "…",
        "protocol_version": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26",
        "protocol_implemented": false,
        "note": "returns the input mask unchanged; head_removal_applied is always false" },
      { "name": "feature_calculation", "runtime": "cpp",
        "source": "ML/pipeline/feature_calculation.py", "source_sha256": "…",
        "families_compiled": ["baseline5"] },           // chen16 is reference-only (section 5.5)
      { "name": "weight_prediction",   "runtime": "cpp",
        "source": "ML/pipeline/weight_prediction.py",   "source_sha256": "…" }
    ]
  },

  "capabilities": {
    "view": {
      "available": true,
      "model": { "path": "view/model.onnx", "sha256": "…",
                 "architecture": "ghostnetv3_100",
                 "arch_source": { "path": "ML/models/ghostnetv3.py", "sha256": "…",
                                  "reason": "not_a_timm_builtin" },
                 "reparam": { "trained_form": "multi_branch_rpr", "exported_form": "deploy_fused",
                              "fuse_tool": "ML/export/fuse_reparam.py",
                              "equivalence_max_abs": 1e-5 },
                 "opset": 17,
                 "input": { "name": "input", "layout": "NCHW", "size": [224,224], "channels": "rgb" } },
      "preprocessing": { "exif": "expect_normalized", "resize_shorter_side": 255, "center_crop": 224,
                         "scale": 0.00392156862745098,
                         "mean": [0.485,0.456,0.406], "std": [0.229,0.224,0.225],
                         "interpolation": "bilinear", "source": "raw_photo" },
      "class_map": { "path": "view/classes.json", "sha256": "…" },
      "protocol_version": "view_suitability_v1",
      "expected_labels": ["dorsal_valid","health_only","reject"],
      "decision_rule": "argmax",          // NOT a threshold — section 12, defect B
      "recorded_metrics": { "test_accuracy": 0.9727, "macro_f1": 0.9498, "macro_roc_auc_ovr": 0.9987,
                            "false_weight_accept_rate": 0.0015, "false_weight_reject_rate": 0.0289,
                            "note": "recorded research metrics; never a runtime threshold" }
    },

    "segmentation": {
      "available": true,
      "model": { "path": "segmentation/yolo.onnx", "sha256": "…",
                 "architecture": "yolo11s-seg-ldconv-acmix", "opset": 17,
                 "input": { "name": "images", "layout": "NCHW", "size": [640,640], "channels": "rgb" },
                 "letterbox": { "color": [114,114,114], "stride": 32, "scaleup": false } },
      "postprocess": { "conf": 0.25, "iou": 0.7, "single_largest_instance": true,
                       "mask_coefficients": 32, "proto_size": [160,160], "mask_ratio": 4,
                       "retina_masks": false,
                       "mask_protocol": "original_coordinate_polygon_v1" },
      "class_map": { "path": "segmentation/classes.json", "sha256": "…" },
      "export_mode": "onnx_native",
      "protocol_version": "yolo11s_ldconv_acmix_fixed_seed42",
      "source_run": { "dir": "ML/segmentation", "checkpoint": "weights/best_eval_fp32.pt",
                      "checkpoint_sha256": "…", "checkpoint_branch": "ema",
                      "epoch": 147, "seed": 42, "imgsz": 640, "ultralytics": "8.4.121",
                      "module_alias": { "src.yolo_modifications": "ML/yolo_modifications.py" },
                      "neck_modification": { "first_neck_index": 17, "second_neck_index": 20,
                                             "ldconv_num_param": 5, "acmix_kernel_att": 7,
                                             "acmix_heads": 4, "acmix_kernel_conv": 3 } }
    },

    "health": {
      "available": true,
      "model": { "path": "health/model.onnx", "sha256": "…", "architecture": "ghostnetv3_100",
                 "arch_source": { "path": "ML/models/ghostnetv3.py", "sha256": "…" },
                 "reparam": { "trained_form": "multi_branch_rpr", "exported_form": "deploy_fused",
                              "equivalence_max_abs": 1e-5 },
                 "opset": 17,
                 "input": { "name": "input", "layout": "NCHW", "size": [224,224], "channels": "rgb" } },
      "input": { "protocol": "full_frame",
                 "supported": ["full_frame","segmentation_crop","segmentation_masked","abnormality_crop"],
                 "implemented": ["full_frame"],
                 "bbox_padding_ratio": 0.06,
                 "background_fill": "imagenet_mean",
                 "on_segmentation_failure": "full_frame",
                 "evidence": "probe_status=not_run; the 2812 test images are not in the repo" },
      "preprocessing": { "exif": "expect_normalized", "resize_shorter_side": 255, "center_crop": 224,
                         "scale": 0.00392156862745098,
                         "mean": [0.485,0.456,0.406], "std": [0.229,0.224,0.225],
                         "interpolation": "bilinear" },
      "class_map": { "path": "health/classes.json", "sha256": "…" },
      "protocol_version": "health_cvsafe_v3",
      "decision_rule": "argmax",
      "recorded_metrics": { "test_accuracy": 0.9285, "macro_f1": 0.9290, "n_test": 2812 }
    },

    "weight": {
      "available": false,                          // section 3.4 — NOT a bug, a stated contract
      "unavailable_reason": "cutter_identity_stub",
      "stability": "temporary",
      "regressor": { "format": "onnx", "path": "weight/xgboost.onnx", "sha256": "…",
                     "meta_path": "weight/xgboost.meta.json", "meta_sha256": "…",
                     "feature_order_path": "weight/feature_order.json", "feature_order_sha256": "…",
                     "feature_family": "baseline5", "n_estimators": 300, "max_depth": 5,
                     "learning_rate": 0.05, "objective": "reg:squarederror", "target": "weight_kg" },
      "feature_extractor": { "protocol_version": "baseline5_v1",
                             "names": ["RA","LC","BL","BW","E"], "linear_scale": 1.0 },
      "provisional_features": {
        // The one thing the dummy cutter DOES deliver (section 3.4 rule 3). Real numbers from
        // an uncut mask, permanently labelled as not a weight.
        "available": true,
        "entrypoint": "instaham_ml_extract_features_provisional_json",
        "qc_always": { "head_removal_applied": false, "pair_valid": false,
                       "cutter": "identity_stub" }
      },
      "capture_contract": { "feature_space": "fixed_camera_pixels",
                            "training_camera_height_m": 1.88,
                            "camera_height_is_xgboost_feature": false },
      "source_run": { "dir": "ML/weight_prediction", "model": "model.json", "model_sha256": "…" }
    }
  }
}
```

Asserted on load, else `INSTAHAM_ML_ERR_CONTRACT`:

- `feature_extractor.names == ["RA","LC","BL","BW","E"]`, and `feature_order.json` and the XGBoost
  meta's feature names both agree (`AGENTS.md` rule 2).
- `health.input.protocol` ∈ `supported`; if it is not in `implemented`, native runs the fallback and
  reports the degradation rather than failing (`AGENTS.md` rule 4).
- `pipeline.stages` names exactly the five processes, in order.
- **`weight.available == true` requires `pipeline.stages[cutter].protocol_implemented == true`.**
  This is the manifest-level expression of section 3.4: it is not possible to ship a manifest that
  turns the weight branch on while the cutter is the dummy. A build that tries fails at
  `build_manifest.py`, not on a phone.
- `feature_extractor.protocol_version`'s family ∈ `stages[feature_calculation].families_compiled`
  (section 5.5).

Labels always resolve through `classes.json` by name, never by position (`AGENTS.md` rule 1). A
capability with `available: false` has its sha256 checks skipped and every call into it returns
`ERR_UNAVAILABLE` — a manifest with a dark capability is still a valid, shippable manifest.

---

## 9. Result envelope

One JSON document per photo, from `instaham_ml_run_pipeline_json`. Every stage reports its own
status, so a failure in one never fabricates or blocks another.

```json
{
  "status": "ok",
  "pipeline_protocol": "instaham_pipeline_v4",
  "view": { "status": "ok", "label": "dorsal_valid", "confidence": 0.9998,
            "probabilities": { "dorsal_valid": 0.9998, "health_only": 0.00015, "reject": 0.000026 },
            "decision_rule": "argmax",
            "class_map_sha256": "…", "protocol_version": "view_suitability_v1" },
  "segmentation": { "status": "ok", "confidence": 0.94, "instances_found": 1 },
  "construction": { "status": "ok", "mask_protocol": "original_coordinate_polygon_v1",
                    "mask_area_px": 184203, "bbox": [x, y, w, h], "source": "proto_coefficients" },
  "cutter": { "status": "identity_stub", "head_removal_applied": false, "pair_valid": false,
              "protocol_version": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26",
              "protocol_implemented": false },
  "features": { "status": "provisional", "family": "baseline5",
                "order": ["RA","LC","BL","BW","E"],
                "values": { "RA": 0.21, "LC": 246.8, "BL": 121.3, "BW": 44.1, "E": 0.87 },
                "measured_on": "uncut_mask" },
  "weight": { "status": "unavailable", "reason": "cutter_identity_stub",
              "user_message_key": "weight_unavailable_cutter_not_implemented",
              "capture_contract": { "feature_space": "fixed_camera_pixels",
                                    "training_camera_height_m": 1.88,
                                    "camera_height_is_xgboost_feature": false } },
  "health": { "status": "ok", "label": "Healthy", "confidence": 0.9999,
              "probabilities": { "…": 0.0 },
              "input_protocol_requested": "full_frame",
              "input_protocol_applied": "full_frame",
              "input_protocol_fallback": false,
              "decision_rule": "argmax",
              "class_map_sha256": "…", "protocol_version": "health_cvsafe_v3" },
  "artifacts": { "bundle_id": "…", "manifest_sha256": "…" }
}
```

Note the shape of the honest case. `features` is present and real; `weight` is absent as a number
and present as a state; `cutter` says exactly why. A UI cannot accidentally render the features as
a weight, because they are in a different object with `measured_on: "uncut_mask"` written on them.

Routing and failure shapes:

```json
// View rejected. Nothing downstream runs.
{ "status": "stopped", "reason": "view_rejected",
  "view": { "status": "ok", "label": "reject", "confidence": 0.97 } }

// Non-dorsal. Health runs from the constructed mask; the weight branch is skipped, not failed.
{ "status": "ok",
  "view":   { "status": "ok", "label": "health_only" },
  "segmentation": { "status": "ok" },
  "construction": { "status": "ok", "mask_area_px": 151002 },
  "cutter": { "status": "skipped", "reason": "view_not_dorsal" },
  "features": { "status": "skipped", "reason": "view_not_dorsal" },
  "weight": { "status": "skipped", "reason": "view_not_dorsal" },
  "health": { "status": "ok", "input_protocol_applied": "segmentation_crop" } }

// Segmentation found nothing. Health degrades its input; it does NOT fail. AGENTS.md rule 4.
{ "status": "ok",
  "segmentation": { "status": "error", "reason": "no_instance_above_conf" },
  "construction": { "status": "skipped", "reason": "no_instance" },
  "weight":       { "status": "unavailable", "reason": "segmentation_failed" },
  "health":       { "status": "ok", "input_protocol_requested": "segmentation_crop",
                    "input_protocol_applied": "full_frame",
                    "input_protocol_fallback": true } }
```

`input_protocol_fallback: true` is surfaced in the UI — never silently. So is
`cutter.protocol_implemented: false`, wherever a weight would otherwise have appeared.

---

## 10. Parity gates and tolerances

Three gates: **A** (Python vs the originals), **B** (C++ vs Python, per stage), and a new
degenerate **D** that pins the dummy cutter. Gate C is deleted — after section 5.2(3) no primitive
exists twice, so there is nothing left for it to compare.

**Gate A — `ML/pipeline/*.py` vs the originals** (Python vs Python, same fixtures). Run by
`ML/parity/gate_a.py`, which reconstructs `body_mask.py`, `mask_features.py`,
`extended_mask_features.py`, and `yolo_inference.py` from `git show 5bd99ce:ML/…`, so this gate
keeps running after section 5.6 removes them from the working tree.

Gate A now runs **per stage and end to end**, which is the direct benefit of splitting by process —
a failure names the stage:

| Comparison | Tolerance |
|---|---|
| stage 1+2: `construct_pig_mask(segment(img))` vs `predict_largest_mask(img)` | IoU ≥ 0.999 |
| stage 2 alone: `clean_binary_mask`, `largest_contour`, unletterbox round-trip | exact |
| stage 3: `isolate_body_only_mask(mask)` vs the original module's | IoU ≥ 0.999 |
| stage 3 QC (`pair_valid`, `head_removal_applied`, `status`) | exact match |
| stage 3 override coverage: both branches of each section-5.3(b) function | both exercised |
| stage 4: `RA, LC, BL, BW, E` | ≤ 0.5 % relative |
| stage 4: chen16 vector, where a fixture exercises it | ≤ 0.5 % relative |
| stage 5: `estimated_kg` from a fixed feature vector | ≤ 0.05 kg absolute |
| end to end: `WeightEstimator.predict()` before vs after | ≤ 0.05 kg absolute |

Re-run after **every** simplification, including the section-5.3(c) dead-code deletion. A change
that breaks gate A is reverted.

**Gate B — the five C++ stage units vs the five Python stage modules** (the shipping gate). One
file against one file, name against name:

| C++ unit | vs | Tolerance |
|---|---|---|
| `stages/segmentation.cpp` | `ML/pipeline/segmentation.py` | selected instance identical; box ≤ 1 px; coefficients ≤ 1e-3 (matches the recorded torch-vs-ORT 1.2e-3) |
| `stages/construction.cpp` | `ML/pipeline/construction.py` | mask IoU ≥ 0.95; bbox ≤ 2 px; `mask_area_px` ≤ 1 % |
| `stages/cutter.cpp` | — | **gate D below**, not gate B: there is no Python behaviour to match |
| `stages/feature_calculation.cpp` | `ML/pipeline/feature_calculation.py` | `RA, LC, BL, BW, E` ≤ 1 % relative |
| `stages/weight_prediction.cpp` | `ML/pipeline/weight_prediction.py` | `estimated_kg` ≤ 0.1 kg absolute |
| `classifier.cpp` (view) | torch reference | top-1 exact; probabilities ≤ 0.005 per class |
| `classifier.cpp` (health) | torch reference | top-1 exact; probabilities ≤ 0.01 per class |
| `pipeline.cpp` | `ML/weight_runtime.py` | routing (`reject`/`health_only`/`dorsal_valid`) exact on the corpus |

**Gate D — the cutter identity gate.** Small, and it exists so the dummy cannot silently stop being
a dummy or silently start pretending:

1. `cut_body_mask(m).mask == m` byte for byte, for every fixture mask and for edge cases (1×1,
   all-zero, all-one, non-square, odd strides).
2. `head_removal_applied == false` and `status == "identity_stub"` in **every** successful call —
   there is no input for which the dummy claims a cut.
3. `instaham_ml_predict_weight_json` returns `ERR_UNAVAILABLE` for every fixture while
   `manifest.pipeline.stages[cutter].protocol_implemented == false`.
4. The manifest assertion of section 8 (`weight.available` requires `protocol_implemented`) fails
   the build when violated.

Gate D is the mechanical form of `AGENTS.md` rule 8 for this specific stage: it makes "never force
a prediction after a failed check" a test rather than a discipline.

**~~Gate C~~ — deleted.** Revision 5 created it to pin five primitives that had to exist in both a
C++ and a Python runtime; revision 6 demoted it; revision 7 removes the duplication entirely
(stage 3 imports stage 2's primitives rather than inlining copies), so there is nothing left to
compare. `ML/parity/gate_c.py` is deleted with it.

All gates run against the exact ORT and opencv-mobile builds that will ship.

---

## 11. What the port actually costs

Three costs are named here because each has been quietly assumed in earlier revisions.

### 11.1 OpenCV becomes a hard dependency, not an option

`INSTAHAM_ML_WITH_OPENCV` is currently `OFF` and the native library uses `stb_image` plus
hand-written resize/letterbox in `util/image_io.cpp`. Stages 2 and 4 cannot be written that way.
Between them the Python reference calls:

`cv2.connectedComponentsWithStats`, `cv2.morphologyEx`, `cv2.getStructuringElement`,
`cv2.findContours`, `cv2.contourArea`, `cv2.arcLength`, `cv2.minAreaRect`, `cv2.fitEllipse`,
`cv2.fillPoly`, `cv2.drawContours`, `cv2.resize`, `cv2.warpAffine`, `cv2.PCACompute`,
`cv2.boundingRect`.

`fitEllipse` and `minAreaRect` in particular are non-trivial numerical routines whose exact output
gate B's 1 % tolerance depends on; reimplementing them by hand would put stage 4 in the same
category as stage 3.

So: **turn `INSTAHAM_ML_WITH_OPENCV` on for Android and iOS, and fetch opencv-mobile
(`core` + `imgproc` only) in `scripts/fetch_deps.sh`.** Expected size, static, per ABI: **3–6 MB**,
against the ~40 MB segmentation model already in the bundle. That is an acceptable trade and it is
the enabling decision for stages 2 and 4 — it should be taken explicitly at the start of the port
slice rather than discovered in the middle of it.

`util/image_io.cpp`'s decode path stays on `stb_image`: it works, it is small, and swapping it for
`cv::imdecode` would change the decoded pixels under every recorded classifier metric.

### 11.2 The fixture corpus is still the thing everything is gated on

Verified on disk: `test/fixtures/` does not exist, and `ML/health_cnn/` holds CSVs but no images.
Two consequences, unchanged from revision 6 and still true:

| Gate | Needs | Status |
|---|---|---|
| `probe_health_input.py` (sets `health.input.protocol`) | the 2812 Roboflow test images named in `test_predictions.csv` | **not in repo** — reports `probe_status: "not_run"` |
| Gates A, B, D | 30–60 pig photos + their YOLO masks, spanning dorsal and non-dorsal, covering **both branches of each section-5.3(b) override** | **not in repo** |

The corpus work is a slice of its own (section 13). Commit the **derived** artifacts —
`mask.npy`, expected feature vectors, expected envelopes — not the photos, so the corpus lives in
git while the imagery stays under whatever consent terms it carries (`AGENTS.md`: no retaining
research images without explicit consent). Assert override coverage before declaring the corpus
done: without it, gate A can be green on a corpus that cannot tell the two implementations apart,
and the section-5.6 deletion would be unsafe while looking safe.

**Until the corpus exists, gate A runs on synthetic masks only.** That is what it does today
(`ML/parity/gate_a.py` builds synthetic shapes), and it is honest — it catches structural breakage
from the merge, which is most of what the merge can break, and it does not catch numerical drift on
real pig geometry. The plan does not claim otherwise.

### 11.3 Two model problems that no amount of this work fixes

Recorded in `TASKS.md` cause D and repeated here so the refactor is not mistaken for a fix:

- **The view model's three classes come from disjoint source datasets** (`dorsal_valid` from
  `pigrgb_*`/`piglife`/`porac`; `health_only` **entirely** from the `health` Roboflow set). The
  easiest boundary available during training was "which dataset is this", not "what pose is this",
  so 0.9727 test accuracy does not transfer to a phone photo in a pen.
- **The health model is trained on close-up lesion crops** and is being run `full_frame` on a
  distant whole-pig photo. Softmax will still return a confident label.

Both are data problems. Sections 5–12 make the pipeline correct, inspectable, and honest; they do
not make an extrapolating classifier right. The measurement that would settle the health half is
`probe_health_input.py`, and it is blocked on 11.2.

---

## 12. Fixing the wiring of the models in the app

`refactor_plan.md`: *"Make sure that the wiring of the models in the app gets fixed by this change
too."* Five defects were catalogued here; execution (slice R5) found two already fixed by
`TASKS.md` P0/P2 before this revision was written, and closed the remaining three. What follows is
the defect as found, and the fix as actually applied — not always the fix originally proposed,
where checking the live code changed what the right fix was.

### 12.1 Defect A — the dead pipeline use case still contradicts the pipeline ⚠ live → ✅ fixed (deleted)

`lib/features/inference_pipeline/domain/use_cases/run_inference_pipeline_use_case.dart` is
referenced by **nothing in `lib/`** — only by
`test/features/inference_pipeline/run_inference_pipeline_use_case_test.dart`. The app runs
`RunAndPersistPipelineUseCase` instead (`results_screen.dart:58`). The dead file nevertheless
still encodes the old, wrong contract:

- Line 33–34: `viewConfidenceThreshold = 0.70`, `healthConfidenceThreshold = 0.60` — the invented
  constants `TASKS.md` cause B measured as destroying 70 correctly-classified dorsal images out of
  2599.
- Line 70–73: rewrites any sub-threshold prediction to `reject`.
- Line 81: `if (viewResult.isReject || !viewResult.isDorsalValid)` returns
  `health: null` — so a `health_only` photo gets **no health result at all**. That is the exact
  opposite of `refactor_plan.md`'s `no -> use base segmentation mask for health cnn`, and it
  breaks `AGENTS.md` rule 4.

**Fix, as executed:** the live path (`RunAndPersistPipelineUseCase`, wired from
`results_screen.dart`) already runs argmax with no invented threshold and already routes
`health_only` through health — that bug lives only in the dead file. Rather than resurrect it as a
second, competing pipeline implementation (which is the actual defect per the closing sentence
above), it was deleted outright along with its dedicated test and the test-only mocks that existed
solely to exercise it (`run_inference_pipeline_use_case.dart`,
`run_inference_pipeline_use_case_test.dart`, `test/helpers/mock_ml_services.dart`). Verified before
deletion: every entity and use case it also touched (`SegmentationResultEntity`,
`WeightResultEntity`, `HealthResultEntity`, `ViewResultEntity`, `ComputeScaleUseCase`,
`WeightEligibilityChecker`) has its own independent test and is not orphaned.
`instaham_ml_run_pipeline_json` remains the target for a future real migration off the
DB/`PipelineEvent` persistence model this app actually uses — that migration is a larger,
separate piece of work than this defect, and is not part of this pass.

### 12.2 Defect B — segmentation output cannot express a mask ⚠ live → ✅ fixed

`lib/services/ml/segmentation_service.dart`'s `SegmentationResult` was `{pigCount, confidence,
maskAvailable}` with a `TODO` for the mask. Now that stage 2 exists, `instaham_ml_segment_json`
returns `mask_area_px`, `bbox`, and `mask_protocol` (section 7), and `SegmentationResult` carries
them (`maskAreaPx`, `bboxX/Y/W/H`, `maskProtocol`); `maskAvailable` now means "a mask was
constructed", not "a box was detected".

### 12.3 Defect C — the weight service is an interface with no implementation ⚠ live → ✅ fixed

`lib/services/ml/weight_regression_service.dart` declared `IWeightRegressionService` with
`loadModel()` and `predict(WeightFeatures)`. Nothing implemented it, and its shape assumed the app
computes features and calls a regressor — the revision-3 Dart-orchestration model this plan has
rejected three times. Deleted, along with `MockWeightRegressionService` (its only remaining
consumer, itself only used by the dead file removed in 12.1). No live code referenced either.

### 12.4 Defect D — the view gate at capture time ✅ fixed, keep it fixed

`capture_screen.dart:410` calls `RunAndPersistPipelineUseCase.resolveViewGate` before routing, and
`RunAndPersistPipelineUseCase` reuses the persisted `view` event rather than re-running the model.
That is `TASKS.md` P0 and it is correct: the view gate decides whether reference marking — which
exists only to serve the weight branch — happens at all.

**Keep:** a regression test asserting that a `health_only` photo never reaches
`/reference-marking`, and that a `reject` photo reaches neither reference marking nor analysis.

### 12.5 Defect E — the results screen collapses distinct outcomes into "Unavailable" ⚠ partially live → ✅ fixed

Corrected during execution: `TASKS.md` cause C (no view card; every view-gate stop reads as a
health failure) was **already fixed** by the time this revision was written — `results_screen.dart`
has its own `_viewCard`, and `_healthCard` already distinguishes `'Skipped'`
(`viewEvent?.status == 'reject'`) from `'Unavailable'` (a real classification failure). Revision 6's
description of this defect was stale against `TASKS.md`'s own P2, not against the current code.

**What was actually still live:** `_weightCard` had no equivalent split — a not-dorsal photo
(`ViewResultEntity` routing) and a genuine `segmentation_failed`/no-model-yet failure both rendered
as the single word "Unavailable". Fixed by giving `_weightCard` the same `skippedByViewGate` pattern
`_healthCard` already uses: `viewEvent.status != 'dorsal_valid'` now renders `'Skipped'`
(`ResultStatus.skipped`), everything else renders `'Unavailable'` (`ResultStatus.blocked`), and the
existing `failureReason` text (already stage-specific in `RunAndPersistPipelineUseCase`) supplies
the message either way — no new data plumbing needed.

A `measured_on: uncut_mask` diagnostics view for the provisional features of section 3.4 rule 3 is
not part of this pass — `instaham_ml_extract_features_provisional_json` exists and is correct, but
nothing in `lib/` calls it yet, matching the DB/`PipelineEvent` architecture note in 12.1.

### 12.6 One smaller wiring correction

Corrected during execution: revision 6 claimed `assets/ml/segmentation/classes.json` was missing
from `pubspec.yaml` while `MlRuntime._bundledMlAssets` expected to stage it. Checked against the
actual code: `manifest.cpp`'s `load_segmentation()` never reads a `class_map` block at all (`nc=1`,
a single "pig" class, never looked up by name), and `_bundledMlAssets` never referenced the file
either. There was nothing to add — the claim did not survive contact with the code, so this item
is dropped rather than "fixed" against a file nothing needs.

- **`instaham_ml.h` and `ml_runtime.dart` both reference `MlRuntime.exifNormalize`, which does not
  exist.** EXIF is actually baked at capture by `ImageService.processRawBytes`
  (`lib/core/utils/image_service.dart:29`, `img.bakeOrientation`), and
  `ImageUtils.correctExifOrientation` is dead code. `AGENTS.md` rule 5 is satisfied — but by a
  different function than every comment claims. Point the comments at the real site and delete the
  unused one, so the next reader does not go looking for a guarantee where it is not.

---

## 13. Ordering, sizing, and exit criteria

Sizes are **engineer-days for one engineer**, stated as *p50 – p80*, each with the assumption it
rests on. An estimate without a stated assumption is a guess wearing a number.

**Total: 25–39 engineer-days** to a shipped view + segmentation + construction + health product
with honest provisional features on both platforms. The weight branch is not in that number
because it is not deliverable while the cutter is a dummy — by design (section 3.4).

| Slice | Contents | Size | Assumes | Definition of done |
|---|---|---:|---|---|
| **R0 — Fixtures** | 30–60 photos + YOLO masks; derived artifacts committed under `test/fixtures/parity/`; both section-5.3(b) override branches covered; `ML/parity/data_sources.json`. | **3–5 d** | Suitable photos are obtainable from the existing research sets. If not, gate A stays synthetic and this is recorded, not papered over. | Corpus committed; override coverage asserted. |
| **R1 — Python refactor** | The section-5.2 merge into `ML/pipeline/*.py`; section 5.3 corrections; section 5.6 deletions; section 5.7 repoints; `consolidate_helpers.py` rewritten; `check_five_stages.sh` + rewritten `check_cutter_purity.sh`; gate A extended to five stages. | **3–5 d** | The merge is mechanical because `consolidate_helpers.py` already solved the override resolution once. | Five stage files; four predecessors deleted; gate A green (synthetic if R0 has not landed); `pytest ML/parity` green. |
| **R2 — Stage 1+2 native** | OpenCV turned on and fetched (11.1); `segmenter.cpp` → `stages/segmentation.cpp` emitting coefficients + proto; `stages/construction.cpp`; `test_construction.cpp`; `instaham_ml_segment_json` gains mask fields. | **6–9 d** | opencv-mobile prebuilts fetch cleanly for both ABIs; the proto decode matches the reference within IoU 0.95 without a second export. | A real pig mask, in original image coordinates, on a device. |
| **R3 — Stage 3+4 native** | `stages/cutter.{h,cpp}` moved under `stages/` unchanged; `test_cutter_identity.cpp` (gate D); `stages/feature_calculation.cpp` (baseline5); `instaham_ml_extract_features_provisional_json` returns real features. | **4–6 d** | `fitEllipse` / `minAreaRect` reproduce the Python within 1 % — the reason 11.1 insists on real OpenCV rather than hand-rolled geometry. | Gate D green; gate B green for stages 3 and 4; provisional features visible in a diagnostics view. |
| **R4 — Stage 5 + pipeline** | `stages/weight_prediction.cpp`; `pipeline.{h,cpp}`; `instaham_ml_run_pipeline_json`; the section-8 manifest bump to `schema_version: 4` incl. the `weight.available` ⇒ `protocol_implemented` assertion; `result_envelope`. | **3–5 d** | The XGBoost ONNX already exports (it does — `ML/export/export_xgboost.py` runs today). | One FFI call returns the complete section-9 envelope; `weight` is `unavailable` with the right reason on every path. |
| **R5 — App wiring** | All of section 12. `inference_pipeline_service.dart` + impl; `weight_regression_service.dart` deleted; the results screen's view card and three-state weight card; pubspec + comment corrections; regression tests for routing. | **4–6 d** | The section-9 envelope is stable by the time this starts — hence R4 first. | `flutter test` green; on a device: a dorsal photo shows mask + health + an honest weight-unavailable card; a `health_only` photo shows health and skips reference marking. |
| **R6 — Health input protocols** | `segmentation_crop`, `segmentation_masked` implemented in `health_input.cpp` now that a mask exists; `abnormality_crop` per the `TASKS.md` P5 addendum, behind its healthy-first gate; `test_health_input.cpp` over all four. | **3–5 d** | R2 landed, so there is a mask to crop against. The *choice* between protocols still needs `probe_health_input.py`, which needs 11.2's images. | All four protocols implemented and switchable by manifest; the applied protocol reported in every envelope. |
| **R7 — Hardening** | APK size (models + OpenCV); quantisation evaluated against section 10, not assumed; Play Asset Delivery / ODR; device benchmarks; the full parity suite un-skipped. | **3–5 d** | Quantisation may be rejected on parity grounds. | Size delta recorded and accepted; benchmarks published. |

### 13.1 Critical path

```
R0 ──┐
     ├──► R1 ──► R2 ──► R3 ──► R4 ──► R5 ──► R7
     │            └────────────────► R6 ──►┘
     └── (if R0 slips, R1 still runs on synthetic gate A; R2/R3 gate B waits for R0)
```

- **R1 is independent of every native decision** and can start immediately.
- **R2 is the single highest-value slice**: it is the first time a real pig mask exists anywhere in
  the product, and it unblocks R3, R6, and half of R5.
- **R5 is the natural stopping point.** After it, the app runs the full `refactor_plan.md` graph
  minus weight, honestly, on both platforms.
- **Nothing here waits on a cutter.** That is the whole point of section 3.4.

### 13.2 Health checks — how to tell a slice is in trouble before it is late

| Slice | Check | Trigger | Response |
|---|---|---|---|
| R1 | day 2 | gate A fails on stage 3 after the merge | The override resolution (5.3(b)) is wrong. Re-run `consolidate_helpers.py` rather than hand-patching; a hand-patch here is how late binding gets silently swapped. |
| R2 | day 3 | the decoded mask disagrees with the reference beyond IoU 0.95 | Suspect the `mask_ratio 4` upsample and the letterbox crop order before suspecting the export — the export is verified to 6.7e-6 on the prototype. |
| R2 | day 2 | opencv-mobile will not fetch or link for an ABI | Re-baseline R2 and R3 immediately; hand-rolling `fitEllipse` is not an option (11.1). |
| R3 | any | a temptation appears to "just make the cutter do something" | No. Gate D exists to stop this. A partial cut is worse than no cut: it produces features that look plausible and are wrong. |
| R4 | any | a manifest is produced with `weight.available: true` | The section-8 assertion should already have failed the build. If it did not, fix the assertion before anything else. |
| R5 | end | a device shows mask + health + an honest weight card | ✅ **This is the milestone that answers "does the pipeline work?"** |
| any | any | a stated assumption is found false | Re-estimate that slice openly. The assumptions are written down precisely so this is mechanical rather than an argument. |

### 13.3 What is deliberately not estimated

- **Implementing the cutter for real.** Out of scope by instruction. When it returns, it returns as
  its own programme with its own reachability numbers (5.3(c)), and section 8's
  `protocol_implemented` flag is the switch it flips.
- **Retraining the weight regressor** so it no longer depends on a fixed 1.88 m camera height
  (section 2.3). Most likely to make the cutter question moot by changing what the weight branch
  needs.
- **Recovering the health test split.** Depends on an environment outside this repo; if it is gone,
  no engineering replaces it and the response is the declared partial probe.
- **Retraining the view model on a pooled, source-balanced set** (11.3). The single highest-value
  ML action available, and not a code task.

---

## 14. Enforcement

Conventions that are not checked are decoration. Four scripts, all fast, all in CI:

| Script | Asserts |
|---|---|
| `scripts/check_five_stages.sh` | exactly five files in `ML/pipeline/` and five `.cpp` in `stages/`, names matching pairwise; no sixth in either |
| `scripts/check_stage_order.sh` | no stage imports a later stage, in Python or C++ (grep of `from ML.pipeline.` and `#include "stages/`) |
| `scripts/check_cutter_purity.sh` | *(rewritten)* stage 3 imports only stage 2, does no file IO, touches no model runtime, reads no manifest |
| `scripts/check_layering.sh` | the section-3.1 include table; `instaham_ml.cpp` includes only `pipeline.h` and infrastructure |

`scripts/check_one_helper.sh` is deleted — its rule (exactly two helper files) is superseded.

Plus the two assertions that live in the manifest builder rather than a script, because they must
fail the *bundle*, not the source tree: `weight.available` ⇒ `cutter.protocol_implemented`, and
`feature_extractor` family ∈ `families_compiled`.

---

## 15. Risks, ranked

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **The mask decode does not reproduce ultralytics' postprocess.** 32 coefficients × a 160×160 prototype, sigmoid, crop to box, upsample, unletterbox — the order matters and small mistakes look plausible. | medium | R2 slips; every downstream stage waits | Gate B stage 2 at IoU 0.95 against the Python reference on real fixtures; test the round-trip separately from the decode |
| 2 | **The corpus never materialises**, so gates A and B stay synthetic. | medium | the port is structurally verified but numerically unverified | Stated openly rather than claimed; `probe_status`/`evidence` fields carry the truth into the manifest; R0 runs first if it can |
| 3 | **Someone makes the cutter "do something".** A partial cut produces confident, wrong weights. | low–medium | wrong kilograms shown to a user | Gate D; the section-8 manifest assertion; three separate places in the envelope that say `identity_stub` |
| 4 | **`fitEllipse` / `minAreaRect` differ between opencv-mobile and desktop OpenCV** enough to breach the 1 % feature tolerance. | low | R3 slips | Gate B runs against the shipping opencv-mobile build, not a host build |
| 5 | **The merge silently swaps an overridden implementation** (5.3(b)). | low | wrong body masks, invisibly | Static resolution via `consolidate_helpers.py`; gate A with mandatory both-branch coverage; never dedupe on name |
| 6 | **The app keeps two pipeline use cases with different routing.** | medium | the defect fixed in one reappears from the other | 12.1 deletes one; a routing regression test covers the survivor |
| 7 | **OpenCV pushes the APK past a size the team will accept.** | low | R7 rework | 3–6 MB per ABI against ~40 MB of model — measure in R2, decide in R7 |

---

## 16. Plan rating

**8 / 10.**

**Pros**

- **The organising axis now matches the instruction and the pipeline.** Five processes, five Python
  files, five C++ units, names matching pairwise, enforced by a two-line CI script. Gate B becomes
  five file-to-file comparisons that each name the stage that broke, instead of one comparison
  against a 1,200-line blob.
- **It deletes far more than it adds.** Chaquopy, the suspended pipeline, three ABI entrypoints, the
  handle table and its TTL, `CutterChannel.kt`, the Gradle copy task, the Python manifest block, the
  device gate, gate C, two spikes, and 65–85 MB per ABI all go. The dummy cutter is the cheapest
  possible seam and it is already on disk.
- **The merge inputs are verified, not assumed.** All six `.old_py_files/` modules are byte-identical
  to `git show 5bd99ce:ML/*`, so gate A stays runnable after the working copies are deleted and the
  subtractive rule survives intact.
- **The dishonest failure mode is closed mechanically.** `weight.available ⇒
  cutter.protocol_implemented` fails the *bundle build*; gate D fails the *test suite*; three
  envelope fields carry `identity_stub` to the UI. `AGENTS.md` rule 8 stops being a discipline and
  becomes a check.
- **The app wiring is in scope with named files and line numbers**, including one defect
  (`health: null` for `health_only`) that contradicts both `AGENTS.md` rule 4 and `refactor_plan.md`
  directly.
- **Two costs that earlier revisions left implicit are now explicit**: OpenCV becomes a hard
  dependency with a size number attached, and the fixture corpus is named as the thing every
  numerical claim rests on.

**Cons**

- **The weight branch still ships nothing.** That is the honest consequence of a dummy cutter, and
  it is the deliverable the product most visibly lacks. The plan is candid about it, but candour is
  not a weight estimate. Anyone reading this expecting kilograms will be disappointed, and correctly
  so.
- **Gate B is only as good as a corpus that does not exist.** Until R0 lands, "gate B green" means
  "green on synthetic masks", which will not catch the numerical drift most likely to matter.
- **Stage 5 is built against a regressor that is flagged temporary and is valid only at a fixed
  1.88 m camera height.** The port is cheap and manifest-driven, so this is a small bet — but it is
  a bet on a model that may be replaced before it is ever used.
- **`predict_largest_mask` splitting across two stages is the one place the merge can change
  behaviour**, and it is exactly the place where letterbox arithmetic gets re-derived by accident.
  Section 5.4 constrains it and gate A measures it; it remains the merge's sharpest edge.
- **The C++ rename churn is real.** `segmenter.cpp` → `stages/segmentation.cpp`, `cutter.cpp` →
  `stages/cutter.cpp`, plus a new `pipeline.cpp` that did not exist under any previous revision's
  actual (as opposed to documented) tree. Renames are cheap but they invalidate the build cache and
  every path in `CMakeLists.txt` and the Android `.cxx` config.
- **chen16 is deferred to reference-only status** on the argument that no shipping model selects it.
  That is true today and would need revisiting the moment a 16-feature regressor is trained — at
  which point `skeletonize` becomes a C++ problem after all, just a small one.
