# ML Inference Integration — INSTAHAM Flutter App (Native C++ / `dart:ffi`)

> **Revision 6 (2026-08-28).** Spike S3 was run early, and its result splits revision 5's single
> decision into two — one now settled on evidence, one now explicitly deferred.
>
> **(1) The cutter is not ported to C++. Settled, and now measured.** S3's reachability pass over
> `ML/pig_cutter.py` from `isolate_body_only_mask()` found **9,911 of 10,855 lines live (91 %)**,
> with only 380 lines dead. Seven live functions totalling **1,985 lines** call
> `scipy.gaussian_filter1d`, `scipy.find_peaks`, or `skimage.skeletonize` directly. Revision 5
> guessed this port was the programme's largest risk; revision 6 has the number. Not porting it is
> correct (section 5.2(c) records the full result).
>
> **(2) Shipping that Python *on device* is a separate decision, and it is DEFERRED to slice 5.**
> Revision 5 conflated "don't port the cutter" with "ship Chaquopy on Android", and committed to
> both at once. They are not the same decision and they do not cost the same. Not porting is free;
> shipping Chaquopy costs **the entire iOS weight branch** plus roughly 65–85 MB of APK per ABI
> (CPython + numpy + scipy + scikit-image) on top of the ~40 MB segmentation model — and S1, which
> would tell us it even works, has not run. Revision 6 therefore builds everything that does not
> depend on that choice first, and takes the choice when it is actually due (section 3.5).
>
> **(3) The runtime boundary moves, if Python ships at all.** Revision 5 split mid-geometry: C++
> cleans the mask, Python cuts, C++ extracts features. That split is what forced five primitives to
> exist in both runtimes and what created gate C. Drawing the boundary at the **segmentation mask**
> instead — one hop, mask in, five features out — deletes the duplication and gate C outright
> (section 3.3). The old split bought nothing for its complexity.
>
> **What this means for sequencing.** Slices 1, 3, and 4 need **no cutter at all**, work identically
> on both platforms, and deliver view + segmentation + health — most of `TASKS.md`. They are the
> whole near-term plan. The cutter's runtime is decided at slice 5, by which point S1 has run and
> the weight model's `"temporary"` status and fixed-1.88 m-camera contract (section 2.3) may have
> changed. **The decision is cheap now and expensive to unwind once Chaquopy is in the build.**
>
> Carried forward from revisions 4–5: consolidation is *subtractive* — the originals are deleted,
> not kept as "frozen reference" (section 5.5); the one-file-per-runtime rule holds (section 3.1.1);
> and section 11 keeps sizes, assumptions, definitions of done, and exit criteria for every slice.
>
> Supersedes revisions 1–5.

---

## 1. The pipeline

From `TASKS.md`:

```
pig -> view type -> segment -> dorsal? -> yes or no
yes -> use py cut off helpers to predict weight -> use base segmentation mask for health cnn
no  ->                                            use base segmentation mask for health cnn
```

Resolved against what the checkpoints actually accept:

```
EXIF-normalised RGB photo
  │
  ├─► [view]  GhostNetV3 1.0x, 3 classes, raw full photo
  │      ├── reject       ──► STOP. No segment, no health, no weight.
  │      ├── health_only  ──┐
  │      └── dorsal_valid ──┤
  │                         │
  ├─────────────────────────┴─► [segment]  YOLO11s-seg (LDConv+ACmix), 640 letterbox
  │                                 └── base mask, remapped to original coordinates
  │                                        │
  │        dorsal_valid only ──────────────┼──► [clean + dorsal core]      C++
  │                                        │        └──► ✂ [CUT head/neck]  PYTHON, not ported
  │                                        │                └──► [features] RA,LC,BL,BW,E   C++
  │                                        │                      └──► [weight] XGBoost ──► kg
  │                                        │
  │        both branches ──────────────────┴──► health input (manifest protocol)   C++
  │                                                 └──► [health] GhostNetV3 1.0x, 10 classes
```

Everything above is C++ except the one box marked **PYTHON**. That box is `ML/pig_cutter.py`
running under Chaquopy on Android; on iOS it does not exist and the weight branch reports
`unavailable`. Section 3.3 is the runtime boundary; section 3.4 is why the flow suspends there.

### 1.1 Four consequences that change the design

**(a) View runs on the raw photo, before segmentation.** Evidence:
`ML/view_model/test_predictions.csv` draws from five sources —
`pigrgb_rgb` (2208), `health` (2859), `piglife` (431), `pigrgb_masked` (389), `porac` (11).
Mostly unmasked. The view model is a source-agnostic gate, so it cannot require a mask, and
`TASKS.md`'s `view type -> segment` order holds as written.

**(b) Segmentation is now on the critical path for health, not just weight.** Previously a failed
segmentation only cost the weight branch. Under this pipeline it would also cost health, which
collides with `AGENTS.md` rule 4 (weight and health branches independent). Resolved by making the
health input protocol manifest-declared with an explicit fallback — see (c) — and recording which
protocol was actually used in the result envelope. Segmentation failure degrades health input; it
never silently blocks health.

**(c) ⚠ The shipped health checkpoint was trained on plain photos, not segmentation masks.**
`ML/health_cnn/test_predictions.csv` is 100 % `health::train|valid/<class>/<file>.rf.<hash>.jpg` —
a Roboflow disease dataset of skin-lesion photos. No masked or segmented source appears.
Feeding it a segmentation-masked crop is train/serve skew and will silently degrade accuracy below
the recorded 0.9285.

This does **not** block the work. The design asked for is delivered, made switchable rather than
hardcoded:

| `health.input.protocol` | Meaning |
|---|---|
| `full_frame` | resize-shorter-side 255 + center-crop 224 of the EXIF-normalised photo. Matches the shipped checkpoint's training distribution. |
| `segmentation_crop` | crop to the mask bounding box (with padding ratio), background **retained**, then the same resize/crop. |
| `segmentation_masked` | crop to the mask bounding box, background zeroed or mean-filled, then the same resize/crop. |

All three are cheap `geometry/` operations and all three are built. The manifest picks one; there
is no rebuild, no ABI change, and no Dart change to switch. `on_segmentation_failure` selects
`full_frame` or `abort` per `AGENTS.md` rule 8.

**Decisive verification, cheap to run (Slice 1 gate).** `ML/health_cnn/test_predictions.csv`
records per-sample probabilities for 2812 test images. Re-run the checkpoint over those images
under each protocol; the protocol that reproduces the recorded probabilities *is* the training
protocol. That result — not this document — sets the manifest default. Until it runs, the default
is `full_frame`, because that is what the dataset paths indicate.

⚠ **Cheap to run, but not yet runnable.** The CSV records paths and probabilities; the images
themselves are not in the repo. Recovering them is slice −1 (section 11.3.1), and if they cannot be
recovered the probe degrades to a partial run over whatever subset exists, recorded honestly in
`health.input.evidence` rather than asserted as 2812.

**(d) The weight branch may end up platform-asymmetric — and either way that must be a
first-class state, not a bug.** *If* the cutter ships as on-device Python (the deferred decision of
section 3.5), the weight branch exists on Android and not on iOS. The plan already has the
vocabulary for this — `capabilities.weight.available: false` and an envelope `status: "unavailable"`
with a reason — so no new mechanism is needed under any option; what is needed is the discipline to
treat a device-without-weight as a **shipped, coherent product** rather than a broken build.
Concretely:

- The manifest is built per platform. `weight.available` reflects whether *this* build can actually
  reach a cutter, whatever the eventual mechanism.
- `AGENTS.md` rule 4 already forbids a failed weight branch from touching health, so a
  weight-less build is view + segmentation + health, complete and honest.
- The UI renders "weight estimation is not available on this device" — a stated limitation, never
  a spinner that never resolves and never an invented number (`AGENTS.md`: no invented scores).
- Nothing else in the pipeline changes shape between platforms. One code path, one manifest schema,
  one envelope; a flag decides.

**This machinery is built in slice 4 regardless of the section-3.5 decision**, because a
weight-unavailable envelope is exactly what slices 1–4 ship on *both* platforms anyway. That is
what makes the deferral cheap: the "no weight here" path is not a fallback bolted on later, it is
the default state of the product until slice 5 fills it in.

---

## 2. Research artifacts on disk

Folders are now named by purpose. Checkpoints are `.gitignore`d (`*.pt` line 60, `*.onnx` line 62),
so weights are local-only export inputs; provenance travels as the `source_run.checkpoint_sha256`
recorded in the manifest.

| Folder | Capability | Weights | Classes | Status |
|---|---|---|---|---|
| `ML/view_model/` | view type | `best.pt` 28.6 MB, `last.pt` 84.2 MB | `{dorsal_valid:0, health_only:1, reject:2}` | **complete** |
| `ML/segmentation/` | segment | `weights/best.pt` 80.7 MB, `weights/best_eval_fp32.pt` 40.5 MB | `{0: pig}` | **complete** |
| `ML/health_cnn/` | health cnn | `best.pt` 28.6 MB, `last.pt` 84.3 MB | 10 disease classes | **complete** |
| `ML/weight_prediction/` | weight | `model.json`, `model.metadata.json` | features `[RA, LC, BL, BW, E]` | **complete, treated as temporary** |

### 2.1 View and health are the same architecture

Both checkpoints are **GhostNetV3 1.0x**: `conv_stem.weight` `[16,3,3,3]`, `conv_head.bias`
`[1280]`, 3404 re-parameterisation (`rpr`) key hits each. Only the classifier head differs —
`[3,1280]` for view, `[10,1280]` for health. One vendored architecture file and one C++
`classifier_model` serve both; the head size comes from `classes.json`.

| | view | health |
|---|---|---|
| best epoch | 2 (early-stopped at 14, patience 12) | recorded in checkpoint |
| optimizer | `adamw`, lr 1e-4, wd 1e-4 | `adam`, lr 1e-4, wd 1e-4 |
| scheduler | factor 0.5, patience 5 | factor 0.5, patience 20 |
| epochs configured | 80 | 150 (patience 40) |
| seed / batch / AMP | 42 / 32 / on | 42 / 32 / on |
| test accuracy | 0.9727 (macro-F1 0.9498, ROC-AUC ovr 0.9987) | 0.9285 (macro-F1 0.9290) |

Recorded view-gate safety, carried into the manifest as **recorded metrics, never runtime
thresholds**: false-weight-accept 5/3299 (0.15 %), false-weight-reject 75/2599 (2.9 %). Roughly
1 in 35 genuinely dorsal photos is routed away from the weight branch — that sizes the "weight
unavailable, health still shown" UX path.

### 2.2 Segmentation checkpoint facts that constrain the export

Read from `ML/segmentation/weights/best_eval_fp32.pt` and `args.yaml`:

- `ultralytics` **8.4.121** — pin it; `SegmentationModel` is pickled, so the loader must match.
- Weights live in `ema`; top-level `model` is `None`; `optimizer` and `scaler` are `None`.
  `best_eval_fp32.pt` (40.5 MB) is the clean fp32 EMA export candidate — use it, not `best.pt`.
- Epoch 147, `instaham_checkpoint_precision: fp32`.
- **Custom modules are pickled under the module path `src.yolo_modifications`** —
  `LDConv`, `ACmix`, `ACmixLDConvDownsample`. The repo has `ML/yolo_modifications.py`. Unpickling
  fails unless that path resolves. `ML/weight_runtime.py` documents the same `src.` root for
  `src.body_mask` / `src.yolo_inference`, so **one shim serves everything**.
- `instaham_neck_modification`: `first_neck_index 17`, `second_neck_index 20`,
  `ldconv_num_param 5`, `acmix_kernel_att 7`, `acmix_heads 4`, `acmix_kernel_conv 3`.
  "LDConv replaces both neck stride-2 Conv blocks; ACmix is immediately before the second LDConv."
- `imgsz 640`, `rect false`, `single_cls false` with `nc 1` (`names {0: "pig"}`),
  `mask_ratio 4` → mask prototypes are **160×160**, 32 coefficients; `overlap_mask true` is a
  training-only setting; `retina_masks false`; `iou 0.7`.

### 2.3 `ML/weight_prediction/` is temporary

`model.metadata.json`: `features [RA, LC, BL, BW, E]`, `n_estimators 300`, `max_depth 5`,
`learning_rate 0.05`, `subsample 0.8`, `colsample_bytree 1.0`, `reg_alpha 0.1`, `reg_lambda 1.0`,
target `weight_kg`.

Because `model.json` is expected to change, the weight capability is built to be **replaced by
re-running one export script**: the feature order, estimator count, and objective all come from
`model.metadata.json` into the manifest, and the native regressor reads its contract from the
manifest. Swapping the model is an export plus a sha256 change — no C++ edit, no ABI change, no
Dart change. The native layer refuses to run if the new model's feature names are not exactly
`RA, LC, BL, BW, E` (`AGENTS.md` rule 2).

---

## 3. Architecture — layering and isolation

`TASKS.md` sets three hard constraints:

1. Models and helpers must not affect each other.
2. Inference-running code must be separate from model and helper code.
3. There must be a clear entry point.

These are satisfied by five layers with a **one-directional dependency rule**:

```
  ┌──────────────────────────────────────────────────────────────┐
  │  instaham_ml.cpp        the C ABI. Thin. Marshals only.      │  entry point
  └───────────────────────────┬──────────────────────────────────┘
                              │ includes pipeline/ only
  ┌───────────────────────────▼──────────────────────────────────┐
  │  pipeline/              THE FLOW. Section 1's graph lives     │  orchestration
  │                         here and nowhere else.                │
  └───────────────────────────┬──────────────────────────────────┘
                              │ includes capabilities/ only
  ┌───────────────────────────▼──────────────────────────────────┐
  │  capabilities/          one facade per capability. The only   │  composition
  │                         layer allowed to touch both sides.    │
  └──────────────┬───────────────────────────┬───────────────────┘
                 │                           │
  ┌──────────────▼─────────────┐ ┌───────────▼───────────────────┐
  │  models/                   │ │  geometry/ — ONE unit:        │
  │  ONNX sessions. Tensors in,│ │  pig_geometry.{hpp,cpp}, the  │
  │  tensors out. Knows nothing│ │  1:1 port of pig_geometry.py. │
  │  about masks or features.  │ │  Never sees models or ONNX.   │
  └──────────────┬─────────────┘ └───────────┬───────────────────┘
                 │                           │
  ┌──────────────▼───────────────────────────▼───────────────────┐
  │  core/    manifest · image IO · tensor buffers · json · errors │  infrastructure
  └──────────────────────────────────────────────────────────────┘
```

### 3.1 The dependency rule, stated exactly

| Layer | May include | Must never include |
|---|---|---|
| `core/` | standard library, OpenCV, nlohmann/json | anything in this project |
| `models/` | `core/`, ONNX Runtime | `geometry/`, `capabilities/`, `pipeline/` |
| `geometry/` | `core/`, OpenCV | `models/`, ONNX Runtime, `capabilities/`, `pipeline/` |
| `capabilities/` | `core/`, `models/`, `geometry/` | `pipeline/`, another `capabilities/` header |
| `pipeline/` | `core/`, `capabilities/` | `models/`, `geometry/` directly |
| `instaham_ml.cpp` | `core/`, `pipeline/` | everything else |
| `ML/pig_cutter.py` (Python, if it ships) | numpy, cv2, scipy, skimage, its own private copies of the cleanup primitives and `extract_five_features` | anything C++, any model, any file IO, any manifest |

Note what the last row forbids: the cutter never loads a model, never reads a file, and never sees
the manifest. It is a pure function from mask to mask. That keeps it inside the same isolation rule
as `geometry/` — it simply happens to be written in a different language and to run in a different
runtime.

**`models/` and `geometry/` never see each other.** That is constraint 1, mechanically.
**`pipeline/` is the only file that knows the order of operations.** That is constraints 2 and 3.

Enforced two ways, both cheap:

- CMake `OBJECT` libraries per layer with `target_include_directories(... PRIVATE)`, so a forbidden
  include is a compile error, not a convention.
- A CI script `scripts/check_layering.sh` greps every `#include "` against the table above and
  fails the build on a violation. Runs in under a second and needs no toolchain.

### 3.1.1 The single-unit rule for `geometry/`

`TASKS.md` asks for the cut-off helpers to be **one file**, and that request does not expire at the
language boundary. The rule as it now stands, at every stage:

Revision 5 splits the target by runtime, so the rule is now **one file per runtime**:

| Stage | Helper logic lives in | Count |
|---|---|---|
| Original research code | `body_mask.py` + `mask_features.py` + `extended_mask_features.py` + mask math in `yolo_inference.py` | 4 files |
| After section 5 stage A | `ML/pig_cutter.py` (head/neck cut-off, **not ported**; runtime per section 3.5) + `ML/pig_geometry.py` (everything else, **reference for the port**) — the four originals are **deleted** (section 5.5) | 2 files, one per runtime |
| After the C++ port | `ML/pig_cutter.py` unchanged + `geometry/pig_geometry.{hpp,cpp}` — one header, one translation unit | 1 Python file + 1 C++ unit |

Two files is not a weakening of the rule; it is the same rule applied to a two-runtime system. The
count that matters is **one helper file per runtime**, and the split is on the runtime boundary of
section 3.3, not on convenience.

`geometry/health_input.{hpp,cpp}` is the one deliberate exception and is **not** part of this rule:
it is new C++ with no Python-helper ancestor (the three input protocols of section 1.1(c) were
never research code), and keeping it out of `pig_geometry.cpp` keeps gate B a clean file-to-file
comparison — everything in `pig_geometry.cpp` has a line in `pig_geometry.py` to be measured
against, and nothing else does.

`scripts/check_layering.sh` gains a second assertion: the set of `.cpp` files under `geometry/` is
exactly `{pig_geometry.cpp, health_input.cpp}`. Adding a seventh geometry file is a CI failure, not
a review comment.

### 3.2 Why this shape and not a flat `src/`

A flat layout is what forces the coupling `TASKS.md` prohibits: the file that runs YOLO ends up
also owning mask cleanup, and the file that computes features ends up loading XGBoost. Once that
happens, swapping `ML/weight_prediction/model.json` touches geometry code, and changing a mask
heuristic risks the segmentation session. The split above makes both swaps local by construction:

- New XGBoost model → `models/regressor_model.cpp` unchanged, manifest changes.
- New mask heuristic → `geometry/` only; no model file recompiles.
- New pipeline order → `pipeline/pipeline.cpp` only; no model or geometry file changes.

### 3.3 The runtime boundary — drawn at the segmentation mask, not mid-geometry

Revision 5 drew this boundary in the wrong place. It split *inside* the geometry stack — C++ cleans
the mask, Python cuts, C++ extracts the features — which meant five primitives had to exist in both
runtimes, and gate C existed solely to stop those two copies drifting. That complexity bought
nothing: it was an artifact of where the line was drawn, not a requirement of the problem.

Revision 6 draws the line at the **segmentation mask**. Everything from the raw mask to the five
features is one side or the other, never both:

```
        C++ (both platforms)                    PYTHON (if it ships — section 3.5)
  ┌────────────────────────────────┐
  │ models/segmenter_model         │
  │   YOLO -> instance mask        │──── uint8 mask, H×W ────►┌──────────────────────────┐
  │                                │      + ji_config          │  ML/pig_cutter.py        │
  │                                │                           │    clean_binary_mask     │
  │                                │                           │    isolate_dorsal_core   │
  │                                │                           │    isolate_body_only_    │
  │                                │                           │        mask()            │
  │                                │◄─── 5 features + QC ──────│    extract_five_features │
  │                                │      RA LC BL BW E        │  (scipy, skimage)        │
  └────────────┬───────────────────┘      pair_valid, ...      └──────────────────────────┘
               ▼
     models/regressor_model  ──► kg
```

**One hop, not two. No duplicated primitives. No gate C.**

| Direction | Payload | Notes |
|---|---|---|
| C++ → Python | `mask` (uint8 `H×W`, 0/1), `ji_config` (JSON) | The raw largest-instance mask, straight from the segmenter. No image, no file path, no model. |
| Python → C++ | `features` (`RA, LC, BL, BW, E`), `status`, `pair_valid`, `head_removal_applied`, `protocol_version` | Exactly what `weight_runtime.py` already assembles today, so the contract is lifted from the working reference rather than invented. |

No photo crosses the boundary — only a binary mask and five floats — which also keeps the
`AGENTS.md` consent rule uncomplicated.

**What C++ `geometry/` still owns.** `clean_binary_mask` and the unletterbox math are still needed
on the C++ side for the *segmentation* capability itself — displaying the mask, computing its area
and bbox, and feeding `health_input`'s `segmentation_crop` / `segmentation_masked` protocols. But
that is C++ owning them for C++ purposes; the Python side owns its own copies for the weight path
and the two never have to agree, because **they are no longer used in the same computation.** That
is the whole difference: revision 5 had one pipeline threaded through two implementations of the
same primitive; revision 6 has two pipelines that each use their own.

Gate C is therefore **deleted** (section 10). `manifest.weight.shared_primitives` is deleted with it
(section 8). Neither has a job any more.

### 3.4 If Python ships, the flow suspends once — and that is a documented exception

*This section applies only under section 3.5's on-device-Python option. Under any other option the
pipeline is a single C++ call and none of this exists.*

Chaquopy's Python lives in the JVM, not in the native library. C++ cannot call it without a JNI
detour that would put a platform dependency inside `pipeline/` — precisely the coupling section 3
exists to prevent. So the pipeline **suspends** at the cutter instead:

```
Dart  ──► instaham_ml_run_pipeline_json(photo)          [FFI]      view, segment, health done
      ◄──   envelope + { weight: "pending_cutter", mask_handle }    raw mask held natively

      ──► MethodChannel("instaham/cutter").cut(mask)    [Android]  Chaquopy -> pig_cutter.py
      ◄──   5 features + QC                                        (clean, core, cut, features)

      ──► instaham_ml_finish_weight_json(ctx, handle,   [FFI]      XGBoost only
                                         features)
      ◄──   weight fragment, merged into the envelope
```

Three properties keep this from becoming the Dart-orchestration mess revision 3 rejected:

1. **`pipeline/` still owns the order.** It decides *whether* the cutter is needed (dorsal only,
   segmentation succeeded, `weight.available`) and emits `pending_cutter`. Dart does not branch;
   it reacts to a state the C++ told it about.
2. **Exactly one Dart file may see the suspension**: `impl/weight_pipeline_service_impl.dart`.
   Everything else — including `IInferencePipelineService` — sees a single `run(photo)` returning a
   complete envelope. This is the only exception to "the flow lives in C++", and it is one file.
3. **Where weight is unavailable the suspension never occurs.** `weight.available` is false,
   `pipeline/` never emits `pending_cutter`, and the same Dart file returns the envelope unchanged.
   The platform difference is one manifest flag, not a second code path.

The cost is two FFI crossings per dorsal photo instead of one — microseconds against a ~1–2 s
pipeline. Note that `instaham_ml_finish_weight_json` now receives **five floats rather than a
second full-resolution mask**, so the resumed call is trivially cheap and `cutter_gap` holds only
the handle's bookkeeping, not a second image buffer.

### 3.5 The deferred decision: where the cutter actually runs

Not porting the cutter (settled, section 5.2(c)) does **not** determine where it runs. That is a
separate choice with a materially different cost, and revision 6 does not make it yet:

| Option | Weight on Android | Weight on iOS | APK cost | Other cost |
|---|---|---|---|---|
| **A. On-device Python** (Chaquopy) | ✅ | ❌ none | **+65–85 MB per ABI** | Two runtimes, two debugging stories; needs S1 to pass |
| **B. Server-side cutter** | ✅ | ✅ | none | Backend to run and pay for; offline handling; a mask leaves the device (consent, `AGENTS.md`) |
| **C. Defer weight entirely** | ❌ | ❌ | none | Ship view + segmentation + health; weight when the model is ready |

**The decision is due at slice 5 and not before.** Three things make waiting strictly better than
choosing now:

1. **Slices 1, 3, and 4 are identical under all three options.** They need no cutter, and they are
   the whole near-term plan. Nothing is idled by deferring.
2. **S1 will have run** by then, so option A stops being a guess.
3. **The weight model may not be the same model.** `ML/weight_prediction/model.json` is flagged
   `"temporary"` and expected to change (section 2.3), and its `capture_contract` records
   `feature_space: fixed_camera_pixels` at `training_camera_height_m: 1.88` —
   i.e. the current regressor is only valid at a fixed ~1.88 m camera height, which is a research
   constraint rather than a handheld-phone product. Committing 85 MB of APK and the iOS weight
   branch to a regressor that may be replaced is the wrong order of operations.

Until that decision is taken, the plan builds **option-neutral** code: the manifest's
`weight.available` flag, the `unavailable` envelope state, and the UI's weight-unavailable card are
all built in slice 4 and are correct under every option.

### 3.4 The flow suspends at the cutter — and that is a documented exception

Chaquopy's Python lives in the JVM, not in the native library. C++ cannot call it without a JNI
detour that would put a platform dependency inside `pipeline/` — precisely the coupling section 3
exists to prevent. So the pipeline **suspends** at the cutter instead:

```
Dart  ──► instaham_ml_run_pipeline_json(photo)          [FFI]      view, segment, health,
      ◄──   envelope + { weight: "pending_cutter", mask_handle }    clean+dorsal-core done

      ──► MethodChannel("instaham/cutter").cut(mask)    [Android]  Chaquopy -> pig_cutter.py
      ◄──   body_mask + QC

      ──► instaham_ml_finish_weight_json(ctx, handle,   [FFI]      features5 + XGBoost
                                         body_mask)
      ◄──   weight fragment, merged into the envelope
```

Three properties keep this from becoming the Dart-orchestration mess revision 3 rejected:

1. **`pipeline/` still owns the order.** It decides *whether* the cutter is needed (dorsal only,
   segmentation succeeded, `weight.available`) and emits `pending_cutter`. Dart does not branch;
   it reacts to a state the C++ told it about.
2. **Exactly one Dart file may see the suspension**: `impl/weight_pipeline_service_impl.dart`.
   Everything else — including `IInferencePipelineService` — sees a single `run(photo)` returning a
   complete envelope. This is the only exception to "the flow lives in C++", and it is one file.
3. **On iOS the suspension never occurs.** `weight.available` is false, `pipeline/` never emits
   `pending_cutter`, and the same Dart file returns the envelope unchanged. The platform difference
   is one manifest flag, not a second code path.

The cost is two FFI crossings per dorsal photo on Android instead of one. That is measured in
microseconds against a ~1–2 s pipeline, and it is the price of not porting 10,701 lines.

---

## 4. Directory structure

Legend: **[has]** on disk · **[new]** to create.

### 4.1 Native — `packages/instaham_ml_ffi/src/`

```
src/
├── CMakeLists.txt                       # [has] -> [new] one OBJECT library per layer
├── include/instaham_ml.h                # [has] THE C ABI
├── instaham_ml.map                      # [has] export only instaham_ml_*
├── instaham_ml.cpp                      # [has] stubs -> [new] ABI impl, delegates to pipeline/
│
├── core/                                # infrastructure — no ML, no geometry
│   ├── errors.{hpp,cpp}                 # [new] thread-local last-error, status enum mapping
│   ├── json_out.{hpp,cpp}               # [new] result-envelope builder
│   ├── sha256.{hpp,cpp}                 # [new]
│   ├── image.{hpp,cpp}                  # [new] decode JPEG/PNG -> RGB cv::Mat. NO EXIF rotation.
│   ├── tensor.{hpp,cpp}                 # [new] NCHW buffer, resize/center-crop/normalize, letterbox
│   └── manifest.{hpp,cpp}               # [new] parse, schema_version, capability flags, contracts
│
├── models/                              # pure inference. Never includes geometry/
│   ├── onnx_session.{hpp,cpp}           # [new] Ort::Env + Session wrapper, IO binding, arena reuse
│   ├── classifier_model.{hpp,cpp}       # [new] GhostNetV3: float[1,3,224,224] -> logits[1,N]
│   ├── segmenter_model.{hpp,cpp}        # [new] YOLO11s-seg: [1,3,640,640] -> boxes + 32 coeffs
│   │                                    #       + proto[1,32,160,160]. Raw tensors only.
│   └── regressor_model.{hpp,cpp}        # [new] XGBoost ONNX: float[1,5] -> float[1]
│
├── geometry/                            # pure CPU math. Never includes models/ or ORT
│   ├── pig_geometry.hpp                 # [new] THE single helper header. Public surface only:
│   │                                    #       clean_binary_mask, largest_contour,
│   │                                    #       unletterbox_mask, isolate_dorsal_core,
│   │                                    #       isolate_body_only_mask, extract_five_features.
│   ├── pig_geometry.cpp                 # [new] THE single helper unit — 1:1 port of
│   │                                    #       ML/pig_geometry.py. Everything else is static in
│   │                                    #       an anonymous namespace, grouped by the same
│   │                                    #       section markers as the .py (section 5.6).
│   │                                    #       Does NOT contain the head/neck cut-off — that is
│   │                                    #       ML/pig_cutter.py, Python, Android (section 3.3).
│   └── health_input.{hpp,cpp}           # [new] full_frame | segmentation_crop | segmentation_masked
│                                        #       NOT a port — new code, no .py ancestor (3.1.1).
│
├── capabilities/                        # composition. One facade each. Never includes each other
│   ├── view_capability.{hpp,cpp}        # [new] core/tensor + models/classifier + manifest[view]
│   ├── segment_capability.{hpp,cpp}     # [new] models/segmenter + geometry/pig_geometry
│   ├── health_capability.{hpp,cpp}      # [new] geometry/health_input + models/classifier
│   └── weight_capability.{hpp,cpp}      # [new] geometry/pig_geometry + models/regressor
│
├── pipeline/                            # THE FLOW. Section 1 lives here and nowhere else
│   ├── pipeline.{hpp,cpp}               # [new] run(image_path) -> PipelineResult, may end in
│   │                                    #       pending_cutter (section 3.4)
│   ├── cutter_gap.{hpp,cpp}             # [new] holds the suspended state between the two FFI
│   │                                    #       calls: mask handle, TTL, dorsal/QC context.
│   │                                    #       Pure C++ bookkeeping — knows NOTHING about
│   │                                    #       Chaquopy, JNI, or Python.
│   └── result_envelope.{hpp,cpp}        # [new] PipelineResult -> section-9 JSON
│
├── third_party/                         # [new] nlohmann_json (vendored), ORT + opencv (fetched)
└── test/
    ├── CMakeLists.txt                   # [has]
    ├── test_abi.cpp                     # [has]
    ├── test_layering.cpp                # [new] compile-fence + geometry single-unit assertions
    ├── test_manifest.cpp                # [new] schema, hashes, contracts, capability gating
    ├── test_classifier_golden.cpp       # [new] fused-deploy logits vs committed reference
    ├── test_segmenter_postprocess.cpp   # [new] proto+coeff -> mask, unletterbox round-trip
    ├── test_pig_geometry.cpp            # [new] the whole geometry unit vs ML/parity fixtures:
    │                                    #       unletterbox, dorsal core, features5, primitives
    ├── test_health_input.cpp            # [new] all three protocols on a fixture mask
    ├── test_cutter_gap.cpp              # [new] suspend/resume: stale handle, wrong-size body
    │                                    #       mask, TTL expiry, weight.available=false path
    └── test_pipeline_routing.cpp        # [new] reject / health_only / dorsal_valid graphs
                                         #       x { cutter present, cutter absent (iOS) }
```

### 4.2 Python — reference, export, parity

```
ML/
├── models/                              # [new] vendored, read-only architecture definitions
│   └── ghostnetv3.py                    # [new] GhostNetV3 1.0x — not a timm builtin. Serves
│                                        #       BOTH view and health.
│
├── compat/                              # [new] the `src.` shim, ~10 lines
│   └── src_alias.py                     # [new] sys.modules["src.yolo_modifications"] = ...
│                                        #       Required to unpickle the YOLO checkpoint and to
│                                        #       match ML/weight_runtime.py's documented imports.
│
├── pig_cutter.py                        # [new] ⭐ NOT PORTED. The head/neck cut-off,
│                                        #       consolidated from body_mask.py. Pure mask->mask.
│                                        #       Owns scipy + skimage. Carries its own copies of
│                                        #       the 5 shared primitives (section 3.3).
│                                        #       Loaded by Chaquopy; never imports ML.export,
│                                        #       ML.parity, or anything with file IO.
│
├── pig_geometry.py                      # [new] Everything else: mask cleanup, unletterbox,
│                                        #       dorsal core, five features, chen16. NOT shipped —
│                                        #       this is the reference the C++ port is gated
│                                        #       against (gate B).
│
├── body_mask.py                         # [has] 10,701 lines, 73 defs -> [DELETE] at gate A;
│                                        #       becomes pig_cutter.py (Python, not ported)
├── mask_features.py                     # [has] 349 lines, 9 defs    -> [DELETE] at gate A;
│                                        #       splits: 5 primitives duplicated into
│                                        #       pig_cutter.py, all 9 into pig_geometry.py
├── extended_mask_features.py            # [has] 309 lines, 7 defs    -> [DELETE] at gate A
├── yolo_inference.py                    # [has] 276 lines, 4 defs    -> [DELETE] at gate A;
│                                        #       mask math moves to pig_geometry.py,
│                                        #       predict_largest_mask to ML/parity/reference_yolo.py
├── yolo_modifications.py                # [has] LDConv / ACmix / ACmixLDConvDownsample.
│                                        #       KEPT — the checkpoint unpickles through it.
├── weight_runtime.py                    # [has] 589 lines — reference ORCHESTRATOR, mirrors
│                                        #       pipeline/ + core/manifest, NOT geometry/.
│                                        #       KEPT, but [new] repointed at pig_geometry
│                                        #       (section 5.5.1) — it imports the deleted files.
│
├── export/
│   ├── __init__.py                      # [has]
│   ├── common.py                        # [has] sha256, RESIZE_RATIO 1.14, IMAGENET_MEAN/STD,
│   │                                    #       BASELINE5, preprocessing block
│   │                                    # [new] build_arch() registry: ML/models/* then timm
│   ├── fuse_reparam.py                  # [new] GhostNetV3 rpr fusion + equivalence assertion
│   ├── export_classifier.py             # [has] [new] fuse first; assert classes == class_to_idx;
│   │                                    #       --capability view|health, same code path
│   ├── export_yolo.py                   # [has] [new] load via compat shim + ultralytics 8.4.121,
│   │                                    #       from best_eval_fp32.pt, ema branch
│   ├── export_xgboost.py                # [has] reads ML/weight_prediction/model.metadata.json
│   ├── probe_health_input.py            # [new] section 1.1(c) — reproduces test_predictions.csv
│   │                                    #       under each protocol; picks the manifest default
│   ├── build_manifest.py                # [has] [new] --schema, pipeline block, always 4 blocks
│   ├── manifest.schema.json             # [new] JSON Schema, enforced in CI and test_manifest
│   ├── ort_op_config.py                 # [has] reduced-build op allowlist
│   └── requirements-export.txt          # [has] [new] pin ultralytics==8.4.121
│
└── parity/
    ├── __init__.py                      # [has]
    ├── run_reference.py                 # [has] [new] full section-1 graph, not just classifiers;
    │                                    #       imports pig_geometry, not mask_features
    ├── reference_yolo.py                # [new] predict_largest_mask lifted out of
    │                                    #       yolo_inference.py — model loading, so it is
    │                                    #       reference-runner code, never a geometry helper
    ├── gate_a.py                        # [new] section 5.3 gate A harness: pig_geometry.py vs
    │                                    #       the pre-deletion originals, pinned by git rev
    └── compare.py                       # [has]
```

### 4.3 Flutter app side

```
android/app/src/main/python/               # [new] slice 5, section 3.5 OPTION A ONLY
└── instaham_cutter/
    ├── __init__.py                       # [new]
    ├── pig_cutter.py                     # [new] copied from ML/pig_cutter.py at build time by
    │                                     #       a Gradle task — never hand-edited here; the
    │                                     #       copy is sha256-verified against the manifest
    └── bridge.py                          # [new] the ONLY Chaquopy entry point: decodes the
                                          #       mask bytes, calls isolate_body_only_mask,
                                          #       encodes body mask + QC back. No logic.

android/app/src/main/kotlin/.../CutterChannel.kt   # [new] MethodChannel("instaham/cutter"),
                                                   #       Python.getInstance() -> bridge.py

lib/services/ml/
├── view_model_service.dart              # [has] interface unchanged (doc comment: GhostNetV3)
├── health_model_service.dart            # [has] interface unchanged
├── segmentation_service.dart            # [has] interface unchanged
├── weight_regression_service.dart       # [has] -> DELETE
├── weight_pipeline_service.dart         # [new] replaces the above
├── inference_pipeline_service.dart      # [new] ONE call for the whole section-1 graph
├── ml_runtime.dart                      # [new] singleton + long-lived inference isolate
├── ml_exceptions.dart                   # [new]
└── impl/                                # [new]
    ├── inference_pipeline_service_impl.dart
    ├── view_model_service_impl.dart
    ├── health_model_service_impl.dart
    ├── segmentation_service_impl.dart
    └── weight_pipeline_service_impl.dart
```

The per-capability services stay for testability and for screens that need one model in isolation.
`IInferencePipelineService` is the production path: one FFI crossing per photo instead of four,
and the branch logic lives in C++ `pipeline/` rather than being duplicated in Dart.

### 4.4 Assets

```
assets/ml/                               # [new] generated, never hand-edited
├── manifest.json
├── view/          model.onnx  classes.json  preprocessing.json
├── segmentation/  model.onnx  classes.json                  # ~40 MB -> Play Asset Delivery
│                                                            # (Android) / On-Demand Resources (iOS)
├── health/        model.onnx  classes.json  preprocessing.json
└── weight/        xgboost.onnx  feature_order.json  xgboost.meta.json
```

All four are buildable today — every checkpoint exists.

---

## 5. Consolidating the cut-off helpers

`TASKS.md`: *"The standalone python files (py cut off helpers) should be in one file instead, port
to c++ but may be open to code change."*

Read as a whole sentence, that is one requirement with two halves: **one file**, and **ported**.
Revision 3 delivered the first half additively — it created the consolidated file but left the
originals in place, and then split the port into six C++ units. The instruction is satisfied only
when the count actually drops and stays dropped.

Revision 5 keeps the "one file" half in full and **narrows the "ported" half deliberately**: the
head/neck cutter is not ported. `TASKS.md` also says the helpers are *"open to code change"*, and
declining to port the single riskiest 10,701 lines — while porting everything else — is the
largest such change available. The resulting shape:

```
  4 original files  ──►  2 consolidated files  ──►  1 Python file (ships) + 1 C++ unit
                          ML/pig_cutter.py            ML/pig_cutter.py      (unchanged)
                          ML/pig_geometry.py          geometry/pig_geometry.cpp
```

Sections 5.5 and 5.6 make that true; section 3.1.1 is the rule; section 13 enforces it.

### 5.0 The split, and why it lands exactly on file boundaries

The split was not chosen for convenience — it is where the existing import graph already cuts.
Verified on disk:

- `body_mask.py` imports **exactly two** project symbols, both from `mask_features.py` (line 40):
  `clean_binary_mask` and `isolate_dorsal_core_ji_duan`. Nothing else.
- `mask_features.py` imports **nothing** from the project — only `cv2` and `numpy`.
- `scipy.gaussian_filter1d` (5 uses), `scipy.find_peaks` (4 uses), and `skimage.skeletonize`
  (2 uses, lines 480 and 707) appear **only** in `body_mask.py`.

So "the head/neck cutter" and "everything else" is a clean cut with a two-symbol seam, and every
hard-to-port scientific-Python primitive falls on the Python side of it. That is the whole
argument for this revision in three bullet points.

| Goes to `ML/pig_cutter.py` (Python, not ported) | Goes to `ML/pig_geometry.py` (ported to C++) |
|---|---|
| All of `body_mask.py` — entry `isolate_body_only_mask` | All 9 defs of `mask_features.py` |
| Its own copies of the mask-cleanup primitives it calls internally | `extract_chen16_features` + helpers from `extended_mask_features.py` |
| `extract_five_features`, so the weight path is one hop (section 3.3) | The mask math from `yolo_inference.py` |
| `scipy` + `skimage` usage stays here, unported | *(C++ keeps `clean_binary_mask` + unletterbox for the **segmentation** capability — a separate pipeline, not a shared implementation)* |

Note that `extract_five_features` and the cleanup primitives appear on **both** sides of this table.
That is deliberate and is not the revision-5 duplication problem: the two copies are never used in
the same computation (section 3.3), so they are not required to agree and nothing gates them
against each other.

### 5.1 What goes in, what stays out

Both consolidated files take only **pure array math with no model loading, no file IO, and no
protocol verification**:

| Source | Take | Leave |
|---|---|---|
| `body_mask.py` (10,701 lines, 73 defs) → **`pig_cutter.py`** | all of it — entry `isolate_body_only_mask` (line 10611, delegating to `_isolate_body_only_mask_fixed06q` at 10016) | — |
| `mask_features.py` (349, 9) | `clean_binary_mask`, `_largest_component_fill`, `largest_contour`, `_odd_window`, `_rolling_median`, `ji_duan_adaptive_kernel_sizes`, `isolate_dorsal_core_ji_duan`, `isolate_dorsal_core`, `extract_five_features` | — |
| `extended_mask_features.py` (309, 7) | `extract_chen16_features` and helpers, only if a chen16 model is ever selected | — |
| `yolo_inference.py` (276, 4) | `_largest_mask_index`, `_polygon_mask_in_original_coordinates`, `_unletterbox_native_mask` | `predict_largest_mask` — it loads and runs the model. In C++ it is `models/segmenter`; in Python it moves to `ML/parity/reference_yolo.py`, so the file itself is emptied and deleted, not kept for one function |
| `weight_runtime.py` (589, 13) | nothing | the whole file. `WeightEstimator` + its seven `_verify_*` methods are the **orchestrator and contract checker** — they map to C++ `pipeline/` and `core/manifest`, not to `geometry/`. |

That split is the Python mirror of section 3's layering, which is why it is worth doing before the
port rather than after.

### 5.2 Three corrections worth recording

**(a) `_vN` is provenance, not a version switch.** The `_vN` prefixes in `body_mask.py`
(`_v9`×5, `_v14`×6, `_v15`×4, `_v16`×1, `_v26`×1 definitions) look like abandoned versions.
**They are not.** Every one has at least one live call site (`_v14`: 8 calls, `_v15`: 9, `_v9`: 6,
`_v26`: 2, `_v16`: 1). The prefix is a provenance tag on a live sub-step. So consolidation must
**not** be planned around deleting old variants — any reduction has to come from a measured
reachability pass from `isolate_body_only_mask`, not from the naming.

**(b) `body_mask.py` overrides two of its own functions by redefinition, and the merge can break
that silently.** Two names are defined twice in the same module:

| Name | First `def` | Alias capture | Second `def` (wins) |
|---|---|---|---|
| `choose_body_circle_pair` | 5882 | `_choose_body_circle_pair_fixed06q = choose_body_circle_pair` at **10184** | 10392, calls the alias at 10396 |
| `isolate_body_only_mask` | 10016 | `_isolate_body_only_mask_fixed06q = isolate_body_only_mask` at **10185** | 10611, calls the alias at 10618 |

The module's own comment at 10167 states the intent: *"are intentionally unchanged. Only
`choose_body_circle_pair()` is overridden."* This is a deliberate monkey-patch-by-redefinition
layer, and it is **order-dependent late binding**: the call at line 9177 reads
`choose_body_circle_pair(...)` but resolves at runtime to the **10392 override**, not to the 5882
definition it sits beside. The alias only captures the original because it is bound *between* the
two `def`s.

Three consolidation rules follow, and they are not optional:

1. **Never dedupe on name.** A tool or a reviewer removing "the duplicate `def`" silently swaps
   which implementation runs.
2. **Never reorder across an alias-capture line.** Moving `_choose_body_circle_pair_fixed06q =`
   above the first `def` makes it capture nothing; moving it below the second makes it capture the
   override and recurse forever.
3. **Resolve the override statically during stage A.** In `ML/pig_geometry.py` the two originals
   are renamed to their captured alias names (`_choose_body_circle_pair_fixed06q`,
   `_isolate_body_only_mask_fixed06q`) and the overrides keep the public names, so the file has no
   duplicate definitions and no rebinding. This is a *behaviour-preserving* rename, gate A proves
   it, and it is what makes the C++ port possible at all — **C++ has no late binding at namespace
   scope, so an unresolved override cannot be ported**, only mis-ported.

Rule 3 is the single most important line in section 5. It is also why the fixture corpus must
cover both branches of each override before deletion (section 5.5), since a corpus that never
exercises the wrapper cannot tell the two implementations apart.

**(c) Spike S3 result — the cutter does not shrink, and that settles the port question.**
Run against `ML/pig_cutter.py` (AST call-graph, BFS from `isolate_body_only_mask`):

| | functions | lines |
|---|---|---|
| **Reachable** from the entry point | 72 | **9,911** |
| Unreachable (dead) | 7 | 380 |
| *file total* | *79* | *10,855* |

**91 % of the file is live.** Revision 4 hoped "a measured reachability pass" would find enough dead
code to make the port tractable; correction (a) already warned it would not, and S3 confirms it.

Of the live functions, **seven — 1,985 lines — call `scipy`/`skimage` directly**:

| lines | function | primitive |
|---:|---|---|
| 586 | `cleanup_residual_lateral_appendages` | `skeletonize` |
| 499 | `_refine_actual_neck_index` | `find_peaks` |
| 376 | `analyze_extension_beyond_circle` | `find_peaks` |
| 229 | `build_cross_section_profiles` | `gaussian_filter1d` |
| 159 | `generate_sharp_peak_candidates` | `find_peaks` |
| 114 | `resample_centerline_profile` | `gaussian_filter1d` |
| 22 | `build_medial_axis` | `skeletonize` |

So a C++ port means **~9,900 lines of dense geometric code, ~2,000 of which are numerically coupled
to exact SciPy/scikit-image semantics.** That is the measured basis for not porting it (revision
note (1)) — no longer a judgement call. It also retires the last of revision 4's optimism: there is
no reachability win to be had here, and any future attempt to shrink this file has to come from
genuine simplification, re-gated against gate A, not from deleting unreachable code.

**The 380 dead lines are free to delete now**, independent of every other decision in this plan:
`_v14_fit_head_closure_circle` (179), `_v14_choose_head_side` (112), `_ordered_terminal_indices`
(27), `_v14_disk_mask_occupancy` (23), `make_circle_defined_structure_overlay` (19), a stale
`_rolling_median` (12, shadowed by the inlined primitive), `_v14_candidate_from_geometry` (8).
Note this is the one place correction (a) does *not* apply: these `_v14` functions have no live
call site remaining from the entry point, which is exactly what makes them safe to remove — the
rule was never "keep everything `_vN`", it was "do not infer deadness from the name". Deletion is
still gated on gate A, like every other change.

### 5.3 The consolidation is a two-stage gate

Because code change is permitted, the port target is the consolidated file, not the original:

```
stage A   body_mask + mask_features + extended + yolo mask math      (4 files)
             │  merge, resolve the 5.2(b) overrides, split on the section-3.3 runtime boundary
             ▼
   ML/pig_cutter.py  +  ML/pig_geometry.py     ── gate A ──►  together match the ORIGINAL
             │                                                modules on the fixture corpus
             │  ✂ gate A green ⇒ DELETE the 4 originals (section 5.5)        (2 files)
             │
             ├── pig_cutter.py ──► SHIPS AS IS on Android. No port, no gate B.
             │                     No gate B; nothing ports it (section 5.2(c)).
             ▼
          geometry/pig_geometry.cpp    ── gate B ──►  matches ML/pig_geometry.py on the same corpus
                                                      (1 translation unit, section 5.6)
```

Gate A is run on the **pair**, end to end (mask → cut → features → kg), not on each file alone.
The split is an internal detail of the consolidation; what must not change is the answer.

Gate A is what makes stage-B simplification safe: once the corpus pins the original's behaviour,
every later change is measured against a fixed reference rather than against a moving one.

It is also what makes the deletion safe. The corpus, not the source files, is the reference the
port is measured against — once gate A is green and its expected outputs are committed, the
original modules carry no information the corpus does not, and keeping them only creates a second
place for the logic to drift.

### 5.4 The SciPy/scikit-image risk is now cancelled, not mitigated

Every previous revision carried the same top technical risk: reproducing three scientific-Python
primitives bit-exactly in C++. All three live only in `body_mask.py`, which is no longer ported.
**They keep running as the identical library calls that produced the research results.**

| Primitive | Uses | Revision 4 plan | Revision 5 |
|---|---|---|---|
| `scipy.ndimage.gaussian_filter1d` | 5 | reimplement in C++, hold gate A | **unchanged, still SciPy** |
| `scipy.signal.find_peaks` | 4 | reimplement prominence/width/distance logic | **unchanged, still SciPy** |
| `skimage.morphology.skeletonize` | 2 (lines 480, 707) | pin Zhang-Suen or substitute a ridge transform | **unchanged, still scikit-image** — but see below |

This removes the plan's single largest source of silent numerical drift. Nothing is approximated;
the shipped cutter is the research cutter.

**One dependency is still worth removing, for size rather than correctness.** `scikit-image` is
pulled in for exactly one function at two call sites. A Chaquopy wheel for it may not exist
(spike S2, section 11.1), and it is heavy for what it does. If the spike says it is unavailable or
too large, `skeletonize` is replaced with a vendored Zhang-Suen thinning — skimage's own 2-D
default algorithm, ~40 lines — and re-gated. `scipy` and `numpy` stay regardless; they have
maintained Chaquopy wheels and are not negotiable for this code.

The "open to code change" licence from `TASKS.md` is therefore spent differently than revision 4
spent it: not on substituting primitives, but on **not porting the component that needed them**.

### 5.5 Deleting the originals — the step revision 3 was missing

Consolidation is not done when `ML/pig_cutter.py` and `ML/pig_geometry.py` exist. It is done when
they are the **only** helper files. The four originals are deleted in one commit, and that commit
is gated:

**Deletion preconditions, all required:**

1. Gate A is green on the full fixture corpus at section 10 tolerances.
2. Gate A's expected outputs are committed under `test/fixtures/parity/` — the corpus, not the
   source, becomes the behavioural record.
3. `ML/parity/gate_a.py` can still reconstruct the originals from the pinned pre-deletion git
   revision (`git show <rev>:ML/body_mask.py`), so gate A remains re-runnable forever without the
   working tree carrying the files.
4. No importer of the deleted names remains — see 5.5.1.

**Deleted:** `ML/body_mask.py`, `ML/mask_features.py`, `ML/extended_mask_features.py`,
`ML/yolo_inference.py`.

**Explicitly kept, and why:**

| File | Why it survives |
|---|---|
| `ML/yolo_modifications.py` | Not a helper. `LDConv` / `ACmix` / `ACmixLDConvDownsample` are pickled *into* the segmentation checkpoint under `src.yolo_modifications`; deleting it makes `best_eval_fp32.pt` unloadable (section 6.2). |
| `ML/weight_runtime.py` | Not a helper. It is the reference orchestrator and contract checker, mirroring C++ `pipeline/` + `core/manifest` (section 5.1). It is repointed, not removed. |

**The deletion is now less final than it was.** In revision 4 every one of these files was headed
for a C++ port, so deleting them removed the last Python copy of shipping logic. In revision 5 the
largest of them — `body_mask.py` — is not being replaced by C++ at all; it is being *renamed and
consolidated into `pig_cutter.py`, which ships*. The deletion is therefore closer to a refactor
than to a removal, which lowers the risk on old con 5a considerably.

The originals stay recoverable in git history, which is what "frozen reference" should have meant.
A working-tree copy is not a freeze — it is a second implementation that nothing tests.

#### 5.5.1 The repoint work the deletion forces

Deletion is not a `git rm`; four live import sites break. This is real work and is part of slice 2:

| Site | Current | After |
|---|---|---|
| `ML/weight_runtime.py:145-152` | `from src.yolo_inference import MASK_COORDINATE_PROTOCOL, predict_largest_mask`, `from src.body_mask import (…)`, `from src.mask_features import extract_five_features`, `from src.extended_mask_features import (…)` | one `from ML.pig_geometry import (…)`, plus `predict_largest_mask` from `ML.parity.reference_yolo` |
| `ML/weight_runtime.py:356-359` | hashes `src/{yolo_inference,body_mask,mask_features,extended_mask_features}.py` in its provenance record | hashes `ML/pig_geometry.py` alone — one `source_sha256`, matching `manifest.weight.body_mask.source_sha256` (section 8) |
| `ML/weight_runtime.py:275-281` | `_verify_*` compares `BODY_MASK_PROTOCOL_VERSION` / `BODY_MASK_METHOD` imported from `body_mask` | same constants, re-exported from `pig_geometry.py` unchanged — the protocol string `ji_duan_residual_06q_v9_headfit_exact_twotangent_v26` must **not** change, it is asserted in the manifest and echoed in the section-9 envelope |
| `ML/parity/run_reference.py:68` | `from mask_features import extract_five_features  # frozen reference` | `from ML.pig_geometry import extract_five_features` |

`ML/compat/src_alias.py` also narrows: it keeps `src.yolo_modifications` (needed for unpickling)
and drops the `src.body_mask` / `src.mask_features` / `src.yolo_inference` aliases, which now have
no target.

**The four-file provenance hash becomes one.** That is a manifest-visible change and is the reason
`manifest.weight.body_mask.stage` is `"consolidated"` with a single `source_sha256` — a bundle
built before consolidation and one built after are distinguishable, which is the point.

### 5.6 The port is one translation unit, not six

Revision 3 split `geometry/` into `mask_ops`, `unletterbox`, `dorsal_core`, `body_cutoff`,
`features5`, and `health_input`. That silently undid the consolidation at the language boundary:
the same call graph that was merged in Python was re-scattered in C++, and gate B stopped being a
file-to-file comparison. The port target is now:

```
ML/pig_geometry.py   ──1:1──►   geometry/pig_geometry.hpp   (public surface, ~6 functions)
                                geometry/pig_geometry.cpp   (everything, one unit)

ML/pig_cutter.py     ──────►    NOT PORTED. Ships as Python (section 3.3).
```

**The unit is now small.** With the cutter out, `pig_geometry.py` is roughly
`mask_features.py` (349) + `extended_mask_features.py` (309) + the three mask-math functions from
`yolo_inference.py` — call it **~700 lines of Python, ~1,200 of C++**. Revision 4 projected 6–10k.
This is the single biggest change in the programme's shape: the port stops being the critical path
and becomes an ordinary week of work.

**Structure inside the single unit.** One file is not an excuse for one undifferentiated blob:

- `pig_geometry.hpp` declares **only** what a `capabilities/` facade actually calls:
  `clean_binary_mask`, `largest_contour`, `unletterbox_mask`, `isolate_dorsal_core`,
  `extract_five_features`, `extract_chen16_features`. Everything else is internal.
  Note what is **absent**: `isolate_body_only_mask`. There is no C++ symbol for the cut-off, by
  design — `capabilities/weight_capability` reaches it only through the section-3.4 suspension,
  so a future contributor cannot accidentally call a half-ported cutter that does not exist.
- `pig_geometry.cpp` puts every helper in an **anonymous namespace**, so the ported internals have
  internal linkage and cannot leak, be called out of order, or be depended on by another layer.
  That is the C++ equivalent of the leading-underscore convention in the Python file.
- Both files carry the **same section markers in the same order** as `ML/pig_geometry.py`
  (`// ===== [1] mask cleanup =====`, `[2] unletterbox`, `[3] dorsal core`, `[4] five features`,
  `[5] chen16`). A reviewer diffing the port reads the two files side by side; a marker present in
  one and absent in the other is a missed port.
- The `_vN` provenance tags of section 5.2 are **preserved verbatim** wherever they survive into
  `pig_geometry.py`. Most of them live in the cutter and therefore never reach C++ at all.

**What this costs and what it buys.** Cost: one `.cpp` of ~1,200 lines — no longer a meaningful
build-time or merge-conflict concern, so revision 4's con 5b is retired. Buys: `TASKS.md`'s
requirement met literally; gate B is one file against one file; and a change to a geometry
heuristic touches exactly one C++ file, which is the property section 3.2 was arguing for.

---

## 6. Reconstructing the models from `best.pt`

`TASKS.md`: *"The best.pt weights will be used for the reconstruction of the trained yolo and
ghostnet models."* Each has a distinct obstacle.

### 6.1 GhostNetV3 ×2 — view and health

Two obstacles, both real:

1. **Not a `timm` builtin.** `create_model("ghostnetv3_100")` fails on stock timm, so `--arch`
   alone cannot construct the model. The training definition is vendored read-only as
   `ML/models/ghostnetv3.py` and resolved through one `build_arch()` registry point; genuine timm
   names still fall through to timm. Its sha256 goes in the manifest (`model.arch_source`), so a
   silently edited architecture file invalidates the bundle exactly like a swapped weight would.
2. **The checkpoint is re-parameterised and not fused.** `model_state` carries
   `blocks.*.ghost1.cheap_rpr_conv.{0,1,2}.*`, `dw_rpr_conv`, `dw_rpr_scale` — the multi-branch
   training form. Exporting it as-is ships every training branch: a fan of parallel `Conv`s plus a
   scalar-scaled `Add` per Ghost module, inflating the op allowlist and latency for zero accuracy
   gain. `fuse_reparam.py` folds them and asserts fused-vs-trained logits agree to < 1e-5 before
   any ONNX write.

Once fused, GhostNetV3 is ordinary Conv / BatchNorm / ReLU / HardSigmoid / Add / Concat / Split /
GlobalAveragePool / Gemm — all core ORT, no custom kernels, BN absorbed by constant folding.

Export contract checks, all fatal:

- `classes.json` == the checkpoint's `class_to_idx`
  (view: `{dorsal_valid:0, health_only:1, reject:2}`; health: the 10 disease classes).
- `classifier.weight.shape[0]` == `len(classes.json)` — 3 and 10 respectively.
- fused vs trained logits < 1e-5; fused torch vs ORT < 1e-4.

### 6.2 YOLO11s-seg — one blocker before anything else

Load `ML/segmentation/weights/best_eval_fp32.pt` (not `best.pt`) and take the `ema` branch.
`torch.load` will fail on `ModuleNotFoundError: No module named 'src'` until the shim is in place:

```python
# ML/compat/src_alias.py  — installed before any torch.load of a project checkpoint
import sys, types
import ML.yolo_modifications as _ym
_src = types.ModuleType("src")
_src.__path__ = []
sys.modules.setdefault("src", _src)
sys.modules["src.yolo_modifications"] = _ym
```

The same shim covers `src.body_mask` and `src.yolo_inference`, which `ML/weight_runtime.py`
documents as its import root — so it is one file, not a per-checkpoint workaround.

Export then follows the ladder, with `manifest.segmentation.export_mode` recording where it stopped:

1. `onnx_native` — `torch.onnx.export`, static 640×640, opset 17, ultralytics 8.4.121.
2. `ort_customop` — register the `LDConv` / `ACmix` gather as an ORT custom op in
   `models/onnx_session.cpp`. Contained to one file by section 3's layering.
3. `unavailable` — `segmentation.available=false`. Under this pipeline that also forces
   `health.input.on_segmentation_failure` and disables weight, so it is a **degraded but coherent**
   product (view + full-frame health), not a broken one.

Post-processing constants, all manifest-driven, none hardcoded: 640 letterbox with `color
[114,114,114]`, `stride 32`, `scaleup false`; 32 mask coefficients against a `[1,32,160,160]`
prototype (`mask_ratio 4`); `conf 0.25`, `iou 0.7`; single largest instance; `nc 1`, `names
{0: pig}`; `retina_masks false`. `overlap_mask true` is training-only and must not be replicated
at inference.

---

## 7. The C ABI — the clear entry point

`packages/instaham_ml_ffi/src/include/instaham_ml.h` is already committed and its shape is
unchanged: opaque handle, `int` status enum plus out-params, heap JSON strings freed by the caller,
thread-local `instaham_ml_last_error()`, synchronous entrypoints that Dart serialises on one
isolate.

One entrypoint is **added** for the section-1 graph:

```c
/* Runs the pipeline: view -> segment -> health, plus mask cleanup + dorsal core.
   On iOS, or whenever weight is unavailable/not applicable, this returns the COMPLETE
   section-9 envelope and nothing further is needed.
   On Android with a dorsal photo it returns the envelope with
   weight.status == "pending_cutter" and a non-zero out_cutter_handle. */
int32_t instaham_ml_run_pipeline_json(InstahamMlContext* ctx,
                                      const char* image_path,
                                      char** out_json,
                                      int64_t* out_cutter_handle);

/* Fetches the dorsal-core mask the cutter must operate on, for the handle above.
   Caller frees with instaham_ml_free_buffer. */
int32_t instaham_ml_cutter_input(InstahamMlContext* ctx, int64_t handle,
                                 uint8_t** out_mask, int32_t* out_h, int32_t* out_w,
                                 char** out_ji_config_json);

/* Resumes the suspended pipeline with the body mask the Python cutter returned:
   five features -> XGBoost -> the COMPLETE section-9 envelope.
   Consumes the handle; a second call with the same handle returns ERR_INVALID_ARG. */
int32_t instaham_ml_finish_weight_json(InstahamMlContext* ctx, int64_t handle,
                                       const uint8_t* body_mask, int32_t h, int32_t w,
                                       const char* cutter_qc_json,
                                       char** out_json);

/* Releases a handle without finishing it — the cutter failed, or the user cancelled.
   The envelope is completed with weight.status == "error". Idempotent. */
int32_t instaham_ml_abandon_cutter(InstahamMlContext* ctx, int64_t handle,
                                   const char* reason, char** out_json);
```

**Handles are not pointers and do not leak.** `cutter_gap.cpp` holds suspended state in a bounded
map — at most 4 live handles, each with a TTL of 60 s; the oldest is evicted and completed as
`weight.status: "error", reason: "cutter_timeout"` if the app never comes back. A crashed or
force-stopped cutter therefore cannot pin native memory, and `instaham_ml_destroy` abandons all
live handles. `test_cutter_gap` covers stale handles, double-finish, TTL eviction, and a body mask
whose dimensions disagree with the input mask.

The existing per-capability entrypoints (`instaham_ml_classify_view_json`,
`instaham_ml_classify_health_json`, `instaham_ml_predict_weight_json`,
`instaham_ml_extract_features_provisional_json`, `instaham_ml_capability_available`) stay for
tests, for parity runs, and for isolated debugging. `instaham_ml_abi_version()` goes to `3` — revision 5 adds the three suspension entrypoints above.

`image_path` is always an **already-EXIF-normalised** RGB image. Native performs no rotation;
`AGENTS.md` rule 5 is enforced once, Dart-side, in `MlRuntime.exifNormalize`.

Existing error codes are unchanged (`ERR_MANIFEST`, `ERR_HASH_MISMATCH`, `ERR_MODEL_LOAD`,
`ERR_IO`, `ERR_INFERENCE`, `ERR_UNAVAILABLE`, `ERR_CONTRACT`, `ERR_INVALID_ARG`). The pipeline
never returns a partial-success error code: a branch that fails is reported *inside* the envelope
with its own status, so a failed weight branch cannot mask a successful health branch
(`AGENTS.md` rule 4).

---

## 8. Manifest

`assets/ml/manifest.json` is generated by `build_manifest.py` and never hand-edited. Everything
the native layer needs — paths, sha256, architecture, input size, mean/std, class-map path, feature
order, protocol versions, the pipeline graph, and per-capability `available` flags — comes from it.
**Nothing is hardcoded** in C++ or Dart (`AGENTS.md` rules 1, 2, 7).

```jsonc
{
  "schema_version": 3,
  "bundle_id": "instaham-ml-<git-sha>",
  "reference_commit": "<git SHA of the ML/ snapshot exported from>",
  "platform": "android",                  // or "ios" — the manifest is built per platform
  "runtime": { "engine": "onnxruntime", "min_abi_version": 3,

    // Present only when a Python cutter ships (Android). Absent on iOS, and its absence is
    // what makes weight.available false there.
    "python": { "provider": "chaquopy", "chaquopy_version": "<pinned>",
                "python_version": "3.<pinned>",
                "packages": { "numpy": "<pinned>", "scipy": "<pinned>",
                              "scikit-image": "<pinned or null if vendored>" },
                "entry": "instaham_cutter.bridge:cut",
                "source": { "path": "ML/pig_cutter.py", "sha256": "…" },
                "abis": ["arm64-v8a"] } },

  // The section-1 graph, declared. pipeline/pipeline.cpp reads it; it does not embed it.
  "pipeline": {
    "protocol_version": "instaham_pipeline_v3",
    "order": ["view", "segment", "weight", "health"],
    "view_routing": {
      "reject":       { "stop": true },
      "health_only":  { "segment": true, "weight": false, "health": true },
      "dorsal_valid": { "segment": true, "weight": true,  "health": true }
    },
    "weight_requires": ["segment"],
    "health_requires": ["segment"]        // subject to health.input.on_segmentation_failure
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
      "source_run": { "dir": "ML/view_model", "checkpoint": "best.pt", "checkpoint_sha256": "…",
                      "best_epoch": 2, "epochs_trained": 14, "seed": 42, "optimizer": "adamw",
                      "learning_rate": 1e-4, "batch_size": 32, "val_macro_f1": 0.9809 },
      "recorded_metrics": { "test_accuracy": 0.9727, "macro_f1": 0.9498, "macro_roc_auc_ovr": 0.9987,
                            "false_weight_accept_rate": 0.0015, "false_weight_reject_rate": 0.0289,
                            "note": "recorded research metrics; never a runtime threshold" }
    },

    "segmentation": {
      "available": true,
      "model": { "path": "segmentation/model.onnx", "sha256": "…",
                 "architecture": "yolo11s-seg-ldconv-acmix", "opset": 17,
                 "input": { "name": "images", "layout": "NCHW", "size": [640,640], "channels": "rgb" },
                 "letterbox": { "color": [114,114,114], "stride": 32, "scaleup": false } },
      "postprocess": { "conf": 0.25, "iou": 0.7, "single_largest_instance": true,
                       "mask_coefficients": 32, "proto_size": [160,160], "mask_ratio": 4,
                       "retina_masks": false,
                       "mask_protocol": "original_coordinate_polygon_v1" },
      "class_map": { "path": "segmentation/classes.json", "sha256": "…" },   // {"pig": 0}
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
      "model": { "path": "health/model.onnx", "sha256": "…",
                 "architecture": "ghostnetv3_100",
                 "arch_source": { "path": "ML/models/ghostnetv3.py", "sha256": "…" },
                 "reparam": { "trained_form": "multi_branch_rpr", "exported_form": "deploy_fused",
                              "equivalence_max_abs": 1e-5 },
                 "opset": 17,
                 "input": { "name": "input", "layout": "NCHW", "size": [224,224], "channels": "rgb" } },

      // Section 1.1(c). Set by ML/export/probe_health_input.py, not by hand.
      "input": { "protocol": "full_frame",
                 "supported": ["full_frame","segmentation_crop","segmentation_masked"],
                 "bbox_padding_ratio": 0.06,
                 "background_fill": "imagenet_mean",
                 "on_segmentation_failure": "full_frame",
                 "evidence": "reproduces ML/health_cnn/test_predictions.csv (2812 samples)" },

      "preprocessing": { "exif": "expect_normalized", "resize_shorter_side": 255, "center_crop": 224,
                         "scale": 0.00392156862745098,
                         "mean": [0.485,0.456,0.406], "std": [0.229,0.224,0.225],
                         "interpolation": "bilinear" },
      "class_map": { "path": "health/classes.json", "sha256": "…" },
      "protocol_version": "health_cvsafe_v3",
      "source_run": { "dir": "ML/health_cnn", "checkpoint": "best.pt", "checkpoint_sha256": "…",
                      "seed": 42, "optimizer": "adam", "learning_rate": 1e-4, "batch_size": 32,
                      "scheduler": { "factor": 0.5, "patience": 20 } },
      "recorded_metrics": { "test_accuracy": 0.9285, "macro_f1": 0.9290, "n_test": 2812 }
    },

    "weight": {
      "available": true,                  // ANDROID: true. iOS: false — no Python runtime.
                                          // When false: no regressor load, no cutter, and every
                                          // call returns ERR_UNAVAILABLE. Health is untouched.
      "unavailable_reason": null,         // e.g. "no_cutter_runtime" where unavailable
      "stability": "temporary",           // ML/weight_prediction/model.json is expected to change
      "regressor": { "format": "onnx", "path": "weight/xgboost.onnx", "sha256": "…",
                     "meta_path": "weight/xgboost.meta.json", "meta_sha256": "…",
                     "feature_order_path": "weight/feature_order.json", "feature_order_sha256": "…",
                     "feature_family": "baseline5", "n_estimators": 300, "max_depth": 5,
                     "learning_rate": 0.05, "objective": "reg:squarederror", "target": "weight_kg" },
      "feature_extractor": { "protocol_version": "baseline5_v1",
                             "names": ["RA","LC","BL","BW","E"], "linear_scale": 1.0 },
      // ONE source hash, not four (section 5.5.1). The pre-consolidation four-file provenance
      // record in ML/weight_runtime.py collapses to this single entry.
      "body_mask": { "stage": "consolidated",
                     "protocol_version": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26",
                     "runtime": "python",            // NOT ported — sections 3.3, 5.2(c)
                     "source": "ML/pig_cutter.py", "source_sha256": "…",
                     // Present only under section 3.5 option A. Absent otherwise, and the
                     // capability is then simply unavailable — no other manifest change.
                     "bridge": "instaham_cutter.bridge:cut",
                     // The cutter returns the five features directly (section 3.3's one-hop
                     // boundary), so no geometry is shared across the runtime edge and there
                     // is no shared-primitive set to pin. Revision 5's "shared_primitives"
                     // block and its gate C are deleted.
                     "returns": ["RA", "LC", "BL", "BW", "E",
                                 "pair_valid", "head_removal_applied"] },
      "capture_contract": { "feature_space": "fixed_camera_pixels",
                            "training_camera_height_m": 1.88,
                            "camera_height_is_xgboost_feature": false },
      "source_run": { "dir": "ML/weight_prediction", "model": "model.json", "model_sha256": "…" }
    }
  }
}
```

Asserted on load, else `INSTAHAM_ML_ERR_CONTRACT`: `feature_extractor.names ==
["RA","LC","BL","BW","E"]`; `feature_order.json` matches; the XGBoost meta's feature names match
(already `[RA, LC, BL, BW, E]` in `ML/weight_prediction/model.metadata.json`);
`health.input.protocol` is in `supported`; every `pipeline.order` entry names a real capability.
Labels always resolve through `classes.json` by name, never by position.

A capability with `available: false` has its sha256 checks skipped and every call into it returns
`ERR_UNAVAILABLE` — a manifest with a dark capability is still a valid, shippable manifest.

---

## 9. Result envelope

One JSON document per photo, from `instaham_ml_run_pipeline_json`. Every branch reports its own
status, so a failure in one never fabricates or blocks another.

```json
{
  "status": "ok",
  "pipeline_protocol": "instaham_pipeline_v3",
  "view":    { "status": "ok", "label": "dorsal_valid", "confidence": 0.9998,
               "probabilities": { "dorsal_valid": 0.9998, "health_only": 0.00015, "reject": 0.000026 },
               "class_map_sha256": "…", "protocol_version": "view_suitability_v1" },
  "segmentation": { "status": "ok", "confidence": 0.94, "instances_found": 1,
                    "mask_protocol": "original_coordinate_polygon_v1",
                    "mask_area_px": 184203, "bbox": [x, y, w, h] },
  "weight":  { "status": "ok", "estimated_kg": 82.4, "feature_family": "baseline5",
               "feature_order": ["RA","LC","BL","BW","E"],
               "features": { "RA": 0.21, "LC": 246.8, "BL": 121.3, "BW": 44.1, "E": 0.87 },
               "qc": { "pair_valid": true, "head_removal_applied": true },
               "capture_contract": { "feature_space": "fixed_camera_pixels",
                                     "training_camera_height_m": 1.88,
                                     "camera_height_is_xgboost_feature": false } },
  "health":  { "status": "ok", "label": "Healthy", "confidence": 0.9999,
               "probabilities": { "…": 0.0 },
               "input_protocol_used": "full_frame",
               "input_protocol_fallback": false,
               "class_map_sha256": "…", "protocol_version": "health_cvsafe_v3" },
  "protocols": { "mask_coordinate_protocol": "original_coordinate_polygon_v1",
                 "body_mask_protocol": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26" },
  "artifacts": { "bundle_id": "…", "manifest_sha256": "…" }
}
```

Branch-level failure and routing shapes:

```json
{ "status": "stopped", "view": { "status": "ok", "label": "reject", "confidence": 0.97 },
  "reason": "view_rejected" }

{ "view":   { "status": "ok", "label": "health_only" },
  "weight": { "status": "skipped", "reason": "view_not_dorsal" },
  "health": { "status": "ok", "input_protocol_used": "segmentation_crop" } }

{ "segmentation": { "status": "error", "reason": "no_instance_above_conf" },
  "weight":       { "status": "unavailable", "reason": "segmentation_failed" },
  "health":       { "status": "ok", "input_protocol_used": "full_frame",
                    "input_protocol_fallback": true } }
```

Revision 5 adds two weight states, both first-class:

```json
// Any build that cannot reach a cutter -- i.e. every build through slice 4,
// and one platform or none thereafter. A COMPLETE, shippable envelope.
{ "status": "ok",
  "view":   { "status": "ok", "label": "dorsal_valid" },
  "segmentation": { "status": "ok" },
  "weight": { "status": "unavailable", "reason": "no_cutter_runtime",
              "user_message_key": "weight_unavailable_on_this_device" },
  "health": { "status": "ok", "label": "Healthy" } }

// Android, dorsal photo, first FFI call. NOT a final envelope — the app must resume.
{ "status": "pending",
  "view":   { "status": "ok", "label": "dorsal_valid" },
  "segmentation": { "status": "ok" },
  "weight": { "status": "pending_cutter", "cutter_handle": 7, "expires_in_ms": 60000 },
  "health": { "status": "ok", "label": "Healthy" } }
```

Note that `health` is already final in the pending envelope. The UI renders health immediately and
shows the weight card as in-progress — `AGENTS.md` rule 4 is not merely respected here, it is
visible to the user as faster health results. If the cutter then fails, `weight.status` becomes
`"error"` and health is untouched.

`instaham_ml_finish_weight_json` returns the same document with `status: "ok"` and the weight
fragment filled in; the cutter's own QC (`pair_valid`, `head_removal_applied`) is copied through
from the Python side, never recomputed in C++.

The last shape is `AGENTS.md` rule 4 made concrete: segmentation is a shared dependency, but its
failure degrades the health input rather than blocking health. `input_protocol_fallback: true` is
surfaced in the UI — never silently.

---

## 10. Parity tolerances

Three gates. A and B as before; C is new, and pins the five section-3.3 primitives that genuinely
exist in both runtimes.

**Gate B's scope shrank.** It no longer covers the head/neck cut-off, because that is not ported —
`pig_cutter.py` ships as the same code that produced the research numbers, so there is nothing to
compare it against. What gate B still owns is mask cleanup, unletterbox, dorsal core, the five
features, and chen16.

**Gate A — `ML/pig_geometry.py` vs the original modules** (Python vs Python, same fixtures).
Run by `ML/parity/gate_a.py`, which reconstructs the originals from the pinned pre-deletion git
revision, so this gate keeps running after section 5.5 removes them from the working tree:

| Output | Tolerance |
|---|---|
| Base mask (unletterboxed) | IoU ≥ 0.999 |
| Body mask after cut-off helpers | IoU ≥ 0.999 |
| QC fields (`pair_valid`, `head_removal_applied`) | exact match |
| Feature vector (RA, LC, BL, BW, E) | ≤ 0.5 % relative |
| `estimated_kg` | ≤ 0.05 kg absolute |

Re-run after **every** simplification in section 5.4. A change that breaks gate A is reverted.

**Gate B — `geometry/pig_geometry.cpp` vs `ML/pig_geometry.py`** (the shipping gate). One file
against one file, section marker against section marker (section 5.6):

| Output | Tolerance |
|---|---|
| View label (top-1) | exact match |
| View probability vector | ≤ 0.005 per class |
| Health label (top-1) | exact match |
| Health probability vector | ≤ 0.01 per class |
| YOLO selected mask | IoU ≥ 0.95 |
| Body-mask QC fields | exact match — **passed through from Python, not recomputed** |
| Feature vector (RA, LC, BL, BW, E) | ≤ 1 % relative |
| XGBoost `estimated_kg` | ≤ 0.1 kg absolute |
| End-to-end routing (`reject` / `health_only` / `dorsal_valid`) | exact match on the fixture corpus |
| Weight-branch routing (`pending_cutter` / `unavailable`) | exact match, both platform manifests |

**~~Gate C~~ — deleted in revision 6.** Revision 5 needed it because its mid-geometry boundary
(old section 3.3) forced five primitives to exist in both runtimes *within one computation*, so the
two copies had to be pinned to each other. Revision 6's one-hop boundary removes that: the Python
weight path and the C++ segmentation path each use their own copy, never together, so there is
nothing to keep in agreement. `ML/parity/gate_c.py` was implemented under revision 5 and is
**retained but demoted to a regression guard, not a release gate** — it costs nothing to keep
running while the two copies still happen to be identical, and it will be deleted outright when the
section-3.5 decision lands on anything other than option A.

**Device gate (only under section 3.5 option A).** Gates A and B are host-side. If on-device Python
ships, one more check runs on a real arm64 device before slice 5 is done: the same fixture corpus
through the shipped Chaquopy cutter must match host Python within gate-A tolerances. This catches
ABI-specific numerical differences in the on-device `scipy` build, which host testing cannot. Under
options B and C this gate does not exist.

All gates run against the exact ORT, opencv-mobile, and Chaquopy builds that will ship.

---

## 11. Ordering, sizing, and exit criteria

Revision 4 scored 6.5/10 on executability: correct dependencies, no sizes, no spikes, no way to
tell whether a slice was in trouble until it was late. This section is rewritten to fix that.

**How to read the sizes.** Every estimate is in **engineer-days for one engineer**, and every one
carries the assumption it rests on. An estimate without a stated assumption is a guess wearing a
number, and the assumptions here are the things most likely to be wrong. Ranges are
*p50 – p80*, not best-case.

**Total: 33–50 engineer-days to a shipped view + segmentation + health product on both platforms**
(slices −1 → 4), **plus 8–12 days for weight** (slice 5) once section 3.5 is decided, plus 5–8 for
hardening. Spikes are 4–7 days and two of them now run *inside* slice 5 rather than up front.

Revision 5 quoted 47–71 days and put S1 first. Revision 6 is lower and differently shaped for one
reason: **slices −1 through 4 do not depend on the section-3.5 decision at all**, so the plan stops
paying for that decision before it needs to be made.

Revision 4's equivalent figure was never stated; it would have been roughly 90–140 days, because it
included a C++ port of the cutter. S3 (section 5.2(c)) now shows that port would have been ~9,900
live lines with ~2,000 SciPy-coupled — so that figure was, if anything, optimistic.

### 11.1 Spikes — and which ones are no longer urgent

Revision 5 ran four spikes up front. **S3 has now run** (section 5.2(c)), and its result moves S1
and S2 *later*, because they only inform a decision that is itself deferred:

| # | Spike | Size | When | Question it answers | If the answer is bad |
|---|---|---|---|---|---|
| **S3** | Cutter reachability pass | — | ✅ **DONE** | How much of the cutter is live? | **9,911/10,855 live, 1,985 lines SciPy-coupled.** Confirms: do not port. |
| **S4** | LDConv/ACmix `torch.onnx.export` attempt | **2 d** | **first — before slice 1** | Does the segmentation model export natively (section 6.2 rung 1)? | Fall to rung 2 (ORT custom op, +5–8 d) or rung 3 (`available:false`, product is view + full-frame health). This is now the **only** spike that can force a near-term replan. |
| **S1** | Chaquopy + scipy on a real arm64 device, **and the APK delta** | **1–2 d** | at the **start of slice 5**, not before | Does on-device Python work, and what does it actually cost in MB? | Section 3.5 option A is out; take option B or C. Nothing built in slices 1–4 is wasted either way. |
| **S2** | `scikit-image` wheel availability + `skeletonize` substitution | **1–2 d** | with S1, only if option A is live | Usable wheel? If not, does vendored Zhang-Suen (~40 lines) hold gate A? | Vendor the 40 lines. Low risk — packaging, not correctness (section 5.4). |

**S4 is now the only spike on the critical path**, and it is 2 days. That is the single highest-value
scheduling change in revision 6: the plan's near-term risk is the segmentation export, not Chaquopy.

### 11.2 The platform matrix

| Capability | Android | iOS | Set by |
|---|---|---|---|
| view | ✅ | ✅ | — |
| segmentation | ✅ | ✅ | S4 outcome |
| health | ✅ | ✅ | — |
| **weight** | ⏸ deferred | ⏸ deferred | **section 3.5, decided at slice 5** |

Through slice 4, weight is `unavailable` on **both** platforms and the product is view +
segmentation + health everywhere — complete and honest (section 1.1(d)). Whether weight later
lands on Android only (option A), both (option B), or neither yet (option C) is section 3.5's
call. No slice below is blocked on it, and no platform-specific inference code is written before
that point.

### 11.3 The slices

| Slice | Contents | Size | Estimate assumes | Definition of done | User-visible outcome | Depends on |
|---|---|---|---|---|---|---|
| **−1 — Data** | Recover the health test split; assemble the parity fixture corpus with section-11.3.1 override coverage; `ML/parity/data_sources.json`. | **3–5 d** | The training environment is reachable and the Roboflow split still exists. **If it does not, this becomes 5–8 d** and the health probe degrades to partial (section 1.1(c)). | 30–60 fixtures committed as derived artifacts; both override branches covered; `probe_health_input` runnable or its degradation recorded in the manifest. | none | — |
| **0 — Toolchain** ✅ *skeleton committed* | Layered `CMakeLists.txt` + `check_layering.sh`; Android **and** iOS builds green; `pod lib lint` clean; host `ctest` green in CI. | **3–5 d** *(partly paid)* | Prebuilt ORT + opencv-mobile binaries fetch cleanly; no NDK toolchain surprises. | CI green on both platforms with the stub ABI. | none | — |
| **1 — Reconstruct + export** | `ML/models/ghostnetv3.py`; `ML/compat/src_alias.py`; `build_arch()`; `fuse_reparam.py`; export view, health, XGBoost; `probe_health_input.py`; `manifest.schema.json`; per-platform `build_manifest`. | **6–9 d** | GhostNetV3 rpr fusion is mechanical once the architecture file is vendored; the `src.` shim unpickles the checkpoint first try. | All four ONNX artifacts exist; fused-vs-trained < 1e-5; two manifests (android, ios) validate against the schema. | none | S4 for the segmentation export |
| **2 — Consolidation (Python)** ✅ *done* | `ML/pig_cutter.py` + `ML/pig_geometry.py`; 5.2(b) overrides resolved; `gate_a.py`; **section 5.5 deletion** committed; the 5.5.1 repoint; `ML/tools/consolidate_helpers.py`; `check_one_helper.sh`, `check_cutter_purity.sh`. | **~2 d** *(spent)* | — | Two helper files; four originals deleted; `pytest ML/parity/test_consolidation.py` 4/4 green. **Remaining:** gate A is synthetic-only until slice −1 lands a real corpus; delete the 380 dead lines from 5.2(c). | none | — |
| **3 — View E2E** | `core/*`; `models/{onnx_session,classifier_model}`; `capabilities/view_capability`; `MlRuntime` + inference isolate; `ViewModelServiceImpl`; **`instaham_ml_ffi` added to `pubspec.yaml` and the `assets:` block uncommented**; asset copy + sha256 verify; `main.dart` init. | **6–9 d** | ORT session setup on Android is routine; the isolate pattern works first try. **Note:** the FFI package is not currently a dependency and `assets:` is commented out (`pubspec.yaml:75`) — this slice is where the app first links to any of this. | Real view classification on a device, both platforms. **First slice where the app stops showing "Pending".** | real view classification on device | 0, 1 |
| **4 — Segment + health + geometry port** | `models/segmenter_model`; `geometry/pig_geometry.{hpp,cpp}` (~1,200 lines — the port is small now); `geometry/health_input`; `capabilities/{segment,health}`; `pipeline/`; `IInferencePipelineService` + impls; **`RunInferencePipelineUseCase` actually wired into the app**; results-screen branch states incl. weight-`unavailable`; **gate B green**. | **10–15 d** | S4 landed on rung 1 or 2. **Rung 2 adds 5–8 d.** The ~700-line Python source ports at roughly 100 lines/day including tests. | The whole `TASKS.md` flow minus weight, **on both platforms**; gate B green; health card shows a real classification. | **most of `TASKS.md`** — real masks, real health, honest weight-unavailable state | 2, 3 |
| **DECISION POINT** | **Section 3.5: where does the cutter run?** Run S1 + S2 here. Re-check whether `ML/weight_prediction/model.json` is still the temporary fixed-1.88 m regressor. | **1–2 d** | — | A recorded decision: option A (on-device Python), B (server), or C (defer weight further). | none | 4 |
| **5 — Weight** *(shape depends on the decision above)* | **A:** Chaquopy + `bridge.py` + `CutterChannel.kt` + `pipeline/cutter_gap` + the suspension ABI + device gate. **B:** a backend cutter service + client + offline handling + consent review. **C:** nothing — slice 5 does not run. | **A: 8–12 d · B: 10–16 d · C: 0 d** | A assumes S1/S2 clean. B assumes a backend exists to deploy to. Both assume the regressor is still the one being targeted. | Weight on a dorsal photo on a real device; the other platform shows `unavailable` and is otherwise unaffected; `test_cutter_gap` green (A only). | weight estimation, where the decision allows it | 4, decision point |
| **6 — Hardening** | APK size work (models, and the Python runtime under option A); quantisation evaluated against section 10; Play Asset Delivery / On-Demand Resources; device benchmarks; full parity suite un-skipped. | **5–8 d** | Quantisation is evaluated, not assumed — it may be rejected on parity grounds. | Size delta recorded and accepted; benchmarks published. | smaller download, measured latency | 5 |

### 11.3.1 Slice −1 in detail — the image data every gate depends on

Neither the plan nor the repo currently supplies the pixels that slices 1, 2, and 5 are gated on.
Verified on disk: `ML/health_cnn/` holds `best.pt`, `classes.json`, `history.csv`, `metrics.json`,
`per_class_report.csv`, `test_predictions.csv` — **no images** — and `test/fixtures/` does not
exist. Two gates therefore cannot run as written:

| Gate | Needs | Status |
|---|---|---|
| `probe_health_input.py` (slice 1, sets `health.input.protocol`) | the 2812 Roboflow test images named in `test_predictions.csv` | **not in repo** — the CSV records paths and probabilities, not pixels |
| Gate A and gate B (slices 2, 5) | a fixture corpus of pig photos + their YOLO masks, spanning dorsal and non-dorsal, and **both branches of each section-5.2(b) override** | **not in repo** — `test/fixtures/parity/` is referenced throughout but never sourced |

This is scheduled, not waved at. **Slice −1 runs before slice 1** and is small but blocking:

1. Locate the Roboflow health test split from the original training environment; record its
   sha256 manifest in `ML/parity/data_sources.json`. If it is unrecoverable, `probe_health_input`
   degrades to a **partial** probe over whatever subset exists, and the manifest default stays
   `full_frame` with `evidence: "partial_probe_n=<k>"` rather than a false claim of 2812.
2. Assemble the parity corpus — 30–60 photos is enough — and commit the **derived** artifacts
   (`mask.npy`, expected feature vectors, expected envelopes) rather than the photos, so the
   corpus lives in git while the imagery stays under whatever consent terms it carries
   (`AGENTS.md`: no retaining research images without explicit consent).
3. Assert coverage of the two overrides before the corpus is declared done: at least one fixture
   must take the wrapper path and one the aliased-original path for each of
   `choose_body_circle_pair` and `isolate_body_only_mask`.

Without step 3, gate A can be green on a corpus that cannot distinguish the two implementations,
and the deletion in section 5.5 would be unsafe while looking safe.

### 11.4 Critical path and parallelism

```
S3 ✅ done ── settles "don't port the cutter"

S4 ──┐
     ▼
 −1 ─┴─► 1 ──► 3 ──► 4 ──► [ DECISION 3.5 ] ──► 5 ──► 6
      0 ──────►┘     ▲          ▲   ▲
                     │          │   └── S1, S2 run HERE
      2 ✅ done ─────┘          │
                                └── ship-able product line: view + segment + health,
                                    both platforms, weight honestly unavailable
```

- **Critical path to a working product: S4 → −1 → 1 → 3 → 4.** That is the whole near-term plan,
  and **none of it touches section 3.5**.
- **Slice 2 is done.** The Python consolidation landed; `pig_geometry.py` is ready for slice 4's
  port and `pig_cutter.py` is ready for whichever option slice 5 takes.
- **Slice 4 is the natural stopping point.** It delivers most of `TASKS.md` on both platforms. If
  the programme has to pause, it should pause after 4 — with a coherent shipped product — rather
  than mid-way through a weight integration whose runtime has not been chosen.
- **Everything after slice 4 is optional in a way everything before it is not.**

### 11.5 Health checks — how to tell a slice is in trouble before it is late

Each has a trigger and a pre-decided response, so the decision is not made under pressure:

| Slice | Check | Trigger | Response |
|---|---|---|---|
| S4 | day 2 | native ONNX export fails | Go to rung 2 (ORT custom op) and re-baseline slice 4 to +5–8 d **before** starting it, not during. |
| 1 | day 3 | GhostNetV3 rpr fusion does not reproduce trained logits < 1e-5 | Stop; the architecture file is wrong or the checkpoint is not the form assumed (section 6.1). Do not export an unfused model "for now" — it changes the op set and the latency budget. |
| 3 | day 4 | ORT session will not load on device | Suspect the reduced-build op allowlist (`ort_op_config.py`) before suspecting the model. |
| 4 | day 5 | S4 landed on rung 2 | Re-baseline immediately and say so, rather than absorbing it silently. |
| 4 | end | health card shows a real class on a real device | ✅ **This is the milestone that answers "do the models work?"** Everything before it is scaffolding. |
| 5 (A) | S1, day 2 | scipy will not import on-device, or the APK delta exceeds ~60 MB | Option A is out. Take option B or C — **nothing built in slices 1–4 is wasted**, which is the entire point of deferring. |
| any | any | an estimate's stated assumption is found false | Re-estimate that slice openly. The assumptions are written down precisely so this is a mechanical act, not an argument. |

### 11.6 What is deliberately not estimated

Honesty about the edges of the estimate:

- **Recovering the health test split (slice −1)** depends on an environment outside this repo. If
  it is gone, no amount of engineering replaces it; the response is the declared partial probe, not
  a longer estimate.
- **Chaquopy licensing and Play Store review** of an app embedding a Python runtime are not
  engineering tasks and are not costed here. S1 should confirm the licence terms in passing —
  under option A only.
- **A backend for option B** — hosting, auth, cost, uptime, and the consent review for a mask
  leaving the device — is a separate programme, not a slice. It is priced here only as the
  client-side integration.
- **Retraining the weight regressor** so it no longer depends on a fixed 1.88 m camera height
  (section 2.3) is out of scope entirely, and is the thing most likely to make the whole
  section-3.5 question moot by changing what the weight branch even needs.

### 11.7 DI and threading (unchanged, locked)

- **DI: a plain top-level singleton `MlRuntime.instance`**, initialised in `main.dart` — not an
  InheritedWidget. Services stay constructor-injected at the interface level, so
  `test/helpers/mock_ml_services.dart` keeps working and `MlRuntime` never appears in use-case
  tests.
- **Threading: one long-lived inference isolate** spawned in `MlRuntime.init()`. It opens the
  `DynamicLibrary`, calls `instaham_ml_create`, and holds the context pointer; the main isolate
  sends `{op, path}` over a `SendPort`. `Isolate.run`-per-call is rejected — it re-creates the ORT
  session every call. With `instaham_ml_run_pipeline_json` this is one crossing per photo on iOS, and two on Android for a dorsal photo (section 3.4). The isolate owns both halves of the suspension; the MethodChannel hop to Chaquopy is issued from the main isolate and its result posted back, because platform channels are not available on a background isolate.

---

## 12. Existing files modified

| File | Change |
|---|---|
| `lib/main.dart` | after `ensureInitialized()`: `await MlRuntime.instance.init(await getApplicationSupportDirectory());` in try/catch — init failure logs and the app still runs. |
| `lib/services/ml/weight_regression_service.dart` | **delete**; replaced by `weight_pipeline_service.dart`. |
| `lib/services/ml/view_model_service.dart` | doc comment only: "MobileNetV4" → GhostNetV3 1.0x. Interface unchanged. |
| `lib/services/ml/health_model_service.dart` | doc comment: GhostNetV3 1.0x selected; note the manifest-declared input protocol. Interface unchanged. |
| `lib/features/inference_pipeline/domain/use_cases/run_inference_pipeline_use_case.dart` | delegate to `IInferencePipelineService.run(imagePath)` and map the section-9 envelope onto the existing entities. Delete the hardcoded `WeightFeatures(ra: 0.21, …)` placeholder and the `segment → eligibility → computeScale → predict` sequence — that order now lives in C++ `pipeline/`. Keep `WeightEligibilityChecker` and `ComputeScaleUseCase` for `cmPerPixel` **display only** (`camera_height_is_xgboost_feature == false`). |
| `lib/features/weight_estimation/domain/entities/weight_result_entity.dart` | add `final CaptureContract? captureContract;` + `capture_contract` in `toJson`/`fromJson`. |
| `lib/features/results/presentation/screens/results_screen.dart` + weight card | render "Research / fixed-camera (1.88 m) — provisional" when `featureSpace == 'fixed_camera_pixels'`; render an explicit unavailable state for each branch status; surface `input_protocol_fallback` on the health card. Never display invented values. |
| `test/helpers/mock_ml_services.dart` | replace `MockWeightRegressionService` with `MockWeightPipelineService`; add `MockInferencePipelineService` with `reject` / `health_only` / `dorsal_valid` / segmentation-failure presets. |
| `test/features/inference_pipeline/run_inference_pipeline_use_case_test.dart` | test all four routing shapes from section 9. |
| `test/parity/parity_test.dart` | un-skip view, health, segmentation, and features against a **test manifest**; gate-B tolerances from section 10. |
| `pubspec.yaml` | add `ffi: ^2.1`, `crypto: ^3.0`, `instaham_ml_ffi: { path: packages/instaham_ml_ffi }`; dev dep `ffigen: ^13`; uncomment `assets:` and add `- assets/ml/` (excluding the large segmentation model). |
| `.gitignore` | add `!assets/ml/**/*.onnx` (or Git LFS for `assets/ml/**`). Training `.pt` files stay ignored deliberately — they are local export inputs identified by `source_run.checkpoint_sha256`. |
| `android/app/build.gradle.kts` | **slice 3:** `defaultConfig { ndk { abiFilters += listOf("arm64-v8a", "x86_64") } }`; `packagingOptions { jniLibs { pickFirsts += "**/libc++_shared.so" } }`. **Slice 5, option A only:** apply the Chaquopy plugin; `python { pip { install "numpy"; install "scipy"; install "scikit-image" /* or vendored */ } }`; a `copyPigCutter` task that copies `ML/pig_cutter.py` into the Python source root and fails the build if its sha256 disagrees with the manifest. **Consider dropping `x86_64` under option A** — it doubles every Python native wheel for emulator-only benefit. |
| `android/app/src/main/kotlin/.../MainActivity.kt` | **slice 5, option A only:** register `CutterChannel`; `Python.start(AndroidPlatform(this))` once, guarded. Untouched under options B and C. |
| `ios/Podfile` | picks up the podspec; bump `platform :ios, '13.0'` (ORT minimum). No Python — the iOS manifest ships `weight.available: false`. |
| `lib/features/results/.../weight_card` | **[new, slice 4]** replace the current `value: 'Pending'` placeholder (`results_screen.dart:340`) with real branch states: `unavailable` + reason (a stated limitation, not an error) and `error`. Add `pending_cutter` (in progress) in slice 5 under option A only. Health renders immediately in every state. |
| `lib/features/results/.../_healthCard` | **[new, slice 4]** same treatment for `results_screen.dart:372` — today it renders `'Pending'` whenever no `HealthResult` row exists, which is always, because nothing writes one. |
| `lib/core/router/app_router.dart` | **[new, slice 4]** `/analysis` currently maps straight to `ResultsScreen` with no inference step between confirm and results. Insert the pipeline run (or an analysis screen that awaits it) so a result actually exists before the results screen reads it. |
| `ML/body_mask.py`, `ML/mask_features.py`, `ML/extended_mask_features.py`, `ML/yolo_inference.py` | **delete** in slice 2, once gate A is green and its fixtures are committed (section 5.5). Recoverable from git history; `ML/parity/gate_a.py` pins the revision. |
| `ML/weight_runtime.py` | repoint imports at `ML.pig_geometry` + `ML.parity.reference_yolo`; collapse the four-file provenance hash at lines 356-359 to one `ML/pig_geometry.py` hash; `BODY_MASK_PROTOCOL_VERSION` / `BODY_MASK_METHOD` re-exported unchanged so `_verify_*` still passes (section 5.5.1). |
| `ML/parity/run_reference.py` | line 68 `from mask_features import extract_five_features` → `from ML.pig_geometry import extract_five_features`. |
| `ML/compat/src_alias.py` | keeps only the `src.yolo_modifications` alias; the `src.body_mask` / `src.mask_features` / `src.extended_mask_features` / `src.yolo_inference` aliases are dropped with their targets. |
| `ML/export/requirements-export.txt` | pin `ultralytics==8.4.121` to match the checkpoint. |
| `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §2.2, §2.4 | annotate: deployed view model is `ML/view_model/` (GhostNetV3 1.0x), health is `ML/health_cnn/` (GhostNetV3 1.0x). Research record — annotate, do not rewrite. |

---

## 13. Verification

**Layering and the one-file rule (runs first, needs no toolchain):**

- `scripts/check_layering.sh` — fails on any `#include` that violates the section 3.1 table, **and**
  fails if the `.cpp` set under `geometry/` is not exactly `{pig_geometry.cpp, health_input.cpp}`
  (section 3.1.1).
- `scripts/check_one_helper.sh` — the Python half of the same rule, run in CI from slice 2 onward:
  - `ML/body_mask.py`, `ML/mask_features.py`, `ML/extended_mask_features.py`,
    `ML/yolo_inference.py` must **not** exist;
  - no file in the repo may import them (`grep -rn "from src.body_mask\|import mask_features\|…"`);
  - exactly two helper files exist — `ML/pig_cutter.py` and `ML/pig_geometry.py` — one per runtime
    (section 3.1.1), and `pig_cutter.py` is the sole `body_mask` provenance hash in the manifest.
- `scripts/check_cutter_purity.sh` — `ML/pig_cutter.py` may import only `numpy`, `cv2`, `scipy`,
  `skimage`, and the standard library. Any `open(`, `Path(`, `onnxruntime`, `torch`, or
  `ML.` import is a CI failure. This is the section-3.1 dependency rule applied to the one file
  that is not compiled and therefore cannot be fenced by the linker.
- `scripts/check_cutter_copy.sh` — **slice 5, section 3.5 option A only.** The Chaquopy copy under
  `android/app/src/main/python/` must be byte-identical to `ML/pig_cutter.py`, so the shipped cutter
  and the gated cutter cannot drift. Does not exist under options B or C.
- `scripts/check_port_sections.sh` — compares the section markers of `ML/pig_geometry.py` and
  `geometry/pig_geometry.cpp` (section 5.6). Two modes, because the port lands across slice 4 in
  pieces:
  - `--subset` (during slice 4): the `.cpp` markers must be a **prefix-ordered subset** of the `.py`
    markers — a ported section may not be renamed, reordered, or invented.
  - `--exact` (slice 4 DoD onward, and in CI from then on): the two lists must be identical.

  Without the two modes this check would fail for most of slice 4 and be disabled by whoever
  hit it first, which is how a "half-finished port that gate B's fixtures happen not to exercise"
  actually ships. Note that `pig_geometry.py`'s chen16 section is optional (section 5.1) — if it is
  deliberately not ported, `--exact` is run against an explicit allow-list of skipped markers, never
  by loosening the check.
- `test_layering.cpp` — compile-fence assertions for the include rule.

**Native (`ctest`, slice 3+):**

- `test_manifest` — schema-version accept/reject; hash mismatch → `ERR_HASH_MISMATCH`; permuted
  `feature_order.json` → `ERR_CONTRACT`; unknown `health.input.protocol` → `ERR_CONTRACT`;
  `available:false` blocks load with null hashes and still return `ERR_UNAVAILABLE` on call.
- `test_classifier_golden` — fused-deploy logits vs committed reference < 1e-3, for **both** view
  and health; permuted `classes.json` → the reported label follows the map, proving no positional
  hardcoding.
- `test_segmenter_postprocess` — proto + coefficients → mask; unletterbox round-trip IoU ≥ 0.99 on
  synthetic polygons; odd-padding handled.
- `test_health_input` — all three protocols on one fixture mask produce the documented crops; the
  fallback path sets `input_protocol_fallback`.
- `test_pig_geometry` — the whole single unit against `ML/parity` fixtures at gate-B tolerance:
  unletterbox round-trip, dorsal core, body cut-off QC fields, and the five features. One test
  binary for one translation unit.
- `test_pipeline_routing` — the section-9 shapes, including that a weight failure leaves
  `health.status == "ok"`, and both platform manifests: with `weight.available:true` a dorsal photo
  yields `pending_cutter`; with `false` it yields `unavailable` +
  `no_cutter_runtime` and an otherwise identical envelope.
- `test_cutter_gap` — suspend/resume: unknown handle, double-finish, TTL eviction, a body mask
  whose dimensions disagree with the input, and `instaham_ml_destroy` with handles still live.
- ~~Gate C~~ — deleted in revision 6 (section 10). `ML/parity/gate_c.py` is retained only as a
  cheap regression guard while the two primitive copies still happen to match; it gates nothing.

**Python:**

- `python -m ML.export.fuse_reparam --check ML/view_model/best.pt` and `… ML/health_cnn/best.pt`
  — fused vs trained logits < 1e-5. Runs before any classifier export.
- `python -m ML.export.probe_health_input --run ML/health_cnn` — reproduces
  `test_predictions.csv`; writes the winning protocol into the health fragment.
- `python -m ML.export.export_yolo --checkpoint ML/segmentation/weights/best_eval_fp32.pt` —
  fails loudly if the `src.` alias is missing rather than half-loading.
- `python -m ML.export.build_manifest --check --schema` — deterministic re-export, stable sha256,
  schema-valid.
- `python -m ML.parity.run_reference --fixtures test/fixtures/parity --out …/expected.json` — the
  full section-1 graph.
- `python -m ML.parity.gate_a --against <pre-deletion-rev>` — gate A, section 10 tolerances.
  Reconstructs the deleted originals from git, so it keeps working after section 5.5 and is
  re-runnable after every section-5.4 substitution.
- `python -m ML.weight_runtime --selftest` — proves the section-5.5.1 repoint: imports resolve
  against `ML.pig_cutter` / `ML.pig_geometry`, the provenance record carries one `source_sha256`,
  and `BODY_MASK_PROTOCOL_VERSION` / `BODY_MASK_METHOD` are byte-identical to their pre-deletion
  values, so `_verify_*` and the manifest still agree.
- `pytest ML/parity/test_cutter_contract.py` — the section-3.3 boundary contract: the cutter
  accepts a uint8 mask and `ji_config` and returns the documented QC fields, on the fixture corpus.
  Runs host-side against `ML/pig_cutter.py`.

**Android device (slice 5 DoD):**

- `scripts/device_gate.sh` — the fixture corpus through the **shipped Chaquopy cutter** on a real
  arm64 device, compared to host Python at gate-A tolerances. This is the only check that can catch
  an ABI-specific numerical difference in the on-device `scipy` build, and no host test substitutes
  for it.
- APK size delta recorded before and after the Python runtime is added, per ABI.

**Flutter (`AGENTS.md` validation order):**

1. `dart format` on changed files.
2. `flutter analyze`.
3. `flutter test test/features/inference_pipeline/run_inference_pipeline_use_case_test.dart`.
4. `flutter test test/parity/parity_test.dart`.
5. `flutter test` — full suite.
6. Manual device smoke — APK size delta recorded; first-launch asset copy + sha256 verify.

**`AGENTS.md`-specific gates:**

- Rule 1: enforced three ways — the exporter refuses a `classes.json` that disagrees with the
  checkpoint's `class_to_idx`; the native loader resolves labels only by name; the golden test
  permutes `classes.json` and asserts the label follows.
- Rule 2: `RA, LC, BL, BW, E` asserted in native (`ERR_CONTRACT` otherwise) and in the retained
  `test/features/weight_estimation/weight_features_order_test.dart`.
- Rule 4: `test_pipeline_routing` proves a failed weight branch leaves health untouched, and that
  a failed segmentation degrades health input rather than blocking health.
- Rule 5: a rotated-EXIF fixture must yield output identical to its pre-rotated twin.
- Rule 8: no branch ever emits a number after a failed upstream check — it emits `skipped`,
  `unavailable`, or `error` with a reason.
- Rule 9: reference-point coordinates map to the displayed image rect including `BoxFit`
  letterboxing — unchanged, and unaffected by this plan.

---

## 14. Plan rating: 9.5 / 10

Revision 4 rated 8 (executability 6.5, a 10,701-line C++ port on the critical path). Revision 5
rated 9 but bought its schedule with a product hole — Android-only weight — and rested its keystone
on an unrun spike. Revision 6 keeps revision 5's gains, **proves** the premise instead of assuming
it (S3), and then declines to pay for the expensive half of the decision until it is actually due.

The half point it still does not get is honest: the plan describes a product whose weight branch
has no committed delivery mechanism, and the near-term work is now unstarted rather than
theoretically sized. Deferring the right decision is a virtue; it is not the same as having shipped.

### 14.1 Scored by dimension

| Dimension | Rev 4 | Rev 5 | Rev 6 | What moved |
|---|---|---|---|---|
| Meets the `TASKS.md` brief | 9.5 | 9 | 9 | Unchanged. "Port to c++" is still *partially* declined — defensible under "open to code change", and now backed by S3's numbers rather than judgement, but still narrower than the sentence's plain reading. |
| Architecture and isolation | 9 | 9.5 | **10** | The one-hop boundary (section 3.3) removes the last piece of accidental complexity: no duplicated primitives, no gate C, one hop instead of two, and `finish_weight` now takes five floats rather than a second full mask. The design got *smaller*, which is the strongest kind of improvement. |
| Evidence quality | 9 | 9.5 | **10** | S3 replaces the plan's biggest remaining estimate with a measurement: 9,911/10,855 live, 1,985 lines SciPy-coupled, seven named functions. The port decision is no longer a judgement call. |
| Risk identification | 8.5 | 9 | **9.5** | The largest technical risk is measured and cancelled; the largest *product* risk is now explicitly deferred rather than silently absorbed, with three costed options and a named decision point. |
| **Executability** | **6.5** | **8.5** | **9** | Near-term work is 33–50 days to a shipping product, and **none of it depends on the deferred decision**. Only one spike (S4, 2 d) remains on the critical path. Slice 2 is done, which removes the widest range in the previous table. |
| Verifiability | 9 | 9 | 9 | Gate B's scope matches the smaller port; gate C is deleted as unnecessary rather than kept as ceremony. The device gate applies only under option A. |
| Reversibility | 8 | 8 | **9.5** | The core improvement of this revision. Revision 5 committed to Chaquopy — 85 MB of APK and the iOS weight branch — before S1 ran. Revision 6 keeps all three options open at no cost, because slices 1–4 are option-neutral. |
| **Product completeness** | — | 6.5 | **7** | Still the weakest dimension, but better: revision 5 *guaranteed* an iOS product without weight; revision 6 leaves open an option (B) where both platforms get it. Weight is deferred for everyone rather than amputated on one platform. |

Weakest link governs, and it has moved again — from *can we build it in reasonable time* (rev 4),
to *is an iOS product without weight acceptable* (rev 5), to simply **product completeness: the
weight branch has no delivery mechanism yet, and its regressor is still the temporary fixed-1.88 m
one.** That is the right problem to be left with, because it is a product decision resting on a
model that may change, not an engineering unknown blocking work.

### Pros

- **The programme's largest work item and largest technical risk are deleted on measured evidence,
  not judgement.** S3 (section 5.2(c)): 9,911 of 10,855 lines live, 1,985 of them SciPy-coupled
  across seven named functions. Those lines are not ported, and `gaussian_filter1d`, `find_peaks`,
  and `skeletonize` keep running as the exact library calls that produced the research results.
  Nothing is approximated, so there is no numerical-drift risk to gate against — the cutter *is*
  the research cutter.
- **The expensive decision is deferred at zero cost.** "Don't port" and "ship Chaquopy" were
  conflated in revision 5 and are now separated (section 3.5). Slices 1–4 are identical under all
  three options, so waiting costs nothing and buys S1's result, the APK measurement, and whatever
  happens to the temporary regressor. This is the difference between a plan that commits early
  because it is anxious and one that commits when the information arrives.
- **The design got smaller under review.** Moving the boundary to the segmentation mask deleted
  gate C, `manifest.weight.shared_primitives`, the five-primitive duplication, and one of the two
  FFI hops — with nothing added in exchange. Revision 5's complexity there was an artifact of
  where the line was drawn, not a property of the problem.
- **The split lands on a seam that already exists.** `body_mask.py` imports exactly two project
  symbols; `mask_features.py` imports none; all three hard primitives are confined to the cutter.
  The boundary was found in the code, not drawn on the plan.
- **The runtime boundary is genuinely narrow.** One mask in, five floats out. No photo crosses it,
  no model, no file path, no manifest — which keeps both the `AGENTS.md` consent rule and the
  section-3 isolation rule intact across a language boundary.
- **A weight-less build is the default state, not a fallback.** `available:false`,
  `ERR_UNAVAILABLE`, and per-branch envelope statuses are built in slice 4 and are correct under
  every section-3.5 option, so the "no weight here" path is exercised from the first shipped build
  rather than bolted on if something fails.
- **The port stops being the critical path.** ~700 lines of Python to ~1,200 of C++ is an ordinary
  slice, not a programme. Revision 4's con 5 ("High" residual) and con 5b (huge translation unit)
  are both retired.
- **Executability is real and the near-term path is short.** 33–50 days to a shipped view +
  segmentation + health product on both platforms, with one 2-day spike (S4) on the critical path.
  Every size carries the assumption it rests on, and every health check has a pre-decided response.
- **Slice 2 is done and verified.** Consolidation, the section-5.2(b) override resolution, the
  deletion of the four originals, the repoint, and a 4/4-green test suite are committed — so the
  widest estimate in revision 5's table is now a fact rather than a range.
- **"One helper file" survives the runtime split.** One Python file that ships, one C++ unit,
  each CI-enforced — plus `check_cutter_purity.sh`, which applies the layering rule to the one file
  a compiler cannot fence.
- Carried forward and undiminished: mechanical layering, every checkpoint present, shared
  GhostNetV3 architecture, a genuinely swappable XGBoost model, the train/serve skew caught before
  implementation, and every `AGENTS.md` rule mapped to a named test.

### Cons, each with its mitigation

| # | Con | Mitigation | Residual |
|---|---|---|---|
| 1 | **The weight branch has no committed delivery mechanism.** Through slice 4 it is `unavailable` on both platforms, and section 3.5's three options have materially different costs and reach. | Deferred on purpose, not overlooked: three options costed, a named decision point after slice 4, and slices 1–4 built option-neutral so the wait is free. Option B (server) keeps both platforms; revision 5 had already conceded iOS. | **Medium-high — still the weakest part of the plan. Deferring the decision well is not the same as delivering weight.** |
| 2 | **Chaquopy running scipy on a real device is still undemonstrated.** | No longer load-bearing. S1 moved to the start of slice 5, where it informs a decision instead of underwriting the whole plan; if it fails, options B and C are waiting and nothing built in slices 1–4 is wasted. | Low — the exposure was removed by resequencing, not by solving it. |
| 3 | **Under option A, embedding CPython + numpy + scipy (+ scikit-image) grows the APK by an estimated 65–85 MB per ABI**, on top of a ~40 MB segmentation model. | The estimate is now an explicit input to the section-3.5 decision rather than a consequence discovered afterwards: S1 measures it before anything commits, S2 removes scikit-image if the wheel is missing or heavy, and dropping `x86_64` is on the table. Options B and C cost nothing here. | Medium — the number is still unmeasured, but it can no longer surprise the plan, only inform a choice. |
| 4 | ~~**Five primitives exist in both runtimes and can drift.**~~ | **Retired in revision 6.** The one-hop boundary (section 3.3) means the two copies are never used in the same computation, so they are not required to agree. Gate C and `manifest.weight.shared_primitives` are both deleted. | None — the problem is designed out, not mitigated. |
| 5 | **Under option A the pipeline suspends mid-flow**, so that platform needs two FFI crossings plus a MethodChannel hop, and some flow knowledge leaves C++. | `pipeline/` still decides *whether* to suspend; exactly one Dart file may see it; `cutter_gap` bounds handles with a TTL so a crashed cutter cannot pin memory; `test_cutter_gap` covers stale, double-finish, TTL, and dimension-mismatch. The resumed call now carries five floats, not a second mask. Does not exist under options B/C. | Low — contained, conditional, and cheaper than in revision 5. |
| 6 | **The cutter remains ~9,900 live lines that nobody on the team has read**, and S3 confirms there is no dead-code win to be had. Not porting it does not make it comprehensible. | Consolidation is done and the self-override is resolved and tested. Beyond that the plan explicitly does *not* promise comprehension: the file ships as the research artifact it is, gated by gate A on a real corpus once slice −1 lands. | Medium — a maintenance liability rather than a delivery risk, and it would have been strictly worse under any porting option. |
| 7 | **The image data three gates depend on is not in the repo** (unchanged from revision 4). | Slice −1, sized 3–5 d (5–8 d if the split is unrecoverable), with the probe degrading to a *declared* partial run rather than a false 2812-sample claim. | Medium-high — it gates the health-protocol decision and every parity gate, and recovery depends on an environment outside this repo. |
| 8 | **LDConv/ACmix ONNX export is still uncertain.** | Now spike S4 (2 d) rather than a slice-4 discovery; the ladder records where it stopped; rung 2 is contained to one file; rung 3 is still a coherent product. | Medium. |
| 9 | **Chaquopy licensing and Play Store review** of an app embedding a Python runtime are outside the estimate. | Flagged explicitly in section 11.6; S1 confirms licence terms in passing. | Low-medium — process risk, not technical, but it can surprise a release date. |
| 10 | **Two runtimes means two debugging stories**, two crash-reporting paths, and a Python traceback that must be marshalled into a C-ABI error. | `bridge.py` catches everything and returns a structured error; `instaham_ml_abandon_cutter` completes the envelope with `weight.status: "error"`; health is never affected. | Low. |
| 11 | **A green gate A does not by itself prove the 5.2(b) overrides were resolved correctly** (unchanged). | Corpus coverage of both branches of both overrides is a precondition for declaring the corpus done (section 11.3.1). | Medium — a coverage obligation, and those are the ones waived under pressure. |
| 12 | **Gate A and gate B tolerances stack** (unchanged, though the composed distance is now smaller since the cutter is not ported). | After gate B is green, run the corpus once C++-vs-originals and record the composed delta in the release notes. A measurement, not a gate. | Low. |
| 13 | **Estimates for slices 1, 3, 4 remain pre-execution**, even though S3 is done and slice 2 is spent. | Each names its assumption; section 11.5 makes re-estimation mechanical rather than an argument. S4 (2 d) is the only remaining input that can move a near-term number. | Low-medium — the two widest ranges in revision 5 (slice 2, the cutter port) are now resolved. |
| 14 | **The manifest gains a per-platform dimension** (schema_version 3), so there are now two manifests to keep consistent. | One generator, one schema, both validated in CI; `test_manifest` covers both; through slice 4 the two are identical apart from platform metadata, since weight is unavailable everywhere. | Low. |
| 15 | Toolchain, download size, and iOS validation risks carried forward from revision 4 (its cons 7–9, 11). | Unchanged mitigations: pinned prebuilt binaries, reduced ORT build, `pod lib lint` in slice 0, provenance hashes for gitignored checkpoints. | Medium. |

### Residual risk, unmitigated

1. **The weight branch has no delivery mechanism yet (con 1)**, and the regressor it would deliver
   is still the temporary fixed-1.88 m one (section 2.3). These compound: it is possible to spend
   slice 5 shipping a mechanism for a model that then gets replaced. Re-check the model's status at
   the decision point, not just S1's result.
2. **Recovering the health test split (con 7).** Depends on an environment outside this repo. No
   engineering substitutes for it; the response is a declared partial probe.
3. **The segmentation export (con 8).** S4 is 2 days and is the only near-term item that can force
   a replan. Everything downstream of slice 1 assumes it lands on rung 1 or 2.
4. **Nobody has read the cutter (con 6).** It ships, or is served, as a research artifact. That is
   acceptable while it is gate-A-pinned to the original, and it is a real liability the first time
   it needs to change.

### 14.2 What would raise this to a 10

1. **Run S4** — 2 days, and it is the only spike left that can force a near-term replan. Until it
   reports, slice 1's segmentation export is a hypothesis.
2. **Run slice −1** (con 7), so gate A stops being synthetic and the health-protocol probe can
   actually run. It blocks nothing else from *starting*, but it is what makes the gates mean
   something.
3. **Ship slice 4.** The plan's remaining weakness is product completeness, and the fastest way to
   fix that is a real view + segmentation + health build on a device — which is also the first
   point at which the app stops showing "Pending".

All three are execution and need no decision from anyone. The section-3.5 question is deliberately
*not* on this list: it should be answered after slice 4, with S1's measurement and the model's
status in hand, not sooner.
