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

#include "stages/canvas_scale.h"

#include <cassert>
#include <cmath>
#include <cstdio>

using instaham_ml::stages::decide_canvas_scale;

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

  std::puts("test_segmentation_canvas: all assertions passed");
  return 0;
}
