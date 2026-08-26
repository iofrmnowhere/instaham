from __future__ import annotations

import cv2
import numpy as np


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
