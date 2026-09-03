// TASKS.md W5 / section 7.5: scale_mask_to_training_space() and extract_five_features()'s
// explicit RA denominator. Needs OpenCV (construction.cpp / feature_calculation.cpp both
// include opencv2/imgproc.hpp), so this is gated behind INSTAHAM_ML_WITH_OPENCV in
// CMakeLists.txt exactly like the rest of stages/ -- it cannot build or run in an
// environment without the Android NDK + opencv-mobile fetched (scripts/fetch_deps.sh).

#include "stages/construction.h"
#include "stages/feature_calculation.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <vector>

using instaham_ml::stages::FiveFeatures;
using instaham_ml::stages::PigMask;
using instaham_ml::stages::extract_five_features;
using instaham_ml::stages::scale_mask_to_training_space;

namespace {

// A filled disc roughly `radius` px across, centered in a `size x size` mask -- gives
// extract_five_features a real contour (>= 5 points) to fit an ellipse and rect to.
PigMask make_disc_mask(int size, int radius) {
  PigMask mask;
  mask.width = size;
  mask.height = size;
  mask.pixels.assign(size_t(size) * size, 0);
  const int cx = size / 2, cy = size / 2;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const int dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) mask.pixels[size_t(y) * size + x] = 255;
    }
  }
  return mask;
}

bool approx(double a, double b, double tol) { return std::fabs(a - b) <= tol; }

}  // namespace

int main() {
  const PigMask disc = make_disc_mask(200, 60);

  // k = 1.0 is the identity: same dimensions, same pixel count to within nearest-neighbour
  // resampling of an already-integer-sized mask (exact here since scaled_w/h round to 200).
  {
    PigMask identity = scale_mask_to_training_space(disc, 1.0);
    assert(!identity.empty());
    assert(identity.width == disc.width);
    assert(identity.height == disc.height);
    assert(identity.area_px == disc.area_px);
  }

  // k = 2.0 doubles every length feature (LC, BL, BW) to within resampling tolerance, and
  // leaves E (a length ratio) unchanged -- TASKS.md section 3, the RA/E-vs-LC/BL/BW split.
  {
    PigMask base_features_mask = disc;
    auto base = extract_five_features(base_features_mask.pixels, base_features_mask.width,
                                       base_features_mask.height, /*linear_scale=*/1.0,
                                       /*preserve_processed_mask=*/true);
    assert(base.has_value());

    PigMask scaled = scale_mask_to_training_space(disc, 2.0);
    assert(!scaled.empty());
    auto doubled = extract_five_features(scaled.pixels, scaled.width, scaled.height,
                                          /*linear_scale=*/1.0,
                                          /*preserve_processed_mask=*/true);
    assert(doubled.has_value());

    assert(approx(doubled->lc, base->lc * 2.0, base->lc * 0.03));
    assert(approx(doubled->bl, base->bl * 2.0, base->bl * 0.03));
    assert(approx(doubled->bw, base->bw * 2.0, base->bw * 0.03));
    assert(approx(doubled->e, base->e, 0.01));
  }

  // RA with an explicit 720x720 denominator reproduces the training CSV's own relationship
  // (TASKS.md section 3.1: body_mask_area_px / RA == 518400 on every row of
  // fixed_test_predictions_POSTHOC.csv) on a synthetic mask of a different native size.
  {
    auto feats = extract_five_features(disc.pixels, disc.width, disc.height,
                                        /*linear_scale=*/1.0,
                                        /*preserve_processed_mask=*/true,
                                        /*ra_frame_w=*/720, /*ra_frame_h=*/720);
    assert(feats.has_value());
    assert(approx(feats->ra, feats->area_pixels / 518400.0, 1e-9));
  }

  // Non-finite / zero / negative k must never silently fall back to k = 1.0
  // (AGENTS.md rule 8) -- always an empty mask, for the caller to turn into
  // {"status":"unavailable","reason":"scale_..."} rather than a number.
  {
    assert(scale_mask_to_training_space(disc, 0.0).empty());
    assert(scale_mask_to_training_space(disc, -1.0).empty());
    assert(scale_mask_to_training_space(disc, std::nan("")).empty());
    assert(scale_mask_to_training_space(PigMask{}, 1.0).empty());  // empty input mask too
  }

  return 0;
}
