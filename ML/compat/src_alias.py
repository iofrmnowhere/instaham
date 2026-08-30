"""Install the `src.*` module alias needed to unpickle project YOLO checkpoints.

Section 6.2 of ML_implementation_plan.md: `ML/segmentation/weights/best_eval_fp32.pt`
pickles its custom modules (`LDConv`, `ACmix`, `ACmixLDConvDownsample`) under the module
path `src.yolo_modifications`, but the repo only has `ML/yolo_modifications.py`. Without
this shim, `torch.load` on that checkpoint fails with `ModuleNotFoundError: No module
named 'src'`. `ML/weight_runtime.py` documents the same `src.` root for `src.body_mask`
and `src.yolo_inference`, so this one shim covers every project checkpoint, not just
segmentation.

Import this module (for its side effect) before any `torch.load` of a project checkpoint:

    import ML.compat.src_alias  # noqa: F401
"""
from __future__ import annotations

import sys
import types

import ML.yolo_modifications as _yolo_modifications

_src = types.ModuleType("src")
_src.__path__ = []  # mark as a package so `src.<submodule>` resolves
sys.modules.setdefault("src", _src)
sys.modules["src.yolo_modifications"] = _yolo_modifications

# ML/weight_runtime.py used to document src.body_mask / src.yolo_inference as legacy
# import roots for the pre-refactor cutter helpers (ML_implementation_plan.md revision 6).
# Those modules were deleted at revision 6's section 5.5 and their successors
# (ML/pig_cutter.py, ML/pig_geometry.py) were themselves deleted at revision 7's section
# 5.6 in favour of ML/pipeline/*.py -- so no alias is installed for either; if a
# checkpoint ever needs one, add it here rather than duplicating this shim elsewhere.
