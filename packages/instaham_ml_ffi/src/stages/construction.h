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

// TASKS.md W5 (section 3.3, Option B): resamples `mask` by `k = cm_per_px_actual /
// cm_per_px_target` into the pixel space the weight regressor's features were trained in,
// so the cutter and feature_calculation stages run on training-normalized pixels rather
// than whatever the live camera's distance-to-subject happened to produce. Nearest-
// neighbour, matching construct_pig_mask's own unletterbox resize -- this stays a binary
// mask throughout, never a soft/antialiased one. Returns an empty PigMask (never an
// unscaled copy of `mask`) when `k` is not finite and strictly positive -- there is no
// implicit k = 1.0 fallback (AGENTS.md rule 8).
//
// docs/fix-3.md (round 7): this two-step chain (construct_pig_mask ->
// scale_mask_to_training_space) rasterizes the mask twice and is what F55 replaces on the
// weight path. It is retained for the no-reference fallback (pipeline.cpp bounds an unscaled
// mask by kUnscaledCutterMaxDimPx through this), which has no calibrated target space to
// compose a transform into -- see docs/fix-phase-3/3-pipeline-rewire.md F58.
PigMask scale_mask_to_training_space(const PigMask& mask, double k);

// docs/fix-3.md (round 7), phase 2. Maps the 640x640 binary segmentation mask DIRECTLY into
// the weight regressor's training pixel space in ONE resampling operation, replacing the
// construct_pig_mask -> scale_mask_to_training_space chain that rasterized it twice (F55: the
// first, nearest-neighbour resize to full capture resolution turned the 640-px contour into
// staircase blocks; the second could only average that staircase, and both grid-snapped in a
// way that depended on `k` and therefore on one pixel of reference marking).
//
// Composes letterbox-padding removal + undo-YOLO-resize + the reference/camera scale
// `k = cm_per_px_actual / cm_per_px_target` into a single crop-and-scale. The crop is exact
// -- letterbox pads are integer pixel counts and the crop width equals letterbox()'s own
// new_w -- so the only resampling is one cv::resize (INTER_AREA shrinking, INTER_LINEAR
// enlarging, then re-thresholded to strict 0/255). This is
// INSTAHAM_CORRECTED_SEGMENTATION_XGBOOST_PIPELINE.md sections 4-5 and 10;
// `x_final = (x_640 - padX) * (k / r)` with `r = seg.letterbox_scale` read verbatim, NOT
// recomputed as min(640/W, 640/H) (docs/fix-3.md F57 -- the two differ whenever the canvas
// was composed scale-aware).
//
// Returns an empty PigMask -- never an unscaled copy -- when `k` is not finite and strictly
// positive (AGENTS.md rule 8), when `seg.has_detection` is false, or when the composed output
// dimensions would be non-positive. construct_pig_mask() is unchanged and stays the input to
// the posture/truncation gates, which must remain in original capture coordinates
// (docs/fix-phase-3/3-pipeline-rewire.md).
PigMask transform_mask_to_training_space(const SegmentationOutput& seg, double k);

// docs/fix-phase-4/1-normalize-before-segment.md (F60): undoes the normalize_first canvas
// path's pre-model 90-degree clockwise rotation (SegmentationOutput::was_rotated_clockwise),
// once `mask` has already been cropped back into the normalized image's own coordinate
// space by construct_pig_mask()/transform_mask_to_training_space() -- at that point it is a
// mask of the ROTATED content, and this restores it to the un-rotated normalized image's
// orientation (width/height swapped back). A no-op copy of `mask` when
// `was_rotated_clockwise` is false. Uses mask_geometry.h's rotate90_ccw(), the tested
// inverse of the rotate90_cw() applied to the RGB image before the model ran.
PigMask rotate_pig_mask_90_ccw(const PigMask& mask, bool was_rotated_clockwise);

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
