#!/usr/bin/env bash
# ML_implementation_plan.md revision 7, section 5.7 / 14: ML/pipeline/cutter.py may
# import ML.pipeline.construction (the one earlier stage it genuinely depends on --
# clean_binary_mask, _largest_component_fill) and stdlib/numpy/cv2/scipy/skimage.
# Nothing else project-local -- no other stage, no manifest, no model runtime, no file
# IO. This replaces revision 6's "zero project-local imports" rule: that rule existed
# because pig_cutter.py had to ship standalone under Chaquopy (section 3.1 of that
# revision); revision 7 deletes Chaquopy entirely (section 3.4), so cutter.py is free
# to import its one real earlier-stage dependency instead of inlining a duplicate copy.
set -euo pipefail
cd "$(dirname "$0")/.."

f="ML/pipeline/cutter.py"
fail=0

if [ ! -f "$f" ]; then
  echo "FAIL: $f does not exist"
  exit 1
fi

if grep -nE "^\s*(from|import)\s+ML(\.|$| )" "$f" | grep -qv "ML\.pipeline\.construction"; then
  echo "FAIL: $f imports a project-local ML.* module other than ML.pipeline.construction:"
  grep -nE "^\s*(from|import)\s+ML(\.|$| )" "$f" | grep -v "ML\.pipeline\.construction"
  fail=1
fi

if grep -nE "^\s*(from|import)\s+src(\.|$| )" "$f"; then
  echo "FAIL: $f still imports from the old src.* alias above -- section 5.2 inlines these"
  fail=1
fi

if grep -nE "\bopen\(|Path\(|onnxruntime|\btorch\b|ultralytics" "$f"; then
  echo "FAIL: $f does file IO or touches a model runtime above -- it must be pure mask-to-mask"
  fail=1
fi

allowed='^(from __future__|from typing|import math|import cv2|import numpy|from scipy|from skimage|from ML\.pipeline\.construction)'
bad=$(grep -E '^(import |from )' "$f" | grep -vE "$allowed" || true)
if [ -n "$bad" ]; then
  echo "FAIL: $f has an import outside the allowed set (numpy/cv2/scipy/skimage/stdlib/construction):"
  grep -nE '^(import |from )' "$f" | grep -vE "$allowed"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "check_cutter_purity: OK -- $f imports only ML.pipeline.construction + allowed third-party"
fi
exit $fail
