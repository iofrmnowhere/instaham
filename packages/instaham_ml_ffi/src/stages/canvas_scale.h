#ifndef INSTAHAM_ML_STAGES_CANVAS_SCALE_H
#define INSTAHAM_ML_STAGES_CANVAS_SCALE_H

#include <algorithm>
#include <cmath>

namespace instaham_ml {
namespace stages {

// docs/fix-phase-4/1.1-readme-is-the-path.md: `decide_canvas_scale()` and
// `CanvasScaleDecision`, the round-4 scale-aware canvas composition this file used to also
// hold, were removed here. They served only the `kCanvasScale` branch
// stages/segmentation.cpp no longer implements; nothing else called them directly.
// `pipeline.cpp`'s not-yet-rewired call site (docs/fix-phase-4/4-app-wiring.md) calls
// run_segmentation() itself, so it now runs the normalize-first composition below with
// its ladder multipliers substituting for cm_per_px_target until phase 4 fixes that.

// docs/fix-phase-4/1.1-readme-is-the-path.md: the pure arithmetic behind the
// SegmentationInputScaleMode::kNormalizeFirst path -- resize the source image so it is
// exactly `cm_per_px_target` cm/pixel, rotate it 90 degrees clockwise when that leaves it
// portrait (no dynamic head-direction inference: README section 4), then centre it on a
// 960x540 canvas. Header-only and OpenCV-free like decide_canvas_scale() above, so the
// composition decision -- offsets, rotation, and the oversize fallback -- is unit-testable
// (test_segmentation_canvas.cpp) without a model or a photograph.
struct NormalizeFirstComposition {
  bool valid = false;   // false -> caller must not use this decision (bad inputs, or oversize)
  bool oversize = false;  // true -> valid is also false; README section 6's halt, not bad input
  double resize_factor = 0.0;  // cm_per_px_actual / cm_per_px_target
  int normalized_w = 0, normalized_h = 0;  // after the uniform resize, before rotation
  bool rotated_clockwise = false;
  int content_w = 0, content_h = 0;  // normalized_w/h, swapped if rotated_clockwise
  // docs/fix-phase-4/3-constants.md phase 3: 960x540 is the released PIGRGB RGB_9579 frame
  // size at the 1.88 m training camera height (docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md
  // line 29), the same physical setup training_frame_px's 720x720 (manifest.h) is fitted
  // to -- README section 6 fixes the app's canvas to that released frame size rather than
  // to the training crop. That source document itself says a normalized image "does not
  // need to be exactly 960 x 540" (same file, lines 287/685); the README requires an exact
  // fit and halts otherwise (section 6). This round ships the README's exact-fit reading;
  // the divergence from the normalization doc's own guidance is flagged in fix-4.md, not
  // resolved here.
  int canvas_w_requested = 960, canvas_h_requested = 540;  // README section 6's canvas
  int canvas_w = 0, canvas_h = 0;  // == requested; no enlargement (F61 fallback withdrawn)
  int x_offset = 0, y_offset = 0;  // content's top-left corner on the canvas
};

// `src_w`/`src_h`: the decoded source image's dimensions. `cm_per_px_actual`: the
// user-confirmed reference object's measured cm/pixel for this capture (AGENTS.md rule 7 --
// never invented; <= 0.0 means no reference, and this function returns `valid = false`).
// `cm_per_px_target`: WeightCapability::cm_per_px_target, the scale the regressor was
// trained at (<= 0.0 -- an older manifest fragment with no weight capability -- also
// returns `valid = false`; there is no implicit fallback, matching AGENTS.md rule 8).
//
// docs/fix-phase-4/1.1-readme-is-the-path.md (F61, superseding phase 1's enlargement):
// README section 6 requires the normalized, rotated content fit the 960x540 canvas and
// says to halt otherwise. That halt is shipped here as `valid = false` with `oversize =
// true` -- the caller (stages/segmentation.cpp) turns that into a declared weight-branch
// failure carrying `normalized_w`/`normalized_h` and the 960x540 bound, never a silent
// resize or an enlarged canvas. Content is never shrunk to force a fit either way -- the
// one thing the README is unambiguously right to forbid, since it would silently break
// cm_per_px_target.
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

  const int canvas_w = c.canvas_w_requested;
  const int canvas_h = c.canvas_h_requested;
  if (c.content_w > canvas_w || c.content_h > canvas_h) {
    // README section 6's fit invariant failed. Halt: no enlargement, no shrink, no
    // composition. `canvas_w`/`canvas_h` stay at the requested 960x540 so the caller can
    // report the bound the content was checked against.
    c.canvas_w = canvas_w;
    c.canvas_h = canvas_h;
    c.oversize = true;
    return c;
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
