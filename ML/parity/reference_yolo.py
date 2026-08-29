"""ML/parity/reference_yolo.py -- predict_largest_mask, lifted out of the old
ML/yolo_inference.py (ML_implementation_plan.md revision 5, section 5.1).

This is NOT a geometry helper: it loads and runs a model. In C++ that role belongs
to models/segmenter; in Python it lives here, alongside the other reference/parity
runners, rather than in ML/pig_geometry.py, which must stay pure array math with no
model loading (section 5.1's own rule, applied to itself).

The pure mask-math this file used to contain -- `_largest_mask_index`,
`_polygon_mask_in_original_coordinates`, `_unletterbox_native_mask`, and
`MASK_COORDINATE_PROTOCOL` -- moved to ML/pig_geometry.py and are re-exported here
for callers that used to import them from ML.yolo_inference (e.g. ML/weight_runtime.py).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

from ML.pig_geometry import (
    MASK_COORDINATE_PROTOCOL,
    _largest_mask_index,
    _polygon_mask_in_original_coordinates,
    _unletterbox_native_mask,
)

__all__ = ["MASK_COORDINATE_PROTOCOL", "predict_largest_mask"]


def predict_largest_mask(
    model,
    image_path: str | Path,
    imgsz: int = 640,
    conf: float = 0.25,
    device: int | str = 'cpu',
) -> tuple[np.ndarray | None, float]:
    """
    Predict the largest pig mask and return it in ORIGINAL IMAGE coordinates.

    Coordinate policy
    -----------------
    Primary:
        Rasterize result.masks.xy because Ultralytics exposes those polygon
        coordinates in the original image coordinate system.

    Fallback:
        If the polygon is unavailable, explicitly remove letterbox padding
        from result.masks.data before resizing to the original image.

    This replaces the previous behavior that directly resized the full
    padded masks.data tensor and could shift/stretch the mask overlay.
    """
    results = model.predict(
        source=str(image_path),
        imgsz=imgsz,
        conf=conf,
        verbose=False,
        device=device,
    )

    if not results:
        return None, 0.0

    result = results[0]

    index = _largest_mask_index(
        result
    )

    if index is None:
        return None, 0.0

    mask = _polygon_mask_in_original_coordinates(
        result,
        index,
    )

    if mask is None:
        native = (
            result.masks.data[index]
            .detach()
            .cpu()
            .numpy()
        )

        native = (
            (native > 0.5)
            .astype(np.uint8)
            * 255
        )

        mask = _unletterbox_native_mask(
            native,
            tuple(result.orig_shape),
        )

    confidence = 0.0

    if (
        result.boxes is not None
        and result.boxes.conf is not None
        and index < len(result.boxes.conf)
    ):
        confidence = float(
            result.boxes.conf[index]
            .detach()
            .cpu()
            .item()
        )

    return mask, confidence
