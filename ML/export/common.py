"""Shared helpers for the export scripts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

# Classifier preprocessing contract — must match the training notebooks and
# INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md section 5.1.
RESIZE_RATIO = 1.14            # resize shorter side to round(crop * 1.14)  -> 224 * 1.14 = 255
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

MANIFEST_SCHEMA_VERSION = 1

# The one true weight feature order (AGENTS.md rule 2). Never reorder.
BASELINE5 = ["RA", "LC", "BL", "BW", "E"]

# The chen16_noheight feature order — the shipped weight regressor as of the Chen16 swap.
# This is now the canonical order AGENTS.md rule 2 refers to; BASELINE5 is kept only for
# the rollback export path. Never reorder either list.
CHEN16_NOHEIGHT = [
    "mask_area", "convex_hull_area", "difference", "dif_mask", "body_curve", "perimeter",
    "outline_curve", "longest", "shortest",
    "Hu_1", "Hu_2", "Hu_3", "Hu_4", "Hu_5", "Hu_6", "Hu_7",
]

FEATURE_FAMILIES = {
    "baseline5": BASELINE5,
    "chen16_noheight": CHEN16_NOHEIGHT,
}


def sha256_file(path: str | Path) -> str:
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: str | Path, data: Any) -> Path:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return p


def read_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def classifier_preprocessing(crop: int) -> dict[str, Any]:
    return {
        "exif": "expect_normalized",
        "resize_shorter_side": round(crop * RESIZE_RATIO),
        "center_crop": crop,
        "scale": 1.0 / 255.0,
        "mean": IMAGENET_MEAN,
        "std": IMAGENET_STD,
        "interpolation": "bilinear",
    }


def model_input_block(name: str, size: list[int], channels: str = "rgb") -> dict[str, Any]:
    return {"name": name, "layout": "NCHW", "size": size, "channels": channels}
