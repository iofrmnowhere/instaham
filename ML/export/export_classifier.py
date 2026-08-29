"""Freeze a GhostNetV3 classifier checkpoint (view | health) to ONNX + a manifest fragment.

Both `ML/view_model/best.pt` and `ML/health_cnn/best.pt` are GhostNetV3 1.0x
(section 2.1 / 6.1 of ML_implementation_plan.md). `model_state` is the training,
multi-branch re-parameterised form (`*_rpr_conv`, `*_rpr_skip`, `*_rpr_scale`); it is
loaded strict against timm's `ghostnetv3_100` (timm >= 1.0 ships this arch natively —
no vendored architecture file is needed, unlike the plan's original assumption of an
un-fused stock timm), then folded to the inference-only form with
`timm.utils.model.reparameterize_model` before export. Fusion is asserted < 1e-5
logit divergence against the unfused checkpoint before any ONNX write.

Deterministic: re-run on any checkpoint change. Imports the frozen ML/ files read-only.

    python -m ML.export.export_classifier \
        --checkpoint ML/view_model/best.pt \
        --classes ML/view_model/classes.json \
        --arch ghostnetv3_100 \
        --capability view \
        --out build/ml_export/view
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from ML.export.common import (
    classifier_preprocessing,
    model_input_block,
    sha256_file,
    write_json,
)
from ML.export.fuse_reparam import fuse

# torch vs ORT tolerance for the exported ONNX graph (section 6.1).
ONNX_TOLERANCE = 1e-4


def _load_state(ckpt: Path, model) -> dict:
    import torch

    obj = torch.load(ckpt, map_location="cpu", weights_only=False)
    state = obj.get("model_state", obj.get("state_dict", obj)) if isinstance(obj, dict) else obj
    model.load_state_dict(state, strict=True)
    return obj if isinstance(obj, dict) else {}


def export(
    *,
    checkpoint: Path,
    classes: Path,
    arch: str,
    capability: str,
    out: Path,
    opset: int = 17,
    crop: int = 224,
) -> Path:
    import numpy as np
    import onnxruntime as ort
    import timm
    import torch
    from timm import create_model

    out.mkdir(parents=True, exist_ok=True)

    name_to_idx: dict[str, int] = json.loads(classes.read_text())  # never hardcode indices
    trained = create_model(arch, pretrained=False, num_classes=len(name_to_idx)).eval()
    obj = _load_state(checkpoint, trained)

    class_to_idx = obj.get("class_to_idx")
    if class_to_idx is not None and class_to_idx != name_to_idx:
        raise SystemExit(
            f"checkpoint class_to_idx {class_to_idx} != {classes} contents {name_to_idx}"
        )
    head_shape = trained.get_classifier().weight.shape[0]
    if head_shape != len(name_to_idx):
        raise SystemExit(f"classifier head {head_shape} != len(classes.json) {len(name_to_idx)}")

    # fold the re-parameterisation branches; assert numerically transparent first.
    model, fuse_max_abs = fuse(trained, sample_input=torch.rand(4, 3, crop, crop))

    onnx_path = out / "model.onnx"
    torch.onnx.export(
        model,
        torch.zeros(1, 3, crop, crop),
        onnx_path.as_posix(),
        input_names=["input"],
        output_names=["logits"],
        dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
        opset_version=opset,
        do_constant_folding=True,
        dynamo=False,
    )

    # numeric self-check: fused torch vs ORT
    x = torch.rand(1, 3, crop, crop)
    with torch.no_grad():
        ref = model(x).numpy()
    got = ort.InferenceSession(onnx_path.as_posix()).run(None, {"input": x.numpy()})[0]
    max_abs = float(np.max(np.abs(ref - got)))
    if max_abs >= ONNX_TOLERANCE:
        raise SystemExit(f"ONNX/torch divergence too large: {max_abs:.2e}")

    pre = classifier_preprocessing(crop)
    write_json(out / "preprocessing.json", pre)
    shutil.copy(classes, out / "classes.json")

    fragment = {
        capability: {
            "available": True,
            "model": {
                "path": f"{capability}/model.onnx",
                "sha256": sha256_file(onnx_path),
                "architecture": arch,
                "arch_source": f"timm=={timm.__version__}",
                "opset": opset,
                "input": model_input_block("input", [crop, crop]),
                "fusion_max_abs_diff": fuse_max_abs,
                "onnx_max_abs_diff": max_abs,
            },
            "preprocessing": pre,
            "class_map": {
                "path": f"{capability}/classes.json",
                "sha256": sha256_file(out / "classes.json"),
            },
            "protocol_version": f"{capability}_v1",
            "source_run": {"checkpoint_sha256": sha256_file(checkpoint)},
        }
    }
    return write_json(out / "manifest_fragment.json", fragment)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--classes", type=Path, required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--capability", choices=["view", "health"], required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--opset", type=int, default=17)
    ap.add_argument("--crop", type=int, default=224)
    a = ap.parse_args()
    frag = export(
        checkpoint=a.checkpoint,
        classes=a.classes,
        arch=a.arch,
        capability=a.capability,
        out=a.out,
        opset=a.opset,
        crop=a.crop,
    )
    print(f"wrote {frag}")


if __name__ == "__main__":
    main()
