"""ML/pipeline/construction.py -- (2) construct the pig mask.

Consolidated from the mask-building half of ML/yolo_inference.py's
predict_largest_mask, plus ML/mask_features.py's clean_binary_mask /
_largest_component_fill / largest_contour (ML_implementation_plan.md revision 7,
section 5.2/5.4). Ported to C++ as stages/construction.cpp; gate B measures the two
against each other file to file.

predict_largest_mask itself split across a runtime boundary that does not exist
here (revision 5's C++/Python split, section 5.4 of the current plan): the
model-running half is ML.pipeline.segmentation.run_segmentation, this file's
construct_pig_mask() is the mask-building tail. Both are used together by
ML/weight_runtime.py and by gate A; construct_pig_mask(run_segmentation(...)) must
reproduce predict_largest_mask(...) at IoU >= 0.999 (gate A, section 10).

clean_binary_mask / _largest_component_fill / largest_contour also serve two other
callers that are not part of constructing the mask itself: ML.pipeline.cutter (the
head/neck removal internally re-cleans between steps) and
ML.pipeline.feature_calculation (extract_five_features cleans before measuring).
Both import them from here rather than carrying their own copies, because nothing
in this refactor requires either to ship standalone (section 5.2, contrast with the
old Chaquopy-purity requirement this superseded).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import cv2
import numpy as np

if TYPE_CHECKING:
    from ML.pipeline.segmentation import SegmentationOutput


# Used by downstream notebooks to verify that the project is using the
# coordinate-safe implementation rather than the old direct-resize version.
MASK_COORDINATE_PROTOCOL = "original_coordinate_polygon_v1"



def _largest_component_fill(mask: np.ndarray) -> np.ndarray:
    """Return a filled binary mask containing only the largest external component."""
    binary = (mask > 0).astype(np.uint8) * 255
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return binary
    largest = max(contours, key=cv2.contourArea)
    clean = np.zeros_like(binary)
    cv2.drawContours(clean, [largest], -1, 255, thickness=cv2.FILLED)
    return clean

def clean_binary_mask(mask: np.ndarray) -> np.ndarray:
    """Return a single connected, hole-reduced binary pig mask."""
    clean = _largest_component_fill(mask)
    if not np.any(clean):
        return clean

    # Small closing operation: connect tiny gaps / fill small boundary defects without
    # attempting to perform the anatomical head-tail-leg removal itself.
    short_side = max(3, int(round(min(clean.shape) * 0.006)))
    if short_side % 2 == 0:
        short_side += 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (short_side, short_side))
    clean = cv2.morphologyEx(clean, cv2.MORPH_CLOSE, kernel)
    return _largest_component_fill(clean)

def largest_contour(mask: np.ndarray) -> np.ndarray | None:
    contours, _ = cv2.findContours(
        (mask > 0).astype(np.uint8) * 255,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_NONE,
    )
    return max(contours, key=cv2.contourArea) if contours else None


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


def construct_pig_mask(seg_output: "SegmentationOutput | None") -> np.ndarray | None:
    """(2) CONSTRUCTION -- turn one segmentation.run_segmentation() output into a
    pig mask in ORIGINAL IMAGE coordinates.

    This is predict_largest_mask's mask-building tail (ML/yolo_inference.py,
    pre-refactor), split out so stage 1 (model inference) and stage 2 (mask
    geometry) are separate files per ML/refactor_plan.md. No cleanup is applied
    here -- this reproduces predict_largest_mask's original raw output exactly, so
    gate A can compare byte for byte. Callers that need a cleaned mask call
    clean_binary_mask() explicitly (ML.pipeline.cutter and
    ML.pipeline.feature_calculation both do).

    Coordinate policy
    -----------------
    Primary:   rasterize result.masks.xy, already in original-image coordinates.
    Fallback:  if the polygon is unavailable, remove letterbox padding from
               result.masks.data before resizing to the original image
               (_unletterbox_native_mask).
    """
    if seg_output is None:
        return None

    result = seg_output.result
    index = seg_output.index

    mask = _polygon_mask_in_original_coordinates(result, index)
    if mask is None:
        native = result.masks.data[index].detach().cpu().numpy()
        native = (native > 0.5).astype(np.uint8) * 255
        mask = _unletterbox_native_mask(native, seg_output.orig_shape)
    return mask
