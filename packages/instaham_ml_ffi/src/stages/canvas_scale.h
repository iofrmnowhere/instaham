#ifndef INSTAHAM_ML_STAGES_CANVAS_SCALE_H
#define INSTAHAM_ML_STAGES_CANVAS_SCALE_H

#include <algorithm>
#include <cmath>

namespace instaham_ml {
namespace stages {

// ref_fix.md F18: decides whether stages::run_segmentation composes the model's input
// canvas at a scale derived from the user-confirmed reference object (`content_scale =
// cm_per_px_actual / input_cm_per_px`) or falls back to the plain whole-frame-fit
// letterbox this always used. Factored out of segmentation.cpp, pure-array-math and
// OpenCV/ORT-free, exactly the way F12 factored proto_box_bounds()/cropped_mask_area()
// into mask_geometry.h -- so this decision is unit-testable (test_segmentation_canvas.cpp)
// without a real model or photo.
struct CanvasScaleDecision {
  bool use_scale_aware = false;  // false -> caller must fall back to letterbox()
  float scale = 0.0f;            // valid only when use_scale_aware
};

// `src_w`/`src_h`: the decoded source image's dimensions. `cm_per_px_actual`: the
// user-confirmed reference object's measured cm/pixel for this capture, or <= 0.0 when
// none exists (AGENTS.md rule 7 -- never invented). `input_cm_per_px`: this attempt's
// target canvas scale (manifest.segmentation.input_cm_per_px x a ref_fix.md F19 ladder
// multiplier), or <= 0.0 when scale-aware composition was not requested (an older
// manifest fragment). `canvas_size`: the model's square input side (cap.imgsz).
//
// Returns `use_scale_aware = false` whenever either input is missing/non-finite/non-
// positive, OR the resulting content would overflow the canvas -- never a clipped or
// distorted composition. The caller is responsible for falling back to letterbox() and
// recording that fallback (SegmentationOutput::clamped_to_letterbox) in that case.
inline CanvasScaleDecision decide_canvas_scale(int src_w, int src_h, double cm_per_px_actual,
                                                double input_cm_per_px, int canvas_size) {
  CanvasScaleDecision decision;
  if (!(cm_per_px_actual > 0.0) || !std::isfinite(cm_per_px_actual) || !(input_cm_per_px > 0.0) ||
      !std::isfinite(input_cm_per_px)) {
    return decision;
  }
  const double content_scale = cm_per_px_actual / input_cm_per_px;
  if (!(content_scale > 0.0) || !std::isfinite(content_scale)) {
    return decision;
  }
  const int new_w = std::max(1, int(std::round(src_w * content_scale)));
  const int new_h = std::max(1, int(std::round(src_h * content_scale)));
  if (new_w > canvas_size || new_h > canvas_size) {
    return decision;
  }
  decision.use_scale_aware = true;
  decision.scale = float(content_scale);
  return decision;
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_CANVAS_SCALE_H
