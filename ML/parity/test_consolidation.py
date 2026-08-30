"""pytest wrapper around gate A (ML_implementation_plan.md revision 7, section 5, 10, 13, 14).

    pytest ML/parity/test_consolidation.py -v

Kept separate from gate_a.py's CLI entry point (it stays runnable standalone for CI
scripting -- section 13's `pytest ...` line and the CLI usage serve different callers)
but this is the one a normal `pytest` invocation picks up.

Gate C (ML/parity/gate_c.py, pinning shared primitives between two runtime copies) is
deleted with this revision: after section 5.2's split, ML.pipeline.cutter imports
clean_binary_mask / _largest_component_fill from ML.pipeline.construction rather than
carrying its own copy, so there is nothing left for a gate to keep in agreement
(section 10).
"""
from __future__ import annotations

import sys

import pytest

from ML.parity import gate_a


def test_gate_a_synthetic_smoke():
    """Not the real gate A (no fixture corpus yet -- section 11.2). Proves the
    section-5.6 refactor changed nothing on the shapes it tries, including both
    branches of the section-5.3(b) overrides."""
    assert gate_a.run(gate_a.PRE_DELETION_REV_DEFAULT, n_synthetic=12) == 0


def test_cutter_imports_only_construction_and_allowed_third_party():
    """Section 3.1 / 14 (check_cutter_purity.sh): ML.pipeline.cutter may import
    ML.pipeline.construction (the one earlier stage it genuinely depends on --
    clean_binary_mask, _largest_component_fill) and stdlib/numpy/cv2/scipy/skimage.
    Nothing else project-local -- no other stage, no manifest, no model runtime."""
    import ast
    import pathlib

    src = pathlib.Path("ML/pipeline/cutter.py").read_text(encoding="utf-8")
    tree = ast.parse(src)
    third_party_allowed = {"cv2", "numpy", "scipy", "skimage"}
    project_allowed = {"ML.pipeline.construction"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            names = [node.module] if node.module else []
        else:
            continue
        for name in names:
            root = name.split(".")[0]
            if root.lower() in ("ml", "src"):
                assert name in project_allowed, (
                    f"ML.pipeline.cutter imports a project module outside the allowed "
                    f"set: {name} (allowed: {project_allowed})"
                )
                continue
            is_stdlib = root in sys.stdlib_module_names
            assert is_stdlib or root in third_party_allowed, (
                f"unexpected non-stdlib, non-allowed import in ML.pipeline.cutter: {name}"
            )


def test_no_stage_imports_a_later_stage():
    """Section 3.1 / 14 (check_stage_order.sh): the dependency arrow runs
    1 (segmentation) -> 2 (construction) -> 3 (cutter) -> 4 (feature_calculation)
    -> 5 (weight_prediction) and never backwards-in-time -- i.e. never forwards
    past a stage that hasn't run yet. feature_calculation importing construction
    is legal (it depends on an EARLIER stage, section 3.1's one permitted
    backwards-looking include); nothing may import a LATER one."""
    import ast
    import pathlib

    order = ["segmentation", "construction", "cutter", "feature_calculation", "weight_prediction"]
    index = {name: i for i, name in enumerate(order)}

    for stage in order:
        src = (pathlib.Path("ML/pipeline") / f"{stage}.py").read_text(encoding="utf-8")
        tree = ast.parse(src)
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("ML.pipeline."):
                other = node.module.split(".")[-1]
                if other == stage or other not in index:
                    continue
                assert index[other] < index[stage], (
                    f"ML.pipeline.{stage} imports ML.pipeline.{other}, a later stage "
                    f"(section 3.1: no stage may include a later stage)"
                )


def test_exactly_five_stage_files():
    """Section 3.2 / 14 (check_five_stages.sh): exactly five files under
    ML/pipeline/, one per process named in ML/refactor_plan.md, and the four
    pre-refactor originals plus the revision-6 two-file split are gone."""
    import pathlib

    for gone in (
        "body_mask.py",
        "mask_features.py",
        "extended_mask_features.py",
        "yolo_inference.py",
        "pig_cutter.py",
        "pig_geometry.py",
    ):
        assert not (pathlib.Path("ML") / gone).exists(), f"{gone} should be deleted"

    expected = {
        "segmentation.py",
        "construction.py",
        "cutter.py",
        "feature_calculation.py",
        "weight_prediction.py",
        "__init__.py",
    }
    actual = {p.name for p in pathlib.Path("ML/pipeline").glob("*.py")}
    assert actual == expected, f"ML/pipeline/ should contain exactly {expected}, found {actual}"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
