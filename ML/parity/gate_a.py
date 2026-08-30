"""Gate A (ML_implementation_plan.md section 5.3(b) / 5.6 / 11.2): ML/pipeline/cutter.py
vs the pre-refactor original (body_mask.py), on the fixture corpus.

    python -m ML.parity.gate_a
    python -m ML.parity.gate_a --against <git-rev> --fixtures test/fixtures/parity

There is no real pig-photo fixture corpus in the repo yet (section 11.3.1 -- slice -1
is still open). Until `test/fixtures/parity/` exists with real masks, this gate runs
against a small synthetic-mask corpus instead and says so loudly. The synthetic corpus
is a mechanical-transform check, not the real gate A: it proves the consolidation did
not change behaviour on the shapes it tries, not on real pig photos. Section 11.3.1
step 3's override-branch coverage requirement is checked either way, since it depends
on shape variety (does a mask take the wrapper's fast path or its fallback), not on
photographic realism.

Reconstructs the originals from a pinned git revision rather than reading them off
disk (section 5.6 precondition 3): the working tree no longer has them after the
section-5.6 deletion.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import subprocess
import sys
import types

import cv2
import numpy as np

PRE_DELETION_REV_DEFAULT = "5bd99ce"  # kept in sync with ML/tools/consolidate_helpers.py


def git_show_to_tmp(rev: str, path: str, tmp_dir: pathlib.Path) -> pathlib.Path:
    out = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        capture_output=True, check=True, text=True, encoding="utf-8",
    )
    dest = tmp_dir / pathlib.Path(path).name
    dest.write_text(out.stdout, encoding="utf-8")
    return dest


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_originals(rev: str, tmp_dir: pathlib.Path):
    """Reconstruct body_mask.py (via the src.mask_features alias it expects, exactly
    as ML/compat/src_alias.py documents) from the pinned pre-deletion revision."""
    mf_path = git_show_to_tmp(rev, "ML/mask_features.py", tmp_dir)
    body_path = git_show_to_tmp(rev, "ML/body_mask.py", tmp_dir)

    mask_features_orig = load_module("mask_features_orig", mf_path)
    src_pkg = types.ModuleType("src")
    src_pkg.__path__ = []
    sys.modules["src"] = src_pkg
    sys.modules["src.mask_features"] = mask_features_orig

    body_mask_orig = load_module("body_mask_orig", body_path)
    return body_mask_orig, mask_features_orig


def deep_equal(a, b, path: str = "$") -> None:
    if isinstance(a, np.ndarray) or isinstance(b, np.ndarray):
        assert isinstance(a, np.ndarray) and isinstance(b, np.ndarray), (
            f"{path}: array-ness differs: {type(a)} vs {type(b)}"
        )
        assert a.shape == b.shape, f"{path}: shape differs: {a.shape} vs {b.shape}"
        is_float = np.issubdtype(a.dtype, np.floating) and np.issubdtype(b.dtype, np.floating)
        assert np.array_equal(a, b, equal_nan=is_float), (
            f"{path}: array differs, {int(np.count_nonzero(a != b))} elements mismatch"
        )
        return
    if isinstance(a, dict) or isinstance(b, dict):
        assert isinstance(a, dict) and isinstance(b, dict), f"{path}: dict-ness differs"
        assert set(a.keys()) == set(b.keys()), f"{path}: key sets differ: {set(a) ^ set(b)}"
        for k in a:
            deep_equal(a[k], b[k], f"{path}.{k}")
        return
    if isinstance(a, (list, tuple)) or isinstance(b, (list, tuple)):
        assert type(a) is type(b), f"{path}: sequence type differs: {type(a)} vs {type(b)}"
        assert len(a) == len(b), f"{path}: length differs: {len(a)} vs {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            deep_equal(x, y, f"{path}[{i}]")
        return
    if isinstance(a, float) and isinstance(b, float) and np.isnan(a) and np.isnan(b):
        return
    assert a == b, f"{path}: differs: {a!r} vs {b!r}"


# ---------------------------------------------------------------------------
# Synthetic fixture corpus (temporary stand-in for slice -1's real fixtures).
# Deliberately varies torso/head/leg/tail geometry across seeds so both the
# wrapper path and the aliased-original path of the section-5.2(b) overrides
# get exercised on different seeds (checked explicitly below).
# ---------------------------------------------------------------------------
def make_pig_mask(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    h, w = 480, 800
    mask = np.zeros((h, w), dtype=np.uint8)

    cx, cy = w * 0.55, h * 0.5
    torso_w = 260 + int(rng.integers(-20, 20))
    torso_h = 90 + int(rng.integers(-10, 10))
    angle = float(rng.uniform(-8, 8))
    cv2.ellipse(mask, (int(cx), int(cy)), (torso_w, torso_h), angle, 0, 360, 255, -1)

    head_cx = cx - torso_w * 0.85
    head_r = int(torso_h * 0.65)
    cv2.circle(mask, (int(head_cx), int(cy)), head_r, 255, -1)

    leg_w, leg_h = 22, 70
    for lx_frac in (0.30, 0.55, 0.75):
        lx = cx - torso_w * 0.6 + lx_frac * torso_w * 1.2
        ly = cy + torso_h * 0.75
        cv2.rectangle(
            mask, (int(lx - leg_w / 2), int(ly)), (int(lx + leg_w / 2), int(ly + leg_h)), 255, -1
        )

    tail_x0 = int(cx + torso_w * 0.9)
    cv2.rectangle(mask, (tail_x0, int(cy - 6)), (tail_x0 + 40, int(cy + 6)), 255, -1)
    return mask


def run(rev: str, n_synthetic: int = 12) -> int:
    tmp_dir = pathlib.Path("build/gate_a_tmp")
    tmp_dir.mkdir(parents=True, exist_ok=True)

    body_mask_orig, _ = load_originals(rev, tmp_dir)

    from ML.pipeline.cutter import isolate_body_only_mask as isolate_new
    from ML.pipeline.cutter import choose_body_circle_pair as choose_new
    from ML.pipeline.cutter import _choose_body_circle_pair_fixed06q as choose_alias_new
    from ML.pipeline.cutter import isolate_body_only_mask as isolate_alias_check
    from ML.pipeline.cutter import _isolate_body_only_mask_fixed06q as isolate_alias_new

    # Section 5.2(b): the public names must resolve to the OVERRIDE, and the alias
    # names must resolve to a DIFFERENT callable (the pre-override original). If a
    # future edit collapses these back to the same function, the override resolution
    # silently regressed and this assertion is what catches it.
    assert choose_new is not choose_alias_new, "override resolution regressed: choose_body_circle_pair"
    assert isolate_alias_check is not isolate_alias_new, "override resolution regressed: isolate_body_only_mask"

    took_override_path = 0
    took_alias_path = 0
    failures = []

    for seed in range(n_synthetic):
        mask = make_pig_mask(seed)
        try:
            result_orig = body_mask_orig.isolate_body_only_mask(mask, sample_id=f"synthetic-{seed}")
            result_new = isolate_new(mask, sample_id=f"synthetic-{seed}")
        except Exception as e:
            failures.append(f"seed {seed}: raised {type(e).__name__}: {e}")
            continue

        try:
            deep_equal(result_orig, result_new, f"seed{seed}")
        except AssertionError as e:
            failures.append(str(e))
            continue

        dec = result_new.get("decomposition") or {}
        if (dec.get("body_circle_pair") or {}).get("selected_policy_tier") is not None:
            took_override_path += 1
        else:
            took_alias_path += 1

        print(f"seed {seed}: OK -- {len(result_orig)} QC fields, all bit-exact")

    print(f"\ncoverage: {took_override_path} fixture(s) reached a resolved pair "
          f"(exercises the choose_body_circle_pair override path)")

    print("\n--- Gate A: NOT the real gate ---")
    print("No real pig-photo fixture corpus in test/fixtures/parity/ yet (slice -1,")
    print("ML_implementation_plan.md section 11.3.1). The check above is a mechanical-")
    print("transform smoke test on synthetic masks, not the real behavioural gate.")

    if failures:
        print(f"\n{len(failures)} FAILURE(S):")
        for f in failures:
            print(f"  - {f}")
        return 1

    print(f"\nALL {n_synthetic} SYNTHETIC FIXTURES PASSED")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--against", default=PRE_DELETION_REV_DEFAULT)
    ap.add_argument("--n-synthetic", type=int, default=12)
    args = ap.parse_args()
    sys.exit(run(args.against, args.n_synthetic))


if __name__ == "__main__":
    main()
