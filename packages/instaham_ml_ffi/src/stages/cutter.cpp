#include "stages/cutter.h"

#include <cstddef>

namespace instaham_ml {
namespace stages {

CutterResult cut_body_mask(const MaskView& in) {
  CutterResult out;
  if (!in.valid()) {
    out.status = "invalid_input";
    return out;
  }

  // ---- IDENTITY ------------------------------------------------------------
  // No head/neck removal. See cutter.h: the cut lives in ML/pipeline/cutter.py and is
  // permanently not ported (ML_implementation_plan.md revision 7, section 3.4). Passing
  // the mask through keeps the pipeline seam real without inventing a body mask that the
  // research protocol never produced.
  out.width = in.width;
  out.height = in.height;
  out.mask.assign(in.data, in.data + static_cast<size_t>(in.width) * in.height);
  out.head_removal_applied = false;
  out.status = "identity_stub";
  return out;
}

}  // namespace stages
}  // namespace instaham_ml
