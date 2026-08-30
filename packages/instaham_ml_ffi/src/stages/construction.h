#ifndef INSTAHAM_ML_STAGES_CONSTRUCTION_H
#define INSTAHAM_ML_STAGES_CONSTRUCTION_H

#include <cstdint>
#include <vector>

#include "stages/segmentation.h"

namespace instaham_ml {
namespace stages {

// (2) CONSTRUCTION -- turn one segmentation output into a pig mask in ORIGINAL IMAGE
// coordinates. Ports ML/pipeline/construction.py (ML_implementation_plan.md revision 7,
// section 4.2 / 10, gate B). Never includes onnx_runner or any model -- pure array math
// (section 3.1).

struct PigMask {
  std::vector<uint8_t> pixels;  // width * height, 0/255, row-major
  int width = 0, height = 0;
  int bbox_x = 0, bbox_y = 0, bbox_w = 0, bbox_h = 0;  // of the nonzero region
  long long area_px = 0;                               // count of nonzero pixels, not bbox area

  bool empty() const { return width == 0 || height == 0; }
};

// construct_pig_mask(): decode 32 coefficients x the 160x160 (mask_ratio 4) prototype into
// a per-pixel mask in the letterboxed 640x640 space, crop to the detection box, then
// unletterbox back to (seg.orig_w, seg.orig_h). No cleanup is applied -- this reproduces
// ML.pipeline.construction.construct_pig_mask()'s raw output exactly (gate A/B compare
// this, not a cleaned mask). Returns an empty PigMask if `seg.has_detection` is false.
PigMask construct_pig_mask(const SegmentationOutput& seg);

// clean_binary_mask() / largest_component_fill(): ports of
// ML.pipeline.construction.clean_binary_mask / _largest_component_fill. Used by
// stages::cutter (internally, on later work) and stages::feature_calculation, exactly as
// the Python stage 4/3 files import them from construction rather than duplicating them
// (section 5.2).
std::vector<uint8_t> largest_component_fill(const std::vector<uint8_t>& mask, int w, int h);
std::vector<uint8_t> clean_binary_mask(const std::vector<uint8_t>& mask, int w, int h);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_CONSTRUCTION_H
