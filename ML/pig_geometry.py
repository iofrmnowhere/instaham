"""ML/pig_geometry.py -- geometry helpers ported to C++ (ML_implementation_plan.md,
revision 5, section 5). NOT shipped in the app; this is the reference the C++ unit
geometry/pig_geometry.cpp (section 5.6) is gated against (gate B), and it is what
gate C pins the pig_cutter.py copy of the five shared primitives (section 3.3) against.

Consolidated from ML/mask_features.py, ML/extended_mask_features.py, and the
mask-math functions of ML/yolo_inference.py (predict_largest_mask itself stayed
behind -- it loads and runs a model, so it belongs to ML/parity/reference_yolo.py /
C++ models/segmenter, never to a geometry helper file).

Section markers below match ML_implementation_plan.md section 5.6 and must be
mirrored 1:1 by geometry/pig_geometry.cpp when the C++ port happens.
"""

from __future__ import annotations

import cv2
import numpy as np
from skimage.morphology import skeletonize  # chen16 only (section 5.4) -- not used
                                             # by the shipped baseline5 weight pipeline


# ===== [1] mask cleanup + dorsal core (from ML/mask_features.py) =====



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


def _odd_window(value: int, minimum: int = 5) -> int:
    value = max(minimum, int(value))
    return value if value % 2 == 1 else value + 1


def _rolling_median(values: np.ndarray, window: int) -> np.ndarray:
    """Small dependency-free 1-D rolling median used for torso-envelope smoothing."""
    values = np.asarray(values, dtype=np.float32)
    if len(values) == 0:
        return values
    window = _odd_window(min(window, len(values) if len(values) % 2 else max(1, len(values) - 1)), minimum=1)
    radius = window // 2
    padded = np.pad(values, (radius, radius), mode='edge')
    return np.asarray(
        [np.median(padded[i:i + window]) for i in range(len(values))],
        dtype=np.float32,
    )


def ji_duan_adaptive_kernel_sizes(
    mask: np.ndarray,
    area_divisor: float = 1000.0,
    second_kernel_factor: float = 0.5,
    minimum_kernel: int = 3,
) -> tuple[int, int]:
    """Return the two adaptive opening kernel widths used by the Ji/Duan-style method.

    Ji et al. (2025) state that appendages are removed with continuous morphological
    opening using an adaptive kernel and cite Duan et al. (2023). Duan et al. specify the
    first kernel size as 1/1000 of the target-mask area, followed by a second opening with
    a kernel half the previous size. Neither paper specifies the structuring-element shape;
    this implementation uses an elliptical OpenCV element to reduce axis-aligned bias.
    """
    clean = _largest_component_fill(mask)
    area = float(np.count_nonzero(clean))
    if area <= 0:
        return minimum_kernel, minimum_kernel
    if area_divisor <= 0:
        raise ValueError('area_divisor must be > 0')
    if not (0 < second_kernel_factor <= 1):
        raise ValueError('second_kernel_factor must be in (0, 1].')

    first = _odd_window(int(round(area / float(area_divisor))), minimum=minimum_kernel)
    second = _odd_window(int(round(first * float(second_kernel_factor))), minimum=minimum_kernel)
    return first, second


def isolate_dorsal_core_ji_duan(
    mask: np.ndarray,
    area_divisor: float = 1000.0,
    second_kernel_factor: float = 0.5,
    minimum_kernel: int = 3,
    minimum_retained_fraction: float = 0.20,
) -> np.ndarray:
    """Ji/Duan-style adaptive morphological opening for appendage suppression.

    This is the published-method branch used for the Notebook 6/7 preprocessing
    experiment. The cleaned whole-pig mask is opened twice. The first kernel width is
    mask_area / area_divisor (default 1000), and the second is half the first by default.

    The cited papers do not provide source code or specify the structuring-element shape,
    so an ellipse is used here and recorded in provenance. If the operation collapses the
    mask to an implausibly small region, the cleaned mask is returned so the failure is
    visible in retained-fraction QC instead of emitting a malformed feature vector.
    """
    clean = clean_binary_mask(mask)
    original_area = float(np.count_nonzero(clean))
    if original_area <= 0:
        return clean

    first, second = ji_duan_adaptive_kernel_sizes(
        clean,
        area_divisor=area_divisor,
        second_kernel_factor=second_kernel_factor,
        minimum_kernel=minimum_kernel,
    )

    opened = clean.copy()
    for size in (first, second):
        # OpenCV requires the kernel to fit in practical image bounds. Clamping only
        # protects malformed/tiny masks; normal PIGRGB masks are far below this limit.
        max_size = max(1, min(opened.shape))
        size = min(size, max_size if max_size % 2 == 1 else max(1, max_size - 1))
        size = max(1, int(size))
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))
        opened = cv2.morphologyEx(opened, cv2.MORPH_OPEN, kernel)
        opened = _largest_component_fill(opened)
        if not np.any(opened):
            return clean

    retained = float(np.count_nonzero(opened)) / original_area
    if retained < float(minimum_retained_fraction):
        return clean
    return opened


def isolate_dorsal_core(
    mask: np.ndarray,
    width_threshold: float = 0.50,
    lateral_window_fraction: float = 0.12,
    lateral_cap_factor: float = 1.15,
    minimum_retained_fraction: float = 0.30,
) -> np.ndarray:
    """Isolate the dorsal torso using the INSTAHAM PCA/torso-envelope heuristic.

    The segmentation model supplies a whole-pig mask. Weight estimation must instead
    measure the dorsal torso/back, so this deterministic post-processing stage removes:

    * narrow longitudinal extremes (head and tail), and
    * localized lateral protrusions (legs).

    Procedure
    ---------
    1. Keep/close the largest connected pig region.
    2. Rotate the mask so its PCA major axis is horizontal.
    3. Trim the narrow longitudinal ends using a smoothed width profile.
    4. Build a smooth central-body envelope from local median half-widths and cap
       localized lateral protrusions outside that envelope.
    5. Rotate the torso mask back to the original image coordinates.

    This is the experimental INSTAHAM branch compared against
    ``isolate_dorsal_core_ji_duan`` in Notebooks 6 and 7. Because posture can vary, this
    function falls back conservatively to the cleaned mask if an implausibly small torso
    would otherwise be produced.
    """
    clean = clean_binary_mask(mask)
    points_yx = np.column_stack(np.nonzero(clean > 0))
    if len(points_yx) < 20:
        return clean

    points_xy = points_yx[:, ::-1].astype(np.float32)  # x, y
    center = points_xy.mean(axis=0)
    _, eigenvectors = cv2.PCACompute(points_xy, mean=np.empty((0)))
    if eigenvectors is None or len(eigenvectors) == 0:
        return clean

    axis = eigenvectors[0]
    angle = float(np.degrees(np.arctan2(axis[1], axis[0])))
    matrix = cv2.getRotationMatrix2D(tuple(center), angle, 1.0)
    rotated = cv2.warpAffine(
        clean,
        matrix,
        (clean.shape[1], clean.shape[0]),
        flags=cv2.INTER_NEAREST,
        borderValue=0,
    )

    foreground = rotated > 0
    raw_width = foreground.sum(axis=0).astype(np.float32)
    occupied_x = np.flatnonzero(raw_width > 0)
    if len(occupied_x) < 5:
        return clean

    # ---- A. Remove head and tail from the long axis -------------------------
    body_length = int(occupied_x[-1] - occupied_x[0] + 1)
    longitudinal_window = _odd_window(max(5, int(round(body_length * 0.03))))
    kernel = np.ones(longitudinal_window, dtype=np.float32) / float(longitudinal_window)
    # Localized legs can make a few columns much wider than the torso. Use a robust
    # upper-body width reference instead of the absolute maximum so those spikes do not
    # become the definition of body width.
    positive_widths = raw_width[occupied_x]
    reference_width = float(np.quantile(positive_widths, 0.75))
    if reference_width <= 0:
        return clean
    capped_width = np.minimum(raw_width, reference_width)
    smooth_width = np.convolve(capped_width, kernel, mode='same')

    strong = smooth_width >= float(width_threshold) * reference_width

    # Keep the largest contiguous strong-width run. This prevents a separate broad head
    # region from being joined to the torso merely because both exceed the threshold.
    strong_idx = np.flatnonzero(strong)
    if len(strong_idx) < 2:
        return clean
    splits = np.where(np.diff(strong_idx) > 1)[0] + 1
    runs = np.split(strong_idx, splits)
    core_run = max(runs, key=len)
    if len(core_run) < 2:
        return clean
    x_min, x_max = int(core_run[0]), int(core_run[-1])

    # Avoid an overly aggressive threshold on unusual postures. Expand a little around
    # the strong-width torso while still excluding the narrow extremes.
    pad = max(1, int(round((x_max - x_min + 1) * 0.04)))
    x_min = max(int(occupied_x[0]), x_min - pad)
    x_max = min(int(occupied_x[-1]), x_max + pad)
    if x_max <= x_min:
        return clean

    # ---- B. Remove legs using a smooth lateral torso envelope ----------------
    core_x = np.arange(x_min, x_max + 1)
    centers = np.full(len(core_x), np.nan, dtype=np.float32)
    half_widths = np.full(len(core_x), np.nan, dtype=np.float32)

    core_raw_widths = raw_width[core_x]
    normal_width_reference = float(np.quantile(core_raw_widths[core_raw_widths > 0], 0.65))
    # A leg commonly appears as a localized cross-section that is much wider than the
    # surrounding torso. Mark those columns as outliers and reconstruct their expected
    # torso envelope from neighboring non-outlier columns instead of measuring through
    # the appendage.
    lateral_outlier = core_raw_widths > (1.25 * max(normal_width_reference, 1.0))

    for i, x in enumerate(core_x):
        ys = np.flatnonzero(foreground[:, x])
        if len(ys) == 0 or lateral_outlier[i]:
            continue
        mid = float(np.median(ys))
        centers[i] = mid
        q10, q90 = np.quantile(ys.astype(np.float32), [0.10, 0.90])
        half_widths[i] = max(1.0, float(q90 - q10) / 2.0)

    valid = np.isfinite(centers) & np.isfinite(half_widths)
    if valid.sum() < 5:
        return clean

    # Fill rare empty columns by interpolation before smoothing.
    idx = np.arange(len(core_x), dtype=np.float32)
    centers = np.interp(idx, idx[valid], centers[valid]).astype(np.float32)
    half_widths = np.interp(idx, idx[valid], half_widths[valid]).astype(np.float32)

    lateral_window = _odd_window(max(5, int(round(len(core_x) * lateral_window_fraction))))
    smooth_center = _rolling_median(centers, lateral_window)
    smooth_half = _rolling_median(half_widths, lateral_window)

    # q10-q90 describes 80% of a clean torso slice. Expand back toward the full torso
    # width, then allow a modest margin. Localized leg spikes remain outside this cap.
    allowed_half = np.maximum(2.0, smooth_half * (1.0 / 0.80) * float(lateral_cap_factor))

    torso_rotated = np.zeros_like(rotated)
    height = rotated.shape[0]
    for i, x in enumerate(core_x):
        c = float(smooth_center[i])
        h = float(allowed_half[i])
        y0 = max(0, int(np.floor(c - h)))
        y1 = min(height - 1, int(np.ceil(c + h)))
        column = foreground[y0:y1 + 1, x]
        if column.any():
            torso_rotated[y0:y1 + 1, x][column] = 255

    # Keep a connected torso region and close only tiny holes/gaps introduced by the
    # geometric clipping. Do not use a large opening/closing kernel that could re-grow
    # appendages.
    contours, _ = cv2.findContours(torso_rotated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return clean
    largest = max(contours, key=cv2.contourArea)
    connected = np.zeros_like(torso_rotated)
    cv2.drawContours(connected, [largest], -1, 255, thickness=cv2.FILLED)

    original_area = float(np.count_nonzero(clean))
    torso_area = float(np.count_nonzero(connected))
    if original_area <= 0 or torso_area / original_area < float(minimum_retained_fraction):
        # Conservative failure mode: do not emit a tiny malformed mask.
        return clean

    inverse = cv2.invertAffineTransform(matrix)
    restored = cv2.warpAffine(
        connected,
        inverse,
        (clean.shape[1], clean.shape[0]),
        flags=cv2.INTER_NEAREST,
        borderValue=0,
    )

    # Final largest-component fill without calling clean_binary_mask(), because its
    # morphology step is intentionally for raw masks and could slightly re-expand the
    # torso boundary after appendage removal.
    final = _largest_component_fill(restored)
    return final if np.any(final) else clean


def extract_five_features(
    mask: np.ndarray,
    linear_scale: float = 1.0,
    preserve_processed_mask: bool = False,
) -> dict[str, float] | None:
    """Extract RA, LC, BL, BW and E from a binary dorsal mask.

    ``preserve_processed_mask=True`` is used after appendage removal so feature extraction
    does not apply the small closing operation again and accidentally alter the exact mask
    being compared in the preprocessing experiment.
    """
    clean = _largest_component_fill(mask) if preserve_processed_mask else clean_binary_mask(mask)
    contour = largest_contour(clean)
    if contour is None or len(contour) < 5:
        return None
    height, width = clean.shape
    area_pixels = float(np.count_nonzero(clean))
    ra = area_pixels / float(height * width)
    perimeter = float(cv2.arcLength(contour, True)) * linear_scale
    rect = cv2.minAreaRect(contour)
    side_a, side_b = rect[1]
    bl = float(max(side_a, side_b)) * linear_scale
    bw = float(min(side_a, side_b)) * linear_scale
    ellipse = cv2.fitEllipse(contour)
    minor, major = sorted(ellipse[1])
    eccentricity = float(np.sqrt(max(0.0, 1.0 - (minor / major) ** 2))) if major > 0 else 0.0
    return {
        'RA': ra,
        'LC': perimeter,
        'BL': bl,
        'BW': bw,
        'E': eccentricity,
        'area_pixels': area_pixels,
        'area_scaled': area_pixels * (linear_scale ** 2),
    }


# ===== [2] unletterbox (mask math lifted from ML/yolo_inference.py) =====

MASK_COORDINATE_PROTOCOL = "original_coordinate_polygon_v1"



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


# ===== [3] chen16 extended features (from ML/extended_mask_features.py) =====
# Optional -- only relevant if a chen16 model is ever selected (section 5.1).
# Not part of the shipped baseline5 [RA, LC, BL, BW, E] pipeline.



BASELINE5 = ["RA", "LC", "BL", "BW", "E"]

CHEN16_NOHEIGHT = [
    "mask_area",
    "convex_hull_area",
    "difference",
    "dif_mask",
    "body_curve",
    "perimeter",
    "outline_curve",
    "longest",
    "shortest",
    "Hu_1",
    "Hu_2",
    "Hu_3",
    "Hu_4",
    "Hu_5",
    "Hu_6",
    "Hu_7",
]

EXTENDED_FEATURE_PROTOCOL_VERSION = "chen16_noheight_centerchord_v2"

def _largest_external_contour(mask):
    binary = ((np.asarray(mask) > 0).astype(np.uint8) * 255)
    contours, _ = cv2.findContours(
        binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
    )
    if not contours:
        return binary, None
    contour = max(contours, key=cv2.contourArea)
    if contour is None or len(contour) < 5 or cv2.contourArea(contour) <= 0:
        return binary, None
    return binary, contour


def _center_crossing_axes(binary, contour, angle_step_deg=1.0):
    """Return longest/shortest mask chords through the mask geometric center.

    Chen et al. (Animals 2025, 15(20):2975) define the major/minor axes as
    the longest and shortest lines passing through the geometric center while
    remaining within the mask. The paper does not specify the numerical search
    procedure, so this implementation samples line orientation every 1 degree
    and computes exact intersections with the external contour segments.
    """
    mask_u8 = (np.asarray(binary) > 0).astype(np.uint8)
    moments = cv2.moments(mask_u8, binaryImage=True)
    if moments['m00'] <= 0:
        return np.nan, np.nan

    center = np.array([
        moments['m10'] / moments['m00'],
        moments['m01'] / moments['m00'],
    ], dtype=np.float64)

    # Very concave masks can theoretically have their centroid outside the
    # foreground. If that happens, use the nearest foreground pixel so the
    # center-crossing chord remains defined rather than silently reverting to
    # a different feature concept.
    if cv2.pointPolygonTest(
        contour,
        (float(center[0]), float(center[1])),
        False,
    ) < 0:
        ys, xs = np.nonzero(mask_u8)
        if len(xs) == 0:
            return np.nan, np.nan
        d2 = (xs - center[0]) ** 2 + (ys - center[1]) ** 2
        idx = int(np.argmin(d2))
        center = np.array([float(xs[idx]), float(ys[idx])], dtype=np.float64)

    pts = contour[:, 0, :].astype(np.float64)
    if len(pts) < 3:
        return np.nan, np.nan

    p0 = pts
    p1 = np.roll(pts, -1, axis=0)
    edge = p1 - p0
    q = p0 - center

    angles = np.deg2rad(
        np.arange(0.0, 180.0, float(angle_step_deg), dtype=np.float64)
    )
    dx = np.cos(angles)[:, None]
    dy = np.sin(angles)[:, None]

    ex = edge[:, 0][None, :]
    ey = edge[:, 1][None, :]
    qx = q[:, 0][None, :]
    qy = q[:, 1][None, :]

    # Solve center + t*d = p0 + s*edge for every sampled orientation and
    # every contour segment. t is signed distance along the center line.
    den = dx * ey - dy * ex
    numerator_t = q[:, 0] * edge[:, 1] - q[:, 1] * edge[:, 0]

    with np.errstate(divide='ignore', invalid='ignore'):
        t = numerator_t[None, :] / den
        s_param = (qx * dy - qy * dx) / den

    valid = (
        (np.abs(den) > 1e-12)
        & np.isfinite(t)
        & np.isfinite(s_param)
        & (s_param >= -1e-9)
        & (s_param <= 1.0 + 1e-9)
    )

    # For a line through an interior center, the chord containing the center
    # is bounded by the closest contour intersection on each side.
    neg = np.max(
        np.where(valid & (t <= 1e-9), t, -np.inf),
        axis=1,
    )
    pos = np.min(
        np.where(valid & (t >= -1e-9), t, np.inf),
        axis=1,
    )
    chords = pos - neg
    usable = np.isfinite(chords) & (chords > 0)
    if not np.any(usable):
        return np.nan, np.nan

    chord_lengths = chords[usable]
    longest = float(np.max(chord_lengths))
    shortest = float(np.min(chord_lengths))
    if shortest > longest:
        longest, shortest = shortest, longest
    return longest, shortest


def _skeleton_body_curve(binary):
    ys, xs = np.nonzero(binary)
    if len(xs) < 5:
        return np.nan

    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    crop = (binary[y0:y1 + 1, x0:x1 + 1] > 0)

    skel = skeletonize(crop)
    sy, sx = np.nonzero(skel)
    if len(sx) < 3:
        return np.nan

    # A skeleton endpoint has exactly one 8-connected neighbor.
    sk_u8 = skel.astype(np.uint8)
    neighborhood_count = cv2.filter2D(
        sk_u8,
        ddepth=cv2.CV_16U,
        kernel=np.ones((3, 3), dtype=np.uint8),
        borderType=cv2.BORDER_CONSTANT,
    )
    endpoint_yx = np.argwhere(skel & (neighborhood_count == 2))

    skeleton_xy = np.column_stack([sx, sy]).astype(np.float64)
    centroid = skeleton_xy.mean(axis=0)

    if len(endpoint_yx) >= 2:
        endpoints_xy = endpoint_yx[:, [1, 0]].astype(np.float64)

        # Approximate the diameter among endpoints with two farthest-point passes.
        d0 = np.linalg.norm(endpoints_xy - endpoints_xy[0], axis=1)
        p1 = endpoints_xy[int(np.argmax(d0))]
        d1 = np.linalg.norm(endpoints_xy - p1, axis=1)
        p2 = endpoints_xy[int(np.argmax(d1))]
    else:
        # Fallback: use the two extreme skeleton points along its first PCA axis.
        centered = skeleton_xy - centroid
        cov = np.cov(centered, rowvar=False)
        values, vectors = np.linalg.eigh(cov)
        axis = vectors[:, int(np.argmax(values))]
        projection = centered @ axis
        p1 = skeleton_xy[int(np.argmin(projection))]
        p2 = skeleton_xy[int(np.argmax(projection))]

    v1 = p1 - centroid
    v2 = p2 - centroid
    n1 = float(np.linalg.norm(v1))
    n2 = float(np.linalg.norm(v2))
    if n1 <= 1e-9 or n2 <= 1e-9:
        return np.nan

    cosine = float(np.clip(np.dot(v1, v2) / (n1 * n2), -1.0, 1.0))
    return float(np.degrees(np.arccos(cosine)))


def _resample_closed_contour(points_xy, n_points=256):
    pts = np.asarray(points_xy, dtype=np.float64)
    if len(pts) < 4:
        return None

    closed = np.vstack([pts, pts[0]])
    seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    cumulative = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(cumulative[-1])
    if not np.isfinite(total) or total <= 1e-9:
        return None

    targets = np.linspace(0.0, total, int(n_points), endpoint=False)
    out = np.empty((len(targets), 2), dtype=np.float64)

    j = 0
    for i, target in enumerate(targets):
        while j + 1 < len(cumulative) and cumulative[j + 1] <= target:
            j += 1
        j = min(j, len(pts) - 1)
        denom = seg[j]
        t = 0.0 if denom <= 1e-12 else (target - cumulative[j]) / denom
        out[i] = closed[j] * (1.0 - t) + closed[j + 1] * t
    return out


def _maximum_outline_curvature(contour):
    pts = contour[:, 0, :].astype(np.float64)
    sampled = _resample_closed_contour(pts, n_points=256)
    if sampled is None:
        return np.nan

    # Circular moving-average smoothing reduces pixel stair-step spikes.
    smoothed = np.zeros_like(sampled)
    radius = 3
    for offset in range(-radius, radius + 1):
        smoothed += np.roll(sampled, offset, axis=0)
    smoothed /= float(2 * radius + 1)

    prev = np.roll(smoothed, 1, axis=0)
    nxt = np.roll(smoothed, -1, axis=0)

    d1 = (nxt - prev) / 2.0
    d2 = nxt - 2.0 * smoothed + prev

    numerator = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0])
    denominator = np.power(
        np.square(d1[:, 0]) + np.square(d1[:, 1]),
        1.5,
    )
    curvature = numerator / np.maximum(denominator, 1e-9)
    curvature = curvature[np.isfinite(curvature)]
    return float(curvature.max()) if len(curvature) else np.nan


def extract_extended_shape_features(mask):
    binary, contour = _largest_external_contour(mask)
    if contour is None:
        return None

    mask_area = float(np.count_nonzero(binary))
    if mask_area <= 0:
        return None

    hull = cv2.convexHull(contour)
    hull_mask = np.zeros_like(binary)
    cv2.fillConvexPoly(hull_mask, hull[:, 0, :], 255)
    convex_hull_area = float(np.count_nonzero(hull_mask))

    difference = float(max(convex_hull_area - mask_area, 0.0))
    dif_mask = float(difference / mask_area)

    perimeter = float(cv2.arcLength(contour, True))
    longest, shortest = _center_crossing_axes(binary, contour, angle_step_deg=1.0)
    body_curve = _skeleton_body_curve(binary)
    outline_curve = _maximum_outline_curvature(contour)

    hu = cv2.HuMoments(
        cv2.moments(binary, binaryImage=True)
    ).flatten().astype(np.float64)

    values = {
        'mask_area': mask_area,
        'convex_hull_area': convex_hull_area,
        'difference': difference,
        'dif_mask': dif_mask,
        'body_curve': body_curve,
        'perimeter': perimeter,
        'outline_curve': outline_curve,
        'longest': float(longest),
        'shortest': float(shortest),
        **{f'Hu_{i + 1}': float(hu[i]) for i in range(7)},
    }

    if not all(np.isfinite(v) for v in values.values()):
        return None
    if values['longest'] <= 0 or values['shortest'] <= 0:
        return None
    return values


def extract_chen16_features(mask):
    """Public name used by the new Notebook 6."""
    return extract_extended_shape_features(mask)
