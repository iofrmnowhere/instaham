// ref_fix.md F18: unit test for decide_canvas_scale() (stages/canvas_scale.h), the pure
// arithmetic behind the round-4 fix -- composing the 640x640 segmentation canvas at a
// scale derived from the user-confirmed reference object instead of a plain whole-frame
// fit. Pure array math, no OpenCV/ORT, so it builds and runs unconditionally like
// test_mask_selection.cpp.
//
// The bug this guards against (ref_fix.md section 1.3/1.4): a plain whole-frame letterbox
// makes a typical 2250x3000 phone photo's pig appear at ~220x400px in the model's 640x640
// input, and the exported segmenter does not reliably detect a pig at that apparent size
// (every box above ~100x100px scored 0.000 confidence across all three ground-truth
// photos in .pig_pictures/). Composing the canvas at content_scale = cm_per_px_actual /
// input_cm_per_px instead makes the pig's apparent size reflect its real-world size.
//
// docs/fix-phase-4/1-normalize-before-segment.md (F60/F61): also covers
// decide_normalize_first_composition() (same header) and mask_geometry.h's
// rotate90_cw()/rotate90_ccw() -- the normalize_first path's composition decision and its
// mask round-trip, both pure array math.

#include "stages/canvas_scale.h"
#include "stages/mask_geometry.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <vector>

using instaham_ml::stages::decide_canvas_scale;
using instaham_ml::stages::decide_normalize_first_composition;
using instaham_ml::stages::rotate90_ccw;
using instaham_ml::stages::rotate90_cw;

int main() {
  // ---- no reference marked: cm_per_px_actual <= 0 -- must fall back to letterbox() ----
  {
    auto d = decide_canvas_scale(2250, 3000, /*cm_per_px_actual=*/0.0,
                                  /*input_cm_per_px=*/1.10, /*canvas_size=*/640);
    assert(!d.use_scale_aware);
  }

  // ---- older manifest fragment: input_cm_per_px <= 0 (F18 not declared) -- same fallback,
  // never silently invented ----
  {
    auto d = decide_canvas_scale(2250, 3000, /*cm_per_px_actual=*/0.0653,
                                  /*input_cm_per_px=*/0.0, /*canvas_size=*/640);
    assert(!d.use_scale_aware);
  }

  // ---- non-finite / negative inputs must not produce a scale ----
  {
    auto d1 = decide_canvas_scale(2250, 3000, std::nan(""), 1.10, 640);
    assert(!d1.use_scale_aware);
    auto d2 = decide_canvas_scale(2250, 3000, -0.0653, 1.10, 640);
    assert(!d2.use_scale_aware);
  }

  // ---- the normal case: a real photo's cm_per_px_actual, the manifest's default
  // input_cm_per_px -- must resolve to the exact division, and the content must fit ----
  {
    // ref_log.md's 118kg porac-stick photo: cm_per_px_actual = 0.0653.
    auto d = decide_canvas_scale(2250, 3000, 0.0653, 1.10, 640);
    assert(d.use_scale_aware);
    const float expected_scale = float(0.0653 / 1.10);
    assert(std::fabs(d.scale - expected_scale) < 1e-6f);
    const int content_w = int(std::round(2250 * d.scale));
    const int content_h = int(std::round(3000 * d.scale));
    assert(content_w <= 640 && content_h <= 640);
    assert(content_w > 0 && content_h > 0);
  }

  // ---- clamp: a requested scale that would overflow the 640 canvas must fall back rather
  // than clip -- e.g. a very small input_cm_per_px (near the image's own native scale) on
  // a large image ----
  {
    auto d = decide_canvas_scale(2250, 3000, 0.0653, /*input_cm_per_px=*/0.01,
                                  /*canvas_size=*/640);
    // content_scale = 6.53, content would be 14700x19590px -- must not fit.
    assert(!d.use_scale_aware);
  }

  // ---- boundary: content that lands exactly at the canvas size must be accepted, not
  // clamped (the check is "> canvas_size", not ">="), matching run_segmentation's own
  // round(src*scale) computation ----
  {
    // Choose input_cm_per_px so round(300 * scale) == 640 exactly: scale = 640/300.
    const double scale = 640.0 / 300.0;
    const double cm_per_px_actual = 1.0;
    const double input_cm_per_px = cm_per_px_actual / scale;  // = 300/640
    auto d = decide_canvas_scale(300, 300, cm_per_px_actual, input_cm_per_px, 640);
    assert(d.use_scale_aware);
    assert(int(std::round(300 * d.scale)) == 640);
  }

  // ==== decide_normalize_first_composition() (F60/F61) ==================================

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

  // ---- F61: the README's 960x540 fit invariant fails on a real field capture --
  // 4032x3024 at cm_per_px_actual ~= 0.0644 normalizes to ~764x573, landscape (573 > 540:
  // rotation does not help, matching scaling-rotation-readme-analysis.md's finding). Must
  // enlarge to a 16:9, multiple-of-32 canvas that contains it -- never halt, never shrink
  // the content. ----
  {
    auto c = decide_normalize_first_composition(4032, 3024, 0.0644, 0.34);
    assert(c.valid);
    assert(!c.rotated_clockwise);  // 764x573 stays landscape; rotating doesn't help
    assert(c.content_h > c.canvas_h_requested);  // the invariant genuinely fails here
    assert(c.canvas_w > c.canvas_w_requested || c.canvas_h > c.canvas_h_requested);
    assert(c.canvas_w % 32 == 0 && c.canvas_h % 32 == 0);
    assert(c.canvas_w >= c.content_w && c.canvas_h >= c.content_h);
    // 16:9 within the rounding the multiple-of-32 constraint allows.
    assert(std::fabs(double(c.canvas_w) / double(c.canvas_h) - 16.0 / 9.0) < 0.05);
    assert(c.x_offset >= 0 && c.y_offset >= 0);
    assert(c.x_offset + c.content_w <= c.canvas_w);
    assert(c.y_offset + c.content_h <= c.canvas_h);
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
