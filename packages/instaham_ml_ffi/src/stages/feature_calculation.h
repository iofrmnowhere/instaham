#ifndef INSTAHAM_ML_STAGES_FEATURE_CALCULATION_H
#define INSTAHAM_ML_STAGES_FEATURE_CALCULATION_H

#include <cstdint>
#include <optional>
#include <vector>

namespace instaham_ml {
namespace stages {

// (4) FEATURE CALCULATION -- mask to feature vector. Ports
// ML.pipeline.feature_calculation.extract_five_features (ML_implementation_plan.md
// revision 7, section 4.2 / 5.5 / 10, gate B). baseline5 ONLY -- chen16 stays
// reference-only in Python until a chen16 model is actually selected (section 5.5),
// because it needs skimage.morphology.skeletonize, which this build does not carry.

struct FiveFeatures {
  double ra = 0, lc = 0, bl = 0, bw = 0, e = 0;
  double area_pixels = 0;
};

// `preserve_processed_mask` mirrors the Python parameter of the same name: true skips the
// small closing operation clean_binary_mask() applies, using largest_component_fill()
// alone -- the call ML/weight_runtime.py's predict() makes after the cutter has already
// cleaned the mask once. Returns std::nullopt exactly where the Python returns None: fewer
// than 5 contour points.
//
// `ra_frame_w` / `ra_frame_h` (TASKS.md W5, section 3): the frame RA's denominator is
// measured against. RA = area_pixels / (frame_w * frame_h) is a ratio, invariant to a
// uniform resize of mask AND frame together -- so it does NOT correct for camera height on
// its own, unlike LC/BL/BW which `linear_scale` does correct. Left at 0 (the default), the
// denominator is the mask's own (w, h), exactly the pre-existing behaviour every parity
// caller (ML/parity/run_reference.py, ML/weight_runtime.py) still relies on. Callers that
// have already resampled the mask into the regressor's training pixel space (via
// construction::scale_mask_to_training_space) pass the manifest's training_frame_w/h here
// instead, matching how the training CSV's own RA was computed.
std::optional<FiveFeatures> extract_five_features(const std::vector<uint8_t>& mask, int w, int h,
                                                   double linear_scale = 1.0,
                                                   bool preserve_processed_mask = false,
                                                   int ra_frame_w = 0, int ra_frame_h = 0);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_FEATURE_CALCULATION_H
