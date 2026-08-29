"""One-time mechanical consolidation (ML_implementation_plan.md revision 6, section 5).

Regenerates ML/pig_cutter.py and ML/pig_geometry.py from the pre-consolidation
originals (body_mask.py, mask_features.py, extended_mask_features.py,
yolo_inference.py), as they existed at a pinned git revision. Kept in the repo as
the documented, reviewable, reproducible record of the transform -- not something
you should need to run again, but if the originals need to be reconstructed and
re-split (e.g. after a section-5.4 substitution is reconsidered), this is how.

Usage (from repo root):
    python -m ML.tools.consolidate_helpers [--against <git-rev>]

Default --against is the commit at which the four originals were last present
(see ML/parity/gate_a.py's PRE_DELETION_REV, which must be kept in sync with this
script's default).

What it does, exactly (section 5.2(b), section 5.5.1):
  1. Reads body_mask.py, mask_features.py, extended_mask_features.py,
     yolo_inference.py from the given git revision (never from the working tree,
     since the working tree no longer has them after section 5.5's deletion).
  2. Resolves the two overridden-by-redefinition functions
     (choose_body_circle_pair, isolate_body_only_mask) statically: the
     pre-override definition keeps its already-existing alias name
     (_choose_body_circle_pair_fixed06q / _isolate_body_only_mask_fixed06q), the
     override keeps the public name, and the now-redundant alias assignment
     lines are removed. No behaviour changes -- see gate A.
  3. Inlines the cleanup primitives (clean_binary_mask, _largest_component_fill,
     _odd_window, _rolling_median, ji_duan_adaptive_kernel_sizes) plus
     isolate_dorsal_core_ji_duan into pig_cutter.py, so it stands alone with zero
     project-local imports (section 3.1).
  4. Concatenates mask_features.py + extended_mask_features.py + the mask-math
     functions of yolo_inference.py into pig_geometry.py (section 5.6's C++ port
     reference; never ships).
"""
from __future__ import annotations

import argparse
import subprocess
import pathlib

PRE_DELETION_REV_DEFAULT = "5bd99ce"  # last commit with all four originals present


def git_show(rev: str, path: str) -> str:
    out = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        capture_output=True,
        check=True,
        text=True,
        encoding="utf-8",
    )
    return out.stdout


def find_line(lines: list[str], prefix: str, expected_lineno: int) -> int:
    for i, line in enumerate(lines):
        if line.startswith(prefix) and (i + 1) == expected_lineno:
            return i
    # fall back to first match if the pinned line number ever drifts
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i
    raise RuntimeError(f"line not found: {prefix!r}")


def extract_def(src: str, name: str) -> str:
    lines = src.splitlines(keepends=True)
    start = None
    for i, l in enumerate(lines):
        if l.startswith(f"def {name}("):
            start = i
            break
    if start is None:
        raise RuntimeError(f"def {name} not found")
    end = start + 1
    while end < len(lines):
        if lines[end].startswith("def ") or lines[end].startswith("class "):
            break
        end += 1
    block = lines[start:end]
    while len(block) >= 2 and block[-1].strip() == "" and block[-2].strip() == "":
        block.pop()
    return "".join(block)


def strip_module_header(src: str) -> tuple[str, str]:
    lines = src.splitlines(keepends=True)
    i = 0
    if lines and lines[0].lstrip().startswith(('"""', "'''")):
        quote = lines[0].lstrip()[:3]
        if lines[0].count(quote) >= 2 and len(lines[0].strip()) > 3:
            i = 1
        else:
            i = 1
            while i < len(lines) and quote not in lines[i]:
                i += 1
            i += 1
    while i < len(lines) and lines[i].strip() == "":
        i += 1
    import_end = i
    j = i
    while j < len(lines):
        stripped = lines[j].strip()
        if stripped == "" or stripped.startswith(("import ", "from ")):
            if stripped.startswith(("import ", "from ")):
                import_end = j + 1
            j += 1
            continue
        break
    return "".join(lines[:import_end]), "".join(lines[import_end:])


def build_pig_cutter(body_src: str) -> str:
    body_lines = body_src.splitlines(keepends=True)

    idx_import = find_line(body_lines, "from src.mask_features import", 40)
    idx_def1_choose = find_line(body_lines, "def choose_body_circle_pair(", 5882)
    idx_def1_isolate = find_line(body_lines, "def isolate_body_only_mask(", 10016)
    idx_alias1 = find_line(
        body_lines, "_choose_body_circle_pair_fixed06q = choose_body_circle_pair", 10184
    )
    idx_alias2 = find_line(
        body_lines, "_isolate_body_only_mask_fixed06q = isolate_body_only_mask", 10185
    )

    lo, hi = sorted([idx_alias1, idx_alias2])
    assert hi == lo + 1, "alias lines expected to be adjacent"
    del body_lines[lo:hi + 1]

    line = body_lines[idx_def1_isolate]
    assert line.startswith("def isolate_body_only_mask(")
    body_lines[idx_def1_isolate] = line.replace(
        "def isolate_body_only_mask(", "def _isolate_body_only_mask_fixed06q(", 1
    )

    line = body_lines[idx_def1_choose]
    assert line.startswith("def choose_body_circle_pair(")
    body_lines[idx_def1_choose] = line.replace(
        "def choose_body_circle_pair(", "def _choose_body_circle_pair_fixed06q(", 1
    )

    return body_lines, idx_import


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--against", default=PRE_DELETION_REV_DEFAULT, help="git revision holding the four originals")
    ap.add_argument("--ml-dir", default="ML", help="output ML/ directory (repo-relative)")
    args = ap.parse_args()

    ml_dir = pathlib.Path(args.ml_dir).resolve()

    body_src = git_show(args.against, "ML/body_mask.py")
    mf_src = git_show(args.against, "ML/mask_features.py")
    ext_src = git_show(args.against, "ML/extended_mask_features.py")
    yolo_src = git_show(args.against, "ML/yolo_inference.py")

    # ---- pig_cutter.py ----
    body_lines, idx_import = build_pig_cutter(body_src)

    primitive_names = [
        "_largest_component_fill",
        "clean_binary_mask",
        "_odd_window",
        "_rolling_median",
        "ji_duan_adaptive_kernel_sizes",
        "isolate_dorsal_core_ji_duan",
    ]
    primitive_blocks = [extract_def(mf_src, n) for n in primitive_names]
    inlined = (
        "# ===== [0] shared primitives, inlined from ML/mask_features.py =====\n"
        "# pig_cutter.py must stand alone -- it must not import any\n"
        "# other project file (section 3.1 / 3.3 of ML_implementation_plan.md). These six\n"
        "# functions are therefore duplicated here verbatim. ML/pig_geometry.py has its own\n"
        "# copies for the C++ port; the two are never used in the same computation\n"
        "# (revision 6's one-hop boundary), so they are not required to agree and nothing\n"
        "# gates them against each other.\n"
        "# fmt: off\n\n"
        + "\n\n".join(b.rstrip("\n") for b in primitive_blocks)
        + "\n# fmt: on\n# ===== end shared primitives =====\n\n\n"
    )
    body_lines[idx_import] = inlined
    new_source = "".join(body_lines)

    old_header = '"""Production body-mask preprocessing derived from the finalized fixed 06Q notebook.'
    new_header = '''"""ML/pig_cutter.py -- the head/neck cut-off. NOT PORTED TO C++.

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

Production body-mask preprocessing derived from the finalized fixed 06Q notebook.'''
    assert old_header in new_source
    new_source = new_source.replace(old_header, new_header, 1)

    (ml_dir / "pig_cutter.py").write_text(new_source, encoding="utf-8")
    print(f"wrote {ml_dir / 'pig_cutter.py'} ({len(new_source.splitlines())} lines)")

    # ---- pig_geometry.py ----
    mf_header, mf_body = strip_module_header(mf_src)
    ext_header, ext_body = strip_module_header(ext_src)
    yolo_header, yolo_body = strip_module_header(yolo_src)

    geometry_source = '''"""ML/pig_geometry.py -- geometry helpers ported to C++ (ML_implementation_plan.md,
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

''' + mf_body + '''

# ===== [2] unletterbox (mask math lifted from ML/yolo_inference.py) =====

MASK_COORDINATE_PROTOCOL = "original_coordinate_polygon_v1"

''' + yolo_body + '''

# ===== [3] chen16 extended features (from ML/extended_mask_features.py) =====
# Optional -- only relevant if a chen16 model is ever selected (section 5.1).
# Not part of the shipped baseline5 [RA, LC, BL, BW, E] pipeline.

''' + ext_body
    (ml_dir / "pig_geometry.py").write_text(geometry_source, encoding="utf-8")
    print(f"wrote {ml_dir / 'pig_geometry.py'} ({len(geometry_source.splitlines())} lines)")


if __name__ == "__main__":
    main()
