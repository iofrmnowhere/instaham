"""ML/pipeline/segmentation.py -- (1) run YOLO, pick the largest instance.

Consolidated from the model-running half of ML/yolo_inference.py's
predict_largest_mask (ML_implementation_plan.md revision 7, section 5.2/5.4).
Ported to C++ as stages/segmentation.cpp; gate B measures the two file to file.

The model itself is loaded by the caller (ML/weight_runtime.py is the reference
orchestrator) and passed in already constructed -- this file never touches
torch.load, ultralytics.YOLO(), or ML.compat.src_alias directly, so a checkpoint
swap never means editing this file.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


@dataclass
class SegmentationOutput:
    """The stage 1 -> stage 2 contract (section 5.4). Carries the ultralytics
    Results object and the selected instance index/confidence, plus the original
    image shape needed by construction's unletterbox fallback -- never
    recomputed on the stage-2 side (AGENTS.md rule 9)."""

    result: Any
    index: int
    confidence: float
    orig_shape: tuple[int, int]


def _largest_mask_index(result) -> int | None:
    """Return the largest predicted instance index in native mask space."""
    if result.masks is None or result.masks.data is None:
        return None

    data = result.masks.data.detach().cpu().numpy()

    if len(data) == 0:
        return None

    areas = (
        (data > 0.5)
        .reshape(len(data), -1)
        .sum(axis=1)
    )

    return int(np.argmax(areas))


def run_segmentation(
    model,
    image_path: str | Path,
    imgsz: int = 640,
    conf: float = 0.25,
    device: int | str = 'cpu',
) -> SegmentationOutput | None:
    """(1) SEGMENTATION -- run the model, select the largest instance.

    This is predict_largest_mask's model-running half (ML/yolo_inference.py,
    pre-refactor). Returns None exactly where the original returned
    (None, 0.0): no result, or no mask survives confidence filtering.
    """
    results = model.predict(
        source=str(image_path),
        imgsz=imgsz,
        conf=conf,
        verbose=False,
        device=device,
    )
    if not results:
        return None

    result = results[0]
    index = _largest_mask_index(result)
    if index is None:
        return None

    confidence = 0.0
    if (
        result.boxes is not None
        and result.boxes.conf is not None
        and index < len(result.boxes.conf)
    ):
        confidence = float(result.boxes.conf[index].detach().cpu().item())

    return SegmentationOutput(
        result=result,
        index=index,
        confidence=confidence,
        orig_shape=tuple(result.orig_shape),
    )
