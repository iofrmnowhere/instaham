"""Determine which image protocol `ML/health_cnn/best.pt` was actually trained on.

Section 1.1(c) of ML_implementation_plan.md: the shipped health checkpoint's dataset paths
(`test_predictions.csv`) are all Roboflow disease photos, not segmentation output, so the
manifest defaults `health.input.protocol` to `full_frame`. This script makes that a measured
decision instead of an assumption: it re-runs the checkpoint over the recorded test images
under each candidate protocol (`full_frame`, `segmentation_crop`, `segmentation_masked`) and
picks whichever one reproduces `test_predictions.csv`'s recorded probabilities.

Section 11.3.1: the CSV records paths and probabilities, not pixels — the 2812 Roboflow test
images are not in this repo (slice -1 is what recovers them). Until they exist, this script
degrades honestly: it probes `--images-root` for however many of the recorded paths actually
resolve, runs the comparison on that subset, and records the truth in
`health.input.evidence` rather than asserting the full 2812. With zero images found it emits
a `not_run` verdict and leaves the manifest default at `full_frame` (the shipped default per
section 1.1(c)), rather than guessing.

    python -m ML.export.probe_health_input --run ML/health_cnn --images-root ML/health_cnn/images
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

from ML.export.common import write_json

PROTOCOLS = ("full_frame", "segmentation_crop", "segmentation_masked")
DEFAULT_PROTOCOL = "full_frame"  # section 1.1(c): what the dataset paths indicate, pending this probe


def _load_predictions_csv(csv_path: Path) -> list[dict]:
    with csv_path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _resolve_image(sample_id: str, images_root: Path) -> Path | None:
    """`sample_id` is `health::train|valid/<class>/<file>` — strip the `health::` prefix."""
    rel = sample_id.split("::", 1)[-1]
    candidate = images_root / rel
    return candidate if candidate.exists() else None


def _prob_columns(fieldnames: list[str]) -> list[str]:
    return [c for c in fieldnames if c.startswith("prob__")]


def _preprocess(image_path: Path, protocol: str, crop: int = 224):
    """Full-frame resize-shorter-side + center-crop; the other two protocols need a mask
    and are not exercisable without segmentation output, so they raise NotImplementedError
    until a fixture corpus with masks exists (tracked as slice -1 / gate work, not this probe).
    """
    import numpy as np
    from PIL import Image

    from ML.export.common import IMAGENET_MEAN, IMAGENET_STD, RESIZE_RATIO

    if protocol != "full_frame":
        raise NotImplementedError(
            f"protocol {protocol!r} requires a segmentation mask; no mask fixtures are "
            "available yet (section 11.3.1). Only full_frame can be probed until then."
        )

    img = Image.open(image_path).convert("RGB")
    short = round(crop * RESIZE_RATIO)
    w, h = img.size
    scale = short / min(w, h)
    img = img.resize((round(w * scale), round(h * scale)), Image.BILINEAR)
    w, h = img.size
    left, top = (w - crop) // 2, (h - crop) // 2
    img = img.crop((left, top, left + crop, top + crop))
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = (arr - np.array(IMAGENET_MEAN, dtype=np.float32)) / np.array(IMAGENET_STD, dtype=np.float32)
    return arr.transpose(2, 0, 1)[None, ...]  # NCHW


def probe(*, run_dir: Path, images_root: Path | None, out: Path) -> Path:
    import numpy as np
    import torch
    from timm import create_model

    checkpoint = run_dir / "best.pt"
    classes_path = run_dir / "classes.json"
    predictions_csv = run_dir / "test_predictions.csv"

    import json

    name_to_idx: dict[str, int] = json.loads(classes_path.read_text())
    rows = _load_predictions_csv(predictions_csv)
    prob_cols = _prob_columns(list(rows[0].keys())) if rows else []

    detail = {
        "recorded_test_rows": len(rows),
        "images_root": str(images_root) if images_root else None,
        "resolved": 0,
        "checked_protocols": [],
    }

    def _base(protocol: str, status: str, evidence: str) -> dict:
        return {
            "health": {
                "input": {
                    "protocol": protocol,
                    "supported": list(PROTOCOLS),
                    "bbox_padding_ratio": 0.06,
                    "background_fill": "imagenet_mean",
                    "on_segmentation_failure": "full_frame",
                    "evidence": evidence,
                    "probe_status": status,
                    "probe_detail": detail,
                }
            }
        }

    if images_root is None or not images_root.exists():
        detail["reason"] = "images_root not provided or does not exist"
        return write_json(
            out,
            _base(DEFAULT_PROTOCOL, "not_run", "not probed: images_root not provided or missing"),
        )

    resolved = [(r, _resolve_image(r["sample_id"], images_root)) for r in rows]
    found = [(r, p) for r, p in resolved if p is not None]
    detail["resolved"] = len(found)

    if not found:
        detail["reason"] = "0 of the recorded test images resolved under images_root"
        return write_json(
            out,
            _base(
                DEFAULT_PROTOCOL,
                "not_run",
                f"not probed: 0 of {len(rows)} recorded test images resolved under {images_root}",
            ),
        )

    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = create_model("ghostnetv3_100", pretrained=False, num_classes=len(name_to_idx)).eval()
    model.load_state_dict(ckpt["model_state"], strict=True)

    scores: dict[str, float] = {}
    for protocol in PROTOCOLS:
        try:
            diffs = []
            for row, img_path in found:
                x = torch.from_numpy(_preprocess(img_path, protocol))
                with torch.no_grad():
                    probs = torch.softmax(model(x), dim=1).numpy()[0]
                recorded = np.array([float(row[c]) for c in prob_cols], dtype=np.float32)
                diffs.append(float(np.max(np.abs(probs - recorded))))
            scores[protocol] = sum(diffs) / len(diffs)
            detail["checked_protocols"].append(
                {"protocol": protocol, "n": len(diffs), "mean_max_abs_diff": scores[protocol]}
            )
        except NotImplementedError as exc:
            detail["checked_protocols"].append({"protocol": protocol, "skipped": str(exc)})

    if not scores:
        detail["reason"] = "no protocol could be evaluated (no mask fixtures for the other two)"
        return write_json(
            out,
            _base(DEFAULT_PROTOCOL, "not_run", "not probed: no protocol could be evaluated"),
        )

    winner = min(scores, key=scores.get)
    status = "partial" if len(found) < len(rows) else "full"
    evidence = (
        f"reproduces ML/health_cnn/test_predictions.csv "
        f"({len(found)}/{len(rows)} samples, mean_max_abs_diff={scores[winner]:.2e})"
    )
    return write_json(out, _base(winner, status, evidence))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", type=Path, required=True, help="e.g. ML/health_cnn")
    ap.add_argument("--images-root", type=Path, default=None)
    ap.add_argument("--out", type=Path, default=Path("build/ml_export/health/input_protocol.json"))
    a = ap.parse_args()
    result = probe(run_dir=a.run, images_root=a.images_root, out=a.out)
    print(f"wrote {result}")


if __name__ == "__main__":
    main()
