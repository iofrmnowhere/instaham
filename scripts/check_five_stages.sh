#!/usr/bin/env bash
# ML_implementation_plan.md revision 7, section 3.2 / 14: exactly five process files
# under ML/pipeline/ and exactly five .cpp files under
# packages/instaham_ml_ffi/src/stages/, names matching pairwise. Fails the build if a
# sixth file appears in either, or if a pre-refactor predecessor reappears.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
stages=(segmentation construction cutter feature_calculation weight_prediction)

for gone in ML/body_mask.py ML/mask_features.py ML/extended_mask_features.py \
            ML/yolo_inference.py ML/pig_cutter.py ML/pig_geometry.py; do
  if [ -f "$gone" ]; then
    echo "FAIL: $gone exists -- superseded by ML/pipeline/*.py, git history keeps it recoverable"
    fail=1
  fi
done

for s in "${stages[@]}"; do
  if [ ! -f "ML/pipeline/${s}.py" ]; then
    echo "FAIL: ML/pipeline/${s}.py is missing"
    fail=1
  fi
done

py_extra=$(find ML/pipeline -maxdepth 1 -name '*.py' ! -name '__init__.py' | sed 's#.*/##; s/\.py$//' | sort)
py_expected=$(printf '%s\n' "${stages[@]}" | sort)
if [ "$py_extra" != "$py_expected" ]; then
  echo "FAIL: ML/pipeline/ should contain exactly {${stages[*]}} (plus __init__.py); found:"
  echo "$py_extra"
  fail=1
fi

# The native side is populated starting slice R2 (ML_implementation_plan.md section
# 13); until then this half of the check is a no-op rather than a false failure.
if [ -d packages/instaham_ml_ffi/src/stages ]; then
  cpp_extra=$(find packages/instaham_ml_ffi/src/stages -maxdepth 1 -name '*.cpp' | sed 's#.*/##; s/\.cpp$//' | sort)
  cpp_expected=$(printf '%s\n' "${stages[@]}" | sort)
  if [ "$cpp_extra" != "$cpp_expected" ]; then
    echo "FAIL: packages/instaham_ml_ffi/src/stages/ should contain exactly {${stages[*]}}.cpp; found:"
    echo "$cpp_extra"
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "check_five_stages: OK -- exactly ${#stages[@]} process files per runtime, no predecessors"
fi
exit $fail
