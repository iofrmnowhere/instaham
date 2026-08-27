"""Export the modified YOLO11s-seg (LDConv/ACmix) checkpoint to ONNX + a manifest fragment.

    python -m ML.export.export_yolo \
        --checkpoint "ML/final__yolo11s-seg__ldconv_acmix__.../weights/best_eval_fp32.pt" \
        --out build/ml_export/segmentation

Fallback ladder (recorded in the fragment's "export_mode"):
  1. onnx_native   -- torch.onnx.export with ML/yolo_modifications.py importable, static 640.
  2. ort_customop  -- register LDConv/ACmix gather as an ORT custom op in src/onnx_runner.cpp.
  3. unavailable   -- ship view + health + provisional weight; segmentation.available = false.

The custom LDConv operator uses data-dependent torch.gather on a runtime-built fractional
grid; ACmix uses nn.Unfold + a dynamic odd-size recovery loop. Export is expected to be
fragile -- this script tries (1), and on failure writes an "unavailable" fragment rather
than raising, so the rest of the pipeline still ships.
"""
from __future__ import annotations

import argparse
import sys
import traceback
from pathlib import Path

from ML.export.common import model_input_block, sha256_file, write_json

ML_DIR = Path(__file__).resolve().parent.parent  # so `import yolo_modifications` resolves


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
    if str(ML_DIR) not in sys.path:
        sys.path.insert(0, str(ML_DIR))

    try:
        import yolo_modifications  # noqa: F401  (registers custom module classes)
        from ultralytics import YOLO

        if hasattr(yolo_modifications, "register_checkpoint_safe_globals"):
            yolo_modifications.register_checkpoint_safe_globals()

        model = YOLO(str(checkpoint))
        exported = model.export(format="onnx", imgsz=imgsz, opset=opset, simplify=True, dynamic=False)
        onnx_path = out / "yolo.onnx"
        Path(exported).replace(onnx_path)
    except Exception:  # noqa: BLE001 -- fragile by design; fall back rather than abort the pipeline
        traceback.print_exc()
        print("export_yolo: onnx_native failed -> writing 'unavailable' fragment", file=sys.stderr)
        return _unavailable_fragment(out, "ldconv_acmix_onnx_export_failed")

    fragment = {
        "segmentation": {
            "available": False,  # flip true only after parity (mask IoU >= 0.95)
            "unavailable_reason": "pending_parity_check",
            "model": {
                "path": "segmentation/yolo.onnx",
                "sha256": sha256_file(onnx_path),
                "architecture": "yolo11s-seg-ldconv-acmix",
                "opset": opset,
                "input": model_input_block("images", [imgsz, imgsz]),
                "letterbox": {"color": [114, 114, 114], "stride": 32, "scaleup": False},
            },
            "postprocess": {
                "conf": 0.25,
                "iou": 0.7,
                "single_largest_instance": True,
                "mask_protocol": "original_coordinate_polygon_v1",
            },
            "export_mode": "onnx_native",
            "protocol_version": "yolo11s_ldconv_acmix_fixed_seed42",
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
