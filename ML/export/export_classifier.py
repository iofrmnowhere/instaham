"""Freeze a timm classifier checkpoint (view | health) to ONNX + a manifest fragment.

Deterministic: re-run on any checkpoint change. Imports the frozen ML/ files read-only.

    python -m ML.export.export_classifier \
        --checkpoint ML/mobilenetv4/best.pt \
        --classes ML/mobilenetv4/classes.json \
        --arch mobilenetv4_conv_small.e2400_r224_in1k \
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


def _load_state(ckpt: Path, model) -> None:
    import torch

    obj = torch.load(ckpt, map_location="cpu", weights_only=False)
    state = obj.get("model_state", obj.get("state_dict", obj)) if isinstance(obj, dict) else obj
    model.load_state_dict(state, strict=True)


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
    import torch
    from timm import create_model

    out.mkdir(parents=True, exist_ok=True)

    name_to_idx: dict[str, int] = json.loads(classes.read_text())  # never hardcode indices
    model = create_model(arch, pretrained=False, num_classes=len(name_to_idx)).eval()
    _load_state(checkpoint, model)

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
    )

    # numeric self-check: torch vs ORT
    x = torch.rand(1, 3, crop, crop)
    with torch.no_grad():
        ref = model(x).numpy()
    got = ort.InferenceSession(onnx_path.as_posix()).run(None, {"input": x.numpy()})[0]
    max_abs = float(np.max(np.abs(ref - got)))
    if max_abs >= 1e-4:
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
                "opset": opset,
                "input": model_input_block("input", [crop, crop]),
            },
            "preprocessing": pre,
            "class_map": {
                "path": f"{capability}/classes.json",
                "sha256": sha256_file(out / "classes.json"),
            },
            "protocol_version": f"{capability}_v1",
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
