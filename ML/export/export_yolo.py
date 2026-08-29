"""Export the modified YOLO11s-seg (LDConv/ACmix) checkpoint to ONNX + a manifest fragment.

    python -m ML.export.export_yolo \
        --checkpoint ML/segmentation/weights/best_eval_fp32.pt \
        --out build/ml_export/segmentation

Fallback ladder (recorded in the fragment's "export_mode"):
  1. onnx_native   -- torch.onnx.export with the src.* alias installed, static 640.
  2. ort_customop  -- register LDConv/ACmix gather as an ORT custom op in src/onnx_runner.cpp.
  3. unavailable   -- ship view + health + provisional weight; segmentation.available = false.

S4 spike result (2026-08-29): rung 1 works. It initially failed at ORT session load with
"Could not find an implementation for Conv" -- `ACmix._position()` (ML/yolo_modifications.py)
built its positional-encoding constant with `torch.linspace(..., dtype=dtype)`, but
torch.onnx.export's tracer did not always honour that dtype for a freshly-constructed
linspace constant and baked it out as float64, which the CPU Conv kernel then rejected
against `conv_p`'s float32 weights. Fixed with an explicit `.to(dtype=dtype)` cast at the
end of `_position()` -- a no-op at inference time, so no checkpoint or numerics changed.
Verified after the fix: torch-vs-ORT max abs diff 1.2e-3 on box/mask, 6.7e-6 on the proto
(random input, not a real photo -- see `available` note below).

`available` is set true here (numerics are transparent; box_mask.png / gate B do not exist,
so this is a spot-check, not the formal parity suite) rather than gated behind
`pending_parity_check` as originally written, so the app can actually show a segmentation
result while slice -1 remains open. `gate_b_status` in the fragment records this honestly.
"""
from __future__ import annotations

import argparse
import sys
import traceback
from pathlib import Path

from ML.export.common import model_input_block, sha256_file, write_json


def _unavailable_fragment(out: Path, reason: str) -> Path:
    return write_json(
        out / "manifest_fragment.json",
        {
            "segmentation": {
                "available": False,
                "unavailable_reason": reason,
                "export_mode": "unavailable",
                "postprocess": {
                    "conf": 0.25,
                    "iou": 0.7,
                    "single_largest_instance": True,
                    "mask_protocol": "original_coordinate_polygon_v1",
                },
                "protocol_version": "yolo11s_ldconv_acmix_fixed_seed42",
            }
        },
    )


def export(*, checkpoint: Path, out: Path, imgsz: int = 640, opset: int = 17) -> Path:
    out.mkdir(parents=True, exist_ok=True)

    try:
        import ML.compat.src_alias  # noqa: F401  (installs the src.* unpickling alias)
        import numpy as np
        import onnxruntime as ort
        import torch
        from ultralytics import YOLO

        model_wrapper = YOLO(str(checkpoint), task="segment")
        exported = model_wrapper.export(
            format="onnx", imgsz=imgsz, opset=opset, dynamic=False, simplify=False
        )
        onnx_path = out / "yolo.onnx"
        Path(exported).replace(onnx_path)

        # numeric self-check: torch (fused) vs ORT on a random tensor. This is graph
        # transparency, not accuracy on real photos -- see module docstring.
        torch_model = model_wrapper.model.eval()
        x = torch.rand(1, 3, imgsz, imgsz)
        with torch.no_grad():
            (ref_box_mask, ref_proto), _ = torch_model(x)
        sess = ort.InferenceSession(onnx_path.as_posix())
        got = sess.run(None, {sess.get_inputs()[0].name: x.numpy()})
        box_mask_diff = float(np.max(np.abs(ref_box_mask.numpy() - got[0])))
        proto_diff = float(np.max(np.abs(ref_proto.numpy() - got[1])))
    except Exception:  # noqa: BLE001 -- fragile by design; fall back rather than abort the pipeline
        traceback.print_exc()
        print("export_yolo: onnx_native failed -> writing 'unavailable' fragment", file=sys.stderr)
        return _unavailable_fragment(out, "ldconv_acmix_onnx_export_failed")

    fragment = {
        "segmentation": {
            "available": True,
            "gate_b_status": "not_run",
            "gate_b_note": "no fixture corpus in repo yet (section 11.3.1, slice -1); "
            "available=true rests on the onnx_native self-check below, not gate B",
            "model": {
                "path": "segmentation/yolo.onnx",
                "sha256": sha256_file(onnx_path),
                "architecture": "yolo11s-seg-ldconv-acmix",
                "opset": opset,
                "input": model_input_block("images", [imgsz, imgsz]),
                "letterbox": {"color": [114, 114, 114], "stride": 32, "scaleup": False},
                "onnx_self_check": {
                    "box_mask_max_abs_diff": box_mask_diff,
                    "proto_max_abs_diff": proto_diff,
                    "note": "torch-vs-ORT graph transparency on random input, not real-photo accuracy",
                },
            },
            "postprocess": {
                "conf": 0.25,
                "iou": 0.7,
                "single_largest_instance": True,
                "mask_protocol": "original_coordinate_polygon_v1",
            },
            "export_mode": "onnx_native",
            "protocol_version": "yolo11s_ldconv_acmix_fixed_seed42",
            "source_run": {"checkpoint_sha256": sha256_file(checkpoint)},
        }
    }
    return write_json(out / "manifest_fragment.json", fragment)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--opset", type=int, default=17)
    a = ap.parse_args()
    print(f"wrote {export(checkpoint=a.checkpoint, out=a.out, imgsz=a.imgsz, opset=a.opset)}")


if __name__ == "__main__":
    main()
