#!/usr/bin/env bash
# ML_implementation_plan.md section 13: "one helper file per runtime" (section 3.1.1).
# Fails the build if the four pre-consolidation originals reappear, or if anything
# still imports them, or if pig_cutter.py / pig_geometry.py go missing.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

for f in ML/body_mask.py ML/mask_features.py ML/extended_mask_features.py ML/yolo_inference.py; do
  if [ -f "$f" ]; then
    echo "FAIL: $f exists -- consolidation (section 5.5) requires it deleted, git history keeps it recoverable"
    fail=1
  fi
done

stale=$(grep -rn --include='*.py' \
  -E "from src\.(body_mask|mask_features|extended_mask_features|yolo_inference) import|import src\.(body_mask|mask_features|extended_mask_features|yolo_inference)|^from mask_features import|^from body_mask import|^from extended_mask_features import|^from yolo_inference import" \
  . 2>/dev/null \
  | grep -v '^\./build/' \
  | grep -v '^\./ML/tools/consolidate_helpers.py:' \
  | grep -v '^\./ML/parity/gate_a.py:' \
  || true)
if [ -n "$stale" ]; then
  echo "$stale"
  echo "FAIL: a stale import of a deleted helper module was found above"
  fail=1
fi

for f in ML/pig_cutter.py ML/pig_geometry.py; do
  if [ ! -f "$f" ]; then
    echo "FAIL: $f is missing -- exactly two helper files must exist (section 3.1.1)"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "check_one_helper: OK -- exactly ML/pig_cutter.py + ML/pig_geometry.py, no stale imports"
fi
exit $fail
