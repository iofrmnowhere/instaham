"""Gate C (ML_implementation_plan.md section 10 / 3.3): the five primitives that
exist in both ML/pig_cutter.py (ships on Android) and ML/pig_geometry.py (the C++
port reference) must never drift apart. Run on every change to either file.

    python -m ML.parity.gate_c

Tolerances, from section 10's gate-C table:
    clean_binary_mask, _largest_component_fill        bit-exact
    _odd_window, _rolling_median                       bit-exact (int) / <=1 ULP (float)
    ji_duan_adaptive_kernel_sizes                       exact integer match
    isolate_dorsal_core_ji_duan (composed)              IoU >= 0.999
"""
from __future__ import annotations

import sys

import cv2
import numpy as np

from ML.pig_cutter import (
    clean_binary_mask as clean_cutter,
    _largest_component_fill as fill_cutter,
    _odd_window as odd_window_cutter,
    _rolling_median as rolling_median_cutter,
    ji_duan_adaptive_kernel_sizes as kernel_sizes_cutter,
    isolate_dorsal_core_ji_duan as dorsal_core_cutter,
)
from ML.pig_geometry import (
    clean_binary_mask as clean_geom,
    _largest_component_fill as fill_geom,
    _odd_window as odd_window_geom,
    _rolling_median as rolling_median_geom,
    ji_duan_adaptive_kernel_sizes as kernel_sizes_geom,
    isolate_dorsal_core_ji_duan as dorsal_core_geom,
)


def make_mask(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    h, w = 300, 400
    mask = np.zeros((h, w), dtype=np.uint8)
    cx, cy = w * rng.uniform(0.4, 0.6), h * rng.uniform(0.4, 0.6)
    rw, rh = 80 + int(rng.integers(-15, 15)), 40 + int(rng.integers(-10, 10))
    angle = float(rng.uniform(-15, 15))
    cv2.ellipse(mask, (int(cx), int(cy)), (rw, rh), angle, 0, 360, 255, -1)
    # sprinkle a couple of small disconnected blobs and a hole to exercise
    # component-fill / cleanup behaviour
    cv2.circle(mask, (int(cx + rw * 1.6), int(cy)), 6, 255, -1)
    cv2.circle(mask, (int(cx), int(cy)), 5, 0, -1)
    return mask


def iou(a: np.ndarray, b: np.ndarray) -> float:
    a = (a > 0)
    b = (b > 0)
    inter = np.count_nonzero(a & b)
    union = np.count_nonzero(a | b)
    return 1.0 if union == 0 else inter / union


def run(n: int = 20) -> int:
    failures: list[str] = []

    for seed in range(n):
        mask = make_mask(seed)

        c1, c2 = clean_cutter(mask), clean_geom(mask)
        if not np.array_equal(c1, c2):
            failures.append(f"seed {seed}: clean_binary_mask not bit-exact")

        f1, f2 = fill_cutter(mask), fill_geom(mask)
        if not np.array_equal(f1, f2):
            failures.append(f"seed {seed}: _largest_component_fill not bit-exact")

        for v in (0, 1, 4, 5, 8, 9, 100, 101):
            if odd_window_cutter(v) != odd_window_geom(v):
                failures.append(f"seed {seed}: _odd_window({v}) differs")

        vals = np.random.default_rng(seed).uniform(0, 100, size=17).astype(np.float32)
        r1 = rolling_median_cutter(vals, 5)
        r2 = rolling_median_geom(vals, 5)
        if r1.shape != r2.shape or not np.array_equal(r1, r2):
            failures.append(f"seed {seed}: _rolling_median not bit-exact")

        k1 = kernel_sizes_cutter(mask)
        k2 = kernel_sizes_geom(mask)
        if k1 != k2:
            failures.append(f"seed {seed}: ji_duan_adaptive_kernel_sizes differs: {k1} vs {k2}")

        d1 = dorsal_core_cutter(mask)
        d2 = dorsal_core_geom(mask)
        score = iou(d1, d2)
        if score < 0.999:
            failures.append(f"seed {seed}: isolate_dorsal_core_ji_duan IoU {score:.4f} < 0.999")

        print(f"seed {seed}: OK" if not failures or not failures[-1].startswith(f"seed {seed}") else f"seed {seed}: see failures above")

    if failures:
        print(f"\n{len(failures)} FAILURE(S):")
        for f in failures:
            print(f"  - {f}")
        return 1

    print(f"\nGATE C PASSED -- {n} fixtures, 6 primitives, pig_cutter.py and pig_geometry.py agree")
    return 0


if __name__ == "__main__":
    sys.exit(run())
