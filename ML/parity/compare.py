"""Tolerance helpers shared by run_reference.py and the Dart parity test (via golden json)."""
from __future__ import annotations

from dataclasses import dataclass

# Section 14 of ML/ML_implementation_plan.md.
VIEW_PROB_ABS_TOL = 0.005
HEALTH_PROB_ABS_TOL = 0.01
FEATURE_REL_TOL = 0.01          # RA, LC, BL, BW, E
WEIGHT_KG_ABS_TOL = 0.1
MASK_IOU_MIN = 0.95


@dataclass(frozen=True)
class Mismatch:
    key: str
    expected: float
    actual: float
    tol: str


def abs_close(expected: float, actual: float, tol: float) -> bool:
    return abs(float(expected) - float(actual)) <= tol


def rel_close(expected: float, actual: float, tol: float) -> bool:
    e = float(expected)
    denom = max(abs(e), 1e-9)
    return abs(e - float(actual)) / denom <= tol


def compare_prob_vector(
    expected: dict[str, float], actual: dict[str, float], tol: float, *, prefix: str
) -> list[Mismatch]:
    out: list[Mismatch] = []
    for cls, ev in expected.items():
        av = float(actual.get(cls, 0.0))
        if not abs_close(ev, av, tol):
            out.append(Mismatch(f"{prefix}.{cls}", ev, av, f"abs<={tol}"))
    return out


def compare_features(
    expected: dict[str, float], actual: dict[str, float], tol: float = FEATURE_REL_TOL
) -> list[Mismatch]:
    out: list[Mismatch] = []
    for name in ("RA", "LC", "BL", "BW", "E"):
        if name not in expected:
            continue
        if not rel_close(expected[name], actual.get(name, 0.0), tol):
            out.append(Mismatch(f"features.{name}", expected[name], actual.get(name, 0.0), f"rel<={tol}"))
    return out
