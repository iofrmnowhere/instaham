#!/usr/bin/env bash
# ML_implementation_plan.md section 3.1: ML/pig_cutter.py ships standalone (Chaquopy,
# Android) and must import nothing project-local -- no ML.*, no file IO helpers beyond
# what numpy/cv2/scipy/skimage/stdlib provide, no manifest, no model loading.
set -euo pipefail
cd "$(dirname "$0")/.."

f="ML/pig_cutter.py"
fail=0

if [ ! -f "$f" ]; then
  echo "FAIL: $f does not exist"
  exit 1
fi

if grep -nE "^\s*(from|import)\s+ML(\.|$| )" "$f"; then
  echo "FAIL: $f imports a project-local ML.* module above -- it must ship standalone"
  fail=1
fi

if grep -nE "^\s*(from|import)\s+src(\.|$| )" "$f"; then
  echo "FAIL: $f still imports from the old src.* alias above -- section 5.5.1 inlines these"
  fail=1
fi

if grep -nE "\bopen\(|Path\(|onnxruntime|\btorch\b|ultralytics" "$f"; then
  echo "FAIL: $f does file IO or touches a model runtime above -- it must be pure mask-to-mask"
  fail=1
fi

allowed='^(from __future__|from typing|import math|import cv2|import numpy|from scipy|from skimage)'
bad=$(grep -E '^(import |from )' "$f" | grep -vE "$allowed" || true)
if [ -n "$bad" ]; then
  echo "FAIL: $f has an import outside the allowed set (numpy/cv2/scipy/skimage/stdlib):"
  grep -nE '^(import |from )' "$f" | grep -vE "$allowed"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "check_cutter_purity: OK -- $f has zero project-local imports"
fi
exit $fail
