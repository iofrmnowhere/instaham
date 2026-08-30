#!/usr/bin/env bash
# ML_implementation_plan.md revision 7, section 3.1 / 14: no stage may import a LATER
# stage, in Python or C++. The arrow runs
# segmentation -> construction -> cutter -> feature_calculation -> weight_prediction
# and only backwards-looking includes (a later stage depending on an earlier one) are
# legal. feature_calculation importing construction is the one real example
# (extract_five_features calls clean_binary_mask); nothing may go the other way.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
stages=(segmentation construction cutter feature_calculation weight_prediction)

stage_index() {
  local name="$1"
  for i in "${!stages[@]}"; do
    [ "${stages[$i]}" = "$name" ] && { echo "$i"; return; }
  done
  echo "-1"
}

for i in "${!stages[@]}"; do
  s="${stages[$i]}"
  f="ML/pipeline/${s}.py"
  [ -f "$f" ] || continue
  imports=$(grep -oE '^from ML\.pipeline\.[a-z_]+ import' "$f" | sed -E 's/^from ML\.pipeline\.([a-z_]+) import/\1/' || true)
  for other in $imports; do
    [ "$other" = "$s" ] && continue
    j=$(stage_index "$other")
    [ "$j" -eq -1 ] && continue
    if [ "$j" -gt "$i" ]; then
      echo "FAIL: ML/pipeline/${s}.py imports ML.pipeline.${other}, a later stage"
      fail=1
    fi
  done
done

if [ -d packages/instaham_ml_ffi/src/stages ]; then
  for i in "${!stages[@]}"; do
    s="${stages[$i]}"
    for ext in h cpp; do
      f="packages/instaham_ml_ffi/src/stages/${s}.${ext}"
      [ -f "$f" ] || continue
      includes=$(grep -oE '#include "stages/[a-z_]+\.h"' "$f" | sed -E 's#.*stages/([a-z_]+)\.h.*#\1#' || true)
      for other in $includes; do
        [ "$other" = "$s" ] && continue
        j=$(stage_index "$other")
        [ "$j" -eq -1 ] && continue
        if [ "$j" -gt "$i" ]; then
          echo "FAIL: $f includes stages/${other}.h, a later stage"
          fail=1
        fi
      done
    done
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "check_stage_order: OK -- no stage includes a later stage"
fi
exit $fail
