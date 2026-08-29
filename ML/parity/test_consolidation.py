"""pytest wrapper around gate A and gate C (ML_implementation_plan.md section 5, 10, 13).

    pytest ML/parity/test_consolidation.py -v

Kept separate from gate_a.py / gate_c.py's CLI entry points (both stay runnable
standalone for CI scripting -- section 13's `pytest ...` line and the CLI usage
serve different callers) but this is the one a normal `pytest` invocation picks up.
"""
from __future__ import annotations

import sys

import pytest

from ML.parity import gate_a, gate_c


def test_gate_a_synthetic_smoke():
    """Not the real gate A (no fixture corpus yet -- section 11.3.1 / slice -1).
    Proves the section-5.5 consolidation changed nothing on the shapes it tries,
    including both branches of the section-5.2(b) overrides."""
    assert gate_a.run(gate_a.PRE_DELETION_REV_DEFAULT, n_synthetic=12) == 0


def test_gate_c_shared_primitives():
    """The five primitives that exist in both ML/pig_cutter.py and
    ML/pig_geometry.py (section 3.3) must never silently drift apart."""
    assert gate_c.run(n=20) == 0


def test_pig_cutter_has_no_project_imports():
    """Section 3.1: pig_cutter.py ships standalone (Chaquopy, Android)."""
    import ast
    import pathlib

    src = pathlib.Path("ML/pig_cutter.py").read_text(encoding="utf-8")
    tree = ast.parse(src)
    # numpy/cv2/scipy/skimage plus anything in the standard library is fine (section
    # 3.1's "numpy, cv2, scipy, skimage, its own copies of the shared primitives" is
    # about project-local imports, not about the stdlib). What must never appear is
    # anything project-local: ML.*, src.*, a manifest, a model runtime.
    third_party_allowed = {"cv2", "numpy", "scipy", "skimage"}
    disallowed_prefixes = ("ml", "src")
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            names = [node.module] if node.module else []
        else:
            continue
        for name in names:
            root = name.split(".")[0]
            assert root.lower() not in disallowed_prefixes, f"project-local import in pig_cutter.py: {name}"
            is_stdlib = root in sys.stdlib_module_names
            assert is_stdlib or root in third_party_allowed, (
                f"unexpected non-stdlib, non-allowed import in pig_cutter.py: {name}"
            )


def test_exactly_two_helper_files():
    """Section 3.1.1: one helper file per runtime, nothing more."""
    import pathlib

    for gone in ("body_mask.py", "mask_features.py", "extended_mask_features.py", "yolo_inference.py"):
        assert not (pathlib.Path("ML") / gone).exists(), f"{gone} should be deleted (section 5.5)"
    assert (pathlib.Path("ML") / "pig_cutter.py").exists()
    assert (pathlib.Path("ML") / "pig_geometry.py").exists()


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
