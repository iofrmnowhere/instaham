"""Deterministic Chen-aligned 16-feature extraction for body masks.

The definitions are copied from the established CENTER-CHORD V2 experiment.

Important:
- camera height is NOT a model feature;
- `longest` and `shortest` are center-crossing mask chords;
- `body_curve` uses the mask skeleton;
- `outline_curve` uses uniformly resampled/smoothed external contour curvature.
"""

from __future__ import annotations

import cv2
import numpy as np
from skimage.morphology import skeletonize


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
