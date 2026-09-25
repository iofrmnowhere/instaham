// docs/fix-phase-4/1.1-readme-is-the-path.md: unit test for
// decide_normalize_first_composition() (stages/canvas_scale.h) -- the pure arithmetic
// behind INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md sections 2-8: resize
// the source image to a physical scale, rotate 90 clockwise when that leaves it portrait,
// centre it on a 960x540 canvas, halting (README section 6) rather than enlarging or
// shrinking when it does not fit. Also covers mask_geometry.h's
// rotate90_cw()/rotate90_ccw() round trip. Pure array math, no OpenCV/ORT, so it builds
// and runs unconditionally like test_mask_selection.cpp.
//
// `decide_canvas_scale()` and its round-4 scale-aware canvas tests were removed here --
// stages/segmentation.cpp no longer has a `kCanvasScale` path to exercise
// (docs/fix-phase-4/1.1-readme-is-the-path.md).
//
// docs/fix-phase-4/3-constants.md phase 3 (F62) added the mask_diagonal_fraction() section
// below: it measures the same real-corpus-shaped mask against the pre-README square frame
// (720x720, the training frame's own aspect) and the README's 960x540 canvas aspect, and
// confirms min_mask_diagonal_fraction's (0.35) verdict does not change between them --
// the "if none do, say so" outcome the phase document's Verification section allows for.

#include "stages/canvas_scale.h"
#include "stages/mask_geometry.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <vector>

using instaham_ml::stages::decide_normalize_first_composition;
using instaham_ml::stages::mask_diagonal_fraction;
using instaham_ml::stages::rotate90_ccw;
using instaham_ml::stages::rotate90_cw;

int main() {
  // ==== decide_normalize_first_composition() =============================================

  // ---- missing/invalid inputs must not produce a composition ----
  {
    assert(!decide_normalize_first_composition(2250, 3000, 0.0, 0.34).valid);
    assert(!decide_normalize_first_composition(2250, 3000, 0.0653, 0.0).valid);
    assert(!decide_normalize_first_composition(2250, 3000, std::nan(""), 0.34).valid);
    assert(!decide_normalize_first_composition(0, 3000, 0.0653, 0.34).valid);
  }

  // ---- fits the 960x540 base canvas without rotation: a landscape capture whose
  // normalized size is already <= 960x540 ----
  {
    // cm_per_px_actual chosen so resize_factor = 0.5 -> normalized 900x400, landscape,
    // fits 960x540 with no enlargement.
    auto c = decide_normalize_first_composition(1800, 800, 0.17, 0.34);
    assert(c.valid);
    assert(std::fabs(c.resize_factor - 0.5) < 1e-9);
    assert(c.normalized_w == 900 && c.normalized_h == 400);
    assert(!c.rotated_clockwise);
    assert(c.content_w == 900 && c.content_h == 400);
    assert(c.canvas_w == 960 && c.canvas_h == 540);
    assert(c.x_offset == (960 - 900) / 2 && c.y_offset == (540 - 400) / 2);
  }

  // ---- portrait normalized image rotates 90 clockwise before placement (README section
  // 4: no dynamic head-direction inference -- always this one fixed rotation) ----
  {
    auto c = decide_normalize_first_composition(800, 1800, 0.17, 0.34);
    assert(c.valid);
    assert(c.normalized_w == 400 && c.normalized_h == 900);
    assert(c.rotated_clockwise);
    // content is the ROTATED normalized image: width/height swapped.
    assert(c.content_w == 900 && c.content_h == 400);
    assert(c.canvas_w == 960 && c.canvas_h == 540);
  }

  // ---- F61, README section 6: the fit invariant fails on a real field capture --
  // 4032x3024 at cm_per_px_actual ~= 0.0644 normalizes to ~764x573, landscape (573 > 540:
  // rotation does not help, matching scaling-rotation-readme-analysis.md's finding). Must
  // halt -- `valid = false`, `oversize = true` -- never enlarge the canvas and never
  // shrink the content (docs/fix-phase-4/1.1-readme-is-the-path.md withdraws phase 1's
  // enlargement fallback). ----
  {
    auto c = decide_normalize_first_composition(4032, 3024, 0.0644, 0.34);
    assert(!c.valid);
    assert(c.oversize);
    assert(!c.rotated_clockwise);  // 764x573 stays landscape; rotating doesn't help
    assert(c.content_h > c.canvas_h_requested);  // the invariant genuinely fails here
    // The halt reports the REQUESTED bound, not an enlarged one -- there is no other
    // canvas size to report.
    assert(c.canvas_w == c.canvas_w_requested && c.canvas_h == c.canvas_h_requested);
  }

  // ---- boundary: content that lands exactly at 960x540 must be accepted, not halted
  // (the check is "> canvas", not ">=") ----
  {
    auto c = decide_normalize_first_composition(1920, 1080, 0.17, 0.34);  // factor = 0.5
    assert(c.valid);
    assert(!c.oversize);
    assert(c.content_w == 960 && c.content_h == 540);
    assert(c.canvas_w == 960 && c.canvas_h == 540);
    assert(c.x_offset == 0 && c.y_offset == 0);
  }

  // ==== mask_geometry.h's rotate90_cw()/rotate90_ccw() round trip (F60) ==================
  {
    // A 3x2 (w=3, h=2) synthetic mask with distinct values at every pixel.
    const int w = 3, h = 2;
    const std::vector<uint8_t> src = {10, 20, 30, 40, 50, 60};
    auto rotated = rotate90_cw(src, w, h);
    assert(int(rotated.size()) == w * h);
    // rotate90_cw's output is h x w (dimensions swapped).
    auto back = rotate90_ccw(rotated, /*w=*/h, /*h=*/w);
    assert(back == src);
  }

  // ==== mask_diagonal_fraction() at the pre-README vs README frame aspect (F62) ==========
  // docs/fix-phase-4/3-constants.md phase 3. The gate's real denominator is the mask's own
  // `content` frame (stages/segmentation.cpp sets PigMask::width/height to
  // NormalizeFirstComposition::content_w/h, not the 960x540 canvas), which varies per
  // capture -- so this does not reproduce a specific photo. It instead checks the one thing
  // that genuinely differs between the two frame shapes at EQUAL AREA (720*720 ==
  // 960*540 == 518400 px): a square frame's diagonal is shorter than a 960x540 frame's
  // diagonal for the same area, so the same absolute bbox reads as a smaller fraction on
  // the wider frame. ref_fix.md F23 measured a correct whole-pig mask at 0.62-0.74 of its
  // frame's diagonal and a wrong one at 0.06-0.15, against 0.35. Bboxes placed at the
  // centre of both ranges are checked on both frame shapes; neither crosses 0.35 either
  // way, so the round-4-to-README canvas shape change does not move this gate's verdict.
  {
    const int square_w = 720, square_h = 720;      // pre-README-shaped frame, same area as:
    const int wide_w = 960, wide_h = 540;          // ...the README's canvas, 518400 px both.

    // A plausible whole-pig bbox: diagonal ~0.62 of a 720x720 frame's diagonal.
    const int plausible_bbox = 447;  // sqrt(447^2*2) / sqrt(720^2*2) = 0.6208
    const double plausible_on_square =
        mask_diagonal_fraction(plausible_bbox, plausible_bbox, square_w, square_h);
    const double plausible_on_wide =
        mask_diagonal_fraction(plausible_bbox, plausible_bbox, wide_w, wide_h);
    assert(plausible_on_square > 0.35);
    assert(plausible_on_wide > 0.35);  // still admitted on the README's canvas shape

    // An implausible bbox (F12/F16's kind of bug): diagonal ~0.10 of a 720x720 frame.
    const int implausible_bbox = 72;  // sqrt(72^2*2) / sqrt(720^2*2) = 0.1000
    const double implausible_on_square =
        mask_diagonal_fraction(implausible_bbox, implausible_bbox, square_w, square_h);
    const double implausible_on_wide =
        mask_diagonal_fraction(implausible_bbox, implausible_bbox, wide_w, wide_h);
    assert(implausible_on_square < 0.35);
    assert(implausible_on_wide < 0.35);  // still rejected on the README's canvas shape

    // Frame diagonal (denominator) is smaller for the square, so the same bbox reads as a
    // LARGER fraction on the square than on the wide frame -- confirming the two frames
    // are not equivalent, only that 0.35 sits outside both ranges either way.
    assert(plausible_on_square > plausible_on_wide);
    assert(implausible_on_square > implausible_on_wide);
  }

  std::puts("test_segmentation_canvas: all assertions passed");
  return 0;
}
