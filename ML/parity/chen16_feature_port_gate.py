"""Chen16 feature-port gate (docs/plan-phase/2-native-cutter-chen16.md, last checklist
step): compares the ported C++ `stages::extract_chen16_features` against the Python
oracle, `ML.pipeline.feature_calculation.extract_chen16_features`
(EXTENDED_FEATURE_PROTOCOL_VERSION == the CSV's `extended_feature_protocol_version`,
`chen16_noheight_centerchord_v2`), over the SAME ground-truth masks in
`Instaham/PIGRGB-Weight/MASK_3394/`.

This gates the rest of phase 2 -- do not move on to the cutter seam (already ported
alongside this, but not itself checkable this way; see the plan's open questions) until
this is green. Widen from the default 20-mask sample to the full 3394 in phase 5.

    python -m ML.parity.chen16_feature_port_gate
    python -m ML.parity.chen16_feature_port_gate --limit 3394 --cli <path>

The C++ CLI is `chen16_feature_gate_cli`, built from the
`packages/instaham_ml_ffi/src/test` CMake target of the same name (host ctest build,
INSTAHAM_ML_BUILD_TESTS=ON). This script does not build it -- pass --cli explicitly if it
is not on PATH under a conventional build directory name.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

import cv2

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
from ML.pipeline.feature_calculation import CHEN16_NOHEIGHT, extract_chen16_features  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
MASK_ROOT = REPO_ROOT / "Instaham" / "PIGRGB-Weight" / "MASK_3394"

# docs/plan-phase/2-native-cutter-chen16.md, "Tolerances for the C++/Python feature
# comparison" (proposal, finalized in phase 5).
EXACT = {"mask_area", "convex_hull_area", "difference", "dif_mask"}
REL_1E3 = {"perimeter", "longest", "shortest", "outline_curve", "body_curve"}
REL_1E6 = {f"Hu_{i}" for i in range(1, 8)}

DEFAULT_CLI_CANDIDATES = [
    "packages/instaham_ml_ffi/build/host/src/test/chen16_feature_gate_cli.exe",
    "packages/instaham_ml_ffi/build/host/src/test/chen16_feature_gate_cli",
]


def find_default_cli() -> pathlib.Path | None:
    for rel in DEFAULT_CLI_CANDIDATES:
        p = REPO_ROOT / rel
        if p.exists():
            return p
    return None


def sample_masks(limit: int) -> list[pathlib.Path]:
    """Spans several weight groups, not just the first alphabetically -- one mask per
    group first, then round-robin, until `limit` is reached or the corpus is exhausted."""
    groups = sorted(p for p in MASK_ROOT.iterdir() if p.is_dir())
    per_group = [sorted(g.glob("*.png")) for g in groups]
    out: list[pathlib.Path] = []
    i = 0
    while len(out) < limit and any(per_group):
        for files in per_group:
            if i < len(files):
                out.append(files[i])
                if len(out) >= limit:
                    break
        i += 1
    return out


def run_cpp(cli: pathlib.Path, mask_path: pathlib.Path) -> dict[str, float] | None:
    # OpenCV can print an informational parallel-backend-registry line to stdout ahead of
    # the CLI's own output on some builds -- take the LAST non-empty line, which is always
    # what chen16_feature_gate_cli.cpp itself printed.
    env = {**os.environ, "OPENCV_LOG_LEVEL": "SILENT"}
    result = subprocess.run(
        [str(cli), str(mask_path)], capture_output=True, text=True, check=True, env=env
    )
    lines = [l for l in result.stdout.splitlines() if l.strip()]
    line = lines[-1].strip() if lines else ""
    if line == "invalid" or not line:
        return None
    parts = line.split(",")
    if parts[0] != "valid" or len(parts) != 17:
        raise ValueError(f"unexpected CLI output for {mask_path}: {line!r}")
    return dict(zip(CHEN16_NOHEIGHT, (float(x) for x in parts[1:])))


def run_python(mask_path: pathlib.Path) -> dict[str, float] | None:
    mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if mask is None:
        raise FileNotFoundError(mask_path)
    return extract_chen16_features(mask)


def compare_one(name: str, expected: float, actual: float) -> str | None:
    if name in EXACT:
        if expected != actual:
            return f"{name}: exact mismatch expected={expected!r} actual={actual!r}"
        return None
    tol = 1e-3 if name in REL_1E3 else 1e-6
    denom = max(abs(expected), 1e-9)
    rel = abs(expected - actual) / denom
    if rel > tol:
        return f"{name}: rel {rel:.3g} > {tol:g} (expected={expected!r} actual={actual!r})"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--cli", type=pathlib.Path, default=None)
    args = ap.parse_args()

    cli = args.cli or find_default_cli()
    if cli is None or not cli.exists():
        print(
            "chen16_feature_gate_cli not found -- build it first "
            "(packages/instaham_ml_ffi host ctest target 'chen16_feature_gate_cli') "
            "or pass --cli <path>",
            file=sys.stderr,
        )
        return 2
    if not MASK_ROOT.exists():
        print(f"mask corpus not found at {MASK_ROOT}", file=sys.stderr)
        return 2

    masks = sample_masks(args.limit)
    if not masks:
        print("no masks found under MASK_3394", file=sys.stderr)
        return 2

    failures: list[str] = []
    checked = 0
    for mask_path in masks:
        cpp = run_cpp(cli, mask_path)
        py = run_python(mask_path)
        if (cpp is None) != (py is None):
            failures.append(f"{mask_path.name}: validity mismatch cpp={cpp is None!r} py={py is None!r}")
            continue
        if cpp is None:
            continue  # both agree the mask is unusable
        checked += 1
        for name in CHEN16_NOHEIGHT:
            msg = compare_one(name, py[name], cpp[name])
            if msg:
                failures.append(f"{mask_path.name}: {msg}")

    print(f"checked {checked}/{len(masks)} masks ({len(failures)} mismatches)")
    for f in failures[:50]:
        print(f"  FAIL {f}")
    if len(failures) > 50:
        print(f"  ... and {len(failures) - 50} more")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
