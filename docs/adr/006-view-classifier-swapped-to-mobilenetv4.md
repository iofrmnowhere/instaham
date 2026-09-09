# ADR-006: The view classifier moved from GhostNetV3 to MobileNetV4-Conv-Small

Status: Accepted

Context: The shipped `view` capability (dorsal_valid / health_only / reject) ran
`ghostnetv3_100`, exported by `ML/export/export_classifier.py` from `ML/view_model/best.pt`
(`view_v1`). A retrained checkpoint arrived at `model_and_cutter/mobilenet/best.pt`, later
staged at `ML/view_model_mnv4/best.pt`. Its `class_to_idx` (`{dorsal_valid: 0, health_only:
1, reject: 2}`) is identical to `ML/view_model/classes.json`, its `safety_metrics.json` uses
the same false-weight-accept/-reject vocabulary as the existing view sidecar, and its
test-set support (2599/2859/440) matches `ML/view_model`'s split exactly — evidence this is
a retrained view gate, not a health-disease model, despite the checkpoint's storage folder
name. `classifier.weight` shape `[3, 1280]` and a strict `state_dict` load against timm's
`mobilenetv4_conv_small` (278/278 keys, no missing/unexpected/mismatched) confirmed the
architecture directly (docs/plan.md).

Decision: Export `ML/view_model_mnv4/best.pt` with `mobilenetv4_conv_small` and ship it as
the `view` capability, replacing `ghostnetv3_100`. Preprocessing (resize-shorter-side 255 →
center-crop 224, ImageNet mean/std, bilinear), the class map, and the native runtime path
(`packages/instaham_ml_ffi/src/classifier.cpp`, manifest-driven, architecture-agnostic) are
all unchanged. `capabilities.view.protocol_version` moved `view_v1` → `view_v2` so a stored
scan is attributable to the model that produced it. `ML/export/export_classifier.py` gained
a `--fuse {auto,always,never}` flag (default `auto`): GhostNetV3's re-parameterisation fold
(`ML/export/fuse_reparam.fuse`, `timm.utils.model.reparameterize_model`) is a silent no-op on
MobileNetV4, which has no `*_rpr_*` branches, so running the fold's "< 1e-5" assertion on it
would trivially pass without proving anything. `has_reparam_modules()` (same predicate
`reparameterize_model` uses internally) lets a caller skip the step outright. The GhostNetV3
health export is unaffected — `auto` still folds it, and `--fuse always`/`never` are
available if a future export needs to force either behaviour explicitly.

The exported graph's op set (`Add, Conv, Flatten, Gemm, GlobalAveragePool, Relu`) is a strict
subset of what the shipped GhostNetV3 graphs already used, so no ONNX Runtime build config
change was needed. `ML/view_model/` (the GhostNetV3 checkpoint and sidecars) was kept in
place as the rollback baseline rather than deleted.

Consequences: The checkpoint's `training_config` records optimizer, LR, weight decay,
patience, label smoothing, seed, and AMP settings, but not crop size or normalization — the
preprocessing contract carried into the manifest is therefore asserted from the app's
existing shared contract and timm's default data config for this architecture (224 / ImageNet
mean-std / `crop_pct` ≈ 0.875, consistent with 255→224), not independently reproduced from the
checkpoint's own training images; that image root was not available on the export workstation
at the time of this ADR. The checkpoint's own reported metrics (macro-F1 0.950 → 0.996,
false-weight-reject-rate 2.886% → 0.385%) come from a training run this repository cannot
reproduce, so they are recorded, not independently re-verified, numbers — on-device
verification against real captures is expected to follow (docs/plan.md step 7) before this
is treated as fully confirmed in the field.
