// Gate D (ML_implementation_plan.md revision 7, section 10; carried forward by
// docs/plan-phase/2-native-cutter-chen16.md phase 2). The cutter is no longer a permanent
// identity dummy -- it wraps the ported vendor V176/V144 stack -- so this test no longer
// asserts pass-through. It asserts the two contracts phase 2's plan calls out for gate D:
// a mask with a clearly distinct "head" region comes back smaller (the cut actually
// removed pixels), and an invalid mask still yields "invalid_input" without crashing or
// fabricating a mask.
//
// Phase 2's own open questions note the cutter has no reference implementation to diff a
// single cut against (correctness is phase 5's job, against the CSV's per-row cutter
// telemetry) -- this test only proves the port runs end to end and behaves sanely on a
// synthetic shape, not that its geometry matches the vendor's research numbers.

#include "../stages/cutter.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <vector>

using instaham_ml::stages::CutterResult;
using instaham_ml::stages::cut_body_mask;
using instaham_ml::stages::MaskView;

namespace {

// A bent "dumbbell" silhouette: a small head bulb, offset off the body's long axis and
// joined by a kinked neck, connecting to a much larger body bulb -- the same head/neck/body
// shape the V176 selector and V144 circle cutter are designed to find a cut point on. The
// head is deliberately NOT collinear with the body: a straight dumbbell gives
// computeBodyCurve() an exact 180 degrees on both the whole mask and the head-removed mask
// (two straight skeletons look identical), which would make test_body_curve_dual_call.cpp's
// "the two calls must differ" assertion fail for a shape reason, not a caching bug. The kink
// at the neck means removing the head measurably changes the skeleton's extreme endpoints.
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
  // Fills a neck segment between two columns, linearly interpolating both the center row
  // and the half-width -- used twice, once per side of the bend.
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
  std::vector<uint8_t> mask = make_pig_like_mask(w, h);
  size_t area_before = 0;
  for (uint8_t v : mask) area_before += v;

  MaskView view{mask.data(), w, h};
  CutterResult result = cut_body_mask(view);

  // Gate D requires this specific shape to actually get cut -- a synthetic mask with a
  // clearly distinct head bulb must come back smaller, not merely "some known status".
  assert(result.width == w);
  assert(result.height == h);
  assert(result.mask.size() == mask.size());
  assert(result.status == "cut_applied");
  assert(result.head_removal_applied == true);

  size_t area_after = 0;
  for (uint8_t v : result.mask) area_after += v;
  assert(area_after < area_before);  // the head bulb must have been removed

  // Invalid input must never crash or fabricate a mask.
  {
    MaskView invalid{nullptr, 0, 0};
    CutterResult invalid_result = cut_body_mask(invalid);
    assert(!invalid_result.ok());
    assert(invalid_result.status == "invalid_input");
    assert(invalid_result.mask.empty());
    assert(invalid_result.head_removal_applied == false);
  }

  return 0;
}
