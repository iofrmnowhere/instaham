"""One-time mechanical consolidation (ML_implementation_plan.md revision 7, section 5).

Regenerates the five process files under ML/pipeline/ -- segmentation.py,
construction.py, cutter.py, feature_calculation.py -- from the pre-refactor
originals (body_mask.py, mask_features.py, extended_mask_features.py,
yolo_inference.py) as they existed at a pinned git revision. weight_prediction.py
is written by hand (section 5.2(5)) rather than mechanically, because its stage-5
content is a small, deliberately-scoped extraction, not a bulk move.

Kept in the repo as the documented, reviewable, reproducible record of the
transform -- not something you should need to run again, but if the originals
need to be reconstructed and re-split, this is how.

Usage (from repo root):
    python -m ML.tools.consolidate_helpers [--against <git-rev>]

Default --against is the commit at which the four originals were last present
(see ML/parity/gate_a.py's PRE_DELETION_REV, which must be kept in sync with this
script's default).

What it does, exactly (section 5.2, section 5.3(b)):
  1. Reads body_mask.py, mask_features.py, extended_mask_features.py,
     yolo_inference.py from the given git revision (never from the working tree,
     since the working tree no longer has them after section 5.6's deletion).
  2. Resolves the two overridden-by-redefinition functions
     (choose_body_circle_pair, isolate_body_only_mask) statically: the
     pre-override definition keeps its already-existing alias name
     (_choose_body_circle_pair_fixed06q / _isolate_body_only_mask_fixed06q), the
     override keeps the public name, and the now-redundant alias assignment
     lines are removed. No behaviour change -- see gate A.
  3. Splits by PROCESS, not by runtime (section 5.2):
       segmentation.py         <- yolo_inference.py's model-running half
       construction.py         <- yolo_inference.py's mask-building half +
                                   mask_features.py's clean_binary_mask /
                                   _largest_component_fill / largest_contour
       cutter.py                <- all of body_mask.py + mask_features.py's
                                   dorsal-core family (_odd_window,
                                   _rolling_median, ji_duan_adaptive_kernel_sizes,
                                   isolate_dorsal_core_ji_duan, isolate_dorsal_core)
       feature_calculation.py   <- mask_features.py's extract_five_features +
                                   all of extended_mask_features.py
  4. cutter.py's only project-local import becomes
     `from ML.pipeline.construction import clean_binary_mask, _largest_component_fill`
     -- replacing body_mask.py's original `from src.mask_features import
     clean_binary_mask, isolate_dorsal_core_ji_duan` (isolate_dorsal_core_ji_duan
     itself moved into cutter.py, so that half of the import disappears).
  5. feature_calculation.py imports the same two primitives, plus
     largest_contour, from construction.py, because extract_five_features calls
     all three.
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


def extract_span(src: str, start_prefix: str, stop_prefixes: tuple[str, ...]) -> tuple[str, str, str]:
    """Split `src` into (before, span, after) where `span` runs from the first line
    starting with `start_prefix` up to (not including) the next line starting with
    any of `stop_prefixes`, or end of file."""
    lines = src.splitlines(keepends=True)
    start = None
    for i, l in enumerate(lines):
        if l.startswith(start_prefix):
            start = i
            break
    if start is None:
        raise RuntimeError(f"span start not found: {start_prefix!r}")
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if any(lines[i].startswith(p) for p in stop_prefixes):
            end = i
            break
    return "".join(lines[:start]), "".join(lines[start:end]), "".join(lines[end:])


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


def resolve_overrides(body_src: str) -> str:
    """Section 5.3(b): statically resolve the two override-by-redefinition
    functions and remove the now-redundant alias assignments. Returns the
    rewritten source with the src.mask_features import line still present at
    its original position (the caller replaces it)."""
    body_lines = body_src.splitlines(keepends=True)

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

    return "".join(body_lines)


CUTTER_HEADER = '''"""ML/pipeline/cutter.py -- (3) head/neck removal. NOT PORTED TO C++.

Consolidated from the original ML/body_mask.py plus the dorsal-core family of
ML/mask_features.py (ML_implementation_plan.md revision 7, section 5). This is the
one process the plan deliberately keeps as Python, because it is the sole home of
scipy.gaussian_filter1d, scipy.find_peaks, and skimage.skeletonize, and because it
is by far the largest body of code in the programme. A reachability pass measured
it: 9,911 of 10,855 lines are reachable from isolate_body_only_mask(), and 1,985 of
those live lines call scipy/skimage directly. That measurement is why it is not
ported.

THE SHIPPED C++ STAGE (stages/cutter.cpp) IS AN IDENTITY DUMMY (section 3.4). It
returns the input mask unchanged and never sets head_removal_applied. This file is
used only by the Python reference pipeline (ML/weight_runtime.py) and the parity
gates -- it is not shipped in the app and it is not gated against a C++ port,
because there is no port to gate it against.

Contract: a caller passes the raw constructed pig mask (ML.pipeline.construction)
plus an optional ji_config dict into isolate_body_only_mask(), and the weight path
gets back the QC fields (pair_valid, head_removal_applied) plus a body-only mask
that ML.pipeline.feature_calculation can measure. No model loading, no file IO, no
manifest access -- pure mask-to-mask.

One structural fix from the original is folded in here (not a behaviour change --
see ML_implementation_plan.md section 5.3(b)):
  - `choose_body_circle_pair` and `isolate_body_only_mask` were each defined twice
    in the original module, with the second definition silently overriding the
    first via Python's late-binding of module-level names. That is resolved
    statically here: the original (superseded) definitions keep their alias names
    (`_choose_body_circle_pair_fixed06q`, `_isolate_body_only_mask_fixed06q`) and
    the override keeps the public name. No other change.

The dorsal-core family this file used to reach via
`from src.mask_features import clean_binary_mask, isolate_dorsal_core_ji_duan` is
now split: `isolate_dorsal_core_ji_duan` and its dependents
(_odd_window, _rolling_median, ji_duan_adaptive_kernel_sizes, isolate_dorsal_core)
are moved in below, because they are part of the cut, not part of mask
construction. Only `clean_binary_mask` and `_largest_component_fill` remain an
external import, from ML.pipeline.construction (section 2, the mask-building
stage).

Original docstring, preserved:

Production body-mask preprocessing derived from the finalized fixed 06Q notebook.'''


def build_cutter(body_src: str, mf_src: str) -> str:
    resolved = resolve_overrides(body_src)
    lines = resolved.splitlines(keepends=True)

    idx_import = find_line(lines, "from src.mask_features import", 40)
    old_import_line = lines[idx_import]
    assert "clean_binary_mask" in old_import_line and "isolate_dorsal_core_ji_duan" in old_import_line

    dorsal_family_names = [
        "_odd_window",
        "_rolling_median",
        "ji_duan_adaptive_kernel_sizes",
        "isolate_dorsal_core_ji_duan",
        "isolate_dorsal_core",
    ]
    dorsal_blocks = [extract_def(mf_src, n) for n in dorsal_family_names]
    inserted = (
        "from ML.pipeline.construction import clean_binary_mask, _largest_component_fill\n\n\n"
        "# ===== dorsal-core family, moved in from ML/mask_features.py (section 5.2(3)) =====\n"
        "# These are part of the cut, not part of mask construction: isolate_dorsal_core_ji_duan\n"
        "# is Ji/Duan adaptive opening, the first step of the protocol this file implements, and\n"
        "# isolate_dorsal_core is the alternative INSTAHAM PCA/torso-envelope heuristic compared\n"
        "# against it in the research notebooks (same stage, same reason).\n"
        "# fmt: off\n\n"
        + "\n\n".join(b.rstrip("\n") for b in dorsal_blocks)
        + "\n# fmt: on\n# ===== end dorsal-core family =====\n\n\n"
    )
    lines[idx_import] = inserted
    new_source = "".join(lines)

    old_header = '"""Production body-mask preprocessing derived from the finalized fixed 06Q notebook.'
    assert old_header in new_source
    new_source = new_source.replace(old_header, CUTTER_HEADER, 1)
    return new_source


CONSTRUCTION_HEADER = '''"""ML/pipeline/construction.py -- (2) construct the pig mask.

Consolidated from the mask-building half of ML/yolo_inference.py's
predict_largest_mask, plus ML/mask_features.py's clean_binary_mask /
_largest_component_fill / largest_contour (ML_implementation_plan.md revision 7,
section 5.2/5.4). Ported to C++ as stages/construction.cpp; gate B measures the two
against each other file to file.

predict_largest_mask itself split across a runtime boundary that does not exist
here (revision 5's C++/Python split, section 5.4 of the current plan): the
model-running half is ML.pipeline.segmentation.run_segmentation, this file's
construct_pig_mask() is the mask-building tail. Both are used together by
ML/weight_runtime.py and by gate A; construct_pig_mask(run_segmentation(...)) must
reproduce predict_largest_mask(...) at IoU >= 0.999 (gate A, section 10).

clean_binary_mask / _largest_component_fill / largest_contour also serve two other
callers that are not part of constructing the mask itself: ML.pipeline.cutter (the
head/neck removal internally re-cleans between steps) and
ML.pipeline.feature_calculation (extract_five_features cleans before measuring).
Both import them from here rather than carrying their own copies, because nothing
in this refactor requires either to ship standalone (section 5.2, contrast with the
old Chaquopy-purity requirement this superseded).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import cv2
import numpy as np

if TYPE_CHECKING:
    from ML.pipeline.segmentation import SegmentationOutput


'''

CONSTRUCT_PIG_MASK = '''

def construct_pig_mask(seg_output: "SegmentationOutput | None") -> np.ndarray | None:
    """(2) CONSTRUCTION -- turn one segmentation.run_segmentation() output into a
    pig mask in ORIGINAL IMAGE coordinates.

    This is predict_largest_mask's mask-building tail (ML/yolo_inference.py,
    pre-refactor), split out so stage 1 (model inference) and stage 2 (mask
    geometry) are separate files per ML/refactor_plan.md. No cleanup is applied
    here -- this reproduces predict_largest_mask's original raw output exactly, so
    gate A can compare byte for byte. Callers that need a cleaned mask call
    clean_binary_mask() explicitly (ML.pipeline.cutter and
    ML.pipeline.feature_calculation both do).

    Coordinate policy
    -----------------
    Primary:   rasterize result.masks.xy, already in original-image coordinates.
    Fallback:  if the polygon is unavailable, remove letterbox padding from
               result.masks.data before resizing to the original image
               (_unletterbox_native_mask).
    """
    if seg_output is None:
        return None

    result = seg_output.result
    index = seg_output.index

    mask = _polygon_mask_in_original_coordinates(result, index)
    if mask is None:
        native = result.masks.data[index].detach().cpu().numpy()
        native = (native > 0.5).astype(np.uint8) * 255
        mask = _unletterbox_native_mask(native, seg_output.orig_shape)
    return mask
'''


def build_construction(mf_src: str, yolo_src: str) -> str:
    _, mf_body = strip_module_header(mf_src)
    primitives = "\n\n".join(
        extract_def(mf_src, n).rstrip("\n")
        for n in ("_largest_component_fill", "clean_binary_mask", "largest_contour")
    )

    yolo_lines = yolo_src.splitlines(keepends=True)
    idx_protocol = find_line(
        yolo_lines,
        'MASK_COORDINATE_PROTOCOL = "original_coordinate_polygon_v1"',
        11,
    )
    protocol_block = (
        "# Used by downstream notebooks to verify that the project is using the\n"
        "# coordinate-safe implementation rather than the old direct-resize version.\n"
        + yolo_lines[idx_protocol]
    )
    polygon_fn = extract_def(yolo_src, "_polygon_mask_in_original_coordinates").rstrip("\n")
    unletterbox_fn = extract_def(yolo_src, "_unletterbox_native_mask").rstrip("\n")

    return (
        CONSTRUCTION_HEADER
        + protocol_block
        + "\n\n\n"
        + primitives
        + "\n\n\n"
        + polygon_fn
        + "\n\n\n"
        + unletterbox_fn
        + "\n"
        + CONSTRUCT_PIG_MASK
    )


SEGMENTATION_HEADER = '''"""ML/pipeline/segmentation.py -- (1) run YOLO, pick the largest instance.

Consolidated from the model-running half of ML/yolo_inference.py's
predict_largest_mask (ML_implementation_plan.md revision 7, section 5.2/5.4).
Ported to C++ as stages/segmentation.cpp; gate B measures the two file to file.

The model itself is loaded by the caller (ML/weight_runtime.py is the reference
orchestrator) and passed in already constructed -- this file never touches
torch.load, ultralytics.YOLO(), or ML.compat.src_alias directly, so a checkpoint
swap never means editing this file.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


@dataclass
class SegmentationOutput:
    """The stage 1 -> stage 2 contract (section 5.4). Carries the ultralytics
    Results object and the selected instance index/confidence, plus the original
    image shape needed by construction's unletterbox fallback -- never
    recomputed on the stage-2 side (AGENTS.md rule 9)."""

    result: Any
    index: int
    confidence: float
    orig_shape: tuple[int, int]


'''

RUN_SEGMENTATION = '''

def run_segmentation(
    model,
    image_path: str | Path,
    imgsz: int = 640,
    conf: float = 0.25,
    device: int | str = 'cpu',
) -> SegmentationOutput | None:
    """(1) SEGMENTATION -- run the model, select the largest instance.

    This is predict_largest_mask's model-running half (ML/yolo_inference.py,
    pre-refactor). Returns None exactly where the original returned
    (None, 0.0): no result, or no mask survives confidence filtering.
    """
    results = model.predict(
        source=str(image_path),
        imgsz=imgsz,
        conf=conf,
        verbose=False,
        device=device,
    )
    if not results:
        return None

    result = results[0]
    index = _largest_mask_index(result)
    if index is None:
        return None

    confidence = 0.0
    if (
        result.boxes is not None
        and result.boxes.conf is not None
        and index < len(result.boxes.conf)
    ):
        confidence = float(result.boxes.conf[index].detach().cpu().item())

    return SegmentationOutput(
        result=result,
        index=index,
        confidence=confidence,
        orig_shape=tuple(result.orig_shape),
    )
'''


def build_segmentation(yolo_src: str) -> str:
    largest_idx_fn = extract_def(yolo_src, "_largest_mask_index").rstrip("\n")
    return SEGMENTATION_HEADER + largest_idx_fn + "\n" + RUN_SEGMENTATION


FEATURE_CALC_HEADER = '''"""ML/pipeline/feature_calculation.py -- (4) mask to feature vector.

Consolidated from ML/mask_features.py's extract_five_features plus all of
ML/extended_mask_features.py (ML_implementation_plan.md revision 7, section 5.2/5.5).
Ported to C++ as stages/feature_calculation.cpp -- baseline5 only; chen16 stays
reference-only until a chen16 model is actually selected (section 5.5), because it
needs skimage.morphology.skeletonize, which is otherwise confined to
ML.pipeline.cutter.

Imports clean_binary_mask / _largest_component_fill / largest_contour from
ML.pipeline.construction rather than carrying copies: extract_five_features calls
all three (ML/mask_features.py, pre-refactor).
"""

from __future__ import annotations

import cv2
import numpy as np
from skimage.morphology import skeletonize  # chen16 only -- not used by baseline5

from ML.pipeline.construction import (
    _largest_component_fill,
    clean_binary_mask,
    largest_contour,
)


'''


def build_feature_calculation(mf_src: str, ext_src: str) -> str:
    five_features = extract_def(mf_src, "extract_five_features").rstrip("\n")
    _, ext_body = strip_module_header(ext_src)
    return (
        FEATURE_CALC_HEADER
        + five_features
        + "\n\n\n"
        + "# ===== chen16 extended features (from ML/extended_mask_features.py) =====\n"
        + "# Reference-only (section 5.5): not part of the shipped baseline5\n"
        + "# [RA, LC, BL, BW, E] pipeline, and not ported to C++ until a chen16 model\n"
        + "# is selected.\n\n"
        + ext_body
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--against", default=PRE_DELETION_REV_DEFAULT, help="git revision holding the four originals")
    ap.add_argument("--pipeline-dir", default="ML/pipeline", help="output directory (repo-relative)")
    args = ap.parse_args()

    out_dir = pathlib.Path(args.pipeline_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    body_src = git_show(args.against, "ML/body_mask.py")
    mf_src = git_show(args.against, "ML/mask_features.py")
    ext_src = git_show(args.against, "ML/extended_mask_features.py")
    yolo_src = git_show(args.against, "ML/yolo_inference.py")

    segmentation_source = build_segmentation(yolo_src)
    (out_dir / "segmentation.py").write_text(segmentation_source, encoding="utf-8")
    print(f"wrote {out_dir / 'segmentation.py'} ({len(segmentation_source.splitlines())} lines)")

    construction_source = build_construction(mf_src, yolo_src)
    (out_dir / "construction.py").write_text(construction_source, encoding="utf-8")
    print(f"wrote {out_dir / 'construction.py'} ({len(construction_source.splitlines())} lines)")

    cutter_source = build_cutter(body_src, mf_src)
    (out_dir / "cutter.py").write_text(cutter_source, encoding="utf-8")
    print(f"wrote {out_dir / 'cutter.py'} ({len(cutter_source.splitlines())} lines)")

    feature_calc_source = build_feature_calculation(mf_src, ext_src)
    (out_dir / "feature_calculation.py").write_text(feature_calc_source, encoding="utf-8")
    print(f"wrote {out_dir / 'feature_calculation.py'} ({len(feature_calc_source.splitlines())} lines)")

    print("weight_prediction.py is hand-written (section 5.2(5)), not regenerated here.")


if __name__ == "__main__":
    main()
