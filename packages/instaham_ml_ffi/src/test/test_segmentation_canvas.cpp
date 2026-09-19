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

#include "stages/canvas_scale.h"
#include "stages/mask_geometry.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <vector>

using instaham_ml::stages::decide_normalize_first_composition;
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

  std::puts("test_segmentation_canvas: all assertions passed");
  return 0;
}
