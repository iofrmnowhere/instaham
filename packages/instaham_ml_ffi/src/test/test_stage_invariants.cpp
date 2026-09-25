// docs/fix-phase-4/5-debug-and-assertions.md: one positive and one negative case per
// README section 17 assertion, as implemented by stages/invariants.h. Header-only, pure
// array/scalar math, no OpenCV/ORT, so this builds and runs unconditionally like
// test_segmentation_canvas.cpp and test_mask_selection.cpp.

#include "stages/invariants.h"

#include <cassert>
#include <cstdio>
#include <vector>

using instaham_ml::stages::check_canvas_exact;
using instaham_ml::stages::check_composition_positive;
using instaham_ml::stages::check_content_fits_canvas;
using instaham_ml::stages::check_final_mask_subset_of_base;
using instaham_ml::stages::check_mask_matches_rgb_dimensions;
using instaham_ml::stages::measure_final_mask_against_base;

int main() {
  // ==== check_composition_positive(): reference_px > 0, resize_factor > 0, ==============
  // ==== normalized_width/height > 0 ======================================================
  {
    assert(check_composition_positive(1547.62, 0.19, 900, 400).empty());
    assert(check_composition_positive(0.0, 0.19, 900, 400) == "reference_px_not_positive");
    assert(check_composition_positive(-5.0, 0.19, 900, 400) == "reference_px_not_positive");
    assert(check_composition_positive(1547.62, 0.0, 900, 400) == "resize_factor_not_positive");
    assert(check_composition_positive(1547.62, -0.1, 900, 400) == "resize_factor_not_positive");
    assert(check_composition_positive(1547.62, 0.19, 0, 400) ==
           "normalized_dimensions_not_positive");
    assert(check_composition_positive(1547.62, 0.19, 900, 0) ==
           "normalized_dimensions_not_positive");
  }

  // ==== check_content_fits_canvas(): "after orientation: width <= 960, height <= 540" ===
  {
    assert(check_content_fits_canvas(900, 400, 960, 540).empty());
    // boundary: exactly at the bound is accepted (">", not ">=").
    assert(check_content_fits_canvas(960, 540, 960, 540).empty());
    assert(check_content_fits_canvas(961, 400, 960, 540) == "content_exceeds_canvas");
    assert(check_content_fits_canvas(900, 541, 960, 540) == "content_exceeds_canvas");
  }

  // ==== check_canvas_exact(): "canvas size: exactly 960x540" =============================
  {
    assert(check_canvas_exact(960, 540, 960, 540).empty());
    assert(check_canvas_exact(960, 541, 960, 540) == "canvas_size_mismatch");
    assert(check_canvas_exact(961, 540, 960, 540) == "canvas_size_mismatch");
  }

  // ==== check_mask_matches_rgb_dimensions(): "cropped mask size equals rotated normalized
  // RGB size" / "after inverse rotation: BASE_MASK size equals original normalized RGB
  // size" -- same shape, exercised for both call sites named in the README. ============
  {
    // cropped-mask-vs-rotated-content shape.
    assert(check_mask_matches_rgb_dimensions(900, 400, 900, 400).empty());
    assert(check_mask_matches_rgb_dimensions(899, 400, 900, 400) == "mask_dimensions_mismatch");
    // base-mask-vs-original-normalized shape (dimensions swapped back after the inverse
    // rotation -- a mask that forgot to swap would still be 900x400 here, not 400x900).
    assert(check_mask_matches_rgb_dimensions(400, 900, 400, 900).empty());
    assert(check_mask_matches_rgb_dimensions(900, 400, 400, 900) == "mask_dimensions_mismatch");
  }

  // ==== check_final_mask_subset_of_base(): "FINAL_MASK size equals BASE_MASK size" and ===
  // ==== "FINAL_MASK foreground subset of BASE_MASK foreground" ===========================
  {
    // A 3x2 base mask (0/255 convention, PigMask's) and a final mask (0/1 convention,
    // CutterResult's) that only ever turns pixels OFF relative to the base -- the cutter's
    // actual contract (crop/cut, never grow).
    const std::vector<uint8_t> base = {255, 255, 0, 255, 0, 0};
    const std::vector<uint8_t> final_subset = {1, 0, 0, 1, 0, 0};
    assert(check_final_mask_subset_of_base(base, 3, 2, final_subset, 3, 2).empty());

    // Dimension mismatch.
    assert(check_final_mask_subset_of_base(base, 3, 2, final_subset, 2, 3) ==
           "final_mask_dimensions_mismatch");

    // Negative case: the final mask sets a pixel the base mask does not have --
    // FINAL_MASK not subset of BASE_MASK. Position 2 is 0 in `base`, 1 in `not_subset`.
    const std::vector<uint8_t> not_subset = {1, 0, 1, 1, 0, 0};
    assert(check_final_mask_subset_of_base(base, 3, 2, not_subset, 3, 2) ==
           "final_mask_not_subset_of_base");

    // Equal masks (no cut applied, "cut_not_required") are trivially a subset of themselves.
    const std::vector<uint8_t> base_as_zero_one = {1, 1, 0, 1, 0, 0};
    assert(check_final_mask_subset_of_base(base, 3, 2, base_as_zero_one, 3, 2).empty());
  }

  // ==== measure_final_mask_against_base(): the counted version pipeline.cpp uses to tell
  // ==== the vendor cutter's expected Ji/Duan gap-fill (a handful of scattered pixels)
  // ==== apart from a genuine coordinate error (a large displaced region) =================
  {
    const std::vector<uint8_t> base = {255, 255, 0, 255, 0, 0};
    const std::vector<uint8_t> final_subset = {1, 0, 0, 1, 0, 0};
    const auto m = measure_final_mask_against_base(base, 3, 2, final_subset, 3, 2);
    assert(m.dims_match);
    assert(m.added_px == 0);
    assert(m.removed_px == 1);  // position 1 -- base had it, final does not.

    const std::vector<uint8_t> not_subset = {1, 0, 1, 1, 0, 0};
    const auto m2 = measure_final_mask_against_base(base, 3, 2, not_subset, 3, 2);
    assert(m2.dims_match);
    assert(m2.added_px == 1);  // position 2 -- final has it, base does not.
    assert(m2.removed_px == 1);

    // Dimension mismatch reports no counts, not a misleading zero.
    const auto m3 = measure_final_mask_against_base(base, 3, 2, not_subset, 2, 3);
    assert(!m3.dims_match);
  }

  std::puts("test_stage_invariants: all assertions passed");
  return 0;
}
