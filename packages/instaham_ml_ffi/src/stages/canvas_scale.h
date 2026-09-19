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

// docs/fix-phase-4/1-normalize-before-segment.md (F60/F61): the pure arithmetic behind the
// SegmentationInputScaleMode::kNormalizeFirst path -- resize the source image so it is
// exactly `cm_per_px_target` cm/pixel, rotate it 90 degrees clockwise when that leaves it
// portrait (no dynamic head-direction inference: README section 4), then centre it on a
// 960x540 canvas. Header-only and OpenCV-free like decide_canvas_scale() above, so the
// composition decision -- offsets, rotation, and the oversize fallback -- is unit-testable
// (test_segmentation_canvas.cpp) without a model or a photograph.
struct NormalizeFirstComposition {
  bool valid = false;          // false -> caller must not use this decision (bad inputs)
  double resize_factor = 0.0;  // cm_per_px_actual / cm_per_px_target
  int normalized_w = 0, normalized_h = 0;  // after the uniform resize, before rotation
  bool rotated_clockwise = false;
  int content_w = 0, content_h = 0;  // normalized_w/h, swapped if rotated_clockwise
  int canvas_w_requested = 960, canvas_h_requested = 540;  // README section 6's base canvas
  int canvas_w = 0, canvas_h = 0;                          // actually used
  int x_offset = 0, y_offset = 0;  // content's top-left corner on the canvas
};

// `src_w`/`src_h`: the decoded source image's dimensions. `cm_per_px_actual`: the
// user-confirmed reference object's measured cm/pixel for this capture (AGENTS.md rule 7 --
// never invented; <= 0.0 means no reference, and this function returns `valid = false`).
// `cm_per_px_target`: WeightCapability::cm_per_px_target, the scale the regressor was
// trained at (<= 0.0 -- an older manifest fragment with no weight capability -- also
// returns `valid = false`; there is no implicit fallback, matching AGENTS.md rule 8).
//
// F61: README section 6 asserts the normalized image always fits the 960x540 canvas and
// says to halt otherwise; a 4032x3024 field capture (.pig_pictures/, cm_per_px_actual ~=
// 0.0644) normalizes to 764x573, which does not. Rather than halt, this enlarges the canvas
// to the smallest 16:9, multiple-of-32 box that contains the content -- preserving the
// physical scale the invariant exists to protect -- and never shrinks the content to force
// a fit (the one thing the README is unambiguously right to forbid: it would silently break
// cm_per_px_target).
inline NormalizeFirstComposition decide_normalize_first_composition(int src_w, int src_h,
                                                                      double cm_per_px_actual,
                                                                      double cm_per_px_target) {
  NormalizeFirstComposition c;
  if (src_w <= 0 || src_h <= 0 || !(cm_per_px_actual > 0.0) || !std::isfinite(cm_per_px_actual) ||
      !(cm_per_px_target > 0.0) || !std::isfinite(cm_per_px_target)) {
    return c;
  }
  const double factor = cm_per_px_actual / cm_per_px_target;
  if (!(factor > 0.0) || !std::isfinite(factor)) return c;
  c.resize_factor = factor;
  c.normalized_w = std::max(1, int(std::round(src_w * factor)));
  c.normalized_h = std::max(1, int(std::round(src_h * factor)));
  c.rotated_clockwise = c.normalized_h > c.normalized_w;
  c.content_w = c.rotated_clockwise ? c.normalized_h : c.normalized_w;
  c.content_h = c.rotated_clockwise ? c.normalized_w : c.normalized_h;

  // README section 6's base 960x540 canvas when the content fits it exactly (960x540 is
  // itself the requirement -- it is not a multiple of 32, so it is never "rounded" when it
  // already suffices). Only when the content does not fit does F61's multiple-of-32, 16:9
  // enlargement kick in, since that canvas then feeds a model that letterboxes it again
  // (stride-friendly padding matters there, not for the unmodified base case).
  int canvas_w = c.canvas_w_requested;
  int canvas_h = c.canvas_h_requested;
  if (c.content_w > canvas_w || c.content_h > canvas_h) {
    const int needed_w =
        std::max(c.content_w, int(std::ceil(c.content_h * 16.0 / 9.0)));
    canvas_w = ((needed_w + 31) / 32) * 32;
    canvas_h = ((int(std::ceil(canvas_w * 9.0 / 16.0)) + 31) / 32) * 32;
    // Integer rounding of the 16:9 ratio can theoretically shave a pixel off either
    // dimension; widen by one more 32-px step until both genuinely fit rather than trust
    // the rounding (this loop runs at most once or twice in practice).
    while (canvas_w < c.content_w || canvas_h < c.content_h) {
      canvas_w += 32;
      canvas_h = ((int(std::ceil(canvas_w * 9.0 / 16.0)) + 31) / 32) * 32;
    }
  }
  c.canvas_w = canvas_w;
  c.canvas_h = canvas_h;
  c.x_offset = (canvas_w - c.content_w) / 2;
  c.y_offset = (canvas_h - c.content_h) / 2;
  c.valid = true;
  return c;
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_CANVAS_SCALE_H
