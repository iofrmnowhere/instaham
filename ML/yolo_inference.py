from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np


# Used by downstream notebooks to verify that the project is using the
# coordinate-safe implementation rather than the old direct-resize version.
MASK_COORDINATE_PROTOCOL = "original_coordinate_polygon_v1"


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


def _polygon_mask_in_original_coordinates(
    result,
    index: int,
) -> np.ndarray | None:
    """
    Rasterize Ultralytics' original-coordinate polygon for one mask.

    result.masks.xy has already been mapped back from the inference/
    letterbox space into the original image coordinate system. Using it
    avoids stretching the letterbox padding when the original image and
    masks.data have different aspect ratios.
    """
    if result.orig_shape is None:
        return None

    original_h, original_w = map(
        int,
        result.orig_shape,
    )

    polygons = result.masks.xy

    if polygons is None or index >= len(polygons):
        return None

    polygon = np.asarray(
        polygons[index],
        dtype=np.float32,
    )

    if (
        polygon.ndim != 2
        or polygon.shape[0] < 3
        or polygon.shape[1] != 2
    ):
        return None

    polygon = polygon.copy()

    polygon[:, 0] = np.clip(
        polygon[:, 0],
        0,
        max(0, original_w - 1),
    )
    polygon[:, 1] = np.clip(
        polygon[:, 1],
        0,
        max(0, original_h - 1),
    )

    canvas = np.zeros(
        (original_h, original_w),
        dtype=np.uint8,
    )

    cv2.fillPoly(
        canvas,
        [
            np.rint(polygon)
            .astype(np.int32)
        ],
        255,
    )

    return canvas


def _unletterbox_native_mask(
    native_mask: np.ndarray,
    original_shape: tuple[int, int],
) -> np.ndarray:
    """
    Fallback coordinate restoration for cases where masks.xy is unavailable.

    The old implementation directly resized the entire masks.data tensor to
    the original image. That also stretched the letterbox padding. Here the
    padded rows/columns are removed first, then only the unpadded mask is
    resized to the original image dimensions.
    """
    original_h, original_w = map(
        int,
        original_shape,
    )

    native = np.asarray(
        native_mask,
        dtype=np.uint8,
    )

    native_h, native_w = native.shape[:2]

    if (
        native_h == original_h
        and native_w == original_w
    ):
        return (
            (native > 0)
            .astype(np.uint8)
            * 255
        )

    gain = min(
        native_w / float(original_w),
        native_h / float(original_h),
    )

    scaled_w = original_w * gain
    scaled_h = original_h * gain

    pad_w = max(
        0.0,
        (native_w - scaled_w) / 2.0,
    )
    pad_h = max(
        0.0,
        (native_h - scaled_h) / 2.0,
    )

    # Match the asymmetric rounding convention commonly used by YOLO
    # letterboxing so a one-pixel odd padding amount is handled correctly.
    left = int(round(pad_w - 0.1))
    right = int(round(pad_w + 0.1))
    top = int(round(pad_h - 0.1))
    bottom = int(round(pad_h + 0.1))

    x0 = max(0, left)
    y0 = max(0, top)
    x1 = min(
        native_w,
        native_w - max(0, right),
    )
    y1 = min(
        native_h,
        native_h - max(0, bottom),
    )

    cropped = native[
        y0:y1,
        x0:x1,
    ]

    if cropped.size == 0:
        raise RuntimeError(
            "Mask unletterboxing produced an empty crop: "
            f"native={native_w}x{native_h}, "
            f"original={original_w}x{original_h}, "
            f"crop=({x0}, {y0})-({x1}, {y1})"
        )

    restored = cv2.resize(
        cropped,
        (original_w, original_h),
        interpolation=cv2.INTER_NEAREST,
    )

    return (
        (restored > 0)
        .astype(np.uint8)
        * 255
    )


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
