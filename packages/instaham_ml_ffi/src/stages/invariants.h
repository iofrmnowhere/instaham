#ifndef INSTAHAM_ML_STAGES_INVARIANTS_H
#define INSTAHAM_ML_STAGES_INVARIANTS_H

#include <cstdint>
#include <string>
#include <vector>

namespace instaham_ml {
namespace stages {

// docs/fix-phase-4/5-debug-and-assertions.md: README section 17's "Required Assertions",
// as pure scalar/array checks so they are unit-testable (test_stage_invariants.cpp)
// without OpenCV or an ONNX Runtime session -- the same pattern as canvas_scale.h and
// mask_geometry.h. Each function returns an empty string when the invariant holds, or a
// stable, machine-readable reason string when it does not; the caller (pipeline.cpp) turns
// a non-empty reason into a declared failure with that reason, never a silent extra resize
// (AGENTS.md rule 8; README section 17's closing line: "treat it as a pipeline/coordinate
// error rather than silently applying another resize").
//
// Several of README section 17's checks are already enforced by construction rather than
// needing a runtime check here: `decide_normalize_first_composition()` (canvas_scale.h)
// already returns `valid = false` for a non-positive `resize_factor` or non-positive
// normalized dimensions, and already returns `oversize = true` (never enlarging or
// shrinking) when the rotated content does not fit the 960x540 canvas -- so
// "reference_px > 0 / scale_factor > 0 / normalized_width,height > 0" and "after
// orientation: width <= 960, height <= 540" are covered there, not duplicated here.
// `check_composition_positive()` and `check_content_fits_canvas()` below exist anyway so a
// future caller that does NOT go through `decide_normalize_first_composition()` (a test, or
// a future alternate composition path) still gets the same check, and so the invariant is
// something this file states explicitly rather than only implicitly, per the phase 5
// document's instruction to ship all of README section 17's checks.

// "reference_px > 0 / scale_factor > 0 / normalized_width, normalized_height > 0".
inline std::string check_composition_positive(double reference_px, double resize_factor,
                                               int normalized_w, int normalized_h) {
  if (!(reference_px > 0.0)) return "reference_px_not_positive";
  if (!(resize_factor > 0.0)) return "resize_factor_not_positive";
  if (normalized_w <= 0 || normalized_h <= 0) return "normalized_dimensions_not_positive";
  return "";
}

// "after orientation: width <= 960, height <= 540" -- the rotated content rectangle
// checked against the canvas it must fit inside without enlargement or shrinking.
inline std::string check_content_fits_canvas(int content_w, int content_h, int canvas_w,
                                              int canvas_h) {
  if (content_w > canvas_w || content_h > canvas_h) return "content_exceeds_canvas";
  return "";
}

// "canvas size: exactly 960x540" -- the composed canvas itself, not the content placed on
// it (which may be smaller on either axis and centred).
inline std::string check_canvas_exact(int canvas_w, int canvas_h, int expected_w,
                                       int expected_h) {
  if (canvas_w != expected_w || canvas_h != expected_h) return "canvas_size_mismatch";
  return "";
}

// "cropped mask size equals rotated normalized RGB size" (checked right after
// construct_pig_mask(), before the inverse rotation) and "after inverse rotation: BASE_MASK
// size equals original normalized RGB size" (checked right after
// rotate_pig_mask_90_ccw()) are the same dimension-equality shape at two different points
// in the pipeline, so one function serves both call sites -- the caller supplies whichever
// pair of dimensions is relevant at that point.
inline std::string check_mask_matches_rgb_dimensions(int mask_w, int mask_h, int rgb_w,
                                                      int rgb_h) {
  if (mask_w != rgb_w || mask_h != rgb_h) return "mask_dimensions_mismatch";
  return "";
}

// "FINAL_MASK size equals BASE_MASK size" and "FINAL_MASK foreground subset of BASE_MASK
// foreground". `base`/`final_mask` are row-major, same-length-when-equal-dimensions
// rasters; a pixel counts as foreground when it is non-zero, which holds whether the
// caller's convention is 0/1 (CutterResult::mask) or 0/255 (PigMask::pixels) -- the two
// masks compared here do not need to share that convention, only their dimensions and
// which pixels are zero.
//
// docs/fix-phase-4/5-debug-and-assertions.md phase 5 verification: the cutter's Ji/Duan
// preprocessing (vendor/instaham_v176) applies a morphological CLOSE before the actual cut
// (README section 10's "Ji-Duan preprocessing" step, between BASE_MASK and the V176/V144
// cut), which can legitimately fill small gaps and add a handful of foreground pixels the
// base mask did not have -- this is expected denoising, not a coordinate bug, and measured
// at 17 of 46043 base px (0.037%) on the one real corpus A photograph checked
// (75kg_pig_meter_stick.jpg). `added_px` is reported alongside the
// pass/fail reason precisely so a real coordinate bug (which would add a LARGE, spatially
// displaced region, not a scattering of gap-fill pixels) is distinguishable from this
// noise without re-deriving the masks. `check_final_mask_subset_of_base()`'s reason stays
// literal to README section 17's exact wording (any added pixel is a "violation"); the
// caller decides, using `added_px`, whether an occurrence should withhold weight or only be
// recorded -- see pipeline.cpp's `kMaxTolerableAddedMaskPx` for the threshold this round
// ships.
struct MaskSubsetMeasurement {
  bool dims_match = false;
  long long added_px = 0;    // foreground in final_mask, absent from base -- the violation
  long long removed_px = 0;  // foreground in base, absent from final_mask -- the expected cut
};

inline MaskSubsetMeasurement measure_final_mask_against_base(
    const std::vector<uint8_t>& base, int base_w, int base_h,
    const std::vector<uint8_t>& final_mask, int final_w, int final_h) {
  MaskSubsetMeasurement m;
  m.dims_match = (base_w == final_w && base_h == final_h && base.size() == final_mask.size());
  if (!m.dims_match) return m;
  for (size_t i = 0; i < final_mask.size(); ++i) {
    const bool in_base = base[i] != 0;
    const bool in_final = final_mask[i] != 0;
    if (in_final && !in_base) ++m.added_px;
    if (in_base && !in_final) ++m.removed_px;
  }
  return m;
}

inline std::string check_final_mask_subset_of_base(const std::vector<uint8_t>& base, int base_w,
                                                    int base_h,
                                                    const std::vector<uint8_t>& final_mask,
                                                    int final_w, int final_h) {
  const MaskSubsetMeasurement m =
      measure_final_mask_against_base(base, base_w, base_h, final_mask, final_w, final_h);
  if (!m.dims_match) return "final_mask_dimensions_mismatch";
  if (m.added_px > 0) return "final_mask_not_subset_of_base";
  return "";
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_INVARIANTS_H
