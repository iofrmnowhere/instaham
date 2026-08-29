"""ML/pig_cutter.py -- the head/neck cut-off. NOT PORTED TO C++.

Consolidated from the original ML/body_mask.py (ML_implementation_plan.md, revision 6,
section 5). This is the one component the plan deliberately keeps as Python, because it
is the sole home of scipy.gaussian_filter1d, scipy.find_peaks, and skimage.skeletonize,
and because it is by far the largest body of code in the programme. Spike S3
(section 5.2(c)) measured it: 9,911 of 10,855 lines are reachable from
isolate_body_only_mask(), and 1,985 of those live lines call scipy/skimage directly.
That measurement is why it is not ported.

WHERE THIS RUNS IS NOT YET DECIDED (section 3.5). Not porting it and shipping it
on-device are separate choices with very different costs. The open options are: (A)
on-device Python via Chaquopy, Android only; (B) a server-side cutter, both platforms;
(C) defer the weight branch further. The decision is taken after slice 4. Until then the
weight branch reports "unavailable" on every platform and this file is used only by the
Python reference pipeline and the parity gates.

Contract (section 3.3): a caller passes the raw segmentation mask plus an optional
ji_config dict into isolate_body_only_mask(), and the weight path returns the five
features (RA, LC, BL, BW, E) plus QC fields (pair_valid, head_removal_applied). The
boundary is drawn at the segmentation mask, so no geometry is shared across a runtime
edge. No model loading, no file IO, no manifest access -- pure mask-to-mask.

Two structural fixes from the original are folded in here (not a behaviour change --
see ML_implementation_plan.md section 5.2(b)):
  - `choose_body_circle_pair` and `isolate_body_only_mask` were each defined twice in
    the original module, with the second definition silently overriding the first via
    Python's late-binding of module-level names. That is resolved statically here: the
    original (superseded) definitions keep their alias names
    (`_choose_body_circle_pair_fixed06q`, `_isolate_body_only_mask_fixed06q`) and the
    override keeps the public name. No other change.
  - The five functions this file used to import from ML/mask_features.py
    (clean_binary_mask, _largest_component_fill, _odd_window, _rolling_median,
    ji_duan_adaptive_kernel_sizes, isolate_dorsal_core_ji_duan) are now inlined
    verbatim, because this file must ship with zero project-local imports.

Original docstring, preserved:

Production body-mask preprocessing derived from the finalized fixed 06Q notebook.

Protocol:
    YOLO whole-pig mask
      -> Ji/Duan adaptive opening
      -> conservative residual lateral-appendage cleanup
      -> fixed 06Q neck refinement
      -> neck-plane body-circle candidate
      -> locked two-circle pair validation
      -> fixed 06Q outward circle closure

This module preserves the finalized 06Q geometry and changes ONLY pair fallback policy:
    - gap is measured along the curved medial centerline outside both circles
    - Tier 1: radius similarity >= 0.80 AND curved gap >= 1.00R
    - Tier 2: radius similarity >= 0.70 AND curved gap >= 1.00R
    - Tier 3: radius similarity >= 0.80 with curved-gap relaxation
    - Tier 4: radius similarity >= 0.70 with curved-gap relaxation
    - normalized centerline separation >= 0.30 remains hard
    - existing shaft checks remain hard
    - pair same-plateau bonus remains 0
    - fixed 06Q neck/circle/closure geometry is unchanged

The tuning notebook remains the visual reference. This file removes notebook-only
sampling/plotting code so Notebook 6, deployment code, and tests can reuse one
implementation.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

import math

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
from skimage.morphology import skeletonize

# ===== [0] shared primitives, inlined from ML/mask_features.py =====
# pig_cutter.py must stand alone -- it must not import any
# other project file (section 3.1 / 3.3 of ML_implementation_plan.md). These six
# functions are therefore duplicated here verbatim. ML/pig_geometry.py has its own
# copies for the C++ port; the two are never used in the same computation
# (revision 6's one-hop boundary), so they are not required to agree and nothing
# gates them against each other.
# fmt: off

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
# fmt: on
# ===== end shared primitives =====




BODY_MASK_PROTOCOL_VERSION = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"


# ========================
# FIXED 06Q CONFIGURATION
# ========================

PROFILE_POINTS = 180
RADIUS_SMOOTH_SIGMA = 2.2
MIN_SKELETON_BRANCH_LENGTH_PX = 7
ENABLE_RESIDUAL_APPENDAGE_CLEANUP = True
RESIDUAL_BODY_DISK_RADIUS_FACTOR = 1.08
RESIDUAL_END_PROTECTION_FRACTION = 0.12
RESIDUAL_MIN_COMPONENT_AREA_FRACTION = 0.0010
RESIDUAL_MAX_COMPONENT_AREA_FRACTION = 0.10
RESIDUAL_MAX_TOTAL_REMOVAL_FRACTION = 0.12
RESIDUAL_MIN_BRANCH_PIXELS = 7
RESIDUAL_MIN_LATERALNESS = 0.72
RESIDUAL_MIN_PERP_OFFSET_RADIUS_RATIO = 0.22
RESIDUAL_POST_CLOSE_KERNEL = 3
MIN_PEAK_DISTANCE_FRACTION = 0.13
PEAK_PROMINENCE_RATIO = 0.045
MIN_BODY_LOBE_RADIUS_RATIO = 0.70
ENDPOINT_PEAK_WINDOW_FRACTION = 0.045
ENABLE_BROAD_LOBE_REGIONS = True
BROAD_REGION_MIN_CENTER_RADIUS_RATIO = 0.70
BROAD_REGION_HIGH_RADIUS_FRACTION = 0.80
BROAD_REGION_MIN_LENGTH_RADIUS_RATIO = 0.75
BROAD_REGION_BOUNDARY_DROP_FRACTION = 0.70
BROAD_REGION_BOUNDARY_SEARCH_RADIUS_RATIO = 0.70
BROAD_REGION_SCAN_STRIDE = 2
LONG_PLATEAU_MIN_LENGTH_RADIUS_RATIO = 2.25
PLATEAU_CAP_INWARD_RADIUS_RATIO = 0.60
PLATEAU_CAP_LOCAL_SEARCH_RADIUS_RATIO = 0.22
PLATEAU_CAP_MIN_INTERNAL_SEPARATION_RADIUS_RATIO = 1.00
MERGE_CANDIDATE_ARC_FRACTION = 0.075
ENABLE_CROSS_SECTION_CAP_CANDIDATES = True
CROSS_SECTION_RAY_STEP_PX = 1.0
CROSS_SECTION_MAX_TRACE_RADIUS_FACTOR = 2.60
CROSS_SECTION_SMOOTH_SIGMA = 2.0
CROSS_SECTION_TERMINAL_SEARCH_FRACTION = 0.48
CROSS_SECTION_ENDPOINT_PROTECTION_FRACTION = 0.035
CROSS_SECTION_MIN_BODY_RADIUS_RATIO = 0.64
CROSS_SECTION_LOOKAHEAD_RADIUS_RATIO = 1.10
CROSS_SECTION_MIN_LOOKAHEAD_DISTANCE_RADIUS_RATIO = 0.24
CROSS_SECTION_MIN_ONE_SIDE_DROP_RATIO = 0.16
CROSS_SECTION_MIN_TOTAL_WIDTH_DROP_RATIO = 0.07
CROSS_SECTION_MIN_SUSTAIN_POINTS = 3
NECK_REFINE_MAX_DISTANCE_RADIUS_RATIO = 1.45
NECK_REFINE_BODY_BASELINE_RADIUS_RATIO = 0.65
NECK_REFINE_MIN_PROMINENCE_RATIO = 0.055
NECK_REFINE_MIN_SIDE_CONSTRICTION_RATIO = 0.10
NECK_REFINE_MIN_WIDTH_CONSTRICTION_RATIO = 0.045
NECK_REFINE_REEXPANSION_BONUS_WEIGHT = 0.22
NECK_REFINE_FALLBACK_DISTANCE_PENALTY = 0.12
CROSS_SECTION_MAX_PER_SIDE = 1
CROSS_SECTION_DUP_ARC_RADIUS_RATIO = 0.20
CROSS_SECTION_DUP_MIN_RADIUS_SIMILARITY = 0.90
CROSS_SECTION_CAP_BULGE_WIDTH_RATIO = 0.55
NECK_ANCHOR_MIN_INWARD_DISTANCE_RADIUS_RATIO = 0.35
NECK_ANCHOR_MAX_INWARD_DISTANCE_RADIUS_RATIO = 1.80
NECK_ANCHOR_MIN_RADIUS_RATIO_TO_MAX = 0.68
NECK_ANCHOR_MAX_TANGENCY_ERROR_RATIO = 0.48
NECK_ANCHOR_TANGENCY_WEIGHT = 0.72
NECK_ANCHOR_RADIUS_WEIGHT = 0.20
NECK_ANCHOR_LOCAL_WIDTH_WEIGHT = 0.08
NECK_ANCHOR_LOCAL_WINDOW_RADIUS_RATIO = 0.45
NECK_ANCHOR_DUP_ARC_RADIUS_RATIO = 0.20
NECK_ANCHOR_DUP_MIN_RADIUS_SIMILARITY = 0.90
PAIR_NECK_ANCHOR_BONUS_WEIGHT = 0.22
ENABLE_LOCAL_CANDIDATE_CLASSIFICATION = True
NECK_CONTEXT_INNER_RADIUS_RATIO = 0.30
NECK_CONTEXT_OUTER_RADIUS_RATIO = 1.00
NECK_CONTEXT_PERCENTILE = 80
NECK_SUSPECT_DROP_RATIO = 0.10
TERMINAL_EXTRA_ZONE_FRACTION = 0.25
TERMINAL_EXTRA_MIN_CANDIDATES = 3
TERMINAL_EXTRA_MIN_PAIR_ARC_RADIUS_RATIO = 0.55
TERMINAL_VALLEY_END_MARGIN_RADIUS_RATIO = 0.15
TERMINAL_EXTRA_MIN_RECESS_DROP_RATIO = 0.10
TERMINAL_EXTRA_MIN_REEXPANSION_RATIO = 0.10
TERMINAL_EXTRA_SUSPECT_SCORE = 0.50
TERMINAL_EXTRA_HIGH_CONFIDENCE_SCORE = 0.80
PAIR_NECK_PENALTY_WEIGHT = 0.45
PAIR_TERMINAL_EXTRA_PENALTY_WEIGHT = 0.90
MIN_PAIR_RADIUS_SIMILARITY = 0.80
CIRCLE_EDGE_GAP_RADIUS_FRACTION = 1.00
MIN_PAIR_ARC_SEPARATION_FRACTION = 0.30
SHAFT_LOW_PERCENTILE = 10
MIN_SHAFT_FLOOR_RATIO = 0.52
MIN_SHAFT_MEDIAN_RATIO = 0.68
PAIR_RADIUS_WEIGHT = 1.00
PAIR_SIMILARITY_WEIGHT = 0.65
PAIR_SEPARATION_WEIGHT = 0.03
PAIR_SHAFT_WEIGHT = 0.12
PAIR_PROMINENCE_WEIGHT = 0.10
PAIR_BROAD_SUPPORT_WEIGHT = 0.22
PAIR_SAME_PLATEAU_WEIGHT = 0.00
CAP_DISK_RADIUS_FACTOR = 1.03
CAP_INWARD_VISUAL_OVERLAP = 0.03
MIN_CENTERLINE_EXTENSION_RADIUS_RATIO = 0.42
MIN_CLOSURE_SEARCH_RADIUS_RATIO = 0.20
CLOSURE_RADIUS_RATIO = 0.72
NECK_VALLEY_PROMINENCE_RATIO = 0.08
MIN_REEXPANSION_RADIUS_RATIO = 0.08
NARROW_EXTENSION_MEDIAN_RATIO = 0.68
EXTRA_SCORE_THRESHOLD = 0.28
EXTRA_SCORE_MARGIN = 0.05
EXTRA_SIDE_OVERRIDES = {}
NECK_BAND_POINTS = 3
SHOW_FORCED_GEOMETRY_PREVIEW = False


def apply_ji_duan(mask, ji_config: Optional[dict] = None):
    """Apply the project's Ji/Duan adaptive-opening branch with explicit config."""
    cfg = dict(ji_config or {})

    return isolate_dorsal_core_ji_duan(
        mask,
        area_divisor=float(cfg.get("area_divisor", 1000.0)),
        second_kernel_factor=float(cfg.get("second_kernel_factor", 0.5)),
        minimum_kernel=int(cfg.get("minimum_kernel", 3)),
        minimum_retained_fraction=float(
            cfg.get("minimum_retained_fraction", 0.20)
        ),
    )


def _binary(mask):
    m = clean_binary_mask(mask)
    return (
        np.asarray(m) > 0
    ).astype(np.uint8)


NEIGHBOR_OFFSETS = [
    (-1, -1), (-1, 0), (-1, 1),
    ( 0, -1),          ( 0, 1),
    ( 1, -1), ( 1, 0), ( 1, 1),
]


def _skeleton_neighbors(skeleton, y, x):
    h, w = skeleton.shape

    out = []

    for dy, dx in NEIGHBOR_OFFSETS:
        yy = y + dy
        xx = x + dx

        if (
            0 <= yy < h
            and 0 <= xx < w
            and skeleton[yy, xx]
        ):
            out.append(
                (yy, xx)
            )

    return out


def prune_short_skeleton_branches(
    skeleton,
    max_branch_length=7,
):
    skel = skeleton.copy().astype(bool)

    changed = True

    while changed:
        changed = False

        coords = np.argwhere(
            skel
        )

        endpoints = []

        for y, x in coords:
            deg = len(
                _skeleton_neighbors(
                    skel,
                    int(y),
                    int(x),
                )
            )

            if deg == 1:
                endpoints.append(
                    (int(y), int(x))
                )

        to_remove = set()

        for endpoint in endpoints:
            path = [
                endpoint
            ]

            prev = None
            current = endpoint

            for _ in range(
                int(max_branch_length)
            ):
                nbrs = [
                    p
                    for p in _skeleton_neighbors(
                        skel,
                        current[0],
                        current[1],
                    )
                    if p != prev
                ]

                if len(nbrs) != 1:
                    break

                nxt = nbrs[0]

                path.append(
                    nxt
                )

                prev = current
                current = nxt

                degree = len(
                    _skeleton_neighbors(
                        skel,
                        current[0],
                        current[1],
                    )
                )

                if degree != 2:
                    break

            terminal_degree = len(
                _skeleton_neighbors(
                    skel,
                    current[0],
                    current[1],
                )
            )

            # Short endpoint branch ending at a junction.
            if (
                len(path) - 1
                <= max_branch_length
                and terminal_degree >= 3
            ):
                for p in path[:-1]:
                    to_remove.add(
                        p
                    )

        if to_remove:
            changed = True

            for y, x in to_remove:
                skel[
                    y,
                    x,
                ] = False

    return skel


def _dijkstra_skeleton(
    skeleton,
    start,
):
    # Pixel skeleton is small enough that a heap-based graph
    # search is fine for these sample masks.
    import heapq

    dist = {
        start: 0.0
    }

    parent = {
        start: None
    }

    heap = [
        (
            0.0,
            start,
        )
    ]

    while heap:
        d, node = heapq.heappop(
            heap
        )

        if d != dist.get(
            node
        ):
            continue

        y, x = node

        for yy, xx in _skeleton_neighbors(
            skeleton,
            y,
            x,
        ):
            step = (
                math.sqrt(2.0)
                if (
                    yy != y
                    and xx != x
                )
                else 1.0
            )

            nd = d + step

            if nd < dist.get(
                (yy, xx),
                float('inf'),
            ):
                dist[
                    (yy, xx)
                ] = nd

                parent[
                    (yy, xx)
                ] = node

                heapq.heappush(
                    heap,
                    (
                        nd,
                        (yy, xx),
                    ),
                )

    return dist, parent


def longest_skeleton_path(
    skeleton,
):
    coords = np.argwhere(
        skeleton
    )

    if len(coords) < 2:
        raise ValueError(
            'Skeleton is too small.'
        )

    # Prefer an endpoint as the first seed.
    endpoints = []

    for y, x in coords:
        node = (
            int(y),
            int(x),
        )

        if len(
            _skeleton_neighbors(
                skeleton,
                node[0],
                node[1],
            )
        ) == 1:
            endpoints.append(
                node
            )

    seed = (
        endpoints[0]
        if endpoints
        else tuple(
            map(
                int,
                coords[0],
            )
        )
    )

    dist1, _ = _dijkstra_skeleton(
        skeleton,
        seed,
    )

    a = max(
        dist1,
        key=dist1.get,
    )

    dist2, parent2 = _dijkstra_skeleton(
        skeleton,
        a,
    )

    b = max(
        dist2,
        key=dist2.get,
    )

    path = []

    node = b

    while node is not None:
        path.append(
            node
        )

        if node == a:
            break

        node = parent2.get(
            node
        )

    path = path[::-1]

    if len(path) < 5:
        raise ValueError(
            'Longest skeleton path is too short.'
        )

    return path


def build_medial_axis(mask):
    mask = _binary(mask)

    skeleton = skeletonize(
        mask.astype(bool)
    )

    skeleton = prune_short_skeleton_branches(
        skeleton,
        max_branch_length=int(
            MIN_SKELETON_BRANCH_LENGTH_PX
        ),
    )

    path_yx = longest_skeleton_path(
        skeleton
    )

    return (
        skeleton,
        path_yx,
    )


def _skeleton_endpoints(skeleton):
    endpoints = []

    for y, x in np.argwhere(
        skeleton
    ):
        y = int(y)
        x = int(x)

        if len(
            _skeleton_neighbors(
                skeleton,
                y,
                x,
            )
        ) == 1:
            endpoints.append(
                (y, x)
            )

    return endpoints


def _path_between_skeleton_nodes(
    skeleton,
    start,
    end,
):
    dist, parent = _dijkstra_skeleton(
        skeleton,
        start,
    )

    if end not in dist:
        return None

    path = []
    node = end

    while node is not None:
        path.append(
            node
        )

        if node == start:
            break

        node = parent.get(
            node
        )

    if not path or path[-1] != start:
        return None

    return path[::-1]


def _longitudinal_spine_from_pca(
    mask,
    skeleton,
):
    '''
    Pick skeleton endpoints with the minimum and maximum
    projection along the mask's PCA major axis.

    This favors the pig's longitudinal ends over a lateral leg
    endpoint.
    '''
    ys, xs = np.nonzero(
        mask
    )

    if len(xs) < 10:
        raise ValueError(
            'Mask too small for longitudinal-spine PCA.'
        )

    pts = np.column_stack([
        xs.astype(float),
        ys.astype(float),
    ])

    center = pts.mean(
        axis=0
    )

    centered = (
        pts - center
    )

    _, _, vt = np.linalg.svd(
        centered,
        full_matrices=False,
    )

    major = vt[0]

    endpoints = _skeleton_endpoints(
        skeleton
    )

    if len(endpoints) < 2:
        # Fall back to the standard longest path.
        path = longest_skeleton_path(
            skeleton
        )

        return (
            path,
            center,
            major,
            'fallback_longest_path',
        )

    endpoint_xy = np.array(
        [
            (
                float(x),
                float(y),
            )
            for y, x in endpoints
        ]
    )

    projections = (
        endpoint_xy
        - center
    ) @ major

    order = np.argsort(
        projections
    )

    start = endpoints[
        int(
            order[0]
        )
    ]

    end = endpoints[
        int(
            order[-1]
        )
    ]

    path = _path_between_skeleton_nodes(
        skeleton,
        start,
        end,
    )

    if path is None or len(path) < 5:
        path = longest_skeleton_path(
            skeleton
        )

        return (
            path,
            center,
            major,
            'fallback_longest_path',
        )

    return (
        path,
        center,
        major,
        'pca_endpoint_spine',
    )


def cleanup_residual_lateral_appendages(
    ji_mask,
):
    ji_mask = _binary(
        ji_mask
    )

    empty_diag = {
        'status': 'disabled',
        'removed_mask': np.zeros_like(
            ji_mask
        ),
        'raw_skeleton': np.zeros_like(
            ji_mask,
            dtype=bool,
        ),
        'main_spine': np.zeros_like(
            ji_mask,
            dtype=bool,
        ),
        'branch_skeleton': np.zeros_like(
            ji_mask,
            dtype=bool,
        ),
        'body_envelope': ji_mask.copy(),
        'removed_area_fraction': 0.0,
        'components': [],
    }

    if not ENABLE_RESIDUAL_APPENDAGE_CLEANUP:
        return (
            ji_mask.copy(),
            empty_diag,
        )

    raw_skeleton = skeletonize(
        ji_mask.astype(bool)
    )

    if np.count_nonzero(
        raw_skeleton
    ) < 5:
        empty_diag[
            'status'
        ] = 'skeleton_too_small'

        return (
            ji_mask.copy(),
            empty_diag,
        )

    try:
        (
            main_path,
            pca_center,
            pca_major,
            spine_mode,
        ) = _longitudinal_spine_from_pca(
            ji_mask,
            raw_skeleton,
        )

    except Exception as exc:
        empty_diag[
            'status'
        ] = (
            'spine_failed: '
            + repr(
                exc
            )
        )

        return (
            ji_mask.copy(),
            empty_diag,
        )

    main_spine = np.zeros_like(
        ji_mask,
        dtype=bool,
    )

    for y, x in main_path:
        main_spine[
            int(
                y
            ),
            int(
                x
            ),
        ] = True

    branch_skeleton = (
        raw_skeleton
        & ~main_spine
    )

    distance = cv2.distanceTransform(
        ji_mask,
        cv2.DIST_L2,
        5,
    )

    body_envelope = np.zeros_like(
        ji_mask,
        dtype=np.uint8,
    )

    for k, (
        y,
        x,
    ) in enumerate(
        main_path
    ):
        if (
            k % 2 != 0
            and k
            != len(
                main_path
            )
            - 1
        ):
            continue

        radius = max(
            1,
            int(
                round(
                    float(
                        distance[
                            int(
                                y
                            ),
                            int(
                                x
                            ),
                        ]
                    )
                    * RESIDUAL_BODY_DISK_RADIUS_FACTOR
                )
            ),
        )

        cv2.circle(
            body_envelope,
            (
                int(
                    x
                ),
                int(
                    y
                ),
            ),
            radius,
            1,
            -1,
        )

    body_envelope = (
        body_envelope
        & ji_mask
    ).astype(
        np.uint8
    )

    outside = (
        ji_mask
        & (
            1
            - body_envelope
        )
    ).astype(
        np.uint8
    )

    (
        num_labels,
        labels,
        stats,
        centroids,
    ) = cv2.connectedComponentsWithStats(
        outside,
        connectivity=8,
    )

    mask_area = max(
        int(
            np.count_nonzero(
                ji_mask
            )
        ),
        1,
    )

    path_xy = np.array(
        [
            (
                float(
                    x
                ),
                float(
                    y
                ),
            )
            for y, x in main_path
        ],
        dtype=float,
    )

    removed_mask = np.zeros_like(
        ji_mask,
        dtype=np.uint8,
    )

    component_records = []

    branch_support_map = cv2.dilate(
        branch_skeleton.astype(
            np.uint8
        ),
        np.ones(
            (
                3,
                3,
            ),
            dtype=np.uint8,
        ),
        iterations=1,
    )

    for label_id in range(
        1,
        int(
            num_labels
        ),
    ):
        area = int(
            stats[
                label_id,
                cv2.CC_STAT_AREA,
            ]
        )

        area_fraction = float(
            area
            / mask_area
        )

        component = (
            labels
            == label_id
        )

        branch_pixels = int(
            np.count_nonzero(
                component
                & (
                    branch_support_map
                    > 0
                )
            )
        )

        cx, cy = centroids[
            label_id
        ]

        d2 = (
            (
                path_xy[
                    :,
                    0
                ]
                - float(
                    cx
                )
            ) ** 2
            + (
                path_xy[
                    :,
                    1
                ]
                - float(
                    cy
                )
            ) ** 2
        )

        nearest_path_idx = int(
            np.argmin(
                d2
            )
        )

        u = float(
            nearest_path_idx
            / max(
                len(
                    main_path
                )
                - 1,
                1,
            )
        )

        spine_point = path_xy[
            nearest_path_idx
        ]

        tangent_lo = max(
            0,
            nearest_path_idx
            - 4,
        )

        tangent_hi = min(
            len(
                path_xy
            )
            - 1,
            nearest_path_idx
            + 4,
        )

        tangent = (
            path_xy[
                tangent_hi
            ]
            - path_xy[
                tangent_lo
            ]
        )

        tangent_norm = max(
            float(
                np.linalg.norm(
                    tangent
                )
            ),
            1e-6,
        )

        tangent = (
            tangent
            / tangent_norm
        )

        normal = np.array(
            [
                -tangent[
                    1
                ],
                tangent[
                    0
                ],
            ],
            dtype=float,
        )

        offset = (
            np.array(
                [
                    float(
                        cx
                    ),
                    float(
                        cy
                    ),
                ]
            )
            - spine_point
        )

        axial_offset = float(
            abs(
                np.dot(
                    offset,
                    tangent
                )
            )
        )

        perp_offset = float(
            abs(
                np.dot(
                    offset,
                    normal
                )
            )
        )

        lateralness = float(
            perp_offset
            / max(
                perp_offset
                + axial_offset,
                1e-6,
            )
        )

        local_y = int(
            round(
                main_path[
                    nearest_path_idx
                ][
                    0
                ]
            )
        )

        local_x = int(
            round(
                main_path[
                    nearest_path_idx
                ][
                    1
                ]
            )
        )

        local_radius = max(
            float(
                distance[
                    local_y,
                    local_x,
                ]
            ),
            1e-6,
        )

        perp_offset_radius_ratio = float(
            perp_offset
            / local_radius
        )

        away_from_ends = bool(
            RESIDUAL_END_PROTECTION_FRACTION
            <= u
            <= (
                1.0
                - RESIDUAL_END_PROTECTION_FRACTION
            )
        )

        area_ok = bool(
            RESIDUAL_MIN_COMPONENT_AREA_FRACTION
            <= area_fraction
            <= RESIDUAL_MAX_COMPONENT_AREA_FRACTION
        )

        branch_ok = bool(
            branch_pixels
            >= RESIDUAL_MIN_BRANCH_PIXELS
        )

        lateral_geometry_ok = bool(
            lateralness
            >= RESIDUAL_MIN_LATERALNESS
            and perp_offset_radius_ratio
            >= RESIDUAL_MIN_PERP_OFFSET_RADIUS_RATIO
        )

        # Branch support OR sufficiently strong lateral
        # geometry can support removal.
        appendage_evidence_ok = bool(
            branch_ok
            or lateral_geometry_ok
        )

        remove = bool(
            away_from_ends
            and area_ok
            and appendage_evidence_ok
        )

        if remove:
            removed_mask[
                component
            ] = 1

        component_records.append({
            'component_id': int(
                label_id
            ),
            'area_px': area,
            'area_fraction': area_fraction,
            'nearest_spine_u': u,

            'branch_pixels': branch_pixels,
            'branch_ok': branch_ok,

            'lateralness': lateralness,
            'perp_offset_px': perp_offset,
            'local_radius_px': local_radius,
            'perp_offset_radius_ratio': perp_offset_radius_ratio,
            'lateral_geometry_ok': lateral_geometry_ok,

            'away_from_ends': away_from_ends,
            'area_ok': area_ok,
            'appendage_evidence_ok': appendage_evidence_ok,
            'remove': remove,
        })

    removed_area_fraction = float(
        np.count_nonzero(
            removed_mask
        )
        / mask_area
    )

    if (
        removed_area_fraction
        > RESIDUAL_MAX_TOTAL_REMOVAL_FRACTION
    ):
        cleaned = ji_mask.copy()
        status = 'reverted_too_aggressive'

        removed_mask[
            ...
        ] = 0

        removed_area_fraction = 0.0

    elif np.any(
        removed_mask
    ):
        cleaned = (
            ji_mask
            & (
                1
                - removed_mask
            )
        ).astype(
            np.uint8
        )

        k = int(
            RESIDUAL_POST_CLOSE_KERNEL
        )

        if k >= 3:
            if k % 2 == 0:
                k += 1

            kernel = cv2.getStructuringElement(
                cv2.MORPH_ELLIPSE,
                (
                    k,
                    k,
                ),
            )

            cleaned = cv2.morphologyEx(
                cleaned,
                cv2.MORPH_CLOSE,
                kernel,
            )

        cleaned = _binary(
            cleaned
        )

        status = 'removed_residual_lateral_appendage'

    else:
        cleaned = ji_mask.copy()
        status = 'no_residual_appendage_removed'

    diag = {
        'status': status,
        'spine_mode': spine_mode,
        'removed_mask': removed_mask,
        'raw_skeleton': raw_skeleton,
        'main_spine': main_spine,
        'branch_skeleton': branch_skeleton,
        'body_envelope': body_envelope,
        'removed_area_fraction': removed_area_fraction,
        'components': component_records,
        'pca_center': pca_center,
        'pca_major': pca_major,
    }

    return (
        cleaned,
        diag,
    )


def resample_centerline_profile(
    mask,
    path_yx,
):
    mask = _binary(mask)

    distance = cv2.distanceTransform(
        mask,
        cv2.DIST_L2,
        5,
    )

    path = np.asarray(
        [
            (
                float(x),
                float(y),
            )
            for y, x in path_yx
        ],
        dtype=float,
    )

    if len(path) < 5:
        raise ValueError(
            'Path too short.'
        )

    diffs = np.diff(
        path,
        axis=0,
    )

    step = np.sqrt(
        (
            diffs ** 2
        ).sum(
            axis=1
        )
    )

    arc = np.concatenate([
        [0.0],
        np.cumsum(step),
    ])

    total_length = float(
        arc[-1]
    )

    if total_length <= 0:
        raise ValueError(
            'Invalid centerline arc length.'
        )

    u = np.linspace(
        0.0,
        total_length,
        int(
            PROFILE_POINTS
        ),
    )

    x = np.interp(
        u,
        arc,
        path[:, 0],
    )

    y = np.interp(
        u,
        arc,
        path[:, 1],
    )

    xi = np.clip(
        np.round(x).astype(int),
        0,
        mask.shape[1] - 1,
    )

    yi = np.clip(
        np.round(y).astype(int),
        0,
        mask.shape[0] - 1,
    )

    radius = distance[
        yi,
        xi,
    ].astype(float)

    radius_smooth = gaussian_filter1d(
        radius,
        sigma=float(
            RADIUS_SMOOTH_SIGMA
        ),
        mode='nearest',
    )

    return {
        'distance_transform': distance,
        'u': u,
        'u_normalized': (
            u / total_length
        ),
        'x': x,
        'y': y,
        'xi': xi,
        'yi': yi,
        'radius_raw': radius,
        'radius': radius_smooth,
        'total_length': total_length,
    }


def _candidate_record(
    profile,
    idx,
    source,
    prominence=0.0,
    is_endpoint_peak=False,
    broad_region=None,
    broad_region_id=None,
    broad_region_kind=None,
    broad_role=None,
):
    radius = profile[
        'radius'
    ]

    max_radius = max(
        float(
            np.max(
                radius
            )
        ),
        1e-6,
    )

    idx = int(
        idx
    )

    r = float(
        radius[
            idx
        ]
    )

    n = len(
        radius
    )

    w = max(
        2,
        int(
            round(
                0.04
                * n
            )
        ),
    )

    lo = max(
        0,
        idx
        - w,
    )

    hi = min(
        n,
        idx
        + w
        + 1,
    )

    local_median = max(
        float(
            np.median(
                radius[
                    lo:hi
                ]
            )
        ),
        1e-6,
    )

    record = {
        'index': idx,
        'u': float(
            profile[
                'u_normalized'
            ][
                idx
            ]
        ),
        'arc_length': float(
            profile[
                'u'
            ][
                idx
            ]
        ),
        'x': float(
            profile[
                'x'
            ][
                idx
            ]
        ),
        'y': float(
            profile[
                'y'
            ][
                idx
            ]
        ),
        'radius': r,
        'radius_ratio_to_max': float(
            r
            / max_radius
        ),
        'prominence': float(
            prominence
        ),
        'local_peakness': float(
            r
            / local_median
        ),
        'is_endpoint_peak': bool(
            is_endpoint_peak
        ),
        'candidate_source': str(
            source
        ),

        'broad_region_id': broad_region_id,
        'broad_region_kind': broad_region_kind,
        'broad_role': broad_role,

        'broad_region_start_u': np.nan,
        'broad_region_end_u': np.nan,
        'broad_region_length_px': 0.0,
        'broad_region_length_radius_ratio': 0.0,
        'broad_boundary_left_ok': False,
        'broad_boundary_right_ok': False,
        'broad_support_score': 0.0,
    }

    if broad_region is not None:
        record.update({
            'broad_region_start_u': float(
                broad_region[
                    'start_u'
                ]
            ),
            'broad_region_end_u': float(
                broad_region[
                    'end_u'
                ]
            ),
            'broad_region_length_px': float(
                broad_region[
                    'length_px'
                ]
            ),
            'broad_region_length_radius_ratio': float(
                broad_region[
                    'length_radius_ratio'
                ]
            ),
            'broad_boundary_left_ok': bool(
                broad_region[
                    'left_boundary_ok'
                ]
            ),
            'broad_boundary_right_ok': bool(
                broad_region[
                    'right_boundary_ok'
                ]
            ),
            'broad_support_score': float(
                broad_region[
                    'support_score'
                ]
            ),
        })

    return record


def generate_sharp_peak_candidates(
    profile,
):
    radius = profile[
        'radius'
    ]

    n = len(
        radius
    )

    max_radius = max(
        float(
            np.max(
                radius
            )
        ),
        1e-6,
    )

    median_radius = max(
        float(
            np.median(
                radius
            )
        ),
        1e-6,
    )

    min_distance = max(
        3,
        int(
            round(
                MIN_PEAK_DISTANCE_FRACTION
                * n
            )
        ),
    )

    prominence = (
        PEAK_PROMINENCE_RATIO
        * median_radius
    )

    peaks, properties = find_peaks(
        radius,
        distance=min_distance,
        prominence=prominence,
    )

    prominence_by_index = {}

    for idx, prom in zip(
        peaks,
        properties.get(
            'prominences',
            np.zeros(
                len(
                    peaks
                )
            ),
        ),
    ):
        prominence_by_index[
            int(
                idx
            )
        ] = float(
            prom
        )

    edge_window = max(
        3,
        int(
            round(
                ENDPOINT_PEAK_WINDOW_FRACTION
                * n
            )
        ),
    )

    endpoint_candidates = []

    if (
        radius[
            0
        ]
        >= np.max(
            radius[
                :edge_window
            ]
        )
        - 1e-6
    ):
        endpoint_candidates.append(
            0
        )

    if (
        radius[
            -1
        ]
        >= np.max(
            radius[
                -edge_window:
            ]
        )
        - 1e-6
    ):
        endpoint_candidates.append(
            n
            - 1
        )

    candidate_indices = sorted(
        set(
            [
                int(
                    x
                )
                for x in peaks
            ]
            + endpoint_candidates
        )
    )

    candidates = []

    for idx in candidate_indices:
        if (
            float(
                radius[
                    idx
                ]
            )
            / max_radius
            < MIN_BODY_LOBE_RADIUS_RATIO
        ):
            continue

        candidates.append(
            _candidate_record(
                profile,
                idx,
                source='sharp_peak',
                prominence=prominence_by_index.get(
                    int(
                        idx
                    ),
                    0.0,
                ),
                is_endpoint_peak=(
                    idx
                    in endpoint_candidates
                ),
            )
        )

    return candidates


def _expand_high_radius_region(
    profile,
    center_idx,
):
    radius = profile[
        'radius'
    ]

    arc = profile[
        'u'
    ]

    n = len(
        radius
    )

    center_idx = int(
        center_idx
    )

    center_radius = max(
        float(
            radius[
                center_idx
            ]
        ),
        1e-6,
    )

    high_threshold = (
        BROAD_REGION_HIGH_RADIUS_FRACTION
        * center_radius
    )

    left = center_idx

    while (
        left
        > 0
        and radius[
            left
            - 1
        ]
        >= high_threshold
    ):
        left -= 1

    right = center_idx

    while (
        right
        < n
        - 1
        and radius[
            right
            + 1
        ]
        >= high_threshold
    ):
        right += 1

    length_px = float(
        arc[
            right
        ]
        - arc[
            left
        ]
    )

    length_radius_ratio = float(
        length_px
        / center_radius
    )

    boundary_threshold = (
        BROAD_REGION_BOUNDARY_DROP_FRACTION
        * center_radius
    )

    search_distance = (
        BROAD_REGION_BOUNDARY_SEARCH_RADIUS_RATIO
        * center_radius
    )

    left_boundary_ok = bool(
        left
        == 0
    )

    if not left_boundary_ok:
        left_arc = float(
            arc[
                left
            ]
        )

        j = left

        while (
            j > 0
            and (
                left_arc
                - float(
                    arc[
                        j
                        - 1
                    ]
                )
            )
            <= search_distance
        ):
            j -= 1

            if (
                radius[
                    j
                ]
                <= boundary_threshold
            ):
                left_boundary_ok = True
                break

    right_boundary_ok = bool(
        right
        == n
        - 1
    )

    if not right_boundary_ok:
        right_arc = float(
            arc[
                right
            ]
        )

        j = right

        while (
            j
            < n
            - 1
            and (
                float(
                    arc[
                        j
                        + 1
                    ]
                )
                - right_arc
            )
            <= search_distance
        ):
            j += 1

            if (
                radius[
                    j
                ]
                <= boundary_threshold
            ):
                right_boundary_ok = True
                break

    boundary_ok = bool(
        left_boundary_ok
        or right_boundary_ok
    )

    min_required_length = (
        BROAD_REGION_MIN_LENGTH_RADIUS_RATIO
        * center_radius
    )

    length_ok = bool(
        length_px
        >= min_required_length
    )

    support_score = float(
        min(
            length_radius_ratio
            / max(
                BROAD_REGION_MIN_LENGTH_RADIUS_RATIO,
                1e-6,
            ),
            2.0,
        )
        / 2.0
    )

    if (
        left_boundary_ok
        and right_boundary_ok
    ):
        support_score = min(
            1.0,
            support_score
            + 0.15
        )

    return {
        'center_idx': center_idx,
        'start_idx': int(
            left
        ),
        'end_idx': int(
            right
        ),
        'start_u': float(
            profile[
                'u_normalized'
            ][
                left
            ]
        ),
        'end_u': float(
            profile[
                'u_normalized'
            ][
                right
            ]
        ),
        'center_radius': center_radius,
        'high_threshold': float(
            high_threshold
        ),
        'length_px': length_px,
        'length_radius_ratio': length_radius_ratio,
        'left_boundary_ok': left_boundary_ok,
        'right_boundary_ok': right_boundary_ok,
        'boundary_ok': boundary_ok,
        'length_ok': length_ok,
        'support_score': support_score,
    }


def _local_radius_max_near_arc_target(
    profile,
    target_arc,
    search_radius_px,
):
    arc = profile[
        'u'
    ]

    radius = profile[
        'radius'
    ]

    target_idx = int(
        np.argmin(
            np.abs(
                arc
                - float(
                    target_arc
                )
            )
        )
    )

    arc_distance = np.abs(
        arc
        - float(
            target_arc
        )
    )

    eligible = np.where(
        arc_distance
        <= float(
            search_radius_px
        )
    )[0]

    if len(
        eligible
    ) == 0:
        return target_idx

    best_local = eligible[
        int(
            np.argmax(
                radius[
                    eligible
                ]
            )
        )
    ]

    return int(
        best_local
    )


def _construct_candidates_from_broad_region(
    profile,
    region,
    region_id,
):
    arc = profile[
        'u'
    ]

    radius = profile[
        'radius'
    ]

    start_idx = int(
        region[
            'start_idx'
        ]
    )

    end_idx = int(
        region[
            'end_idx'
        ]
    )

    center_radius = max(
        float(
            region[
                'center_radius'
            ]
        ),
        1e-6,
    )

    # --------------------------------------------------------
    # LONG PLATEAU:
    # two cap candidates near its two ends.
    # --------------------------------------------------------

    if (
        region[
            'length_radius_ratio'
        ]
        >= LONG_PLATEAU_MIN_LENGTH_RADIUS_RATIO
    ):
        inward = (
            PLATEAU_CAP_INWARD_RADIUS_RATIO
            * center_radius
        )

        left_target_arc = min(
            float(
                arc[
                    end_idx
                ]
            ),
            float(
                arc[
                    start_idx
                ]
            )
            + inward,
        )

        right_target_arc = max(
            float(
                arc[
                    start_idx
                ]
            ),
            float(
                arc[
                    end_idx
                ]
            )
            - inward,
        )

        local_search = (
            PLATEAU_CAP_LOCAL_SEARCH_RADIUS_RATIO
            * center_radius
        )

        left_idx = _local_radius_max_near_arc_target(
            profile,
            left_target_arc,
            local_search,
        )

        right_idx = _local_radius_max_near_arc_target(
            profile,
            right_target_arc,
            local_search,
        )

        internal_sep = abs(
            float(
                arc[
                    right_idx
                ]
            )
            - float(
                arc[
                    left_idx
                ]
            )
        )

        min_internal_sep = (
            PLATEAU_CAP_MIN_INTERNAL_SEPARATION_RADIUS_RATIO
            * center_radius
        )

        if (
            left_idx
            < right_idx
            and internal_sep
            >= min_internal_sep
        ):
            return [
                _candidate_record(
                    profile,
                    left_idx,
                    source='broad_plateau_cap',
                    broad_region=region,
                    broad_region_id=int(
                        region_id
                    ),
                    broad_region_kind='long_plateau',
                    broad_role='left_cap',
                ),
                _candidate_record(
                    profile,
                    right_idx,
                    source='broad_plateau_cap',
                    broad_region=region,
                    broad_region_id=int(
                        region_id
                    ),
                    broad_region_kind='long_plateau',
                    broad_role='right_cap',
                ),
            ]

    # --------------------------------------------------------
    # LOCALIZED BROAD LOBE:
    # one candidate at its maximum-radius position.
    # --------------------------------------------------------

    center_idx = int(
        start_idx
        + np.argmax(
            radius[
                start_idx:
                end_idx
                + 1
            ]
        )
    )

    return [
        _candidate_record(
            profile,
            center_idx,
            source='broad_local_lobe',
            broad_region=region,
            broad_region_id=int(
                region_id
            ),
            broad_region_kind='localized_lobe',
            broad_role='single',
        )
    ]


def generate_broad_region_candidates(
    profile,
):
    if not ENABLE_BROAD_LOBE_REGIONS:
        return []

    radius = profile[
        'radius'
    ]

    n = len(
        radius
    )

    max_radius = max(
        float(
            np.max(
                radius
            )
        ),
        1e-6,
    )

    qualifying = []

    stride = max(
        1,
        int(
            BROAD_REGION_SCAN_STRIDE
        ),
    )

    for idx in range(
        0,
        n,
        stride,
    ):
        center_radius = float(
            radius[
                idx
            ]
        )

        if (
            center_radius
            / max_radius
            < BROAD_REGION_MIN_CENTER_RADIUS_RATIO
        ):
            continue

        region = _expand_high_radius_region(
            profile,
            idx,
        )

        if not (
            region[
                'length_ok'
            ]
            and region[
                'boundary_ok'
            ]
        ):
            continue

        qualifying.append(
            region
        )

    if not qualifying:
        return []

    # --------------------------------------------------------
    # Group overlapping detections into physical high-radius
    # regions.
    # --------------------------------------------------------

    qualifying = sorted(
        qualifying,
        key=lambda r: (
            r[
                'start_idx'
            ],
            r[
                'end_idx'
            ],
            r[
                'center_idx'
            ],
        ),
    )

    groups = []

    for region in qualifying:
        if not groups:
            groups.append(
                [
                    region
                ]
            )
            continue

        previous_group = groups[
            -1
        ]

        previous_end = max(
            r[
                'end_idx'
            ]
            for r in previous_group
        )

        if (
            region[
                'start_idx'
            ]
            <= previous_end
            + 1
        ):
            previous_group.append(
                region
            )
        else:
            groups.append(
                [
                    region
                ]
            )

    candidates = []

    for region_id, group in enumerate(
        groups
    ):
        group_start = min(
            r[
                'start_idx'
            ]
            for r in group
        )

        group_end = max(
            r[
                'end_idx'
            ]
            for r in group
        )

        representative_idx = int(
            group_start
            + np.argmax(
                radius[
                    group_start:
                    group_end
                    + 1
                ]
            )
        )

        # Canonical region around the strongest point.
        region = _expand_high_radius_region(
            profile,
            representative_idx,
        )

        # Preserve the union extent when it is larger than the
        # representative expansion. This matters for very flat
        # plateaus whose thresholds vary slightly across scans.
        canonical_start = min(
            int(
                region[
                    'start_idx'
                ]
            ),
            int(
                group_start
            ),
        )

        canonical_end = max(
            int(
                region[
                    'end_idx'
                ]
            ),
            int(
                group_end
            ),
        )

        region[
            'start_idx'
        ] = canonical_start

        region[
            'end_idx'
        ] = canonical_end

        region[
            'start_u'
        ] = float(
            profile[
                'u_normalized'
            ][
                canonical_start
            ]
        )

        region[
            'end_u'
        ] = float(
            profile[
                'u_normalized'
            ][
                canonical_end
            ]
        )

        region[
            'length_px'
        ] = float(
            profile[
                'u'
            ][
                canonical_end
            ]
            - profile[
                'u'
            ][
                canonical_start
            ]
        )

        region[
            'length_radius_ratio'
        ] = float(
            region[
                'length_px'
            ]
            / max(
                region[
                    'center_radius'
                ],
                1e-6,
            )
        )

        region_candidates = _construct_candidates_from_broad_region(
            profile,
            region,
            region_id=region_id,
        )

        candidates.extend(
            region_candidates
        )

    return candidates


def merge_lobe_candidates(
    profile,
    sharp_candidates,
    broad_candidates,
):
    all_candidates = (
        list(
            sharp_candidates
        )
        + list(
            broad_candidates
        )
    )

    if not all_candidates:
        return []

    all_candidates = sorted(
        all_candidates,
        key=lambda c: c[
            'arc_length'
        ],
    )

    total_arc = max(
        float(
            profile[
                'total_length'
            ]
        ),
        1e-6,
    )

    merge_distance = (
        MERGE_CANDIDATE_ARC_FRACTION
        * total_arc
    )

    groups = []

    for c in all_candidates:
        if not groups:
            groups.append(
                [
                    c
                ]
            )
            continue

        previous = groups[
            -1
        ]

        if (
            c[
                'arc_length'
            ]
            - previous[
                -1
            ][
                'arc_length'
            ]
            <= merge_distance
        ):
            previous.append(
                c
            )
        else:
            groups.append(
                [
                    c
                ]
            )

    merged = []

    for group in groups:
        best = max(
            group,
            key=lambda c: (
                c[
                    'radius'
                ],
                c.get(
                    'broad_support_score',
                    0.0,
                ),
                c.get(
                    'prominence',
                    0.0,
                ),
            ),
        ).copy()

        broad_members = [
            c
            for c in group
            if c.get(
                'candidate_source',
                ''
            ).startswith(
                'broad_'
            )
        ]

        sharp_members = [
            c
            for c in group
            if c.get(
                'candidate_source'
            )
            == 'sharp_peak'
        ]

        if (
            broad_members
            and sharp_members
        ):
            best[
                'candidate_source'
            ] = 'sharp+broad'

        if broad_members:
            # Prefer broad metadata belonging to the candidate
            # nearest the chosen center.
            broad_best = min(
                broad_members,
                key=lambda c: abs(
                    float(
                        c[
                            'arc_length'
                        ]
                    )
                    - float(
                        best[
                            'arc_length'
                        ]
                    )
                ),
            )

            for key in [
                'broad_region_id',
                'broad_region_kind',
                'broad_role',
                'broad_region_start_u',
                'broad_region_end_u',
                'broad_region_length_px',
                'broad_region_length_radius_ratio',
                'broad_boundary_left_ok',
                'broad_boundary_right_ok',
                'broad_support_score',
            ]:
                best[
                    key
                ] = broad_best.get(
                    key,
                    best.get(
                        key
                    ),
                )

        merged.append(
            best
        )

    return merged


def _profile_unit_tangent(
    profile,
    index,
):
    n = len(
        profile[
            'x'
        ]
    )

    i0 = max(
        0,
        int(
            index
        )
        - 2,
    )

    i1 = min(
        n
        - 1,
        int(
            index
        )
        + 2,
    )

    tangent = np.array([
        float(
            profile[
                'x'
            ][
                i1
            ]
            - profile[
                'x'
            ][
                i0
            ]
        ),
        float(
            profile[
                'y'
            ][
                i1
            ]
            - profile[
                'y'
            ][
                i0
            ]
        ),
    ])

    norm = max(
        float(
            np.linalg.norm(
                tangent
            )
        ),
        1e-6,
    )

    return tangent / norm


def _ray_distance_to_mask_boundary(
    mask,
    center_xy,
    direction_xy,
    max_distance_px,
):
    '''
    March from an interior centerline point until the ray exits
    the binary mask. Return the last foreground distance and
    corresponding boundary-side point.
    '''
    mask = (
        np.asarray(
            mask
        )
        > 0
    ).astype(
        np.uint8
    )

    h, w = mask.shape[
        :2
    ]

    center_xy = np.asarray(
        center_xy,
        dtype=float,
    )

    direction_xy = np.asarray(
        direction_xy,
        dtype=float,
    )

    direction_xy /= max(
        float(
            np.linalg.norm(
                direction_xy
            )
        ),
        1e-6,
    )

    step = max(
        float(
            CROSS_SECTION_RAY_STEP_PX
        ),
        0.25,
    )

    last_inside_distance = 0.0
    last_inside_point = center_xy.copy()

    d = 0.0

    while (
        d
        <= float(
            max_distance_px
        )
    ):
        p = (
            center_xy
            + d
            * direction_xy
        )

        x = int(
            round(
                p[
                    0
                ]
            )
        )

        y = int(
            round(
                p[
                    1
                ]
            )
        )

        if (
            x < 0
            or y < 0
            or x >= w
            or y >= h
        ):
            break

        if mask[
            y,
            x
        ] == 0:
            break

        last_inside_distance = float(
            d
        )

        last_inside_point = p.copy()

        d += step

    return (
        float(
            last_inside_distance
        ),
        last_inside_point,
    )


def build_cross_section_profiles(
    mask,
    profile,
):
    mask = (
        np.asarray(
            mask
        )
        > 0
    ).astype(
        np.uint8
    )

    n = len(
        profile[
            'x'
        ]
    )

    max_profile_radius = max(
        float(
            np.max(
                profile[
                    'radius'
                ]
            )
        ),
        1e-6,
    )

    max_trace = (
        CROSS_SECTION_MAX_TRACE_RADIUS_FACTOR
        * max_profile_radius
    )

    plus_distance = np.full(
        n,
        np.nan,
        dtype=float,
    )

    minus_distance = np.full(
        n,
        np.nan,
        dtype=float,
    )

    plus_points = np.full(
        (
            n,
            2,
        ),
        np.nan,
        dtype=float,
    )

    minus_points = np.full(
        (
            n,
            2,
        ),
        np.nan,
        dtype=float,
    )

    normals = np.full(
        (
            n,
            2,
        ),
        np.nan,
        dtype=float,
    )

    tangents = np.full(
        (
            n,
            2,
        ),
        np.nan,
        dtype=float,
    )

    for idx in range(
        n
    ):
        tangent = _profile_unit_tangent(
            profile,
            idx,
        )

        normal = np.array([
            -tangent[
                1
            ],
            tangent[
                0
            ],
        ])

        center = np.array([
            float(
                profile[
                    'x'
                ][
                    idx
                ]
            ),
            float(
                profile[
                    'y'
                ][
                    idx
                ]
            ),
        ])

        plus_d, plus_p = _ray_distance_to_mask_boundary(
            mask,
            center,
            normal,
            max_trace,
        )

        minus_d, minus_p = _ray_distance_to_mask_boundary(
            mask,
            center,
            -normal,
            max_trace,
        )

        plus_distance[
            idx
        ] = plus_d

        minus_distance[
            idx
        ] = minus_d

        plus_points[
            idx
        ] = plus_p

        minus_points[
            idx
        ] = minus_p

        normals[
            idx
        ] = normal

        tangents[
            idx
        ] = tangent

    # Fill any isolated invalid samples before smoothing.
    x_idx = np.arange(
        n
    )

    for arr in [
        plus_distance,
        minus_distance,
    ]:
        valid = np.isfinite(
            arr
        )

        if np.count_nonzero(
            valid
        ) >= 2:
            arr[
                ~valid
            ] = np.interp(
                x_idx[
                    ~valid
                ],
                x_idx[
                    valid
                ],
                arr[
                    valid
                ],
            )

    plus_smooth = gaussian_filter1d(
        plus_distance,
        sigma=float(
            CROSS_SECTION_SMOOTH_SIGMA
        ),
        mode='nearest',
    )

    minus_smooth = gaussian_filter1d(
        minus_distance,
        sigma=float(
            CROSS_SECTION_SMOOTH_SIGMA
        ),
        mode='nearest',
    )

    total_width = (
        plus_distance
        + minus_distance
    )

    total_width_smooth = gaussian_filter1d(
        total_width,
        sigma=float(
            CROSS_SECTION_SMOOTH_SIGMA
        ),
        mode='nearest',
    )

    return {
        'plus_distance': plus_distance,
        'minus_distance': minus_distance,
        'plus_smooth': plus_smooth,
        'minus_smooth': minus_smooth,

        'total_width': total_width,
        'total_width_smooth': total_width_smooth,

        'plus_points': plus_points,
        'minus_points': minus_points,

        'normal': normals,
        'tangent': tangents,
    }


def _cross_section_drop_record(
    profile,
    cross_section,
    index,
    side,
):
    radius_profile = profile[
        'radius'
    ]

    arc = profile[
        'u'
    ]

    idx = int(
        index
    )

    local_radius = max(
        float(
            radius_profile[
                idx
            ]
        ),
        1e-6,
    )

    plus = cross_section[
        'plus_smooth'
    ]

    minus = cross_section[
        'minus_smooth'
    ]

    width = cross_section[
        'total_width_smooth'
    ]

    plus_now = max(
        float(
            plus[
                idx
            ]
        ),
        1e-6,
    )

    minus_now = max(
        float(
            minus[
                idx
            ]
        ),
        1e-6,
    )

    width_now = max(
        float(
            width[
                idx
            ]
        ),
        1e-6,
    )

    min_distance = (
        CROSS_SECTION_MIN_LOOKAHEAD_DISTANCE_RADIUS_RATIO
        * local_radius
    )

    max_distance = (
        CROSS_SECTION_LOOKAHEAD_RADIUS_RATIO
        * local_radius
    )

    if side == 'right':
        distances = (
            arc
            - arc[
                idx
            ]
        )

        outward = np.where(
            (
                distances
                >= min_distance
            )
            & (
                distances
                <= max_distance
            )
        )[0]

    elif side == 'left':
        distances = (
            arc[
                idx
            ]
            - arc
        )

        outward = np.where(
            (
                distances
                >= min_distance
            )
            & (
                distances
                <= max_distance
            )
        )[0]

    else:
        raise ValueError(
            side
        )

    if len(
        outward
    ) < 2:
        return None

    # Robust outward lows rather than a single noisy minimum.
    plus_low = float(
        np.percentile(
            plus[
                outward
            ],
            20,
        )
    )

    minus_low = float(
        np.percentile(
            minus[
                outward
            ],
            20,
        )
    )

    width_low = float(
        np.percentile(
            width[
                outward
            ],
            20,
        )
    )

    plus_drop = float(
        max(
            0.0,
            (
                plus_now
                - plus_low
            )
            / plus_now,
        )
    )

    minus_drop = float(
        max(
            0.0,
            (
                minus_now
                - minus_low
            )
            / minus_now,
        )
    )

    width_drop = float(
        max(
            0.0,
            (
                width_now
                - width_low
            )
            / width_now,
        )
    )

    one_side_drop = float(
        max(
            plus_drop,
            minus_drop,
        )
    )

    asymmetric_side = (
        'plus'
        if plus_drop
        >= minus_drop
        else 'minus'
    )

    qualifies = bool(
        one_side_drop
        >= CROSS_SECTION_MIN_ONE_SIDE_DROP_RATIO
        and width_drop
        >= CROSS_SECTION_MIN_TOTAL_WIDTH_DROP_RATIO
    )

    score = float(
        0.58
        * one_side_drop
        + 0.27
        * width_drop
        + 0.15
        * (
            float(
                radius_profile[
                    idx
                ]
            )
            / max(
                float(
                    np.max(
                        radius_profile
                    )
                ),
                1e-6,
            )
        )
    )

    return {
        'index': idx,
        'side': side,

        'plus_distance_px': float(
            cross_section[
                'plus_distance'
            ][
                idx
            ]
        ),

        'minus_distance_px': float(
            cross_section[
                'minus_distance'
            ][
                idx
            ]
        ),

        'total_width_px': float(
            cross_section[
                'total_width'
            ][
                idx
            ]
        ),

        'plus_drop_ratio': plus_drop,
        'minus_drop_ratio': minus_drop,
        'one_side_drop_ratio': one_side_drop,
        'total_width_drop_ratio': width_drop,

        'dominant_closing_side': asymmetric_side,

        'qualifies': qualifies,
        'score': score,
    }


def _true_runs_in_order(
    ordered_indices,
    qualifies_by_index,
):
    runs = []
    current = []

    for idx in ordered_indices:
        idx = int(
            idx
        )

        if bool(
            qualifies_by_index.get(
                idx,
                False,
            )
        ):
            current.append(
                idx
            )

        else:
            if current:
                runs.append(
                    current
                )

                current = []

    if current:
        runs.append(
            current
        )

    return runs


def _local_radius_support_score(
    profile,
    index,
):
    radius = profile[
        'radius'
    ]

    arc = profile[
        'u'
    ]

    idx = int(
        index
    )

    r = max(
        float(
            radius[
                idx
            ]
        ),
        1e-6,
    )

    half_window = (
        NECK_ANCHOR_LOCAL_WINDOW_RADIUS_RATIO
        * r
    )

    eligible = np.where(
        np.abs(
            arc
            - arc[
                idx
            ]
        )
        <= half_window
    )[0]

    if len(
        eligible
    ) < 2:
        return 0.5

    local_median = max(
        float(
            np.median(
                radius[
                    eligible
                ]
            )
        ),
        1e-6,
    )

    # 1.0 means at least as broad as its local neighborhood.
    return float(
        np.clip(
            r
            / local_median,
            0.0,
            1.0,
        )
    )


def _find_body_anchor_for_neck(
    profile,
    cross_section,
    neck_index,
    neck_side,
):
    '''
    Search ONLY inward from the refined neck.

    Tangency is measured against the ACTUAL neck cross-section:

        line through N
        perpendicular to centerline tangent T

    distance_to_plane = |dot(C - N, T)|

    with the sign constrained so C is on the BODY side.
    '''
    radius = profile[
        'radius'
    ]

    n = len(
        radius
    )

    neck_index = int(
        neck_index
    )

    max_profile_radius = max(
        float(
            np.max(
                radius
            )
        ),
        1e-6,
    )

    neck_center = np.array([
        float(
            profile[
                'x'
            ][
                neck_index
            ]
        ),
        float(
            profile[
                'y'
            ][
                neck_index
            ]
        ),
    ])

    neck_tangent = np.asarray(
        cross_section[
            'tangent'
        ][
            neck_index
        ],
        dtype=float,
    )

    neck_tangent /= max(
        float(
            np.linalg.norm(
                neck_tangent
            )
        ),
        1e-6,
    )

    if neck_side == 'left':
        # Profile direction increases from left terminal toward
        # the body.
        possible = np.arange(
            neck_index
            + 1,
            n,
            dtype=int,
        )

        body_sign = 1.0

    elif neck_side == 'right':
        # Body lies toward decreasing profile index.
        possible = np.arange(
            0,
            neck_index,
            dtype=int,
        )

        body_sign = -1.0

    else:
        raise ValueError(
            neck_side
        )

    if len(
        possible
    ) == 0:
        return None

    records = []

    for idx in possible:
        idx = int(
            idx
        )

        candidate_radius = max(
            float(
                radius[
                    idx
                ]
            ),
            1e-6,
        )

        radius_ratio_to_max = float(
            candidate_radius
            / max_profile_radius
        )

        if (
            radius_ratio_to_max
            < NECK_ANCHOR_MIN_RADIUS_RATIO_TO_MAX
        ):
            continue

        candidate_center = np.array([
            float(
                profile[
                    'x'
                ][
                    idx
                ]
            ),
            float(
                profile[
                    'y'
                ][
                    idx
                ]
            ),
        ])

        displacement = (
            candidate_center
            - neck_center
        )

        signed_plane_distance = float(
            body_sign
            * np.dot(
                displacement,
                neck_tangent,
            )
        )

        # Candidate must genuinely lie on the BODY side of the
        # neck cross-section.
        if (
            signed_plane_distance
            <= 0.0
        ):
            continue

        plane_distance = float(
            signed_plane_distance
        )

        euclidean_distance = float(
            np.linalg.norm(
                displacement
            )
        )

        inward_distance_ratio = float(
            plane_distance
            / candidate_radius
        )

        if (
            inward_distance_ratio
            < NECK_ANCHOR_MIN_INWARD_DISTANCE_RADIUS_RATIO
            or inward_distance_ratio
            > NECK_ANCHOR_MAX_INWARD_DISTANCE_RADIUS_RATIO
        ):
            continue

        tangency_error_ratio = float(
            abs(
                plane_distance
                - candidate_radius
            )
            / candidate_radius
        )

        if (
            tangency_error_ratio
            > NECK_ANCHOR_MAX_TANGENCY_ERROR_RATIO
        ):
            continue

        tangency_score = float(
            np.clip(
                1.0
                - tangency_error_ratio
                / max(
                    NECK_ANCHOR_MAX_TANGENCY_ERROR_RATIO,
                    1e-6,
                ),
                0.0,
                1.0,
            )
        )

        local_width_score = _local_radius_support_score(
            profile,
            idx,
        )

        score = float(
            NECK_ANCHOR_TANGENCY_WEIGHT
            * tangency_score
            + NECK_ANCHOR_RADIUS_WEIGHT
            * radius_ratio_to_max
            + NECK_ANCHOR_LOCAL_WIDTH_WEIGHT
            * local_width_score
        )

        projection_point = (
            candidate_center
            - np.dot(
                displacement,
                neck_tangent,
            )
            * neck_tangent
        )

        # Where the candidate circle reaches toward the neck
        # along the neck-plane normal.
        circle_neck_edge = (
            candidate_center
            - body_sign
            * candidate_radius
            * neck_tangent
        )

        records.append({
            'index': idx,

            'plane_distance_to_neck_px': plane_distance,
            'euclidean_distance_to_neck_px': euclidean_distance,

            # Keep legacy field name for downstream displays,
            # but it now means neck-PLANE distance.
            'distance_to_neck_px': plane_distance,

            'inward_distance_ratio': inward_distance_ratio,

            'candidate_radius': candidate_radius,
            'radius_ratio_to_max': radius_ratio_to_max,

            'tangency_error_ratio': tangency_error_ratio,
            'tangency_score': tangency_score,

            'local_width_score': local_width_score,
            'score': score,

            'neck_plane_projection_x': float(
                projection_point[
                    0
                ]
            ),
            'neck_plane_projection_y': float(
                projection_point[
                    1
                ]
            ),

            'circle_neck_edge_x': float(
                circle_neck_edge[
                    0
                ]
            ),
            'circle_neck_edge_y': float(
                circle_neck_edge[
                    1
                ]
            ),
        })

    if not records:
        return None

    return max(
        records,
        key=lambda row: row[
            'score'
        ],
    )


def _ordered_terminal_indices(
    n,
    start_index,
    side,
):
    if side == 'right':
        return np.arange(
            int(
                start_index
            ),
            n,
            dtype=int,
        )

    if side == 'left':
        return np.arange(
            int(
                start_index
            ),
            -1,
            -1,
            dtype=int,
        )

    raise ValueError(
        side
    )


def _bodyward_indices_within_distance(
    profile,
    index,
    side,
    distance_px,
):
    arc = profile[
        'u'
    ]

    idx = int(
        index
    )

    if side == 'right':
        # Body is toward lower index.
        eligible = np.where(
            (
                arc
                < arc[
                    idx
                ]
            )
            & (
                (
                    arc[
                        idx
                    ]
                    - arc
                )
                <= distance_px
            )
        )[0]

    elif side == 'left':
        # Body is toward higher index.
        eligible = np.where(
            (
                arc
                > arc[
                    idx
                ]
            )
            & (
                (
                    arc
                    - arc[
                        idx
                    ]
                )
                <= distance_px
            )
        )[0]

    else:
        raise ValueError(
            side
        )

    return eligible


def _terminalward_indices_within_distance(
    profile,
    index,
    side,
    distance_px,
    endpoint_guard,
):
    arc = profile[
        'u'
    ]

    idx = int(
        index
    )

    if side == 'right':
        eligible = np.where(
            (
                arc
                >= arc[
                    idx
                ]
            )
            & (
                (
                    arc
                    - arc[
                        idx
                    ]
                )
                <= distance_px
            )
            & (
                np.arange(
                    len(
                        arc
                    )
                )
                <= (
                    len(
                        arc
                    )
                    - 1
                    - endpoint_guard
                )
            )
        )[0]

        return np.sort(
            eligible
        )

    if side == 'left':
        eligible = np.where(
            (
                arc
                <= arc[
                    idx
                ]
            )
            & (
                (
                    arc[
                        idx
                    ]
                    - arc
                )
                <= distance_px
            )
            & (
                np.arange(
                    len(
                        arc
                    )
                )
                >= endpoint_guard
            )
        )[0]

        return np.sort(
            eligible
        )[
            ::-1
        ]

    raise ValueError(
        side
    )


def _refine_actual_neck_index(
    profile,
    cross_section,
    side,
    closure_run,
    endpoint_guard,
):
    '''
    The closure run begins body-side of the true neck because
    its members can see narrowing ahead.

    Starting from that run, find the actual local constriction
    on the dominant closing side.
    '''
    radius = profile[
        'radius'
    ]

    plus = cross_section[
        'plus_smooth'
    ]

    minus = cross_section[
        'minus_smooth'
    ]

    width = cross_section[
        'total_width_smooth'
    ]

    run_records = []

    for idx in closure_run:
        rec = _cross_section_drop_record(
            profile,
            cross_section,
            int(
                idx
            ),
            side,
        )

        if rec is not None:
            run_records.append(
                rec
            )

    if not run_records:
        return None

    mean_plus_drop = float(
        np.mean([
            r[
                'plus_drop_ratio'
            ]
            for r in run_records
        ])
    )

    mean_minus_drop = float(
        np.mean([
            r[
                'minus_drop_ratio'
            ]
            for r in run_records
        ])
    )

    dominant_side = (
        'plus'
        if mean_plus_drop
        >= mean_minus_drop
        else 'minus'
    )

    side_profile = (
        plus
        if dominant_side
        == 'plus'
        else minus
    )

    closure_start = int(
        closure_run[
            0
        ]
    )

    start_radius = max(
        float(
            radius[
                closure_start
            ]
        ),
        1e-6,
    )

    body_baseline_indices = _bodyward_indices_within_distance(
        profile,
        closure_start,
        side,
        (
            NECK_REFINE_BODY_BASELINE_RADIUS_RATIO
            * start_radius
        ),
    )

    if len(
        body_baseline_indices
    ) >= 2:
        side_baseline = float(
            np.median(
                side_profile[
                    body_baseline_indices
                ]
            )
        )

        width_baseline = float(
            np.median(
                width[
                    body_baseline_indices
                ]
            )
        )

    else:
        side_baseline = float(
            side_profile[
                closure_start
            ]
        )

        width_baseline = float(
            width[
                closure_start
            ]
        )

    side_baseline = max(
        side_baseline,
        1e-6,
    )

    width_baseline = max(
        width_baseline,
        1e-6,
    )

    search_indices = _terminalward_indices_within_distance(
        profile,
        closure_start,
        side,
        (
            NECK_REFINE_MAX_DISTANCE_RADIUS_RATIO
            * start_radius
        ),
        endpoint_guard,
    )

    if len(
        search_indices
    ) < 3:
        return None

    search_values = side_profile[
        search_indices
    ]

    prominence_px = max(
        0.5,
        (
            NECK_REFINE_MIN_PROMINENCE_RATIO
            * side_baseline
        ),
    )

    minima_positions, properties = find_peaks(
        -search_values,
        prominence=prominence_px,
    )

    candidates = []

    for pos in minima_positions:
        pos = int(
            pos
        )

        idx = int(
            search_indices[
                pos
            ]
        )

        side_value = max(
            float(
                side_profile[
                    idx
                ]
            ),
            1e-6,
        )

        width_value = max(
            float(
                width[
                    idx
                ]
            ),
            1e-6,
        )

        side_constriction = float(
            max(
                0.0,
                (
                    side_baseline
                    - side_value
                )
                / side_baseline,
            )
        )

        width_constriction = float(
            max(
                0.0,
                (
                    width_baseline
                    - width_value
                )
                / width_baseline,
            )
        )

        if (
            side_constriction
            < NECK_REFINE_MIN_SIDE_CONSTRICTION_RATIO
            or width_constriction
            < NECK_REFINE_MIN_WIDTH_CONSTRICTION_RATIO
        ):
            continue

        # Re-expansion toward the terminal side supports a real
        # neck before a head/lobe.
        after = search_values[
            pos
            + 1:
        ]

        if len(
            after
        ) > 0:
            reexpansion_ratio = float(
                max(
                    0.0,
                    (
                        float(
                            np.max(
                                after
                            )
                        )
                        - side_value
                    )
                    / side_baseline,
                )
            )
        else:
            reexpansion_ratio = 0.0

        prominence_ratio = float(
            properties[
                'prominences'
            ][
                list(
                    minima_positions
                ).index(
                    pos
                )
            ]
            / side_baseline
        )

        # Prefer first meaningful local neck, while allowing
        # re-expansion and prominence to strengthen the score.
        normalized_position = float(
            pos
            / max(
                len(
                    search_indices
                )
                - 1,
                1,
            )
        )

        score = float(
            0.46
            * side_constriction
            + 0.24
            * width_constriction
            + 0.18
            * min(
                prominence_ratio,
                1.0,
            )
            + NECK_REFINE_REEXPANSION_BONUS_WEIGHT
            * min(
                reexpansion_ratio,
                1.0,
            )
            - 0.08
            * normalized_position
        )

        candidates.append({
            'index': idx,
            'method': 'first_local_constriction',
            'dominant_closing_side': dominant_side,

            'side_baseline_px': side_baseline,
            'width_baseline_px': width_baseline,

            'side_value_px': side_value,
            'width_value_px': width_value,

            'side_constriction_ratio': side_constriction,
            'width_constriction_ratio': width_constriction,
            'reexpansion_ratio': reexpansion_ratio,
            'prominence_ratio': prominence_ratio,

            'score': score,
        })

    if candidates:
        # First real local constriction is primary. Among
        # essentially neighboring minima, score resolves ties.
        candidates = sorted(
            candidates,
            key=lambda row: (
                int(
                    np.where(
                        search_indices
                        == row[
                            'index'
                        ]
                    )[0][0]
                ),
                -row[
                    'score'
                ],
            ),
        )

        first_position = int(
            np.where(
                search_indices
                == candidates[
                    0
                ][
                    'index'
                ]
            )[0][0]
        )

        nearby = [
            row
            for row in candidates
            if int(
                np.where(
                    search_indices
                    == row[
                        'index'
                    ]
                )[0][0]
            )
            <= (
                first_position
                + 3
            )
        ]

        return max(
            nearby,
            key=lambda row: row[
                'score'
            ],
        )

    # --------------------------------------------------------
    # Fallback:
    # strongest bounded constriction, not terminal endpoint.
    # --------------------------------------------------------

    fallback = []

    for pos, idx in enumerate(
        search_indices
    ):
        idx = int(
            idx
        )

        side_value = max(
            float(
                side_profile[
                    idx
                ]
            ),
            1e-6,
        )

        width_value = max(
            float(
                width[
                    idx
                ]
            ),
            1e-6,
        )

        side_constriction = float(
            max(
                0.0,
                (
                    side_baseline
                    - side_value
                )
                / side_baseline,
            )
        )

        width_constriction = float(
            max(
                0.0,
                (
                    width_baseline
                    - width_value
                )
                / width_baseline,
            )
        )

        if (
            side_constriction
            < NECK_REFINE_MIN_SIDE_CONSTRICTION_RATIO
            or width_constriction
            < NECK_REFINE_MIN_WIDTH_CONSTRICTION_RATIO
        ):
            continue

        normalized_position = float(
            pos
            / max(
                len(
                    search_indices
                )
                - 1,
                1,
            )
        )

        score = float(
            0.62
            * side_constriction
            + 0.30
            * width_constriction
            - NECK_REFINE_FALLBACK_DISTANCE_PENALTY
            * normalized_position
        )

        fallback.append({
            'index': idx,
            'method': 'bounded_strongest_constriction',
            'dominant_closing_side': dominant_side,

            'side_baseline_px': side_baseline,
            'width_baseline_px': width_baseline,

            'side_value_px': side_value,
            'width_value_px': width_value,

            'side_constriction_ratio': side_constriction,
            'width_constriction_ratio': width_constriction,
            'reexpansion_ratio': 0.0,
            'prominence_ratio': 0.0,

            'score': score,
        })

    if not fallback:
        return None

    return max(
        fallback,
        key=lambda row: row[
            'score'
        ],
    )


def _detect_neck_station_for_side(
    profile,
    cross_section,
    side,
):
    '''
    Stage 1:
        find the first sustained CLOSURE REGION.

    Stage 2:
        refine the ACTUAL NECK inside that region by finding
        the real local constriction on the dominant closing
        mask side.
    '''
    n = len(
        profile[
            'radius'
        ]
    )

    un = profile[
        'u_normalized'
    ]

    radius_profile = profile[
        'radius'
    ]

    max_radius = max(
        float(
            np.max(
                radius_profile
            )
        ),
        1e-6,
    )

    endpoint_guard = max(
        1,
        int(
            round(
                CROSS_SECTION_ENDPOINT_PROTECTION_FRACTION
                * n
            )
        ),
    )

    if side == 'right':
        candidate_indices = [
            int(
                i
            )
            for i in range(
                n
            )
            if (
                un[
                    i
                ]
                >= (
                    1.0
                    - CROSS_SECTION_TERMINAL_SEARCH_FRACTION
                )
                and i
                <= (
                    n
                    - 1
                    - endpoint_guard
                )
            )
        ]

        ordered = sorted(
            candidate_indices
        )

    elif side == 'left':
        candidate_indices = [
            int(
                i
            )
            for i in range(
                n
            )
            if (
                un[
                    i
                ]
                <= CROSS_SECTION_TERMINAL_SEARCH_FRACTION
                and i
                >= endpoint_guard
            )
        ]

        ordered = sorted(
            candidate_indices,
            reverse=True,
        )

    else:
        raise ValueError(
            side
        )

    diagnostics = {}

    for idx in ordered:
        radius_ratio = float(
            radius_profile[
                idx
            ]
            / max_radius
        )

        if (
            radius_ratio
            < CROSS_SECTION_MIN_BODY_RADIUS_RATIO
        ):
            diagnostics[
                idx
            ] = {
                'qualifies': False,
            }
            continue

        record = _cross_section_drop_record(
            profile,
            cross_section,
            idx,
            side,
        )

        if record is None:
            diagnostics[
                idx
            ] = {
                'qualifies': False,
            }
            continue

        diagnostics[
            idx
        ] = record

    qualifies_by_index = {
        idx: bool(
            diagnostics.get(
                idx,
                {}
            ).get(
                'qualifies',
                False,
            )
        )
        for idx in ordered
    }

    runs = _true_runs_in_order(
        ordered,
        qualifies_by_index,
    )

    runs = [
        run
        for run in runs
        if len(
            run
        )
        >= int(
            CROSS_SECTION_MIN_SUSTAIN_POINTS
        )
    ]

    if not runs:
        return None

    closure_run = runs[
        0
    ]

    refined = _refine_actual_neck_index(
        profile,
        cross_section,
        side,
        closure_run,
        endpoint_guard,
    )

    if refined is None:
        return None

    neck_idx = int(
        refined[
            'index'
        ]
    )

    plus_point = cross_section[
        'plus_points'
    ][
        neck_idx
    ]

    minus_point = cross_section[
        'minus_points'
    ][
        neck_idx
    ]

    neck_tangent = np.asarray(
        cross_section[
            'tangent'
        ][
            neck_idx
        ],
        dtype=float,
    )

    neck_tangent /= max(
        float(
            np.linalg.norm(
                neck_tangent
            )
        ),
        1e-6,
    )

    neck_normal = np.asarray(
        cross_section[
            'normal'
        ][
            neck_idx
        ],
        dtype=float,
    )

    neck_normal /= max(
        float(
            np.linalg.norm(
                neck_normal
            )
        ),
        1e-6,
    )

    return {
        'neck_index': neck_idx,

        'neck_u': float(
            profile[
                'u_normalized'
            ][
                neck_idx
            ]
        ),

        'neck_arc_length': float(
            profile[
                'u'
            ][
                neck_idx
            ]
        ),

        'neck_side': side,

        'neck_detection_method': refined[
            'method'
        ],

        'dominant_closing_side': refined[
            'dominant_closing_side'
        ],

        'side_baseline_px': float(
            refined[
                'side_baseline_px'
            ]
        ),

        'width_baseline_px': float(
            refined[
                'width_baseline_px'
            ]
        ),

        'side_constriction_ratio': float(
            refined[
                'side_constriction_ratio'
            ]
        ),

        'width_constriction_ratio': float(
            refined[
                'width_constriction_ratio'
            ]
        ),

        'reexpansion_ratio': float(
            refined[
                'reexpansion_ratio'
            ]
        ),

        'prominence_ratio': float(
            refined[
                'prominence_ratio'
            ]
        ),

        'neck_score': float(
            refined[
                'score'
            ]
        ),

        'plus_x': float(
            plus_point[
                0
            ]
        ),
        'plus_y': float(
            plus_point[
                1
            ]
        ),

        'minus_x': float(
            minus_point[
                0
            ]
        ),
        'minus_y': float(
            minus_point[
                1
            ]
        ),

        'plus_distance_px': float(
            cross_section[
                'plus_distance'
            ][
                neck_idx
            ]
        ),

        'minus_distance_px': float(
            cross_section[
                'minus_distance'
            ][
                neck_idx
            ]
        ),

        'total_width_px': float(
            cross_section[
                'total_width'
            ][
                neck_idx
            ]
        ),

        'tangent_x': float(
            neck_tangent[
                0
            ]
        ),
        'tangent_y': float(
            neck_tangent[
                1
            ]
        ),

        'normal_x': float(
            neck_normal[
                0
            ]
        ),
        'normal_y': float(
            neck_normal[
                1
            ]
        ),

        'closure_run_start_index': int(
            closure_run[
                0
            ]
        ),

        'closure_run_end_index': int(
            closure_run[
                -1
            ]
        ),

        'closure_run_length': int(
            len(
                closure_run
            )
        ),
    }


def _neck_anchored_candidate_for_side(
    profile,
    cross_section,
    side,
):
    neck = _detect_neck_station_for_side(
        profile,
        cross_section,
        side,
    )

    if neck is None:
        return (
            None,
            None,
        )

    anchor = _find_body_anchor_for_neck(
        profile,
        cross_section,
        neck[
            'neck_index'
        ],
        side,
    )

    if anchor is None:
        return (
            None,
            neck,
        )

    anchor_idx = int(
        anchor[
            'index'
        ]
    )

    candidate = _candidate_record(
        profile,
        anchor_idx,
        source='neck_anchored_body_circle',
        prominence=0.0,
        is_endpoint_peak=False,
    )

    candidate.update({
        'neck_anchor_side': side,

        'neck_station_index': int(
            neck[
                'neck_index'
            ]
        ),
        'neck_station_u': float(
            neck[
                'neck_u'
            ]
        ),
        'neck_station_arc_length': float(
            neck[
                'neck_arc_length'
            ]
        ),

        'neck_station_plus_x': float(
            neck[
                'plus_x'
            ]
        ),
        'neck_station_plus_y': float(
            neck[
                'plus_y'
            ]
        ),
        'neck_station_minus_x': float(
            neck[
                'minus_x'
            ]
        ),
        'neck_station_minus_y': float(
            neck[
                'minus_y'
            ]
        ),

        # 06Q refines the neck using the dominant closing side,
        # so the old 06P per-side look-ahead keys no longer
        # necessarily exist. Keep the legacy diagnostic fields
        # safely populated without crashing decomposition.
        'neck_station_plus_drop_ratio': float(
            neck.get(
                'plus_drop_ratio',
                np.nan,
            )
        ),
        'neck_station_minus_drop_ratio': float(
            neck.get(
                'minus_drop_ratio',
                np.nan,
            )
        ),

        # These two now map directly to the refined actual-neck
        # constriction measurements.
        'neck_station_one_side_drop_ratio': float(
            neck.get(
                'side_constriction_ratio',
                0.0,
            )
        ),
        'neck_station_total_width_drop_ratio': float(
            neck.get(
                'width_constriction_ratio',
                0.0,
            )
        ),
        'neck_station_dominant_closing_side': neck[
            'dominant_closing_side'
        ],
        'neck_station_score': float(
            neck[
                'neck_score'
            ]
        ),

        'neck_detection_method': neck.get(
            'neck_detection_method'
        ),
        'neck_side_constriction_ratio': float(
            neck.get(
                'side_constriction_ratio',
                0.0,
            )
        ),
        'neck_width_constriction_ratio': float(
            neck.get(
                'width_constriction_ratio',
                0.0,
            )
        ),
        'neck_reexpansion_ratio': float(
            neck.get(
                'reexpansion_ratio',
                0.0,
            )
        ),
        'neck_prominence_ratio': float(
            neck.get(
                'prominence_ratio',
                0.0,
            )
        ),

        'anchor_distance_to_neck_px': float(
            anchor[
                'distance_to_neck_px'
            ]
        ),
        'anchor_plane_distance_to_neck_px': float(
            anchor[
                'plane_distance_to_neck_px'
            ]
        ),
        'anchor_euclidean_distance_to_neck_px': float(
            anchor[
                'euclidean_distance_to_neck_px'
            ]
        ),
        'anchor_distance_radius_ratio': float(
            anchor[
                'inward_distance_ratio'
            ]
        ),
        'anchor_tangency_error_ratio': float(
            anchor[
                'tangency_error_ratio'
            ]
        ),
        'anchor_tangency_score': float(
            anchor[
                'tangency_score'
            ]
        ),
        'anchor_radius_ratio_to_max': float(
            anchor[
                'radius_ratio_to_max'
            ]
        ),
        'anchor_local_width_score': float(
            anchor[
                'local_width_score'
            ]
        ),
        'anchor_score': float(
            anchor[
                'score'
            ]
        ),

        'neck_plane_projection_x': float(
            anchor[
                'neck_plane_projection_x'
            ]
        ),
        'neck_plane_projection_y': float(
            anchor[
                'neck_plane_projection_y'
            ]
        ),

        'circle_neck_edge_x': float(
            anchor[
                'circle_neck_edge_x'
            ]
        ),
        'circle_neck_edge_y': float(
            anchor[
                'circle_neck_edge_y'
            ]
        ),
    })

    return (
        candidate,
        neck,
    )


def generate_neck_anchored_body_candidates(
    mask,
    profile,
):
    cross_section = build_cross_section_profiles(
        mask,
        profile,
    )

    candidates = []
    neck_stations = []

    for side in [
        'left',
        'right',
    ]:
        (
            candidate,
            neck,
        ) = _neck_anchored_candidate_for_side(
            profile,
            cross_section,
            side,
        )

        if neck is not None:
            neck_stations.append(
                neck
            )

        if candidate is not None:
            candidates.append(
                candidate
            )

    return (
        sorted(
            candidates,
            key=lambda c: c[
                'index'
            ],
        ),
        sorted(
            neck_stations,
            key=lambda n: n[
                'neck_index'
            ],
        ),
        cross_section,
    )


def _add_neck_anchored_candidates_to_06n(
    base_candidates,
    neck_candidates,
):
    merged = [
        c.copy()
        for c in base_candidates
    ]

    for new_candidate in neck_candidates:
        duplicate_idx = None

        for k, existing in enumerate(
            merged
        ):
            smaller_r = max(
                min(
                    float(
                        new_candidate[
                            'radius'
                        ]
                    ),
                    float(
                        existing[
                            'radius'
                        ]
                    ),
                ),
                1e-6,
            )

            larger_r = max(
                float(
                    new_candidate[
                        'radius'
                    ]
                ),
                float(
                    existing[
                        'radius'
                    ]
                ),
                1e-6,
            )

            radius_similarity = float(
                smaller_r
                / larger_r
            )

            arc_gap = abs(
                float(
                    new_candidate[
                        'arc_length'
                    ]
                )
                - float(
                    existing[
                        'arc_length'
                    ]
                )
            )

            if (
                arc_gap
                <= (
                    NECK_ANCHOR_DUP_ARC_RADIUS_RATIO
                    * smaller_r
                )
                and radius_similarity
                >= NECK_ANCHOR_DUP_MIN_RADIUS_SIMILARITY
            ):
                duplicate_idx = int(
                    k
                )
                break

        if duplicate_idx is None:
            merged.append(
                new_candidate.copy()
            )

        else:
            # Keep original 06N geometry; attach neck-anchor
            # evidence so diagnostics still show why it was
            # supported.
            existing = merged[
                duplicate_idx
            ].copy()

            existing[
                'neck_anchor_support'
            ] = True

            for key, value in new_candidate.items():
                if (
                    key.startswith(
                        'neck_'
                    )
                    or key.startswith(
                        'anchor_'
                    )
                ):
                    existing[
                        key
                    ] = value

            merged[
                duplicate_idx
            ] = existing

    return sorted(
        merged,
        key=lambda c: (
            c[
                'index'
            ],
            c[
                'radius'
            ],
        ),
    )


def generate_circle_candidates(
    mask,
    profile,
):
    sharp = generate_sharp_peak_candidates(
        profile
    )

    broad = generate_broad_region_candidates(
        profile
    )

    # Exact original 06N merged set.
    merged_06n = merge_lobe_candidates(
        profile,
        sharp,
        broad,
    )

    (
        neck_candidates,
        neck_stations,
        cross_section_profile,
    ) = generate_neck_anchored_body_candidates(
        mask,
        profile,
    )

    merged = _add_neck_anchored_candidates_to_06n(
        merged_06n,
        neck_candidates,
    )

    return (
        merged,
        sharp,
        broad,
        neck_candidates,
        neck_stations,
        cross_section_profile,
    )


def _arc_window_indices(
    profile,
    center_idx,
    min_distance_px,
    max_distance_px,
    side,
):
    arc = profile[
        'u'
    ]

    center_arc = float(
        arc[
            int(
                center_idx
            )
        ]
    )

    if side == 'left':
        distance = (
            center_arc
            - arc
        )
    elif side == 'right':
        distance = (
            arc
            - center_arc
        )
    else:
        raise ValueError(
            side
        )

    return np.where(
        (
            distance
            >= float(
                min_distance_px
            )
        )
        & (
            distance
            <= float(
                max_distance_px
            )
        )
    )[0]


def _candidate_neck_diagnostics(
    profile,
    candidate,
):
    radius = profile[
        'radius'
    ]

    idx = int(
        candidate[
            'index'
        ]
    )

    r = max(
        float(
            candidate[
                'radius'
            ]
        ),
        1e-6,
    )

    min_distance = (
        NECK_CONTEXT_INNER_RADIUS_RATIO
        * r
    )

    max_distance = (
        NECK_CONTEXT_OUTER_RADIUS_RATIO
        * r
    )

    left_indices = _arc_window_indices(
        profile,
        idx,
        min_distance,
        max_distance,
        'left',
    )

    right_indices = _arc_window_indices(
        profile,
        idx,
        min_distance,
        max_distance,
        'right',
    )

    if (
        len(
            left_indices
        )
        < 2
        or len(
            right_indices
        )
        < 2
    ):
        return {
            'neck_context_valid': False,
            'neck_left_reference_radius': np.nan,
            'neck_right_reference_radius': np.nan,
            'neck_reference_radius': np.nan,
            'neck_drop_ratio': 0.0,
            'neck_score': 0.0,
            'neck_suspect': False,
        }

    left_reference = float(
        np.percentile(
            radius[
                left_indices
            ],
            NECK_CONTEXT_PERCENTILE,
        )
    )

    right_reference = float(
        np.percentile(
            radius[
                right_indices
            ],
            NECK_CONTEXT_PERCENTILE,
        )
    )

    reference = max(
        min(
            left_reference,
            right_reference,
        ),
        1e-6,
    )

    drop_ratio = float(
        max(
            0.0,
            (
                reference
                - r
            )
            / reference,
        )
    )

    # At the suspicion threshold, score ~= 0.5.
    score = float(
        np.clip(
            drop_ratio
            / max(
                2.0
                * NECK_SUSPECT_DROP_RATIO,
                1e-6,
            ),
            0.0,
            1.0,
        )
    )

    suspect = bool(
        drop_ratio
        >= NECK_SUSPECT_DROP_RATIO
    )

    return {
        'neck_context_valid': True,
        'neck_left_reference_radius': left_reference,
        'neck_right_reference_radius': right_reference,
        'neck_reference_radius': reference,
        'neck_drop_ratio': drop_ratio,
        'neck_score': score,
        'neck_suspect': suspect,
    }


def _terminal_pair_diagnostics(
    profile,
    outer,
    inner,
    side,
):
    radius = profile[
        'radius'
    ]

    arc = profile[
        'u'
    ]

    outer_idx = int(
        outer[
            'index'
        ]
    )

    inner_idx = int(
        inner[
            'index'
        ]
    )

    outer_r = max(
        float(
            outer[
                'radius'
            ]
        ),
        1e-6,
    )

    inner_r = max(
        float(
            inner[
                'radius'
            ]
        ),
        1e-6,
    )

    smaller_r = max(
        min(
            outer_r,
            inner_r,
        ),
        1e-6,
    )

    pair_arc_distance = abs(
        float(
            arc[
                outer_idx
            ]
        )
        - float(
            arc[
                inner_idx
            ]
        )
    )

    if (
        pair_arc_distance
        < (
            TERMINAL_EXTRA_MIN_PAIR_ARC_RADIUS_RATIO
            * smaller_r
        )
    ):
        return {
            'terminal_test_valid': False,
            'terminal_side': side,
            'terminal_inward_candidate_index': inner_idx,
            'terminal_pair_arc_distance_px': pair_arc_distance,
            'terminal_valley_index': None,
            'terminal_valley_radius': np.nan,
            'terminal_recess_drop_ratio': 0.0,
            'terminal_reexpansion_ratio': 0.0,
            'terminal_extra_score': 0.0,
            'terminal_extra_suspect': False,
            'terminal_extra_high_confidence': False,
        }

    lo_idx = min(
        outer_idx,
        inner_idx,
    )

    hi_idx = max(
        outer_idx,
        inner_idx,
    )

    left_arc = float(
        arc[
            lo_idx
        ]
    )

    right_arc = float(
        arc[
            hi_idx
        ]
    )

    margin = (
        TERMINAL_VALLEY_END_MARGIN_RADIUS_RATIO
        * smaller_r
    )

    interior = np.where(
        (
            arc
            >= (
                left_arc
                + margin
            )
        )
        & (
            arc
            <= (
                right_arc
                - margin
            )
        )
    )[0]

    if len(
        interior
    ) < 2:
        interior = np.arange(
            lo_idx
            + 1,
            hi_idx,
            dtype=int,
        )

    if len(
        interior
    ) < 1:
        return {
            'terminal_test_valid': False,
            'terminal_side': side,
            'terminal_inward_candidate_index': inner_idx,
            'terminal_pair_arc_distance_px': pair_arc_distance,
            'terminal_valley_index': None,
            'terminal_valley_radius': np.nan,
            'terminal_recess_drop_ratio': 0.0,
            'terminal_reexpansion_ratio': 0.0,
            'terminal_extra_score': 0.0,
            'terminal_extra_suspect': False,
            'terminal_extra_high_confidence': False,
        }

    valley_idx = int(
        interior[
            int(
                np.argmin(
                    radius[
                        interior
                    ]
                )
            )
        ]
    )

    valley_radius = float(
        radius[
            valley_idx
        ]
    )

    recess_drop_ratio = float(
        max(
            0.0,
            (
                smaller_r
                - valley_radius
            )
            / smaller_r,
        )
    )

    reexpansion_ratio = float(
        max(
            0.0,
            (
                outer_r
                - valley_radius
            )
            / smaller_r,
        )
    )

    drop_score = float(
        np.clip(
            recess_drop_ratio
            / max(
                2.0
                * TERMINAL_EXTRA_MIN_RECESS_DROP_RATIO,
                1e-6,
            ),
            0.0,
            1.0,
        )
    )

    reexpansion_score = float(
        np.clip(
            reexpansion_ratio
            / max(
                2.0
                * TERMINAL_EXTRA_MIN_REEXPANSION_RATIO,
                1e-6,
            ),
            0.0,
            1.0,
        )
    )

    score = float(
        min(
            drop_score,
            reexpansion_score,
        )
    )

    suspect = bool(
        recess_drop_ratio
        >= TERMINAL_EXTRA_MIN_RECESS_DROP_RATIO
        and reexpansion_ratio
        >= TERMINAL_EXTRA_MIN_REEXPANSION_RATIO
        and score
        >= TERMINAL_EXTRA_SUSPECT_SCORE
    )

    high_confidence = bool(
        suspect
        and score
        >= TERMINAL_EXTRA_HIGH_CONFIDENCE_SCORE
    )

    return {
        'terminal_test_valid': True,
        'terminal_side': side,
        'terminal_inward_candidate_index': inner_idx,
        'terminal_pair_arc_distance_px': pair_arc_distance,
        'terminal_valley_index': valley_idx,
        'terminal_valley_radius': valley_radius,
        'terminal_recess_drop_ratio': recess_drop_ratio,
        'terminal_reexpansion_ratio': reexpansion_ratio,
        'terminal_extra_score': score,
        'terminal_extra_suspect': suspect,
        'terminal_extra_high_confidence': high_confidence,
    }


def classify_circle_candidates(
    profile,
    candidates,
):
    '''
    IMPORTANT:
    only annotate copies of the 06N candidates.

    x, y, radius, index, u and candidate construction are not
    modified.
    '''
    classified = [
        c.copy()
        for c in candidates
    ]

    if not classified:
        return classified

    for c in classified:
        c.update(
            _candidate_neck_diagnostics(
                profile,
                c,
            )
        )

        c.update({
            'terminal_test_valid': False,
            'terminal_side': None,
            'terminal_inward_candidate_index': None,
            'terminal_pair_arc_distance_px': 0.0,
            'terminal_valley_index': None,
            'terminal_valley_radius': np.nan,
            'terminal_recess_drop_ratio': 0.0,
            'terminal_reexpansion_ratio': 0.0,
            'terminal_extra_score': 0.0,
            'terminal_extra_suspect': False,
            'terminal_extra_high_confidence': False,
        })

    ordered_positions = sorted(
        range(
            len(
                classified
            )
        ),
        key=lambda k: classified[
            k
        ][
            'index'
        ],
    )

    if (
        ENABLE_LOCAL_CANDIDATE_CLASSIFICATION
        and len(
            ordered_positions
        )
        >= TERMINAL_EXTRA_MIN_CANDIDATES
    ):
        left_outer_pos = ordered_positions[
            0
        ]

        left_inner_pos = ordered_positions[
            1
        ]

        right_outer_pos = ordered_positions[
            -1
        ]

        right_inner_pos = ordered_positions[
            -2
        ]

        left_outer = classified[
            left_outer_pos
        ]

        right_outer = classified[
            right_outer_pos
        ]

        if (
            float(
                left_outer[
                    'u'
                ]
            )
            <= TERMINAL_EXTRA_ZONE_FRACTION
        ):
            classified[
                left_outer_pos
            ].update(
                _terminal_pair_diagnostics(
                    profile,
                    classified[
                        left_outer_pos
                    ],
                    classified[
                        left_inner_pos
                    ],
                    'left',
                )
            )

        if (
            float(
                right_outer[
                    'u'
                ]
            )
            >= (
                1.0
                - TERMINAL_EXTRA_ZONE_FRACTION
            )
        ):
            classified[
                right_outer_pos
            ].update(
                _terminal_pair_diagnostics(
                    profile,
                    classified[
                        right_outer_pos
                    ],
                    classified[
                        right_inner_pos
                    ],
                    'right',
                )
            )

    for c in classified:
        neck = bool(
            c.get(
                'neck_suspect',
                False,
            )
        )

        terminal = bool(
            c.get(
                'terminal_extra_suspect',
                False,
            )
        )

        if neck and terminal:
            candidate_class = (
                'neck+terminal_extra_suspect'
            )
        elif terminal:
            candidate_class = (
                'terminal_extra_suspect'
            )
        elif neck:
            candidate_class = (
                'neck_suspect'
            )
        else:
            candidate_class = (
                'body_candidate'
            )

        neck_score = float(
            c.get(
                'neck_score',
                0.0,
            )
        )

        terminal_score = float(
            c.get(
                'terminal_extra_score',
                0.0,
            )
        )

        c[
            'candidate_class'
        ] = candidate_class

        c[
            'body_pair_penalty'
        ] = float(
            PAIR_NECK_PENALTY_WEIGHT
            * neck_score
            + PAIR_TERMINAL_EXTRA_PENALTY_WEIGHT
            * terminal_score
        )

    return classified


def _choose_body_circle_pair_fixed06q(
    profile,
    candidates,
):
    radius = profile[
        'radius'
    ]

    total_arc = max(
        float(
            profile[
                'total_length'
            ]
        ),
        1e-6,
    )

    max_radius = max(
        float(
            np.max(
                radius
            )
        ),
        1e-6,
    )

    max_prominence = max(
        [
            float(
                c.get(
                    'prominence',
                    0.0,
                )
            )
            for c in candidates
        ]
        + [
            1e-6
        ]
    )

    records = []

    for i in range(
        len(
            candidates
        )
    ):
        for j in range(
            i
            + 1,
            len(
                candidates
            ),
        ):
            a = candidates[
                i
            ]

            b = candidates[
                j
            ]

            if (
                a[
                    'index'
                ]
                > b[
                    'index'
                ]
            ):
                a, b = b, a

            r_small = float(
                min(
                    a[
                        'radius'
                    ],
                    b[
                        'radius'
                    ],
                )
            )

            r_large = float(
                max(
                    a[
                        'radius'
                    ],
                    b[
                        'radius'
                    ],
                )
            )

            radius_similarity = float(
                r_small
                / max(
                    r_large,
                    1e-6,
                )
            )

            arc_distance = float(
                b[
                    'arc_length'
                ]
                - a[
                    'arc_length'
                ]
            )

            normalized_arc_separation = float(
                arc_distance
                / total_arc
            )

            center_distance = float(
                np.hypot(
                    b[
                        'x'
                    ]
                    - a[
                        'x'
                    ],
                    b[
                        'y'
                    ]
                    - a[
                        'y'
                    ],
                )
            )

            edge_gap = float(
                center_distance
                - (
                    a[
                        'radius'
                    ]
                    + b[
                        'radius'
                    ]
                )
            )

            required_edge_gap = float(
                CIRCLE_EDGE_GAP_RADIUS_FRACTION
                * r_small
            )

            shaft = radius[
                int(
                    a[
                        'index'
                    ]
                ):
                int(
                    b[
                        'index'
                    ]
                )
                + 1
            ]

            shaft_floor = float(
                np.percentile(
                    shaft,
                    SHAFT_LOW_PERCENTILE,
                )
            )

            shaft_median = float(
                np.median(
                    shaft
                )
            )

            shaft_floor_ratio = float(
                shaft_floor
                / max(
                    r_small,
                    1e-6,
                )
            )

            shaft_median_ratio = float(
                shaft_median
                / max(
                    r_small,
                    1e-6,
                )
            )

            # ------------------------------------------------
            # ORIGINAL 06N HARD RULES — unchanged.
            # ------------------------------------------------

            size_ok = bool(
                radius_similarity
                >= MIN_PAIR_RADIUS_SIMILARITY
            )

            arc_ok = bool(
                normalized_arc_separation
                >= MIN_PAIR_ARC_SEPARATION_FRACTION
            )

            gap_ok = bool(
                edge_gap
                >= required_edge_gap
            )

            shaft_floor_ok = bool(
                shaft_floor_ratio
                >= MIN_SHAFT_FLOOR_RATIO
            )

            shaft_median_ok = bool(
                shaft_median_ratio
                >= MIN_SHAFT_MEDIAN_RATIO
            )

            violations = []

            if not size_ok:
                violations.append(
                    'radius_similarity_below_80pct'
                )

            if not arc_ok:
                violations.append(
                    'insufficient_arc_separation'
                )

            if not gap_ok:
                violations.append(
                    'edge_gap_below_full_smaller_radius'
                )

            if not shaft_floor_ok:
                violations.append(
                    'deep_neck_between_pair'
                )

            if not shaft_median_ok:
                violations.append(
                    'connecting_body_too_narrow'
                )

            valid = bool(
                len(
                    violations
                )
                == 0
            )

            average_radius_ratio = float(
                (
                    a[
                        'radius'
                    ]
                    + b[
                        'radius'
                    ]
                )
                / (
                    2.0
                    * max_radius
                )
            )

            shaft_quality = float(
                min(
                    shaft_floor_ratio,
                    1.20,
                )
            )

            prominence_score = float(
                (
                    a.get(
                        'prominence',
                        0.0,
                    )
                    + b.get(
                        'prominence',
                        0.0,
                    )
                )
                / (
                    2.0
                    * max_prominence
                )
            )

            broad_support_score = float(
                (
                    a.get(
                        'broad_support_score',
                        0.0,
                    )
                    + b.get(
                        'broad_support_score',
                        0.0,
                    )
                )
                / 2.0
            )

            same_plateau_caps = bool(
                a.get(
                    'broad_region_kind'
                )
                == 'long_plateau'
                and b.get(
                    'broad_region_kind'
                )
                == 'long_plateau'
                and a.get(
                    'broad_region_id'
                )
                is not None
                and a.get(
                    'broad_region_id'
                )
                == b.get(
                    'broad_region_id'
                )
                and {
                    a.get(
                        'broad_role'
                    ),
                    b.get(
                        'broad_role'
                    ),
                }
                == {
                    'left_cap',
                    'right_cap',
                }
            )

            same_plateau_score = float(
                1.0
                if same_plateau_caps
                else 0.0
            )

            # ------------------------------------------------
            # ORIGINAL 06N score.
            # ------------------------------------------------

            base_score = float(
                PAIR_RADIUS_WEIGHT
                * average_radius_ratio
                + PAIR_SIMILARITY_WEIGHT
                * radius_similarity
                + PAIR_SEPARATION_WEIGHT
                * normalized_arc_separation
                + PAIR_SHAFT_WEIGHT
                * shaft_quality
                + PAIR_PROMINENCE_WEIGHT
                * prominence_score
                + PAIR_BROAD_SUPPORT_WEIGHT
                * broad_support_score
                + PAIR_SAME_PLATEAU_WEIGHT
                * same_plateau_score
            )

            left_neck_score = float(
                a.get(
                    'neck_score',
                    0.0,
                )
            )

            right_neck_score = float(
                b.get(
                    'neck_score',
                    0.0,
                )
            )

            left_terminal_score = float(
                a.get(
                    'terminal_extra_score',
                    0.0,
                )
            )

            right_terminal_score = float(
                b.get(
                    'terminal_extra_score',
                    0.0,
                )
            )

            neck_penalty = float(
                PAIR_NECK_PENALTY_WEIGHT
                * (
                    left_neck_score
                    + right_neck_score
                )
            )

            terminal_penalty = float(
                PAIR_TERMINAL_EXTRA_PENALTY_WEIGHT
                * (
                    left_terminal_score
                    + right_terminal_score
                )
            )

            local_penalty = float(
                neck_penalty
                + terminal_penalty
            )

            left_anchor_score = float(
                a.get(
                    'anchor_score',
                    0.0,
                )
                if (
                    a.get(
                        'candidate_source'
                    )
                    == 'neck_anchored_body_circle'
                    or a.get(
                        'neck_anchor_support',
                        False,
                    )
                )
                else 0.0
            )

            right_anchor_score = float(
                b.get(
                    'anchor_score',
                    0.0,
                )
                if (
                    b.get(
                        'candidate_source'
                    )
                    == 'neck_anchored_body_circle'
                    or b.get(
                        'neck_anchor_support',
                        False,
                    )
                )
                else 0.0
            )

            neck_anchor_bonus = float(
                PAIR_NECK_ANCHOR_BONUS_WEIGHT
                * (
                    left_anchor_score
                    + right_anchor_score
                )
            )

            adjusted_score = float(
                base_score
                - local_penalty
                + neck_anchor_bonus
            )

            contains_high_conf_terminal_extra = bool(
                a.get(
                    'terminal_extra_high_confidence',
                    False,
                )
                or b.get(
                    'terminal_extra_high_confidence',
                    False,
                )
            )

            # ------------------------------------------------
            # Diagnostic closeness for hard-rule failures.
            # ------------------------------------------------

            size_deficit = max(
                0.0,
                (
                    MIN_PAIR_RADIUS_SIMILARITY
                    - radius_similarity
                )
                / max(
                    MIN_PAIR_RADIUS_SIMILARITY,
                    1e-6,
                ),
            )

            arc_deficit = max(
                0.0,
                (
                    MIN_PAIR_ARC_SEPARATION_FRACTION
                    - normalized_arc_separation
                )
                / max(
                    MIN_PAIR_ARC_SEPARATION_FRACTION,
                    1e-6,
                ),
            )

            gap_deficit = max(
                0.0,
                (
                    required_edge_gap
                    - edge_gap
                )
                / max(
                    required_edge_gap,
                    1e-6,
                ),
            )

            floor_deficit = max(
                0.0,
                (
                    MIN_SHAFT_FLOOR_RATIO
                    - shaft_floor_ratio
                )
                / max(
                    MIN_SHAFT_FLOOR_RATIO,
                    1e-6,
                ),
            )

            median_deficit = max(
                0.0,
                (
                    MIN_SHAFT_MEDIAN_RATIO
                    - shaft_median_ratio
                )
                / max(
                    MIN_SHAFT_MEDIAN_RATIO,
                    1e-6,
                ),
            )

            failure_penalty = float(
                size_deficit
                + 0.35
                * arc_deficit
                + gap_deficit
                + floor_deficit
                + 0.5
                * median_deficit
            )

            diagnostic_score = float(
                base_score
                - 1.5
                * failure_penalty
                - local_penalty
                + neck_anchor_bonus
            )

            records.append({
                'left': a,
                'right': b,

                'valid': valid,

                'reason': (
                    None
                    if valid
                    else '; '.join(
                        violations
                    )
                ),

                'violations': violations,

                'size_ok': size_ok,
                'arc_ok': arc_ok,
                'gap_ok': gap_ok,
                'shaft_floor_ok': shaft_floor_ok,
                'shaft_median_ok': shaft_median_ok,

                'radius_similarity': radius_similarity,

                'center_distance_px': center_distance,
                'edge_gap_px': edge_gap,
                'required_edge_gap_px': required_edge_gap,

                'arc_distance_px': arc_distance,
                'normalized_arc_separation': normalized_arc_separation,

                'shaft_floor_ratio': shaft_floor_ratio,
                'shaft_median_ratio': shaft_median_ratio,

                'average_radius_ratio': average_radius_ratio,
                'prominence_score': prominence_score,
                'broad_support_score': broad_support_score,

                'same_plateau_caps': same_plateau_caps,
                'same_plateau_score': same_plateau_score,

                # Local-candidate diagnostics.
                'left_candidate_class': a.get(
                    'candidate_class'
                ),
                'right_candidate_class': b.get(
                    'candidate_class'
                ),

                'left_neck_score': left_neck_score,
                'right_neck_score': right_neck_score,

                'left_terminal_extra_score': left_terminal_score,
                'right_terminal_extra_score': right_terminal_score,

                'neck_penalty': neck_penalty,
                'terminal_penalty': terminal_penalty,
                'local_candidate_penalty': local_penalty,

                'left_neck_anchor_score': left_anchor_score,
                'right_neck_anchor_score': right_anchor_score,
                'neck_anchor_bonus': neck_anchor_bonus,

                'contains_high_conf_terminal_extra': (
                    contains_high_conf_terminal_extra
                ),

                'base_score': base_score,
                'adjusted_score': (
                    adjusted_score
                    if valid
                    else -np.inf
                ),

                'failure_penalty': failure_penalty,
                'diagnostic_score': diagnostic_score,

                # Keep "score" as the winner-facing score so
                # existing downstream diagnostics still work.
                'score': (
                    adjusted_score
                    if valid
                    else -np.inf
                ),

                'suppressed_by_safer_valid_pair': False,
            })

    valid_pairs = [
        row
        for row in records
        if row[
            'valid'
        ]
    ]

    if not valid_pairs:
        return (
            None,
            records,
        )

    safer_pairs = [
        row
        for row in valid_pairs
        if not row[
            'contains_high_conf_terminal_extra'
        ]
    ]

    if safer_pairs:
        winner_pool = safer_pairs

        for row in valid_pairs:
            if row[
                'contains_high_conf_terminal_extra'
            ]:
                row[
                    'suppressed_by_safer_valid_pair'
                ] = True
    else:
        winner_pool = valid_pairs

    best = max(
        winner_pool,
        key=lambda row: row[
            'adjusted_score'
        ],
    )

    return (
        best,
        records,
    )


def best_failed_pair(
    pair_records,
):
    rejected = [
        row
        for row in pair_records
        if not row.get(
            'valid',
            False,
        )
    ]

    if not rejected:
        return None

    return max(
        rejected,
        key=lambda row: row.get(
            'diagnostic_score',
            -np.inf,
        ),
    )


def local_centerline_tangent(
    profile,
    index,
):
    n = len(
        profile['x']
    )

    i0 = max(
        0,
        int(index) - 2,
    )

    i1 = min(
        n - 1,
        int(index) + 2,
    )

    dx = float(
        profile['x'][i1]
        - profile['x'][i0]
    )

    dy = float(
        profile['y'][i1]
        - profile['y'][i0]
    )

    norm = max(
        float(
            np.hypot(
                dx,
                dy,
            )
        ),
        1e-6,
    )

    return np.array([
        dx / norm,
        dy / norm,
    ])


def circle_geometry(
    profile,
    candidate,
    side,
):
    idx = int(
        candidate['index']
    )

    tangent = local_centerline_tangent(
        profile,
        idx,
    )

    # Centerline ordering is start -> end.
    if side == 'left':
        outward = -tangent
    elif side == 'right':
        outward = tangent
    else:
        raise ValueError(
            side
        )

    return {
        'index': idx,
        'center': np.array([
            float(
                candidate['x']
            ),
            float(
                candidate['y']
            ),
        ]),
        'radius': float(
            candidate['radius']
        ),
        'tangent': tangent,
        'outward': outward,
    }


def pixel_circle_coordinates(
    xs,
    ys,
    geometry,
):
    points = np.column_stack([
        xs.astype(float),
        ys.astype(float),
    ])

    rel = (
        points
        - geometry['center']
    )

    distance = np.sqrt(
        (
            rel ** 2
        ).sum(
            axis=1
        )
    )

    outward_projection = (
        rel
        @ geometry['outward']
    )

    return (
        distance,
        outward_projection,
    )


def analyze_extension_beyond_circle(
    profile,
    accepted_circle,
    side,
):
    radius = profile[
        'radius'
    ]

    arc = profile[
        'u'
    ]

    n = len(radius)

    idx = int(
        accepted_circle[
            'index'
        ]
    )

    r = max(
        float(
            accepted_circle[
                'radius'
            ]
        ),
        1e-6,
    )

    if side == 'left':
        outward_indices = np.arange(
            idx - 1,
            -1,
            -1,
            dtype=int,
        )

    elif side == 'right':
        outward_indices = np.arange(
            idx + 1,
            n,
            dtype=int,
        )

    else:
        raise ValueError(
            side
        )

    if len(
        outward_indices
    ) == 0:
        return {
            'side': side,
            'valid': False,
            'pattern': 'normal_end',
            'score': 0.0,
            'centerline_extension_px': 0.0,
            'centerline_extension_ratio': 0.0,
            'cut_index': None,
            'reason': 'centerline_ends_at_circle',
        }

    center_arc = float(
        arc[idx]
    )

    terminal_arc = float(
        arc[
            outward_indices[-1]
        ]
    )

    centerline_extension_px = abs(
        terminal_arc
        - center_arc
    )

    extension_ratio = float(
        centerline_extension_px
        / r
    )

    if (
        extension_ratio
        < MIN_CENTERLINE_EXTENSION_RADIUS_RATIO
    ):
        return {
            'side': side,
            'valid': False,
            'pattern': 'normal_end',
            'score': 0.0,
            'centerline_extension_px': float(
                centerline_extension_px
            ),
            'centerline_extension_ratio': extension_ratio,
            'cut_index': None,
            'reason': 'too_little_centerline_beyond_circle',
        }

    seq_idx = outward_indices

    seq_radius = radius[
        seq_idx
    ]

    seq_distance = np.abs(
        arc[
            seq_idx
        ]
        - center_arc
    )

    # --------------------------------------------------------
    # First local valley/recess, not global terminal minimum.
    # --------------------------------------------------------

    prominence = (
        NECK_VALLEY_PROMINENCE_RATIO
        * r
    )

    valley_positions, properties = find_peaks(
        -seq_radius,
        prominence=prominence,
    )

    min_search_distance = (
        MIN_CLOSURE_SEARCH_RADIUS_RATIO
        * r
    )

    valley_positions = [
        int(p)
        for p in valley_positions
        if (
            seq_distance[
                int(p)
            ]
            >= min_search_distance
        )
    ]

    valley_position = (
        valley_positions[0]
        if valley_positions
        else None
    )

    cut_index = None
    pattern = 'none'
    neck_drop_ratio = 0.0
    reexpansion_ratio = 0.0

    if valley_position is not None:
        cut_index = int(
            seq_idx[
                valley_position
            ]
        )

        valley_radius = float(
            seq_radius[
                valley_position
            ]
        )

        neck_drop_ratio = max(
            0.0,
            (
                r
                - valley_radius
            )
            / r,
        )

        after_valley = seq_radius[
            valley_position + 1:
        ]

        if len(
            after_valley
        ):
            reexpansion_ratio = max(
                0.0,
                (
                    float(
                        np.max(
                            after_valley
                        )
                    )
                    - valley_radius
                )
                / r,
            )

        if (
            reexpansion_ratio
            >= MIN_REEXPANSION_RADIUS_RATIO
        ):
            pattern = 'neck_then_extra_lobe'

    # --------------------------------------------------------
    # If there was no head-lobe valley, find the FIRST point
    # where the accepted body circle is already clearly
    # closing. A long continuation after that is a narrow
    # overextension.
    # --------------------------------------------------------

    if pattern == 'none':
        closure_positions = np.where(
            (
                seq_distance
                >= min_search_distance
            )
            & (
                seq_radius
                <= (
                    CLOSURE_RADIUS_RATIO
                    * r
                )
            )
        )[0]

        if len(
            closure_positions
        ):
            closure_position = int(
                closure_positions[0]
            )

            cut_index = int(
                seq_idx[
                    closure_position
                ]
            )

            after_closure = seq_radius[
                closure_position + 1:
            ]

            remaining_distance = (
                centerline_extension_px
                - float(
                    seq_distance[
                        closure_position
                    ]
                )
            )

            remaining_ratio = max(
                0.0,
                remaining_distance
                / r,
            )

            if len(
                after_closure
            ):
                after_median_ratio = float(
                    np.median(
                        after_closure
                    )
                    / r
                )
            else:
                after_median_ratio = 0.0

            if (
                remaining_ratio
                >= 0.18
                and after_median_ratio
                <= NARROW_EXTENSION_MEDIAN_RATIO
            ):
                pattern = 'closing_then_narrow_overextension'

    if cut_index is None:
        return {
            'side': side,
            'valid': False,
            'pattern': 'unresolved_extension',
            'score': 0.0,
            'centerline_extension_px': float(
                centerline_extension_px
            ),
            'centerline_extension_ratio': extension_ratio,
            'cut_index': None,
            'neck_drop_ratio': float(
                neck_drop_ratio
            ),
            'reexpansion_ratio': float(
                reexpansion_ratio
            ),
            'reason': 'extended_but_no_clear_closure',
        }

    # --------------------------------------------------------
    # Score only after a closure/recess has been found.
    # --------------------------------------------------------

    cut_arc = float(
        arc[
            cut_index
        ]
    )

    terminal_remaining_px = abs(
        terminal_arc
        - cut_arc
    )

    terminal_remaining_ratio = float(
        terminal_remaining_px
        / r
    )

    score = (
        0.55
        * min(
            extension_ratio,
            1.5,
        )
        + 0.75
        * neck_drop_ratio
        + 0.80
        * reexpansion_ratio
        + 0.45
        * min(
            terminal_remaining_ratio,
            1.0,
        )
    )

    valid = bool(
        pattern
        in {
            'neck_then_extra_lobe',
            'closing_then_narrow_overextension',
        }
        and score
        >= EXTRA_SCORE_THRESHOLD
    )

    return {
        'side': side,
        'valid': valid,
        'pattern': pattern,
        'score': float(
            score
        ),
        'centerline_extension_px': float(
            centerline_extension_px
        ),
        'centerline_extension_ratio': float(
            extension_ratio
        ),
        'cut_index': int(
            cut_index
        ),
        'cut_arc': float(
            cut_arc
        ),
        'neck_drop_ratio': float(
            neck_drop_ratio
        ),
        'reexpansion_ratio': float(
            reexpansion_ratio
        ),
        'terminal_remaining_px': float(
            terminal_remaining_px
        ),
        'terminal_remaining_ratio': float(
            terminal_remaining_ratio
        ),
    }


def choose_extra_side(
    sample_id,
    left_analysis,
    right_analysis,
):
    override = EXTRA_SIDE_OVERRIDES.get(
        str(sample_id)
    )

    if override in {
        'left',
        'right',
        'none',
        'both',
    }:
        return {
            'mode': 'manual_debug_override',
            'selected': override,
            'ambiguous': (
                override == 'both'
            ),
        }

    left_score = (
        float(
            left_analysis.get(
                'score',
                0.0,
            )
        )
        if left_analysis.get(
            'valid',
            False,
        )
        else 0.0
    )

    right_score = (
        float(
            right_analysis.get(
                'score',
                0.0,
            )
        )
        if right_analysis.get(
            'valid',
            False,
        )
        else 0.0
    )

    best = max(
        left_score,
        right_score,
    )

    if (
        best
        < EXTRA_SCORE_THRESHOLD
    ):
        return {
            'mode': 'automatic_none',
            'selected': 'none',
            'ambiguous': False,
            'left_score': left_score,
            'right_score': right_score,
        }

    if (
        left_score > 0
        and right_score > 0
        and abs(
            left_score
            - right_score
        )
        < EXTRA_SCORE_MARGIN
    ):
        return {
            'mode': 'automatic_ambiguous',
            'selected': 'both',
            'ambiguous': True,
            'left_score': left_score,
            'right_score': right_score,
        }

    selected = (
        'left'
        if left_score > right_score
        else 'right'
    )

    return {
        'mode': 'automatic',
        'selected': selected,
        'ambiguous': False,
        'left_score': left_score,
        'right_score': right_score,
    }


COLOR_BODY = np.array(
    [35, 105, 245],
    dtype=np.uint8,
)


COLOR_LEFT_CAP = np.array(
    [40, 210, 80],
    dtype=np.uint8,
)


COLOR_RIGHT_CAP = np.array(
    [30, 220, 220],
    dtype=np.uint8,
)


COLOR_NECK = np.array(
    [255, 220, 20],
    dtype=np.uint8,
)


COLOR_EXTRA = np.array(
    [245, 45, 45],
    dtype=np.uint8,
)


COLOR_UNRESOLVED = np.array(
    [145, 145, 145],
    dtype=np.uint8,
)


def nearest_profile_index_for_mask_pixels(
    mask,
    profile,
):
    ys, xs = np.nonzero(
        mask
    )

    curve = np.column_stack([
        profile['x'],
        profile['y'],
    ])

    points = np.column_stack([
        xs.astype(float),
        ys.astype(float),
    ])

    nearest = np.empty(
        len(points),
        dtype=int,
    )

    chunk_size = 12000

    for start in range(
        0,
        len(points),
        chunk_size,
    ):
        end = min(
            len(points),
            start + chunk_size,
        )

        p = points[
            start:end
        ]

        d2 = (
            (
                p[:, None, :]
                - curve[None, :, :]
            ) ** 2
        ).sum(
            axis=2
        )

        nearest[
            start:end
        ] = np.argmin(
            d2,
            axis=1,
        )

    return (
        ys,
        xs,
        nearest,
    )


def _apply_circle_closure_preview(
    ji_mask,
    ys,
    xs,
    dist,
    outward_projection,
    geometry,
):
    '''
    Tuning-only geometric preview.

    On the outward side of the accepted circle center:
      keep pixels inside the accepted circle disk;
      remove pixels outside it.

    The inward/body side is left untouched.
    '''
    preview = ji_mask.copy()

    outside_circle_on_outward_side = (
        (outward_projection > 0)
        & (
            dist
            > (
                CAP_DISK_RADIUS_FACTOR
                * geometry['radius']
            )
        )
    )

    preview[
        ys[
            outside_circle_on_outward_side
        ],
        xs[
            outside_circle_on_outward_side
        ],
    ] = 0

    return (
        _binary(preview),
        outside_circle_on_outward_side,
    )



def _apply_v19_auxiliary_head_closure_preview(
    ji_mask,
    ys,
    xs,
    nearest,
    dist,
    outward_projection,
    geometry,
    original_head_index,
    purple_index,
    side,
    profile=None,
    cross_section=None,
):
    """Cut ONLY on the HEAD side of the exact two-tangent-point chord.

    Retained mask:

        original_mask AND (BODY_SIDE_OF_TANGENT_CHORD OR PURPLE_DISK)

    The dividing line is the line through the SAME two real pig-outline points
    used by the final purple-circle refinement whenever those points are
    available.

    Therefore any original mask pixel behind/bodyward of that chord is
    unconditionally retained and cannot become a divot.
    """
    preview = ji_mask.copy()

    purple_index = int(purple_index)
    radius = float(geometry['radius'])

    p_plus = geometry.get('tangent_point_plus')
    p_minus = geometry.get('tangent_point_minus')

    # If strict refinement fell back to the initial purple placement, use the
    # local cross-section endpoints as the best available chord.
    if (
        (p_plus is None or p_minus is None)
        and cross_section is not None
    ):
        plus_points = np.asarray(
            cross_section['plus_points'],
            dtype=float,
        )
        minus_points = np.asarray(
            cross_section['minus_points'],
            dtype=float,
        )

        if (
            0 <= purple_index < len(plus_points)
            and np.isfinite(plus_points[purple_index]).all()
            and np.isfinite(minus_points[purple_index]).all()
        ):
            p_plus = plus_points[purple_index]
            p_minus = minus_points[purple_index]

    use_exact_chord = bool(
        p_plus is not None
        and p_minus is not None
        and np.isfinite(np.asarray(p_plus, dtype=float)).all()
        and np.isfinite(np.asarray(p_minus, dtype=float)).all()
    )

    if use_exact_chord:
        p_plus = np.asarray(p_plus, dtype=float)
        p_minus = np.asarray(p_minus, dtype=float)

        chord = p_minus - p_plus
        chord_norm = float(np.linalg.norm(chord))

        if chord_norm > 1e-9:
            chord_unit = chord / chord_norm

            # Normal to the ACTUAL tangent-point chord.
            chord_normal = np.array(
                [-chord_unit[1], chord_unit[0]],
                dtype=float,
            )

            # Choose the normal sign that points from body toward the head.
            if profile is not None:
                local_tangent = np.asarray(
                    local_centerline_tangent(
                        profile,
                        purple_index,
                    ),
                    dtype=float,
                )
                local_tangent /= max(
                    float(np.linalg.norm(local_tangent)),
                    1e-9,
                )
                expected_head_dir = (
                    -local_tangent
                    if side == 'left'
                    else local_tangent
                )

                if float(np.dot(chord_normal, expected_head_dir)) < 0.0:
                    chord_normal *= -1.0
            else:
                # Fall back to geometry's outward direction if profile is absent.
                expected_head_dir = np.asarray(
                    geometry['outward'],
                    dtype=float,
                )
                if float(np.dot(chord_normal, expected_head_dir)) < 0.0:
                    chord_normal *= -1.0

            chord_midpoint = 0.5 * (p_plus + p_minus)

            dx = xs.astype(float) - float(chord_midpoint[0])
            dy = ys.astype(float) - float(chord_midpoint[1])

            signed_headward = (
                dx * float(chord_normal[0])
                + dy * float(chord_normal[1])
            )

            # CRITICAL RULE:
            # <= 0 = bodyward/behind tangent chord => NEVER REMOVE.
            body_side = signed_headward <= 0.0
            head_side = signed_headward > 0.0

            remove_pixels = (
                head_side
                & (
                    dist
                    > (
                        CAP_DISK_RADIUS_FACTOR
                        * radius
                    )
                )
            )

            preview[
                ys[remove_pixels],
                xs[remove_pixels],
            ] = 0

            return (
                _binary(preview),
                remove_pixels,
                body_side,
            )

    # Conservative fallback: still preserve the circle-local body half-plane.
    body_side = outward_projection <= 0.0
    remove_pixels = (
        (outward_projection > 0.0)
        & (
            dist
            > (
                CAP_DISK_RADIUS_FACTOR
                * radius
            )
        )
    )

    preview[
        ys[remove_pixels],
        xs[remove_pixels],
    ] = 0

    return (
        _binary(preview),
        remove_pixels,
        body_side,
    )


# ============================================================================
# V14 — V9 HEAD-SIDE IDENTIFICATION + OFF-CENTER SHOULDER CIRCLE
# ============================================================================
#
# Design constraints:
#   * Start from V9 pair selection unchanged.
#   * Use existing 06Q neck stations as EXTRA evidence for which terminal is
#     actually the head. Do not replace V9 extension analysis.
#   * Once the head side is chosen, fit a NEW closure circle only on that side.
#   * The fitted circle is NOT forced to be centered on the white centerline.
#   * At each candidate station, its center is the midpoint of the two actual
#     cross-section contour hits, so the circle explicitly touches both sides.
#   * The fitted circle must shift terminalward/outward from the original 06Q
#     circle and must still overlap a meaningful portion of the original circle.
#   * The rump/non-head circle is never modified and is never used for cutting.

V14_HEAD_NECK_MIN_SCORE = 0.10
V14_HEAD_NECK_MIN_REEXPANSION = 0.04
V14_HEAD_NECK_MIN_WIDTH_CONSTRICTION = 0.03
V14_HEAD_NECK_MAX_DISTANCE_R = 2.10
V14_HEAD_NECK_SCORE_BONUS = 0.85
V14_HEAD_PATTERN_BONUS = 0.28
V14_HEAD_TAPER_PENALTY = 0.18
V14_HEAD_SCORE_MARGIN = 0.06

V14_FIT_MAX_OUTWARD_SHIFT_R = 1.80
V14_FIT_MIN_OUTWARD_SHIFT_R = 0.04
V14_FIT_MIN_RADIUS_RATIO = 0.58
V14_FIT_MAX_RADIUS_RATIO = 1.55
V14_FIT_MIN_ORIGINAL_OVERLAP = 0.16
V14_FIT_MIN_DISK_MASK_OCCUPANCY = 0.50
V14_FIT_NECK_MARGIN_STATIONS = 1
V14_FIT_RADIUS_EDGE_MARGIN = 1.02

V14_REFINED_CIRCLE_COLOR = (170, 60, 220)


def _v14_circle_intersection_fraction(c0, r0, c1, r1):
    """Intersection area divided by ORIGINAL circle area."""
    c0 = np.asarray(c0, dtype=float)
    c1 = np.asarray(c1, dtype=float)
    r0 = max(float(r0), 1e-6)
    r1 = max(float(r1), 1e-6)
    d = float(np.linalg.norm(c1 - c0))

    if d >= r0 + r1:
        return 0.0
    if d <= abs(r0 - r1):
        inter = math.pi * min(r0, r1) ** 2
        return float(inter / (math.pi * r0 ** 2))

    a0 = math.acos(np.clip((d*d + r0*r0 - r1*r1) / (2*d*r0), -1.0, 1.0))
    a1 = math.acos(np.clip((d*d + r1*r1 - r0*r0) / (2*d*r1), -1.0, 1.0))
    term = max(
        0.0,
        (-d + r0 + r1)
        * (d + r0 - r1)
        * (d - r0 + r1)
        * (d + r0 + r1),
    )
    inter = r0*r0*a0 + r1*r1*a1 - 0.5 * math.sqrt(term)
    return float(inter / (math.pi * r0 ** 2))


def _v14_disk_mask_occupancy(mask, center, radius):
    """Fraction of the proposed disk that is supported by the pig mask."""
    mask_bool = np.asarray(mask) > 0
    h, w = mask_bool.shape
    cx, cy = map(float, center)
    r = max(float(radius), 1.0)

    x0 = max(0, int(math.floor(cx - r - 1)))
    x1 = min(w - 1, int(math.ceil(cx + r + 1)))
    y0 = max(0, int(math.floor(cy - r - 1)))
    y1 = min(h - 1, int(math.ceil(cy + r + 1)))

    if x1 < x0 or y1 < y0:
        return 0.0

    yy, xx = np.mgrid[y0:y1+1, x0:x1+1]
    disk = (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2
    n_disk = int(np.count_nonzero(disk))
    if n_disk == 0:
        return 0.0

    supported = mask_bool[y0:y1+1, x0:x1+1] & disk
    return float(np.count_nonzero(supported) / n_disk)


def _v14_neck_station_for_side(profile, neck_stations, circle, side):
    """Best existing 06Q neck station outside the selected circle."""
    idx0 = int(circle['index'])
    r0 = max(float(circle['radius']), 1e-6)
    arc = np.asarray(profile['u'], dtype=float)
    center_arc = float(arc[idx0])

    rows = []
    for neck in neck_stations:
        if str(neck.get('neck_side')) != str(side):
            continue

        ni = int(neck['neck_index'])
        if side == 'left':
            outward_ok = ni < idx0
        elif side == 'right':
            outward_ok = ni > idx0
        else:
            raise ValueError(side)

        if not outward_ok:
            continue

        distance_r = abs(float(arc[ni]) - center_arc) / r0
        if distance_r > V14_HEAD_NECK_MAX_DISTANCE_R:
            continue

        neck_score = float(neck.get('neck_score', 0.0))
        reexpansion = float(neck.get('reexpansion_ratio', 0.0))
        width_constriction = float(neck.get('width_constriction_ratio', 0.0))
        side_constriction = float(neck.get('side_constriction_ratio', 0.0))
        prominence = float(neck.get('prominence_ratio', 0.0))

        strong = bool(
            neck_score >= V14_HEAD_NECK_MIN_SCORE
            and reexpansion >= V14_HEAD_NECK_MIN_REEXPANSION
            and width_constriction >= V14_HEAD_NECK_MIN_WIDTH_CONSTRICTION
        )

        evidence_score = float(
            0.40 * min(neck_score, 1.0)
            + 0.28 * min(reexpansion, 1.0)
            + 0.16 * min(width_constriction, 1.0)
            + 0.10 * min(side_constriction, 1.0)
            + 0.06 * min(prominence, 1.0)
            - 0.05 * max(0.0, distance_r - 1.2)
        )

        rows.append({
            'neck': neck,
            'strong': strong,
            'score': evidence_score,
            'distance_r': float(distance_r),
        })

    if not rows:
        return None

    return max(rows, key=lambda r: (r['strong'], r['score']))



# ============================================================================
# V15 — EXPLICIT HEAD/RUMP SELECTION + STRICTLY CONTAINED HEAD CIRCLE
# ============================================================================
#
# Rules:
#   * Rump is NEVER used for the final closure.
#   * Purple circle can exist ONLY on the selected HEAD side.
#   * Head selection uses multiple cues, not only the symmetric V9 extension
#     score:
#       - existing 06Q neck/re-expansion evidence;
#       - V9 extension pattern;
#       - terminal width/narrowness profile;
#       - broad smooth terminal veto (rump-like).
#   * The refined head circle may be off the white centerline, but the entire
#     purple disk must be contained by the pig mask.
#   * The new circle must still overlap the original 06Q head-side circle and
#     must move terminalward/outward, never bodyward.

V15_HEAD_MIN_SCORE = 0.30
V15_HEAD_SCORE_MARGIN = 0.075
V15_HEAD_NARROW_MEDIAN_RATIO = 0.70
V15_HEAD_NARROW_Q75_RATIO = 0.84
V15_HEAD_MIN_EXTENSION_RATIO = 0.12
V15_RUMP_BROAD_MEDIAN_RATIO = 0.76
V15_RUMP_BROAD_Q75_RATIO = 0.90
V15_RUMP_MAX_REEXPANSION_FOR_VETO = 0.06

# V17: purple is a SHOULDER / head-cap refinement, not a neck circle.
# It must stay roughly the size of the original cyan head cap. It may be
# larger, but it cannot collapse to a small neck-sized disk.
V15_FIT_MAX_OUTWARD_SHIFT_R = 1.15
V15_FIT_MIN_OUTWARD_SHIFT_R = 0.025
V15_FIT_MIN_RADIUS_RATIO = 0.90
V15_FIT_MAX_RADIUS_RATIO = 1.60
V15_FIT_MIN_ORIGINAL_OVERLAP = 0.25
# V24: these are intentionally the original V17/V19 INITIAL-placement gates.
# Do not make them as strict as the final two-tangent refinement, otherwise
# some valid heads never get any purple circle at all.
V15_FIT_MIN_SIDE_BALANCE = 0.78
V15_FIT_MIN_SIDE_TOUCH_RATIO = 0.86
V15_FIT_NORMAL_SEARCH_R = 0.18
V15_FIT_NORMAL_SEARCH_STEPS = 7
V15_FIT_NECK_MARGIN_STATIONS = 1
V15_FIT_DISTANCE_TRANSFORM_SCALE = 0.96
V15_FIT_EXACT_SHRINK_STEP_PX = 0.50

V15_COLOR_HEAD_CAP = np.array([30, 220, 220], dtype=np.uint8)   # cyan
V15_COLOR_RUMP_CAP = np.array([40, 210, 80], dtype=np.uint8)    # green


def _v15_terminal_signature(profile, circle, side):
    """Width-profile signature outside one ORIGINAL 06Q circle."""
    radius = np.asarray(profile['radius'], dtype=float)
    arc = np.asarray(profile['u'], dtype=float)
    idx0 = int(circle['index'])
    r0 = max(float(circle['radius']), 1e-6)

    if side == 'left':
        ids = np.arange(idx0 - 1, -1, -1, dtype=int)
    elif side == 'right':
        ids = np.arange(idx0 + 1, len(radius), dtype=int)
    else:
        raise ValueError(side)

    if len(ids) == 0:
        return {
            'extension_ratio': 0.0,
            'median_radius_ratio': 1.0,
            'q75_radius_ratio': 1.0,
            'end_median_radius_ratio': 1.0,
            'reexpansion_ratio': 0.0,
            'narrow_terminal': False,
            'broad_rump_like': True,
        }

    vals = radius[ids]
    finite = np.isfinite(vals) & (vals > 0)
    vals = vals[finite]
    finite_ids = ids[finite]

    if len(vals) == 0:
        return {
            'extension_ratio': 0.0,
            'median_radius_ratio': 1.0,
            'q75_radius_ratio': 1.0,
            'end_median_radius_ratio': 1.0,
            'reexpansion_ratio': 0.0,
            'narrow_terminal': False,
            'broad_rump_like': True,
        }

    terminal_arc = float(arc[finite_ids[-1]])
    extension_ratio = abs(terminal_arc - float(arc[idx0])) / r0

    median_ratio = float(np.median(vals) / r0)
    q75_ratio = float(np.quantile(vals, 0.75) / r0)

    tail_n = max(2, int(round(0.28 * len(vals))))
    end_median_ratio = float(np.median(vals[-tail_n:]) / r0)

    # Largest rise after the first meaningful local minimum. This is weak
    # evidence by itself, but helps distinguish neck->head from a smooth rump.
    reexpansion_ratio = 0.0
    if len(vals) >= 4:
        min_pos = int(np.argmin(vals[:-1]))
        if min_pos < len(vals) - 1:
            after_peak = float(np.max(vals[min_pos + 1:]))
            reexpansion_ratio = max(
                0.0,
                (after_peak - float(vals[min_pos])) / r0,
            )

    narrow_terminal = bool(
        extension_ratio >= V15_HEAD_MIN_EXTENSION_RATIO
        and median_ratio <= V15_HEAD_NARROW_MEDIAN_RATIO
        and q75_ratio <= V15_HEAD_NARROW_Q75_RATIO
    )

    broad_rump_like = bool(
        median_ratio >= V15_RUMP_BROAD_MEDIAN_RATIO
        and q75_ratio >= V15_RUMP_BROAD_Q75_RATIO
        and reexpansion_ratio <= V15_RUMP_MAX_REEXPANSION_FOR_VETO
    )

    return {
        'extension_ratio': float(extension_ratio),
        'median_radius_ratio': float(median_ratio),
        'q75_radius_ratio': float(q75_ratio),
        'end_median_radius_ratio': float(end_median_ratio),
        'reexpansion_ratio': float(reexpansion_ratio),
        'narrow_terminal': narrow_terminal,
        'broad_rump_like': broad_rump_like,
    }


def _v15_choose_head_side(
    sample_id,
    profile,
    neck_stations,
    left_circle,
    right_circle,
    left_extension,
    right_extension,
):
    """Choose exactly one HEAD side, or none.

    A broad rump-like terminal is vetoed unless it has strong independent neck
    evidence. The old symmetric V9 choice is recorded only for diagnostics and
    is never allowed to force a rump cut.
    """
    base_v9 = choose_extra_side(
        sample_id,
        left_extension,
        right_extension,
    )

    left_neck = _v14_neck_station_for_side(
        profile, neck_stations, left_circle, 'left'
    )
    right_neck = _v14_neck_station_for_side(
        profile, neck_stations, right_circle, 'right'
    )

    left_sig = _v15_terminal_signature(
        profile, left_circle, 'left'
    )
    right_sig = _v15_terminal_signature(
        profile, right_circle, 'right'
    )

    r_left = max(float(left_circle['radius']), 1e-6)
    r_right = max(float(right_circle['radius']), 1e-6)
    pair_r_max = max(r_left, r_right)

    def one_side(ext, neck, sig, circle_radius):
        pattern = str(ext.get('pattern', 'none'))
        ext_valid = bool(ext.get('valid', False))
        strong_neck = bool(neck is not None and neck.get('strong', False))
        neck_score = float(neck.get('score', 0.0)) if neck is not None else 0.0

        score = 0.0

        # Strongest cues: actual 06Q neck and explicit V9 neck->lobe.
        if strong_neck:
            score += 0.58 + 0.34 * min(neck_score, 1.0)
        elif neck is not None:
            score += 0.22 * min(neck_score, 1.0)

        if ext_valid and pattern == 'neck_then_extra_lobe':
            score += 0.52
        elif ext_valid and pattern == 'closing_then_narrow_overextension':
            score += 0.16

        # Heads generally remain a narrower terminal structure than the torso.
        narrowness = float(np.clip(
            (0.90 - sig['median_radius_ratio']) / 0.45,
            0.0,
            1.0,
        ))
        q75_narrowness = float(np.clip(
            (0.98 - sig['q75_radius_ratio']) / 0.42,
            0.0,
            1.0,
        ))
        score += 0.23 * narrowness
        score += 0.12 * q75_narrowness
        score += 0.10 * min(sig['extension_ratio'], 1.2)
        score += 0.16 * min(sig['reexpansion_ratio'], 1.0)

        # A slightly smaller terminal body lobe is weak head-side evidence.
        score += 0.06 * max(
            0.0,
            1.0 - float(circle_radius / pair_r_max),
        )

        # Hard rump protection: a broad smooth terminal cannot win merely from
        # V9 extension length. A strong neck / explicit neck->lobe can override.
        rump_veto = bool(
            sig['broad_rump_like']
            and not strong_neck
            and pattern != 'neck_then_extra_lobe'
        )
        if rump_veto:
            score -= 0.80

        eligible = bool(
            not rump_veto
            and (
                strong_neck
                or (ext_valid and pattern == 'neck_then_extra_lobe')
                or (
                    ext_valid
                    and pattern == 'closing_then_narrow_overextension'
                    and sig['narrow_terminal']
                )
                or (
                    sig['narrow_terminal']
                    and sig['reexpansion_ratio'] >= 0.035
                )
            )
            and score >= V15_HEAD_MIN_SCORE
        )

        return {
            'eligible': eligible,
            'score': float(score),
            'pattern': pattern,
            'strong_neck': strong_neck,
            'neck_score': float(neck_score),
            'signature': sig,
            'rump_veto': rump_veto,
        }

    left_head = one_side(
        left_extension, left_neck, left_sig, r_left
    )
    right_head = one_side(
        right_extension, right_neck, right_sig, r_right
    )

    le = bool(left_head['eligible'])
    re = bool(right_head['eligible'])

    if le and not re:
        selected = 'left'
        mode = 'v15_only_left_head_eligible'
    elif re and not le:
        selected = 'right'
        mode = 'v15_only_right_head_eligible'
    elif le and re:
        diff = float(left_head['score'] - right_head['score'])

        if abs(diff) >= V15_HEAD_SCORE_MARGIN:
            selected = 'left' if diff > 0 else 'right'
            mode = 'v15_two_head_candidates_scored'
        else:
            # Tie-break by terminal narrowness only when meaningfully different.
            med_diff = (
                left_head['signature']['median_radius_ratio']
                - right_head['signature']['median_radius_ratio']
            )
            if abs(med_diff) >= 0.08:
                selected = 'left' if med_diff < 0 else 'right'
                mode = 'v15_two_head_candidates_narrowness_tiebreak'
            else:
                selected = 'none'
                mode = 'v15_ambiguous_two_head_candidates'
    else:
        selected = 'none'
        mode = 'v15_no_safe_head_candidate'

    return {
        'mode': mode,
        'selected': selected,
        'ambiguous': selected == 'none',
        'left_score': float(left_head['score']),
        'right_score': float(right_head['score']),
        'left_eligible': bool(left_head['eligible']),
        'right_eligible': bool(right_head['eligible']),
        'left_head_diagnostics': left_head,
        'right_head_diagnostics': right_head,
        'left_neck_evidence': left_neck,
        'right_neck_evidence': right_neck,
        'base_v9_selection': base_v9,
    }



# ============================================================================
# V16 — RELATIVE TWO-END HEAD/RUMP ASSIGNMENT
# ============================================================================
#
# The two-circle pair already gives exactly two terminal ends. V15 could return
# head=none because each end had to independently satisfy an absolute threshold.
# V16 instead compares the same evidence RELATIVELY:
#
#   one end = HEAD
#   the opposite end = RUMP
#
# Purple fitting is a SECONDARY refinement step. Failure to fit purple must
# NEVER cancel an already-selected head crop.
V16_RELATIVE_SCORE_MARGIN = 0.035
V16_NARROWNESS_TIE_MARGIN = 0.035
V16_REEXPANSION_TIE_MARGIN = 0.025

# V19: terminal morphology is the primary head/rump discriminator when the
# two ends are clearly different. This prevents a false rump neck valley from
# overpowering an obviously narrower / more head-like terminal.
V19_CLEAR_TERMINAL_WIDTH_MARGIN = 0.075
V19_CLEAR_END_WIDTH_MARGIN = 0.065
V19_SLENDERNESS_RATIO_MARGIN = 1.10


def _v16_choose_head_side(
    sample_id,
    profile,
    neck_stations,
    left_circle,
    right_circle,
    left_extension,
    right_extension,
):
    # Reuse all V15 measurements/scores, but not its absolute eligibility gate.
    base = _v15_choose_head_side(
        sample_id,
        profile,
        neck_stations,
        left_circle,
        right_circle,
        left_extension,
        right_extension,
    )

    left = dict(base.get('left_head_diagnostics') or {})
    right = dict(base.get('right_head_diagnostics') or {})

    left_score = float(left.get('score', 0.0))
    right_score = float(right.get('score', 0.0))

    left_sig = dict(left.get('signature') or {})
    right_sig = dict(right.get('signature') or {})

    left_pattern = str(left.get('pattern', 'none'))
    right_pattern = str(right.get('pattern', 'none'))

    left_strong_neck = bool(left.get('strong_neck', False))
    right_strong_neck = bool(right.get('strong_neck', False))

    left_rump_veto = bool(left.get('rump_veto', False))
    right_rump_veto = bool(right.get('rump_veto', False))

    # --------------------------------------------------------
    # 0. V19 CLEAR TERMINAL MORPHOLOGY.
    #
    # Strong-neck evidence can be false at a rounded rump. Before considering
    # neck/pattern scores, compare the two terminal shapes directly.
    #
    # HEAD is expected to be the relatively narrower / more slender terminal.
    # This rule only fires when the difference is clear; otherwise the existing
    # V17 relative logic still handles the case.
    # --------------------------------------------------------
    left_med = float(left_sig.get('median_radius_ratio', 1.0))
    right_med = float(right_sig.get('median_radius_ratio', 1.0))
    left_end = float(left_sig.get('end_median_radius_ratio', 1.0))
    right_end = float(right_sig.get('end_median_radius_ratio', 1.0))
    left_ext = float(left_sig.get('extension_ratio', 0.0))
    right_ext = float(right_sig.get('extension_ratio', 0.0))

    left_width_index = 0.65 * left_med + 0.35 * left_end
    right_width_index = 0.65 * right_med + 0.35 * right_end

    left_slenderness = left_ext / max(left_width_index, 0.25)
    right_slenderness = right_ext / max(right_width_index, 0.25)

    left_clearly_narrower = bool(
        left_width_index <= right_width_index - V19_CLEAR_TERMINAL_WIDTH_MARGIN
        and left_end <= right_end - V19_CLEAR_END_WIDTH_MARGIN
    )
    right_clearly_narrower = bool(
        right_width_index <= left_width_index - V19_CLEAR_TERMINAL_WIDTH_MARGIN
        and right_end <= left_end - V19_CLEAR_END_WIDTH_MARGIN
    )

    left_clearly_more_slender = bool(
        left_slenderness >= V19_SLENDERNESS_RATIO_MARGIN * max(right_slenderness, 1e-6)
        and left_width_index < right_width_index
    )
    right_clearly_more_slender = bool(
        right_slenderness >= V19_SLENDERNESS_RATIO_MARGIN * max(left_slenderness, 1e-6)
        and right_width_index < left_width_index
    )

    terminal_shape_selected = None
    terminal_shape_mode = None

    if left_clearly_narrower or left_clearly_more_slender:
        terminal_shape_selected = 'left'
        terminal_shape_mode = 'v19_clear_terminal_head_shape'
    elif right_clearly_narrower or right_clearly_more_slender:
        terminal_shape_selected = 'right'
        terminal_shape_mode = 'v19_clear_terminal_head_shape'

    # --------------------------------------------------------
    # 1. Anatomical asymmetries.
    # --------------------------------------------------------
    #
    # IMPORTANT FIX:
    # A one-sided `strong_neck` is NO LONGER an automatic head assignment.
    # The last remaining bad sample showed that the rump can occasionally
    # produce a false neck-like valley. Strong-neck evidence is already heavily
    # rewarded inside left_score/right_score, so it still matters, but it must
    # agree with the terminal morphology instead of bypassing it.
    #
    # V19: when terminal morphology is clearly asymmetric, use it BEFORE
    # neck evidence. Neck evidence remains useful only when shape is ambiguous.
    if terminal_shape_selected is not None:
        selected = terminal_shape_selected
        mode = terminal_shape_mode

    # Then protect against a clearly broad/smooth rump.
    elif left_rump_veto and not right_rump_veto:
        selected = 'right'
        mode = 'v17_headselect_rump_veto'
    elif right_rump_veto and not left_rump_veto:
        selected = 'left'
        mode = 'v17_headselect_rump_veto'

    # Explicit neck->extra-lobe remains stronger than a plain taper, provided
    # the candidate is not simultaneously classified as broad rump-like.
    elif (
        left_pattern == 'neck_then_extra_lobe'
        and right_pattern != 'neck_then_extra_lobe'
        and not left_rump_veto
    ):
        selected = 'left'
        mode = 'v17_headselect_neck_pattern'
    elif (
        right_pattern == 'neck_then_extra_lobe'
        and left_pattern != 'neck_then_extra_lobe'
        and not right_rump_veto
    ):
        selected = 'right'
        mode = 'v17_headselect_neck_pattern'

    # --------------------------------------------------------
    # 2. Compare full evidence scores.
    # --------------------------------------------------------
    elif abs(left_score - right_score) >= V16_RELATIVE_SCORE_MARGIN:
        selected = 'left' if left_score > right_score else 'right'
        mode = 'v16_relative_score'

    else:
        # ----------------------------------------------------
        # 3. Tie-breakers. Heads are usually the narrower/more
        #    constricted terminal compared with the rump.
        # ----------------------------------------------------
        left_med = float(left_sig.get('median_radius_ratio', 1.0))
        right_med = float(right_sig.get('median_radius_ratio', 1.0))

        if abs(left_med - right_med) >= V16_NARROWNESS_TIE_MARGIN:
            selected = 'left' if left_med < right_med else 'right'
            mode = 'v16_relative_terminal_narrowness'
        else:
            left_re = float(left_sig.get('reexpansion_ratio', 0.0))
            right_re = float(right_sig.get('reexpansion_ratio', 0.0))

            if abs(left_re - right_re) >= V16_REEXPANSION_TIE_MARGIN:
                selected = 'left' if left_re > right_re else 'right'
                mode = 'v16_relative_reexpansion'
            else:
                # Final conservative tie-breaker: use V9's original selection
                # when it chose exactly one end. This is only reached after all
                # anatomical relative cues are nearly tied.
                v9_sel = (
                    (base.get('base_v9_selection') or {}).get(
                        'selected',
                        'none',
                    )
                )

                if v9_sel in {'left', 'right'}:
                    selected = v9_sel
                    mode = 'v16_relative_v9_final_tiebreak'
                else:
                    # A valid two-circle pair still has two ends. If every cue
                    # is tied, choose the slightly narrower terminal rather than
                    # returning head=none and skipping cropping entirely.
                    selected = 'left' if left_med <= right_med else 'right'
                    mode = 'v16_relative_last_narrowness'

    # --------------------------------------------------------
    # Final relative sanity check.
    #
    # If the provisional HEAD terminal is substantially broader at BOTH its
    # median and terminal end than the opposite terminal, flip the assignment
    # unless it has an explicit neck->extra-lobe pattern and the opposite does
    # not. This targets the remaining case where a rounded rump generated a
    # false neck score and won despite visibly being the broader terminal.
    # --------------------------------------------------------
    left_med = float(left_sig.get('median_radius_ratio', 1.0))
    right_med = float(right_sig.get('median_radius_ratio', 1.0))
    left_end = float(left_sig.get('end_median_radius_ratio', 1.0))
    right_end = float(right_sig.get('end_median_radius_ratio', 1.0))

    if selected == 'left':
        clearly_broader = bool(
            left_med >= right_med + 0.10
            and left_end >= right_end + 0.10
        )
        protected_head_pattern = bool(
            left_pattern == 'neck_then_extra_lobe'
            and right_pattern != 'neck_then_extra_lobe'
            and not left_rump_veto
        )
        if clearly_broader and not protected_head_pattern:
            selected = 'right'
            mode = 'v17_headselect_broad_terminal_flip'

    elif selected == 'right':
        clearly_broader = bool(
            right_med >= left_med + 0.10
            and right_end >= left_end + 0.10
        )
        protected_head_pattern = bool(
            right_pattern == 'neck_then_extra_lobe'
            and left_pattern != 'neck_then_extra_lobe'
            and not right_rump_veto
        )
        if clearly_broader and not protected_head_pattern:
            selected = 'left'
            mode = 'v17_headselect_broad_terminal_flip'

    rump = 'right' if selected == 'left' else 'left'

    return {
        **base,
        'mode': mode,
        'selected': selected,
        'ambiguous': False,
        'rump_side': rump,
        'left_score': float(left_score),
        'right_score': float(right_score),

        # IMPORTANT: selected head is crop-eligible independently of whether
        # purple refinement succeeds.
        'left_eligible': bool(selected == 'left'),
        'right_eligible': bool(selected == 'right'),

        'relative_assignment': True,
        'purple_required_for_crop': False,
        'left_terminal_width_index': float(left_width_index),
        'right_terminal_width_index': float(right_width_index),
        'left_terminal_slenderness': float(left_slenderness),
        'right_terminal_slenderness': float(right_slenderness),
    }


def _v15_exact_contained_radius(mask, center, radius):
    """Shrink until the rasterized disk has ZERO pixels outside the pig mask."""
    mask_bool = np.asarray(mask) > 0
    h, w = mask_bool.shape
    cx, cy = map(float, center)
    r = max(float(radius), 0.0)

    while r >= 1.0:
        x0 = max(0, int(math.floor(cx - r - 1)))
        x1 = min(w - 1, int(math.ceil(cx + r + 1)))
        y0 = max(0, int(math.floor(cy - r - 1)))
        y1 = min(h - 1, int(math.ceil(cy + r + 1)))

        yy, xx = np.mgrid[y0:y1+1, x0:x1+1]
        disk = (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2

        if not np.any(disk & (~mask_bool[y0:y1+1, x0:x1+1])):
            return float(r)

        r -= V15_FIT_EXACT_SHRINK_STEP_PX

    return 0.0



# ============================================================================
# V19 — POST-PLACEMENT PURPLE GROWTH
# ============================================================================
#
# Placement is still the V17 contained-head-circle logic.
# AFTER that placement is chosen, V19 performs a small local hill-climb:
#   - do not choose a different anatomical station;
#   - allow only a small center adjustment around the placed circle;
#   - grow to the largest fully-contained local circle;
#   - prefer circles that support both local pig sides;
#   - never shrink below the placed purple radius.
#
# This implements "place first, then make it bigger" rather than changing the
# placement algorithm itself.
# V26 exact two-outline-point refinement.
#
# Center is NOT locked. It may move to nearby longitudinal stations and along
# each station's chord perpendicular bisector.
#
# The two actual pig-outline points at a station DEFINE the candidate circle:
# both points are forced onto the same circle before containment validation.
V26_TANGENT_LONGITUDINAL_RANGE_R = 0.22
V26_TANGENT_BISECTOR_RANGE_R = 0.42
V26_TANGENT_BISECTOR_STEPS = 31
V26_TANGENT_MIN_RADIUS_TO_CYAN = 0.90
V26_TANGENT_MAX_RADIUS_TO_CYAN = 1.75
V26_TANGENT_MIN_CYAN_OVERLAP = 0.18

# Final raster-contained radius may be slightly smaller than the exact
# continuous circle because of pixelization, but both outline points must stay
# very close to the final purple boundary.
V26_TANGENT_MAX_RADIAL_ERROR = 0.07
V26_TANGENT_MAX_BODYWARD_SHIFT_R = 0.14
V26_TANGENT_MAX_EXTRA_OUTWARD_SHIFT_R = 0.22


def _v26_refine_purple_exact_two_tangent(
    mask,
    profile,
    cross_section,
    original_circle,
    side,
    placed_geom,
    placed_diag,
):
    """Recenter purple so two REAL pig-outline points define its circle.

    For each nearby cross-section station, p+ and p- are the two actual mask
    outline hits. The center is searched on the perpendicular bisector of the
    chord p+--p-, which guarantees equal geometric distance to BOTH sides.

    The final disk must still be fully contained in the pig mask. Small raster
    shrinkage is tolerated only when the two outline points remain within 7% of
    the final radius.
    """
    if not placed_diag.get('applied', False):
        return placed_geom, {
            **placed_diag,
            'post_growth_applied': False,
            'post_growth_reason': 'placement_not_applied',
        }

    arc = np.asarray(profile['u'], dtype=float)
    plus_points = np.asarray(cross_section['plus_points'], dtype=float)
    minus_points = np.asarray(cross_section['minus_points'], dtype=float)

    r0 = max(float(original_circle['radius']), 1e-6)
    placed_center = np.asarray(placed_geom['center'], dtype=float)
    placed_radius = max(float(placed_geom['radius']), 1e-6)
    placed_index = int(placed_geom['index'])
    placed_arc = float(arc[placed_index])

    original_geom = circle_geometry(profile, original_circle, side)
    original_center = np.asarray(original_geom['center'], dtype=float)
    original_outward = np.asarray(original_geom['outward'], dtype=float)
    original_outward /= max(float(np.linalg.norm(original_outward)), 1e-9)

    placed_outward = float(
        np.dot(placed_center - original_center, original_outward)
    )

    station_ids = np.where(
        np.abs(arc - placed_arc)
        <= V26_TANGENT_LONGITUDINAL_RANGE_R * r0
    )[0].astype(int)

    candidates = []

    for idx in station_ids:
        p_plus = plus_points[idx]
        p_minus = minus_points[idx]

        if not (
            np.isfinite(p_plus).all()
            and np.isfinite(p_minus).all()
        ):
            continue

        chord = np.asarray(p_plus - p_minus, dtype=float)
        chord_len = float(np.linalg.norm(chord))
        if chord_len <= 2.0:
            continue

        midpoint = 0.5 * (p_plus + p_minus)

        # Every circle through p+ and p- has its center on this line.
        bisector = np.array(
            [-chord[1], chord[0]],
            dtype=float,
        )
        bisector /= max(float(np.linalg.norm(bisector)), 1e-9)

        # Orient the bisector roughly along the local pig axis. This makes the
        # search parameter stable but does NOT lock the center to the centerline.
        local_tangent = np.asarray(
            local_centerline_tangent(profile, int(idx)),
            dtype=float,
        )
        local_tangent /= max(float(np.linalg.norm(local_tangent)), 1e-9)

        if float(np.dot(bisector, local_tangent)) < 0.0:
            bisector *= -1.0

        # Start the search near the previous purple center's projection onto
        # this exact perpendicular-bisector line.
        base_lambda = float(
            np.dot(placed_center - midpoint, bisector)
        )

        lambda_offsets = np.linspace(
            -V26_TANGENT_BISECTOR_RANGE_R * r0,
            V26_TANGENT_BISECTOR_RANGE_R * r0,
            V26_TANGENT_BISECTOR_STEPS,
        )

        for delta_lambda in lambda_offsets:
            lam = base_lambda + float(delta_lambda)
            center = midpoint + lam * bisector

            # Exact continuous radius through BOTH outline points.
            tangent_radius = float(
                np.linalg.norm(center - p_plus)
            )
            d_minus_exact = float(
                np.linalg.norm(center - p_minus)
            )

            # Numerical sanity: both distances should be identical because
            # center lies on the perpendicular bisector.
            if abs(tangent_radius - d_minus_exact) > 1e-4 * max(tangent_radius, 1.0):
                continue

            radius_ratio = tangent_radius / r0
            if not (
                V26_TANGENT_MIN_RADIUS_TO_CYAN
                <= radius_ratio
                <= V26_TANGENT_MAX_RADIUS_TO_CYAN
            ):
                continue

            candidate_outward = float(
                np.dot(center - original_center, original_outward)
            )

            if (
                candidate_outward
                < placed_outward - V26_TANGENT_MAX_BODYWARD_SHIFT_R * r0
            ):
                continue

            if (
                candidate_outward
                > placed_outward + V26_TANGENT_MAX_EXTRA_OUTWARD_SHIFT_R * r0
            ):
                continue

            overlap = _v14_circle_intersection_fraction(
                original_center,
                r0,
                center,
                tangent_radius,
            )
            if overlap < V26_TANGENT_MIN_CYAN_OVERLAP:
                continue

            # FULL containment check. If rasterization requires a very small
            # shrink, keep it only if BOTH real outline contacts still lie very
            # close to the final purple boundary.
            contained_radius = _v15_exact_contained_radius(
                mask,
                center,
                tangent_radius,
            )

            if contained_radius <= 1.0:
                continue

            final_radius = float(contained_radius)

            error_plus = abs(tangent_radius - final_radius) / max(final_radius, 1e-6)
            error_minus = abs(d_minus_exact - final_radius) / max(final_radius, 1e-6)
            max_error = float(max(error_plus, error_minus))

            if max_error > V26_TANGENT_MAX_RADIAL_ERROR:
                continue

            final_ratio = final_radius / r0
            if final_ratio < V26_TANGENT_MIN_RADIUS_TO_CYAN:
                continue

            # Do not allow refinement to collapse substantially below the
            # already-accepted purple placement.
            if final_radius + 0.25 < placed_radius:
                continue

            # Prefer strong real two-point tangency first, then larger circle.
            tangency_quality = max(
                0.0,
                1.0 - max_error / V26_TANGENT_MAX_RADIAL_ERROR,
            )

            center_move = float(np.linalg.norm(center - placed_center))

            score = float(
                0.46 * tangency_quality
                + 0.28 * min(final_ratio / 1.30, 1.0)
                + 0.16 * min(overlap, 1.0)
                + 0.10 * max(
                    0.0,
                    1.0 - center_move / max(0.50 * r0, 1e-6),
                )
            )

            candidates.append({
                'index': int(idx),
                'center': center.copy(),
                'radius': float(final_radius),
                'tangent_point_plus': np.asarray(p_plus, dtype=float).copy(),
                'tangent_point_minus': np.asarray(p_minus, dtype=float).copy(),
                'continuous_tangent_radius': float(tangent_radius),
                'max_tangency_error': float(max_error),
                'cyan_overlap_fraction': float(overlap),
                'radius_ratio_to_cyan': float(final_ratio),
                'center_move_px': float(center_move),
                'score': float(score),
            })

    if not candidates:
        # IMPORTANT: keep the original purple rather than making it disappear.
        return placed_geom, {
            **placed_diag,
            'post_growth_applied': False,
            'post_growth_reason': 'no_exact_two_tangent_refinement_keep_initial_purple',
            'initial_purple_retained': True,
            'two_tangent_points_required': True,
            'center_locked': False,
            'purple_fully_contained': True,
        }

    best = max(
        candidates,
        key=lambda r: (
            -r['max_tangency_error'],
            r['radius'],
            r['cyan_overlap_fraction'],
            r['score'],
        ),
    )

    final_geom = dict(placed_geom)
    final_geom['index'] = int(best['index'])
    final_geom['center'] = np.asarray(best['center'], dtype=float)
    final_geom['radius'] = float(best['radius'])

    tangent = local_centerline_tangent(
        profile,
        int(best['index']),
    )
    final_geom['tangent'] = tangent
    final_geom['outward'] = (
        -tangent if side == 'left' else tangent
    )

    # Store the ACTUAL two outline tangent points on the geometry itself so the
    # final cut line can use the same points instead of recomputing a different
    # approximate cross-section.
    final_geom['tangent_point_plus'] = np.asarray(
        best['tangent_point_plus'],
        dtype=float,
    )
    final_geom['tangent_point_minus'] = np.asarray(
        best['tangent_point_minus'],
        dtype=float,
    )

    final_diag = {
        **placed_diag,
        **best,
        'post_growth_applied': True,
        'post_growth_reason': 'exact_two_outline_point_tangent_refinement',
        'placed_center_before_growth': placed_center.copy(),
        'placed_radius_before_growth': float(placed_radius),
        'final_radius': float(best['radius']),
        'center_locked': False,
        'purple_fully_contained': True,
        'two_tangent_points_required': True,
        'initial_purple_retained': False,
    }

    return final_geom, final_diag



def _v15_fit_contained_head_circle(
    mask,
    profile,
    cross_section,
    original_circle,
    side,
    head_extension,
    neck_evidence,
):
    """Fit ONLY the selected head-side circle, fully INSIDE the pig mask.

    The search station moves outward toward the head/neck. At each station,
    the two contour hits define the local shoulder chord. The initial center is
    the chord midpoint (not necessarily on the white centerline), then a small
    normal-direction search finds the largest contained/balanced circle.

    V17 IMPORTANT:
    - this is an auxiliary SHOULDER / head-cap circle, not a neck circle;
    - radius must remain at least 0.80x the original cyan head-cap radius;
    - it may be larger than the cyan head cap;
    - the complete purple disk must remain inside the pig mask;
    - it must still overlap the original cyan head cap;
    - only the selected HEAD side is allowed to receive this circle.
    """
    idx0 = int(original_circle['index'])
    r0 = max(float(original_circle['radius']), 1e-6)
    arc = np.asarray(profile['u'], dtype=float)

    original_geom = circle_geometry(profile, original_circle, side)
    c0 = np.asarray(original_geom['center'], dtype=float)
    outward0 = np.asarray(original_geom['outward'], dtype=float)

    target_idx = None
    if neck_evidence is not None:
        target_idx = int(neck_evidence['neck']['neck_index'])
    elif head_extension.get('cut_index') is not None:
        target_idx = int(head_extension['cut_index'])

    if target_idx is None:
        return original_geom, {
            'applied': False,
            'contained': False,
            'reason': 'no_head_neck_target',
        }

    if side == 'left':
        if target_idx >= idx0:
            return original_geom, {
                'applied': False,
                'contained': False,
                'reason': 'target_not_outward',
            }
        stop_idx = min(
            idx0 - 1,
            target_idx + int(V15_FIT_NECK_MARGIN_STATIONS),
        )
        search_indices = range(idx0 - 1, stop_idx - 1, -1)
    elif side == 'right':
        if target_idx <= idx0:
            return original_geom, {
                'applied': False,
                'contained': False,
                'reason': 'target_not_outward',
            }
        stop_idx = max(
            idx0 + 1,
            target_idx - int(V15_FIT_NECK_MARGIN_STATIONS),
        )
        search_indices = range(idx0 + 1, stop_idx + 1)
    else:
        raise ValueError(side)

    plus_points = np.asarray(cross_section['plus_points'], dtype=float)
    minus_points = np.asarray(cross_section['minus_points'], dtype=float)

    mask_u8 = (np.asarray(mask) > 0).astype(np.uint8)
    dt = cv2.distanceTransform(mask_u8, cv2.DIST_L2, 5)

    proposals = []

    for idx in search_indices:
        idx = int(idx)

        p_plus = plus_points[idx]
        p_minus = minus_points[idx]
        if not (
            np.isfinite(p_plus).all()
            and np.isfinite(p_minus).all()
        ):
            continue

        chord_vec = p_plus - p_minus
        chord_len = float(np.linalg.norm(chord_vec))
        if chord_len <= 2.0:
            continue

        midpoint = 0.5 * (p_plus + p_minus)
        tangent = local_centerline_tangent(profile, idx)
        tangent = np.asarray(tangent, dtype=float)
        normal = np.array([-tangent[1], tangent[0]], dtype=float)
        normal_norm = max(float(np.linalg.norm(normal)), 1e-9)
        normal /= normal_norm

        offsets = np.linspace(
            -V15_FIT_NORMAL_SEARCH_R * r0,
            V15_FIT_NORMAL_SEARCH_R * r0,
            int(V15_FIT_NORMAL_SEARCH_STEPS),
        )

        for normal_offset in offsets:
            center = midpoint + float(normal_offset) * normal

            cx = int(round(float(center[0])))
            cy = int(round(float(center[1])))
            if not (
                0 <= cy < dt.shape[0]
                and 0 <= cx < dt.shape[1]
                and mask_u8[cy, cx] > 0
            ):
                continue

            raw_contained_radius = (
                V15_FIT_DISTANCE_TRANSFORM_SCALE
                * float(dt[cy, cx])
            )
            if raw_contained_radius <= 1.0:
                continue

            radius = _v15_exact_contained_radius(
                mask,
                center,
                raw_contained_radius,
            )
            if radius <= 1.0:
                continue

            radius_ratio = float(radius / r0)
            if not (
                V15_FIT_MIN_RADIUS_RATIO
                <= radius_ratio
                <= V15_FIT_MAX_RADIUS_RATIO
            ):
                continue

            d_plus = float(np.linalg.norm(center - p_plus))
            d_minus = float(np.linalg.norm(center - p_minus))
            if min(d_plus, d_minus) <= 1e-6:
                continue

            side_balance = float(
                min(d_plus, d_minus) / max(d_plus, d_minus)
            )
            side_touch_ratio = float(
                min(
                    radius / d_plus,
                    radius / d_minus,
                )
            )

            if side_balance < V15_FIT_MIN_SIDE_BALANCE:
                continue
            if side_touch_ratio < V15_FIT_MIN_SIDE_TOUCH_RATIO:
                continue

            shift_vec = center - c0
            outward_shift = float(np.dot(shift_vec, outward0))
            outward_shift_r = float(outward_shift / r0)

            if outward_shift_r < V15_FIT_MIN_OUTWARD_SHIFT_R:
                continue
            if outward_shift_r > V15_FIT_MAX_OUTWARD_SHIFT_R:
                continue

            overlap = _v14_circle_intersection_fraction(
                c0, r0, center, radius
            )
            if overlap < V15_FIT_MIN_ORIGINAL_OVERLAP:
                continue

            score = float(
                0.44 * min(
                    outward_shift_r / V15_FIT_MAX_OUTWARD_SHIFT_R,
                    1.0,
                )
                + 0.22 * min(side_touch_ratio, 1.0)
                + 0.14 * min(side_balance, 1.0)
                + 0.12 * min(overlap, 1.0)
                + 0.08 * min(radius_ratio, 1.0)
            )

            proposals.append({
                'index': int(idx),
                'center': center.copy(),
                'radius': float(radius),
                'outward_shift_px': float(outward_shift),
                'outward_shift_r': float(outward_shift_r),
                'original_overlap_fraction': float(overlap),
                'side_balance': float(side_balance),
                'side_touch_ratio': float(side_touch_ratio),
                'normal_offset_px': float(normal_offset),
                'radius_ratio_to_original': float(radius_ratio),
                'score': float(score),
                'plus_point': p_plus.copy(),
                'minus_point': p_minus.copy(),
            })

    if not proposals:
        return original_geom, {
            'applied': False,
            'contained': False,
            'reason': 'no_valid_contained_head_circle',
            'target_index': int(target_idx),
        }

    # Furthest safe pre-neck shoulder station first, then best edge/contact fit.
    best = max(
        proposals,
        key=lambda r: (
            r['outward_shift_r'],
            r['side_touch_ratio'],
            r['score'],
        ),
    )

    tangent = local_centerline_tangent(
        profile,
        int(best['index']),
    )
    outward = -tangent if side == 'left' else tangent

    geom = {
        'index': int(best['index']),
        'center': np.asarray(best['center'], dtype=float),
        'radius': float(best['radius']),
        'tangent': tangent,
        'outward': outward,
    }

    diag = dict(best)
    diag.update({
        'applied': True,
        'contained': True,
        'reason': 'contained_offcenter_head_circle',
        'selection_index': int(idx0),
        'selection_center': c0.copy(),
        'selection_radius': float(r0),
        'target_index': int(target_idx),
        'candidate_count': int(len(proposals)),
    })

    return geom, diag


def _v14_choose_head_side(
    sample_id,
    profile,
    neck_stations,
    left_circle,
    right_circle,
    left_extension,
    right_extension,
):
    """V9 selection, with 06Q neck evidence used to prevent rump-side wins.

    This is deliberately NOT another hard bilateral-neck detector. If neither
    side has useful 06Q neck evidence, it falls back to the original V9
    choose_extra_side() behavior so valid V9 head removals are not lost.
    """
    base = choose_extra_side(
        sample_id,
        left_extension,
        right_extension,
    )

    left_neck = _v14_neck_station_for_side(
        profile, neck_stations, left_circle, 'left'
    )
    right_neck = _v14_neck_station_for_side(
        profile, neck_stations, right_circle, 'right'
    )

    def ext_score(ext):
        return (
            float(ext.get('score', 0.0))
            if ext.get('valid', False)
            else 0.0
        )

    def combined(side, ext, neck):
        s = ext_score(ext)

        if ext.get('pattern') == 'neck_then_extra_lobe':
            s += V14_HEAD_PATTERN_BONUS
        elif ext.get('pattern') == 'closing_then_narrow_overextension':
            # A plain taper is allowed as V9 fallback evidence, but it should
            # not beat a side that also has an actual 06Q neck/re-expansion.
            s -= V14_HEAD_TAPER_PENALTY

        if neck is not None:
            s += V14_HEAD_NECK_SCORE_BONUS * float(neck['score'])
            if neck['strong']:
                s += 0.16

        return float(s)

    left_score = combined('left', left_extension, left_neck)
    right_score = combined('right', right_extension, right_neck)

    left_strong = bool(left_neck is not None and left_neck['strong'])
    right_strong = bool(right_neck is not None and right_neck['strong'])

    # One strong neck is the clearest anatomical discriminator.
    if left_strong and not right_strong:
        selected = 'left'
        mode = 'v14_one_strong_06q_neck'
    elif right_strong and not left_strong:
        selected = 'right'
        mode = 'v14_one_strong_06q_neck'
    elif left_strong and right_strong:
        if abs(left_score - right_score) >= V14_HEAD_SCORE_MARGIN:
            selected = 'left' if left_score > right_score else 'right'
            mode = 'v14_two_necks_scored'
        else:
            # Both ends look neck-like; preserve V9's own decision only if it
            # was unambiguous, otherwise do not invent a new cut.
            selected = base.get('selected', 'none')
            if selected == 'both':
                selected = 'none'
            mode = 'v14_two_necks_base_tiebreak'
    else:
        # No strong 06Q neck evidence: preserve V9 behavior, except prefer a
        # real V9 neck->lobe pattern over a pure closing/taper pattern.
        lp = str(left_extension.get('pattern', 'none'))
        rp = str(right_extension.get('pattern', 'none'))

        if (
            lp == 'neck_then_extra_lobe'
            and rp != 'neck_then_extra_lobe'
            and left_extension.get('valid', False)
        ):
            selected = 'left'
            mode = 'v14_v9_neck_pattern_priority'
        elif (
            rp == 'neck_then_extra_lobe'
            and lp != 'neck_then_extra_lobe'
            and right_extension.get('valid', False)
        ):
            selected = 'right'
            mode = 'v14_v9_neck_pattern_priority'
        else:
            selected = base.get('selected', 'none')
            if selected == 'both':
                selected = 'none'
            mode = 'v14_v9_fallback'

    return {
        'mode': mode,
        'selected': selected,
        'ambiguous': selected == 'none',
        'left_score': float(left_score),
        'right_score': float(right_score),
        'base_v9_selection': base,
        'left_neck_evidence': left_neck,
        'right_neck_evidence': right_neck,
    }


def _v14_fit_head_closure_circle(
    mask,
    profile,
    cross_section,
    original_circle,
    side,
    head_extension,
    neck_evidence,
):
    """Fit an off-center circle to the shoulder immediately before the neck.

    At each centerline station, the two contour-hit points define the diameter:
    center = midpoint(plus_point, minus_point)
    radius = 0.5 * distance(plus_point, minus_point)

    Therefore the proposed circle explicitly touches BOTH local pig edges, while
    its center is free to move off the white centerline.
    """
    idx0 = int(original_circle['index'])
    r0 = max(float(original_circle['radius']), 1e-6)
    arc = np.asarray(profile['u'], dtype=float)

    original_geom = circle_geometry(profile, original_circle, side)
    c0 = np.asarray(original_geom['center'], dtype=float)
    outward0 = np.asarray(original_geom['outward'], dtype=float)

    # Prefer the actual 06Q neck station. Fall back to V9's cut index.
    target_idx = None
    if neck_evidence is not None:
        target_idx = int(neck_evidence['neck']['neck_index'])
    elif head_extension.get('cut_index') is not None:
        target_idx = int(head_extension['cut_index'])

    if target_idx is None:
        return original_geom, {
            'applied': False,
            'reason': 'no_neck_or_cut_target',
        }

    if side == 'left':
        if target_idx >= idx0:
            return original_geom, {
                'applied': False,
                'reason': 'target_not_outward',
            }
        last_idx = min(
            idx0 - 1,
            target_idx + int(V14_FIT_NECK_MARGIN_STATIONS),
        )
        search = range(idx0 - 1, last_idx - 1, -1)
    elif side == 'right':
        if target_idx <= idx0:
            return original_geom, {
                'applied': False,
                'reason': 'target_not_outward',
            }
        last_idx = max(
            idx0 + 1,
            target_idx - int(V14_FIT_NECK_MARGIN_STATIONS),
        )
        search = range(idx0 + 1, last_idx + 1)
    else:
        raise ValueError(side)

    plus_points = np.asarray(cross_section['plus_points'], dtype=float)
    minus_points = np.asarray(cross_section['minus_points'], dtype=float)

    proposals = []

    for idx in search:
        idx = int(idx)
        p_plus = plus_points[idx]
        p_minus = minus_points[idx]

        if not (
            np.isfinite(p_plus).all()
            and np.isfinite(p_minus).all()
        ):
            continue

        chord = p_plus - p_minus
        chord_len = float(np.linalg.norm(chord))
        if chord_len <= 1e-6:
            continue

        center = 0.5 * (p_plus + p_minus)
        radius = 0.5 * chord_len * V14_FIT_RADIUS_EDGE_MARGIN

        radius_ratio = float(radius / r0)
        if not (
            V14_FIT_MIN_RADIUS_RATIO
            <= radius_ratio
            <= V14_FIT_MAX_RADIUS_RATIO
        ):
            continue

        shift_vec = center - c0
        outward_shift = float(np.dot(shift_vec, outward0))
        outward_shift_r = float(outward_shift / r0)

        # The new center must move toward the terminal/head, never bodyward.
        if outward_shift_r < V14_FIT_MIN_OUTWARD_SHIFT_R:
            continue
        if outward_shift_r > V14_FIT_MAX_OUTWARD_SHIFT_R:
            continue

        overlap = _v14_circle_intersection_fraction(
            c0, r0, center, radius
        )
        if overlap < V14_FIT_MIN_ORIGINAL_OVERLAP:
            continue

        occupancy = _v14_disk_mask_occupancy(
            mask, center, radius
        )
        if occupancy < V14_FIT_MIN_DISK_MASK_OCCUPANCY:
            continue

        radius_similarity = min(radius, r0) / max(radius, r0)
        score = float(
            0.52 * min(outward_shift_r / V14_FIT_MAX_OUTWARD_SHIFT_R, 1.0)
            + 0.22 * min(overlap, 1.0)
            + 0.16 * min(occupancy, 1.0)
            + 0.10 * radius_similarity
        )

        proposals.append({
            'index': idx,
            'center': center,
            'radius': float(radius),
            'outward_shift_px': float(outward_shift),
            'outward_shift_r': float(outward_shift_r),
            'original_overlap_fraction': float(overlap),
            'disk_mask_occupancy': float(occupancy),
            'radius_ratio_to_original': float(radius_ratio),
            'score': float(score),
            'plus_point': p_plus.copy(),
            'minus_point': p_minus.copy(),
        })

    if not proposals:
        return original_geom, {
            'applied': False,
            'reason': 'no_valid_two_edge_circle',
            'target_index': int(target_idx),
        }

    # Prefer the farthest valid shoulder position; use score only as a tiebreak.
    best = max(
        proposals,
        key=lambda r: (r['outward_shift_r'], r['score']),
    )

    tangent = local_centerline_tangent(
        profile,
        int(best['index']),
    )
    outward = -tangent if side == 'left' else tangent

    geom = {
        'index': int(best['index']),
        'center': np.asarray(best['center'], dtype=float),
        'radius': float(best['radius']),
        'tangent': tangent,
        'outward': outward,
    }

    diag = dict(best)
    diag.update({
        'applied': True,
        'reason': 'offcenter_two_edge_head_circle',
        'selection_index': int(idx0),
        'selection_center': c0.copy(),
        'selection_radius': float(r0),
        'target_index': int(target_idx),
        'candidate_count': int(len(proposals)),
    })

    return geom, diag


def _v14_candidate_from_geometry(original, geometry):
    out = original.copy()
    idx = int(geometry['index'])
    out['index'] = idx
    out['x'] = float(geometry['center'][0])
    out['y'] = float(geometry['center'][1])
    out['radius'] = float(geometry['radius'])
    return out


def decompose_circle_pair_first(
    ji_mask,
    sample_id,
):
    ji_mask = _binary(
        ji_mask
    )

    skeleton, path_yx = build_medial_axis(
        ji_mask
    )

    profile = resample_centerline_profile(
        ji_mask,
        path_yx,
    )

    (
        raw_candidates,
        sharp_candidates,
        broad_candidates,
        neck_anchored_candidates,
        neck_stations,
        cross_section_profile,
    ) = generate_circle_candidates(
        ji_mask,
        profile,
    )

    candidates = classify_circle_candidates(
        profile,
        raw_candidates,
    )

    pair, pair_records = choose_body_circle_pair(
        profile,
        candidates,
    )

    failed_pair = best_failed_pair(
        pair_records
    )

    if pair is None:
        return {
            'status': 'no_valid_circle_pair',
            'ji_mask': ji_mask,
            'skeleton': skeleton,
            'profile': profile,

            'sharp_circle_candidates': sharp_candidates,
            'broad_circle_candidates': broad_candidates,
            'neck_anchored_candidates': neck_anchored_candidates,
            'neck_stations': neck_stations,
            'cross_section_profile': cross_section_profile,
            'raw_circle_candidates': raw_candidates,
            'circle_candidates': candidates,

            'body_circle_pair': None,
            'best_failed_pair': failed_pair,
            'pair_records': pair_records,

            'overlay': np.dstack([
                ji_mask * 145
            ] * 3).astype(
                np.uint8
            ),

            'preview': ji_mask.copy(),
            'left_preview': ji_mask.copy(),
            'right_preview': ji_mask.copy(),
            'proposal_side': None,

            'left_extension': {},
            'right_extension': {},
            'selection': None,
        }

    left = pair[
        'left'
    ]

    right = pair[
        'right'
    ]

    left_geom = circle_geometry(
        profile,
        left,
        'left',
    )

    right_geom = circle_geometry(
        profile,
        right,
        'right',
    )

    left_extension = analyze_extension_beyond_circle(
        profile,
        left,
        'left',
    )

    right_extension = analyze_extension_beyond_circle(
        profile,
        right,
        'right',
    )

    selection = _v16_choose_head_side(
        sample_id,
        profile,
        neck_stations,
        left,
        right,
        left_extension,
        right_extension,
    )

    # V17 GEOMETRY SEPARATION
    # -----------------------
    # left_geom/right_geom are the ORIGINAL 06Q anchor circles and NEVER move:
    #   CYAN  = original selected HEAD cap
    #   GREEN = original selected RUMP cap
    #
    # Purple is a separate auxiliary HEAD-only closure circle.
    # It does NOT replace/move the cyan cap and does NOT extend the blue torso.
    selected = selection.get('selected', 'none')

    purple_head_geom = None
    head_circle_refinement = {
        'applied': False,
        'contained': False,
        'reason': 'no_selected_head',
    }

    if selected == 'left':
        fitted_geom, head_circle_refinement = _v15_fit_contained_head_circle(
            ji_mask,
            profile,
            cross_section_profile,
            left,
            'left',
            left_extension,
            selection.get('left_neck_evidence'),
        )
        if head_circle_refinement.get('applied', False):
            (
                fitted_geom,
                head_circle_refinement,
            ) = _v26_refine_purple_exact_two_tangent(
                ji_mask,
                profile,
                cross_section_profile,
                left,
                'left',
                fitted_geom,
                head_circle_refinement,
            )
            purple_head_geom = fitted_geom

    elif selected == 'right':
        fitted_geom, head_circle_refinement = _v15_fit_contained_head_circle(
            ji_mask,
            profile,
            cross_section_profile,
            right,
            'right',
            right_extension,
            selection.get('right_neck_evidence'),
        )
        if head_circle_refinement.get('applied', False):
            (
                fitted_geom,
                head_circle_refinement,
            ) = _v26_refine_purple_exact_two_tangent(
                ji_mask,
                profile,
                cross_section_profile,
                right,
                'right',
                fitted_geom,
                head_circle_refinement,
            )
            purple_head_geom = fitted_geom

    # Purple is OPTIONAL. If a safe head-cap-sized purple circle cannot be fit,
    # crop using the original cyan 06Q head circle instead.
    head_crop_geometry_source = (
        'contained_auxiliary_purple'
        if purple_head_geom is not None
        else 'original_06q_cyan_head_circle'
    )

    # Actual crop geometry is separate from the structure/anchor geometry.
    left_crop_geom = left_geom
    right_crop_geom = right_geom

    if selected == 'left' and purple_head_geom is not None:
        left_crop_geom = purple_head_geom
    elif selected == 'right' and purple_head_geom is not None:
        right_crop_geom = purple_head_geom

    ys, xs, nearest = nearest_profile_index_for_mask_pixels(
        ji_mask,
        profile,
    )

    n_pixels = len(xs)

    pixel_label = np.full(
        n_pixels,
        'unresolved',
        dtype=object,
    )

    # --------------------------------------------------------
    # BLUE BODY: between circle-center positions.
    # --------------------------------------------------------

    between_centers = (
        (nearest >= int(left['index']))
        & (nearest <= int(right['index']))
    )

    pixel_label[
        between_centers
    ] = 'body'

    # --------------------------------------------------------
    # DIRECT SELECTED-CIRCLE GEOMETRY.
    # --------------------------------------------------------

    # ORIGINAL anchor-circle coordinates for the readable structure panel.
    left_dist, left_out = pixel_circle_coordinates(
        xs,
        ys,
        left_geom,
    )

    right_dist, right_out = pixel_circle_coordinates(
        xs,
        ys,
        right_geom,
    )

    # Separate closure coordinates. Only the selected HEAD side can differ,
    # and only when the auxiliary purple fit succeeds.
    left_crop_dist, left_crop_out = pixel_circle_coordinates(
        xs,
        ys,
        left_crop_geom,
    )

    right_crop_dist, right_crop_out = pixel_circle_coordinates(
        xs,
        ys,
        right_crop_geom,
    )

    left_cap = (
        left_out
        >= (
            -CAP_INWARD_VISUAL_OVERLAP
            * left_geom['radius']
        )
    ) & (
        left_dist
        <= (
            CAP_DISK_RADIUS_FACTOR
            * left_geom['radius']
        )
    )

    right_cap = (
        right_out
        >= (
            -CAP_INWARD_VISUAL_OVERLAP
            * right_geom['radius']
        )
    ) & (
        right_dist
        <= (
            CAP_DISK_RADIUS_FACTOR
            * right_geom['radius']
        )
    )

    pixel_label[
        left_cap
    ] = 'left_cap'

    pixel_label[
        right_cap
    ] = 'right_cap'

    # V19: show the actual-mask shoulder corridor between fixed CYAN and PURPLE
    # as part of the HEAD CAP. This does not alter the original mask outline.
    if selected == 'left' and purple_head_geom is not None:
        bridge_lo = min(int(left['index']), int(purple_head_geom['index']))
        bridge_hi = max(int(left['index']), int(purple_head_geom['index']))
        structure_bridge = (
            (nearest >= bridge_lo)
            & (nearest <= bridge_hi)
        )
        pixel_label[structure_bridge] = 'left_cap'

    elif selected == 'right' and purple_head_geom is not None:
        bridge_lo = min(int(right['index']), int(purple_head_geom['index']))
        bridge_hi = max(int(right['index']), int(purple_head_geom['index']))
        structure_bridge = (
            (nearest >= bridge_lo)
            & (nearest <= bridge_hi)
        )
        pixel_label[structure_bridge] = 'right_cap'

    # --------------------------------------------------------
    # Pixels geometrically beyond each accepted circle.
    # --------------------------------------------------------

    left_outside_circle = (
        (left_crop_out > 0)
        & (
            left_crop_dist
            > (
                CAP_DISK_RADIUS_FACTOR
                * left_crop_geom['radius']
            )
        )
    )

    right_outside_circle = (
        (right_crop_out > 0)
        & (
            right_crop_dist
            > (
                CAP_DISK_RADIUS_FACTOR
                * right_crop_geom['radius']
            )
        )
    )

    # Always generate BOTH closure previews for debugging.
    # When PURPLE exists, preserve the original cyan->purple shoulder corridor.
    left_head_bridge = np.zeros(n_pixels, dtype=bool)
    right_head_bridge = np.zeros(n_pixels, dtype=bool)

    if selected == 'left' and purple_head_geom is not None:
        (
            left_preview,
            left_remove_pixels,
            left_head_bridge,
        ) = _apply_v19_auxiliary_head_closure_preview(
            ji_mask,
            ys,
            xs,
            nearest,
            left_crop_dist,
            left_crop_out,
            left_crop_geom,
            original_head_index=int(left['index']),
            purple_index=int(purple_head_geom['index']),
            side='left',
            profile=profile,
            cross_section=cross_section_profile,
        )
    else:
        (
            left_preview,
            left_remove_pixels,
        ) = _apply_circle_closure_preview(
            ji_mask,
            ys,
            xs,
            left_crop_dist,
            left_crop_out,
            left_crop_geom,
        )

    if selected == 'right' and purple_head_geom is not None:
        (
            right_preview,
            right_remove_pixels,
            right_head_bridge,
        ) = _apply_v19_auxiliary_head_closure_preview(
            ji_mask,
            ys,
            xs,
            nearest,
            right_crop_dist,
            right_crop_out,
            right_crop_geom,
            original_head_index=int(right['index']),
            purple_index=int(purple_head_geom['index']),
            side='right',
            profile=profile,
            cross_section=cross_section_profile,
        )
    else:
        (
            right_preview,
            right_remove_pixels,
        ) = _apply_circle_closure_preview(
            ji_mask,
            ys,
            xs,
            right_crop_dist,
            right_crop_out,
            right_crop_geom,
        )

    # --------------------------------------------------------
    # Geometry-only proposal side.
    #
    # This does not require confidence=True. It answers:
    # "which accepted circle has the larger amount of mask
    # continuing beyond its expected rounded cap?"
    # --------------------------------------------------------

    left_removed_pixels = int(
        np.count_nonzero(
            left_remove_pixels
        )
    )

    right_removed_pixels = int(
        np.count_nonzero(
            right_remove_pixels
        )
    )

    left_circle_area = max(
        np.pi
        * left_crop_geom['radius'] ** 2,
        1.0,
    )

    right_circle_area = max(
        np.pi
        * right_crop_geom['radius'] ** 2,
        1.0,
    )

    left_pixel_extension_ratio = float(
        left_removed_pixels
        / left_circle_area
    )

    right_pixel_extension_ratio = float(
        right_removed_pixels
        / right_circle_area
    )

    left_centerline_ratio = float(
        left_extension.get(
            'centerline_extension_ratio',
            0.0,
        )
    )

    right_centerline_ratio = float(
        right_extension.get(
            'centerline_extension_ratio',
            0.0,
        )
    )

    left_proposal_score = (
        0.65
        * left_pixel_extension_ratio
        + 0.35
        * left_centerline_ratio
    )

    right_proposal_score = (
        0.65
        * right_pixel_extension_ratio
        + 0.35
        * right_centerline_ratio
    )

    proposal_side = (
        'left'
        if left_proposal_score
        > right_proposal_score
        else 'right'
    )

    # --------------------------------------------------------
    # RED/YELLOW still represent the confidence-gated detector.
    # --------------------------------------------------------

    selected = selection.get(
        'selected',
        'none',
    )

    if (
        selected == 'left'
    ):
        pixel_label[
            left_outside_circle
        ] = 'extra'

    if (
        selected == 'right'
    ):
        pixel_label[
            right_outside_circle
        ] = 'extra'

    for side, analysis in [
        (
            'left',
            left_extension,
        ),
        (
            'right',
            right_extension,
        ),
    ]:
        if (
            analysis.get(
                'cut_index'
            )
            is None
        ):
            continue

        if (
            selected
            not in {
                side,
                'both',
            }
        ):
            continue

        cut_idx = int(
            analysis[
                'cut_index'
            ]
        )

        band = max(
            1,
            int(
                NECK_BAND_POINTS
            ),
        )

        neck_pixels = (
            nearest
            >= max(
                0,
                cut_idx - band,
            )
        ) & (
            nearest
            <= min(
                len(
                    profile['radius']
                ) - 1,
                cut_idx + band,
            )
        )

        if side == 'left':
            neck_pixels &= (
                nearest
                <= int(
                    left['index']
                )
            )
        else:
            neck_pixels &= (
                nearest
                >= int(
                    right['index']
                )
            )

        pixel_label[
            neck_pixels
        ] = 'neck'

    # --------------------------------------------------------
    # Color overlay.
    # --------------------------------------------------------

    overlay = np.zeros(
        (
            ji_mask.shape[0],
            ji_mask.shape[1],
            3,
        ),
        dtype=np.uint8,
    )

    # V15 anatomical color convention:
    #   BLUE  = torso/body between the two anchor circles
    #   CYAN  = HEAD-SIDE body/shoulder cap
    #   GREEN = RUMP-SIDE cap (never cut)
    #   RED   = head pixels selected for removal
    #   PURPLE outline = refined contained HEAD circle only
    if selected == 'left':
        left_cap_color = V15_COLOR_HEAD_CAP
        right_cap_color = V15_COLOR_RUMP_CAP
    elif selected == 'right':
        left_cap_color = V15_COLOR_RUMP_CAP
        right_cap_color = V15_COLOR_HEAD_CAP
    else:
        left_cap_color = COLOR_LEFT_CAP
        right_cap_color = COLOR_RIGHT_CAP

    colors = {
        'body': COLOR_BODY,
        'left_cap': left_cap_color,
        'right_cap': right_cap_color,
        'neck': COLOR_NECK,
        'extra': COLOR_EXTRA,
        'unresolved': COLOR_UNRESOLVED,
    }

    for name, color in colors.items():
        sel = (
            pixel_label
            == name
        )

        overlay[
            ys[sel],
            xs[sel],
        ] = color

    for x, y in zip(
        profile['xi'],
        profile['yi'],
    ):
        cv2.circle(
            overlay,
            (
                int(x),
                int(y),
            ),
            1,
            (
                255,
                255,
                255,
            ),
            -1,
        )

    # V17: purple is a separate auxiliary HEAD circle.
    # It never moves/replaces the cyan head cap.
    if purple_head_geom is not None:
        cv2.circle(
            overlay,
            (
                int(round(float(purple_head_geom['center'][0]))),
                int(round(float(purple_head_geom['center'][1]))),
            ),
            max(1, int(round(float(purple_head_geom['radius'])))),
            V14_REFINED_CIRCLE_COLOR,
            2,
            cv2.LINE_AA,
        )

    # Explicit anatomical labels so left/right ordering is never confused with
    # head/rump. Purple can appear ONLY on the HEAD CAP.
    if selected in {'left', 'right'}:
        # Anatomical labels stay on the ORIGINAL 06Q anchors.
        head_geom = left_geom if selected == 'left' else right_geom
        rump_geom = right_geom if selected == 'left' else left_geom

        def _v15_put_cap_label(geom, label, color):
            px = int(round(float(geom['center'][0])))
            py = int(round(float(geom['center'][1])))
            cv2.putText(
                overlay,
                label,
                (max(2, px - 28), max(12, py - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.34,
                tuple(int(v) for v in color.tolist()),
                1,
                cv2.LINE_AA,
            )

        _v15_put_cap_label(
            head_geom,
            'HEAD CAP',
            V15_COLOR_HEAD_CAP,
        )
        _v15_put_cap_label(
            rump_geom,
            'RUMP CAP',
            V15_COLOR_RUMP_CAP,
        )

        # Small diagnostic showing whether actual removal uses the optional
        # purple refinement or the original 06Q head circle.
        cv2.putText(
            overlay,
            (
                'HEAD CROP: PURPLE'
                if purple_head_geom is not None
                else 'HEAD CROP: ORIGINAL 06Q'
            ),
            (4, max(14, overlay.shape[0] - 6)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.32,
            (255, 255, 255),
            1,
            cv2.LINE_AA,
        )

    # --------------------------------------------------------
    # AUTO PREVIEW
    #
    # If detector is confident, use its selected side.
    # Otherwise, for visual tuning only, use the geometry-only
    # proposal side so the preview is NOT identical to Ji/Duan.
    # --------------------------------------------------------

    if (
        selected == 'left'
    ):
        preview = left_preview.copy()
        preview_mode = 'confidence_gated_left'

    elif (
        selected == 'right'
    ):
        preview = right_preview.copy()
        preview_mode = 'confidence_gated_right'

    elif (
        SHOW_FORCED_GEOMETRY_PREVIEW
        and proposal_side == 'left'
    ):
        preview = left_preview.copy()
        preview_mode = 'forced_geometry_left'

    elif (
        SHOW_FORCED_GEOMETRY_PREVIEW
        and proposal_side == 'right'
    ):
        preview = right_preview.copy()
        preview_mode = 'forced_geometry_right'

    else:
        preview = ji_mask.copy()
        preview_mode = 'unchanged'

    # Purple is auxiliary and must NOT redefine the V9 pair geometry.
    # Record only its size/shift diagnostics; the original pair gap remains
    # the pair-selection diagnostic.
    post_refine_gap_ratio = float('nan')

    return {
        'status': 'ok',
        'ji_mask': ji_mask,
        'skeleton': skeleton,
        'profile': profile,

        'sharp_circle_candidates': sharp_candidates,
        'broad_circle_candidates': broad_candidates,
        'neck_anchored_candidates': neck_anchored_candidates,
        'neck_stations': neck_stations,
        'cross_section_profile': cross_section_profile,
        'raw_circle_candidates': raw_candidates,
        'circle_candidates': candidates,

        'body_circle_pair': pair,
        'best_failed_pair': failed_pair,
        'pair_records': pair_records,

        'left_geometry': left_geom,
        'right_geometry': right_geom,
        'left_crop_geometry': left_crop_geom,
        'right_crop_geometry': right_crop_geom,
        'purple_head_geometry': purple_head_geom,
        'head_circle_refinement': head_circle_refinement,
        'head_selection_method': selection.get('mode'),
        'head_side': selected,
        'head_crop_geometry_source': head_crop_geometry_source,
        'purple_required_for_crop': False,
        'purple_growth_applied': bool(
            head_circle_refinement.get('post_growth_applied', False)
        ),
        'purple_growth_reason': head_circle_refinement.get(
            'post_growth_reason'
        ),
        'purple_center_locked': bool(
            head_circle_refinement.get('center_locked', False)
        ),
        'purple_fully_contained': bool(
            head_circle_refinement.get('purple_fully_contained', True)
        ),
        'purple_two_tangent_points_required': bool(
            head_circle_refinement.get('two_tangent_points_required', False)
        ),
        'purple_max_tangency_error': head_circle_refinement.get(
            'max_tangency_error'
        ),
        'purple_initial_fit_retained': bool(
            head_circle_refinement.get('initial_purple_retained', False)
        ),
        'purple_cut_rule': (
            'exact_tangent_chord__remove_head_side_outside_circle__body_side_always_kept'
        ),
        'purple_min_radius_to_cyan': 0.90,
        'purple_head_radius_ratio_to_cyan': (
            float(purple_head_geom['radius'])
            / max(
                float(
                    left_geom['radius']
                    if selected == 'left'
                    else right_geom['radius']
                ),
                1e-6,
            )
            if purple_head_geom is not None
            else None
        ),
        'rump_side': (
            'right' if selected == 'left'
            else 'left' if selected == 'right'
            else None
        ),
        'left_head_eligible': bool(selection.get('left_eligible', False)),
        'right_head_eligible': bool(selection.get('right_eligible', False)),
        'left_head_diagnostics': selection.get('left_head_diagnostics'),
        'right_head_diagnostics': selection.get('right_head_diagnostics'),

        'left_extension': left_extension,
        'right_extension': right_extension,
        'selection': selection,

        'left_removed_pixels': left_removed_pixels,
        'right_removed_pixels': right_removed_pixels,
        'left_pixel_extension_ratio': left_pixel_extension_ratio,
        'right_pixel_extension_ratio': right_pixel_extension_ratio,
        'left_proposal_score': float(
            left_proposal_score
        ),
        'right_proposal_score': float(
            right_proposal_score
        ),
        'proposal_side': proposal_side,

        'pixel_label': pixel_label,
        'overlay': overlay,

        'left_preview': left_preview,
        'right_preview': right_preview,
        'preview': preview,
        'preview_mode': preview_mode,
    }


def _selected_closure_side(preview_mode: str | None) -> Optional[str]:
    mode = str(preview_mode or "")
    if mode.endswith("_left"):
        return "left"
    if mode.endswith("_right"):
        return "right"
    return None


def _isolate_body_only_mask_fixed06q(
    whole_pig_mask,
    *,
    sample_id: Optional[str] = None,
    ji_config: Optional[dict] = None,
) -> Dict[str, Any]:
    """Run the finalized fixed-06Q body-mask pipeline.

    Returns a dictionary rather than only the mask so Notebook 6 can retain
    preprocessing provenance/QC for every extracted feature row.

    A feature-training row should normally require:
        result["status"] == "ok"
        result["pair_valid"] is True
        result["head_removal_applied"] is True
    """
    whole_mask = _binary(whole_pig_mask)

    ji_mask = _binary(
        apply_ji_duan(
            whole_mask,
            ji_config=ji_config,
        )
    )

    circle_input_mask, residual_diag = cleanup_residual_lateral_appendages(
        ji_mask
    )

    dec = decompose_circle_pair_first(
        circle_input_mask,
        sample_id="" if sample_id is None else str(sample_id),
    )

    final_mask = _binary(
        dec.get(
            "preview",
            circle_input_mask,
        )
    )

    removed_from_circle_input = (
        (circle_input_mask > 0)
        & (final_mask == 0)
    )

    circle_input_area = max(
        int(np.count_nonzero(circle_input_mask)),
        1,
    )

    removed_pixels = int(
        np.count_nonzero(
            removed_from_circle_input
        )
    )

    preview_mode = str(
        dec.get(
            "preview_mode",
            "unchanged",
        )
    )

    pair_valid = bool(
        dec.get(
            "body_circle_pair"
        )
        is not None
    )

    head_removal_applied = bool(
        pair_valid
        and removed_pixels > 0
        and preview_mode != "unchanged"
    )

    return {
        "mask": final_mask,
        "status": str(dec.get("status", "unknown")),
        "protocol_version": BODY_MASK_PROTOCOL_VERSION,

        "pair_valid": pair_valid,
        "head_removal_applied": head_removal_applied,
        "preview_mode": preview_mode,
        "selected_closure_side": _selected_closure_side(
            preview_mode
        ),

        "neck_count": int(
            len(
                dec.get(
                    "neck_stations",
                    [],
                )
            )
        ),

        "removed_head_pixels": removed_pixels,
        "removed_head_fraction": float(
            removed_pixels
            / circle_input_area
        ),

        "residual_cleanup_status": str(
            residual_diag.get(
                "status",
                "unknown",
            )
        ),
        "residual_removed_fraction": float(
            residual_diag.get(
                "removed_area_fraction",
                0.0,
            )
        ),

        "whole_mask_area_px": int(
            np.count_nonzero(
                whole_mask
            )
        ),
        "ji_mask_area_px": int(
            np.count_nonzero(
                ji_mask
            )
        ),
        "circle_input_area_px": int(
            np.count_nonzero(
                circle_input_mask
            )
        ),
        "body_mask_area_px": int(
            np.count_nonzero(
                final_mask
            )
        ),

        # Detailed diagnostics remain available when needed,
        # but are not serialized into the feature CSV.
        "decomposition": dec,
        "residual_cleanup": residual_diag,
    }


# ============================================================================
# V26 BASELINE = V25 + 0.90 MIN PURPLE + EXACT TWO-OUTLINE TANGENCY + EXACT CHORD BODY-SIDE PRESERVATION
# ============================================================================
# IMPORTANT:
#   The fixed-06Q candidate generation, neck refinement, candidate
#   classification, circle geometry, extension analysis, and closure code above
#   are intentionally unchanged. Only choose_body_circle_pair() is overridden.
#
# Priority is lexicographic by tier:
#   1) >=0.80 radius similarity + >=1.00R curved centerline gap
#   2) >=0.70 radius similarity + >=1.00R curved centerline gap
#   3) >=0.80 radius similarity + relaxed curved gap
#   4) >=0.70 radius similarity + relaxed curved gap
#
# This preserves the original 1R preference whenever possible, allows the
# known near-0.80 similarity failure as a controlled fallback, then relaxes the
# gap only when no full-gap pair exists.

V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY = 0.70
V9_RELAXED_GAP_DEFICIT_WEIGHT = 0.20
BODY_MASK_METHOD = 'ji_duan_residual_06q_v9_headfit_exact_twotangent'

# Capture the exact fixed-06Q chooser before overriding its public name.


def _v9_segment_inside_circle_interval(p0, p1, center, radius):
    p0 = np.asarray(p0, dtype=float)
    p1 = np.asarray(p1, dtype=float)
    center = np.asarray(center, dtype=float)
    d = p1 - p0
    f = p0 - center
    aa = float(np.dot(d, d))

    if aa <= 1e-12:
        return (
            (0.0, 1.0)
            if float(np.dot(f, f)) <= float(radius) ** 2
            else None
        )

    bb = 2.0 * float(np.dot(f, d))
    cc = float(np.dot(f, f) - float(radius) ** 2)
    disc = bb * bb - 4.0 * aa * cc

    inside0 = cc <= 0.0
    end_rel = p1 - center
    inside1 = float(np.dot(end_rel, end_rel)) <= float(radius) ** 2

    if disc < 0.0:
        return (0.0, 1.0) if inside0 and inside1 else None

    root = float(np.sqrt(max(disc, 0.0)))
    t0 = (-bb - root) / (2.0 * aa)
    t1 = (-bb + root) / (2.0 * aa)
    lo = max(0.0, min(t0, t1))
    hi = min(1.0, max(t0, t1))

    if hi <= lo:
        return (0.0, 1.0) if inside0 and inside1 else None

    return float(lo), float(hi)


def _v9_merge_unit_intervals(intervals):
    if not intervals:
        return []

    rows = sorted(
        (
            max(0.0, float(lo)),
            min(1.0, float(hi)),
        )
        for lo, hi in intervals
        if float(hi) > float(lo)
    )

    merged = []
    for lo, hi in rows:
        if not merged or lo > merged[-1][1] + 1e-9:
            merged.append([lo, hi])
        else:
            merged[-1][1] = max(merged[-1][1], hi)

    return [(float(lo), float(hi)) for lo, hi in merged]


def _v9_outside_unit_intervals(inside_intervals):
    inside = _v9_merge_unit_intervals(inside_intervals)

    if not inside:
        return [(0.0, 1.0)]

    outside = []
    cursor = 0.0

    for lo, hi in inside:
        if lo > cursor + 1e-9:
            outside.append((cursor, lo))
        cursor = max(cursor, hi)

    if cursor < 1.0 - 1e-9:
        outside.append((cursor, 1.0))

    return outside


def centerline_shaft_gap_geometry(profile, a, b):
    """Curved centerline length outside BOTH circles between circle stations.

    This is the blue-gap definition from the earlier 06Q diagnostic: follow the
    ordered medial centerline, not the straight Euclidean chord joining circle
    centers, and count only centerline pieces lying outside both selected disks.
    """
    if int(a['index']) > int(b['index']):
        a, b = b, a

    ia = int(a['index'])
    ib = int(b['index'])

    x = np.asarray(profile['x'], dtype=float)
    y = np.asarray(profile['y'], dtype=float)
    arc = np.asarray(profile['u'], dtype=float)

    center_a = np.array([float(a['x']), float(a['y'])], dtype=float)
    center_b = np.array([float(b['x']), float(b['y'])], dtype=float)
    radius_a = float(a['radius'])
    radius_b = float(b['radius'])

    pieces = []
    total = 0.0

    for k in range(ia, ib):
        p0 = np.array([x[k], y[k]], dtype=float)
        p1 = np.array([x[k + 1], y[k + 1]], dtype=float)
        segment_arc = float(arc[k + 1] - arc[k])

        if segment_arc <= 0.0:
            continue

        inside = []
        interval_a = _v9_segment_inside_circle_interval(
            p0, p1, center_a, radius_a
        )
        interval_b = _v9_segment_inside_circle_interval(
            p0, p1, center_b, radius_b
        )

        if interval_a is not None:
            inside.append(interval_a)
        if interval_b is not None:
            inside.append(interval_b)

        for t0, t1 in _v9_outside_unit_intervals(inside):
            if t1 <= t0:
                continue

            q0 = p0 + float(t0) * (p1 - p0)
            q1 = p0 + float(t1) * (p1 - p0)
            piece_length = float(segment_arc * (t1 - t0))

            if piece_length <= 1e-9:
                continue

            total += piece_length
            pieces.append({
                'p0': q0,
                'p1': q1,
                'length_px': piece_length,
                'arc_start_px': float(arc[k] + t0 * segment_arc),
                'arc_end_px': float(arc[k] + t1 * segment_arc),
            })

    return {
        'centerline_shaft_gap_px': float(total),
        'centerline_shaft_gap_segments': pieces,
        'centerline_shaft_gap_segment_count': int(len(pieces)),
    }


def _v9_raw_adjusted_score(row):
    return float(
        row.get('base_score', 0.0)
        - row.get('local_candidate_penalty', 0.0)
        + row.get('neck_anchor_bonus', 0.0)
    )


def _v9_first_eligible_tier(rows):
    tier_specs = [
        (
            'strict80_full1R',
            lambda r: (
                r['structural_ok']
                and r['radius_similarity'] >= MIN_PAIR_RADIUS_SIMILARITY
                and r['centerline_gap_ok']
            ),
        ),
        (
            'relaxed70_full1R',
            lambda r: (
                r['structural_ok']
                and r['radius_similarity'] >= V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY
                and r['centerline_gap_ok']
            ),
        ),
        (
            'strict80_relaxed_gap',
            lambda r: (
                r['structural_ok']
                and r['radius_similarity'] >= MIN_PAIR_RADIUS_SIMILARITY
            ),
        ),
        (
            'relaxed70_relaxed_gap',
            lambda r: (
                r['structural_ok']
                and r['radius_similarity'] >= V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY
            ),
        ),
    ]

    for tier_name, predicate in tier_specs:
        pool = [row for row in rows if predicate(row)]
        if pool:
            return tier_name, pool

    return None, []


def choose_body_circle_pair(profile, candidates):
    """Fixed-06Q pair ranking with curved-gap and controlled fallback tiers."""
    # Generate exact fixed-06Q pair records. We reuse its candidate pair score,
    # local neck/terminal penalties, anchor bonus, and every non-gap diagnostic.
    _, original_records = _choose_body_circle_pair_fixed06q(
        profile,
        candidates,
    )

    rows = []

    for source_row in original_records:
        row = dict(source_row)
        left = row['left']
        right = row['right']

        r_small = max(
            min(float(left['radius']), float(right['radius'])),
            1e-6,
        )

        blue = centerline_shaft_gap_geometry(
            profile,
            left,
            right,
        )

        curved_gap = float(blue['centerline_shaft_gap_px'])
        required_gap = float(CIRCLE_EDGE_GAP_RADIUS_FRACTION * r_small)
        curved_gap_ratio = float(curved_gap / r_small)
        curved_gap_ok = bool(curved_gap >= required_gap)

        radius_similarity = float(row.get('radius_similarity', 0.0))
        strict80_ok = bool(radius_similarity >= MIN_PAIR_RADIUS_SIMILARITY)
        relaxed70_ok = bool(
            radius_similarity >= V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY
        )

        structural_ok = bool(
            row.get('arc_ok', False)
            and row.get('shaft_floor_ok', False)
            and row.get('shaft_median_ok', False)
        )

        gap_deficit_ratio = max(0.0, 1.0 - curved_gap_ratio)
        raw_adjusted = _v9_raw_adjusted_score(row)

        # Keep straight-line 06Q diagnostics under explicit names, then make the
        # compatibility edge_gap fields represent the NEW curved measurement.
        row['euclidean_center_distance_px'] = float(
            row.get('center_distance_px', np.nan)
        )
        row['euclidean_edge_gap_px'] = float(
            row.get('edge_gap_px', np.nan)
        )
        row['euclidean_gap_ok_original06q'] = bool(
            row.get('gap_ok', False)
        )

        row['centerline_shaft_gap_px'] = curved_gap
        row['centerline_gap_ratio_to_smaller_radius'] = curved_gap_ratio
        row['centerline_gap_ok'] = curved_gap_ok
        row['centerline_shaft_gap_segments'] = blue[
            'centerline_shaft_gap_segments'
        ]
        row['centerline_shaft_gap_segment_count'] = blue[
            'centerline_shaft_gap_segment_count'
        ]

        row['edge_gap_px'] = curved_gap
        row['required_edge_gap_px'] = required_gap
        row['gap_ok'] = curved_gap_ok

        row['size_ok_strict80'] = strict80_ok
        row['size_ok_relaxed70'] = relaxed70_ok
        # `size_ok` now means the final hard floor of the tiered policy.
        row['size_ok'] = relaxed70_ok
        row['structural_ok'] = structural_ok

        row['gap_relaxed_candidate'] = bool(not curved_gap_ok)
        row['radius_similarity_relaxed_candidate'] = bool(
            relaxed70_ok and not strict80_ok
        )

        row['raw_06q_adjusted_score'] = raw_adjusted
        row['centerline_gap_deficit_ratio'] = gap_deficit_ratio

        # For gap-relaxed tiers only, stay conservative: a pair just below 1R
        # is preferred over an equally good pair with a very small exposed gap.
        row['relaxed_gap_policy_score'] = float(
            raw_adjusted
            - V9_RELAXED_GAP_DEFICIT_WEIGHT * gap_deficit_ratio
        )

        # Final policy rejects only similarity <0.70 or the original arc/shaft
        # structural failures. The full 1R gap is a tier preference, not the
        # ultimate rejection condition.
        final_policy_valid = bool(structural_ok and relaxed70_ok)
        row['valid'] = final_policy_valid

        violations = []
        if not relaxed70_ok:
            violations.append('radius_similarity_below_70pct')
        if not row.get('arc_ok', False):
            violations.append('insufficient_arc_separation')
        if not row.get('shaft_floor_ok', False):
            violations.append('deep_neck_between_pair')
        if not row.get('shaft_median_ok', False):
            violations.append('connecting_body_too_narrow')

        row['violations'] = violations
        row['reason'] = None if final_policy_valid else '; '.join(violations)

        # Recompute a failure score that reflects the V9 final hard policy.
        sim70_deficit = max(
            0.0,
            (
                V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY
                - radius_similarity
            ) / V9_RELAXED_MIN_PAIR_RADIUS_SIMILARITY,
        )
        arc_deficit = max(
            0.0,
            (
                MIN_PAIR_ARC_SEPARATION_FRACTION
                - float(row.get('normalized_arc_separation', 0.0))
            ) / max(MIN_PAIR_ARC_SEPARATION_FRACTION, 1e-6),
        )
        floor_deficit = max(
            0.0,
            (
                MIN_SHAFT_FLOOR_RATIO
                - float(row.get('shaft_floor_ratio', 0.0))
            ) / max(MIN_SHAFT_FLOOR_RATIO, 1e-6),
        )
        median_deficit = max(
            0.0,
            (
                MIN_SHAFT_MEDIAN_RATIO
                - float(row.get('shaft_median_ratio', 0.0))
            ) / max(MIN_SHAFT_MEDIAN_RATIO, 1e-6),
        )
        failure_penalty = float(
            sim70_deficit
            + 0.35 * arc_deficit
            + floor_deficit
            + 0.5 * median_deficit
            + 0.15 * gap_deficit_ratio
        )
        row['failure_penalty'] = failure_penalty
        row['diagnostic_score'] = float(
            raw_adjusted - 1.5 * failure_penalty
        )

        row['selection_tier'] = None
        row['radius_similarity_gate_used'] = None
        row['gap_requirement_used'] = None
        row['policy_score'] = -np.inf
        row['score'] = -np.inf
        row['adjusted_score'] = -np.inf
        row['suppressed_by_safer_valid_pair'] = False

        rows.append(row)

    selected_tier, tier_pool = _v9_first_eligible_tier(rows)

    if not tier_pool:
        return None, rows

    for row in tier_pool:
        row['selection_tier'] = selected_tier
        row['radius_similarity_gate_used'] = (
            0.70 if 'relaxed70' in selected_tier else 0.80
        )
        row['gap_requirement_used'] = (
            'full_1R' if 'full1R' in selected_tier else 'relaxed'
        )

        score = float(row['raw_06q_adjusted_score'])
        if 'relaxed_gap' in selected_tier:
            score = float(row['relaxed_gap_policy_score'])

        row['policy_score'] = score
        row['adjusted_score'] = score
        row['score'] = score

    # Preserve the fixed-06Q safety behavior: if a valid pair without a
    # high-confidence terminal-extra candidate exists in the ACTIVE tier,
    # suppress pairs containing the suspicious terminal extra.
    safer_pairs = [
        row
        for row in tier_pool
        if not row.get('contains_high_conf_terminal_extra', False)
    ]

    if safer_pairs:
        winner_pool = safer_pairs
        for row in tier_pool:
            if row.get('contains_high_conf_terminal_extra', False):
                row['suppressed_by_safer_valid_pair'] = True
    else:
        winner_pool = tier_pool

    best = max(
        winner_pool,
        key=lambda row: float(row['policy_score']),
    )

    best['selected_policy_tier'] = selected_tier
    best['used_radius_similarity_relaxation'] = bool(
        'relaxed70' in selected_tier
    )
    best['used_gap_relaxation'] = bool(
        'relaxed_gap' in selected_tier
    )

    return best, rows


def isolate_body_only_mask(
    whole_pig_mask,
    *,
    sample_id: Optional[str] = None,
    ji_config: Optional[dict] = None,
) -> Dict[str, Any]:
    """Fixed-06Q pipeline with V9 pair policy plus compact QC fields."""
    result = _isolate_body_only_mask_fixed06q(
        whole_pig_mask,
        sample_id=sample_id,
        ji_config=ji_config,
    )

    dec = result.get('decomposition') or {}
    pair = dec.get('body_circle_pair')

    # Convenient top-level fields for Notebook 6 preflight. No geometry change.
    result['circle_input_mask'] = dec.get('ji_mask')
    result['circle_defined_structure'] = dec.get('overlay')
    result['body_mask_method'] = BODY_MASK_METHOD

    selection = dec.get('selection') or {}
    head_fit = dec.get('head_circle_refinement') or {}
    result['head_side'] = selection.get('selected', 'none')
    result['rump_side'] = (
        'right' if result['head_side'] == 'left'
        else 'left' if result['head_side'] == 'right'
        else None
    )
    result['head_selection_mode'] = selection.get('mode')
    result['head_circle_refinement_applied'] = bool(
        head_fit.get('applied', False)
    )
    result['head_circle_contained'] = bool(
        head_fit.get('contained', False)
    )
    result['head_circle_refinement_reason'] = head_fit.get('reason')
    result['head_crop_geometry_source'] = dec.get(
        'head_crop_geometry_source'
    )
    result['purple_required_for_crop'] = False

    if pair is None:
        result['pair_selection_tier'] = None
        result['radius_similarity'] = np.nan
        result['centerline_shaft_gap_px'] = np.nan
        result['centerline_gap_ratio_to_smaller_radius'] = np.nan
        result['used_radius_similarity_relaxation'] = False
        result['used_gap_relaxation'] = False
    else:
        result['pair_selection_tier'] = pair.get(
            'selected_policy_tier', pair.get('selection_tier')
        )
        result['radius_similarity'] = float(
            pair.get('radius_similarity', np.nan)
        )
        result['centerline_shaft_gap_px'] = float(
            pair.get('centerline_shaft_gap_px', np.nan)
        )
        result['centerline_gap_ratio_to_smaller_radius'] = float(
            pair.get('centerline_gap_ratio_to_smaller_radius', np.nan)
        )
        result['used_radius_similarity_relaxation'] = bool(
            pair.get('used_radius_similarity_relaxation', False)
        )
        result['used_gap_relaxation'] = bool(
            pair.get('used_gap_relaxation', False)
        )

    return result


def make_circle_defined_structure_overlay(result):
    """Return the original readable fixed-06Q CIRCLE-DEFINED STRUCTURE panel."""
    panel = result.get('circle_defined_structure')
    if panel is not None:
        return np.asarray(panel).copy()

    dec = result.get('decomposition') or {}
    panel = dec.get('overlay')
    if panel is not None:
        return np.asarray(panel).copy()

    mask = result.get('circle_input_mask')
    if mask is None:
        mask = result.get('mask')
    if mask is None:
        raise ValueError('No mask available for diagnostic overlay.')

    mask = _binary(mask)
    return np.dstack([mask * 145] * 3).astype(np.uint8)
