// docs/plan-phase/2-native-cutter-chen16.md, "Two body-curve calls, not one":
// `postureBodyCurve` runs on the whole YOLO mask before Ji/Duan and feeds the posture
// gate; the Chen16 `body_curve` feature is recomputed on the final cut mask. Same
// algorithm (instaham::computeBodyCurve), two separate invocations, and the numeric
// result must never be cached and reused across them. This test asserts they differ on a
// mask where a cut actually happened -- a shared-value regression would otherwise be
// invisible and would quietly corrupt feature 5 of 16.
//
// This does not exercise pipeline.cpp (wiring the posture gate call is phase 3's job --
// see the plan's "quality_gates/ is a parity dependency" section); it exercises the
// underlying vendor function directly on the whole mask vs. the cutter's own output, which
// is exactly the two masks the two real call sites will eventually see.

#include <cassert>
#include <cmath>
#include <cstdint>
#include <vector>

#include <opencv2/core.hpp>

#include "../stages/cutter.h"
#include "instaham/features/BodyCurve.hpp"

using instaham_ml::stages::CutterResult;
using instaham_ml::stages::cut_body_mask;
using instaham_ml::stages::MaskView;

namespace {

// Same bent synthetic dumbbell shape as test_cutter_identity.cpp (kept collinear-free
// deliberately -- see that file's comment: a straight dumbbell gives an identical 180
// degrees for both calls below, which would fail this test's assertion for a shape reason,
// not a caching bug). Duplicated rather than shared across translation units to keep each
// test self-contained (ctest gate D style).
std::vector<uint8_t> make_pig_like_mask(int w, int h) {
  std::vector<uint8_t> mask(static_cast<size_t>(w) * h, 0);

  const double head_cx = 55, head_cy = 45, head_r = 20;
  const double bend_x = 130, bend_y = h / 2.0;
  const double body_cx = w - 90.0, body_cy = h / 2.0, body_r = 55;

  auto fill_circle = [&](double cx, double cy, double r) {
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        double dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy <= r * r) mask[static_cast<size_t>(y) * w + x] = 1;
      }
    }
  };
  auto fill_neck_segment = [&](double x0, double y0, double w0, double x1, double y1,
                                double w1) {
    int xi0 = static_cast<int>(std::round(std::min(x0, x1)));
    int xi1 = static_cast<int>(std::round(std::max(x0, x1)));
    for (int x = std::max(0, xi0); x <= std::min(w - 1, xi1); ++x) {
      double t = (x1 != x0) ? (x - x0) / (x1 - x0) : 0.0;
      double center_y = y0 + t * (y1 - y0);
      double half_w = w0 + t * (w1 - w0);
      int ylo = std::max(0, static_cast<int>(std::floor(center_y - half_w)));
      int yhi = std::min(h - 1, static_cast<int>(std::ceil(center_y + half_w)));
      for (int y = ylo; y <= yhi; ++y) mask[static_cast<size_t>(y) * w + x] = 1;
    }
  };

  fill_circle(head_cx, head_cy, head_r);
  fill_circle(body_cx, body_cy, body_r);
  fill_neck_segment(head_cx, head_cy, head_r * 0.7, bend_x, bend_y, 26.0);
  fill_neck_segment(bend_x, bend_y, 26.0, body_cx, body_cy, body_r * 0.85);
  return mask;
}

}  // namespace

int main() {
  const int w = 340, h = 170;
  std::vector<uint8_t> whole_mask = make_pig_like_mask(w, h);

  MaskView view{whole_mask.data(), w, h};
  CutterResult cut = cut_body_mask(view);
  assert(cut.status == "cut_applied");  // requires the same shape test_cutter_identity uses

  cv::Mat whole_mat(h, w, CV_8UC1, whole_mask.data());
  cv::Mat cut_mat(cut.height, cut.width, CV_8UC1, cut.mask.data());

  double whole_body_curve = instaham::computeBodyCurve(whole_mat);
  double cut_body_curve = instaham::computeBodyCurve(cut_mat);

  assert(std::isfinite(whole_body_curve));
  assert(std::isfinite(cut_body_curve));
  // The head bulb's removal changes the skeleton this is computed over -- on a shape that
  // was actually cut, the two values must not be bit-identical (that would mean one call
  // silently reused the other's cached result).
  assert(whole_body_curve != cut_body_curve);

  return 0;
}
