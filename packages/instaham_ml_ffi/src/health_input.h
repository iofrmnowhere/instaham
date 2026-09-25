#ifndef INSTAHAM_ML_HEALTH_INPUT_H
#define INSTAHAM_ML_HEALTH_INPUT_H

#include <cstdint>
#include <string>

#include "util/image_io.h"

namespace instaham_ml {

// Health-model input protocols (ML_implementation_plan.md section 1.1(c), plus
// abnormality_crop from the TASKS.md P5 addendum). The manifest names one; this unit
// turns a decoded photo (plus an optional pig region) into the square crop the
// GhostNetV3 health checkpoint consumes.
//
// ---------------------------------------------------------------------------------
// STATUS -- READ BEFORE TOUCHING A PROTOCOL
// ---------------------------------------------------------------------------------
// kFullFrame, kSegmentationCrop and kSegmentationMasked are implemented, ported line for
// line from ML/parity/reference_health_input.py
// (docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md). kAbnormalityCrop remains
// a stub and falls through to the full-frame path: measurement on real phone photos
// (TASKS.md P5 execution log) showed its classical proposer selecting background and ear
// rather than lesions, and porting it before that is resolved would ship a wrong answer
// faster. Whichever path actually ran, `HealthInput::protocol_applied` reports it and it
// is surfaced in the classify_health_json envelope alongside the requested protocol, so a
// scan can never claim a crop it did not perform (AGENTS.md: never display invented model
// state).
//
// The manifest still ships `protocol: "full_frame"` (assets/ml/manifest.json) until
// docs/plan-phase-3/3-measurement.md decides whether a region protocol earns the default
// -- shipping the capability and changing behaviour are deliberately two different
// decisions. The healthy-pig case that motivated this work (P(disease) = 0.937 on a
// visibly healthy pig, full frame) is exactly what that measurement checks.
//
// The C ABI is unaffected either way: instaham_ml.h's payloads are JSON, so
// `input_protocol_requested` / `input_protocol_applied` / `region_source` are additive
// and INSTAHAM_ML_ABI_VERSION does not move.
//
// Python reference: ML/parity/reference_health_input.py. That file is what
// docs/plan-phase-3/2-parity-gate-and-tests.md's gate measures this unit against.
enum class HealthInputProtocol {
  kFullFrame = 0,
  kSegmentationCrop,
  kSegmentationMasked,
  kAbnormalityCrop,
};

// Parses the manifest's health.input.protocol string. An unknown value is not an error:
// it degrades to kFullFrame, matching `on_segmentation_failure: "full_frame"` and
// AGENTS.md rule 4 (a health input problem must never block the health branch).
HealthInputProtocol parse_health_input_protocol(const std::string& name);
const char* health_input_protocol_name(HealthInputProtocol p);

// The pig's location in ORIGINAL image coordinates -- i.e. the same pixel space as the
// `src` image handed to prepare_health_input(), NOT stages::construction's BASE_MASK
// space. `pipeline.cpp` is responsible for making that true, via
// pig_region_from_base_mask() below. The mask bitmap itself is left at its own (`mask_w`,
// `mask_h`) resolution -- prepare_health_input() resamples it against `src`'s own
// dimensions, using the ratio between the two, so the box and the bitmap can never
// disagree about the factor applied.
//
// `has_mask == false` means only a bounding box is known (no segmentation this call, or
// segmentation failed) -- pipeline.cpp is the only caller that currently ever sets
// has_mask=true, over the mask stages::construction::construct_pig_mask() produces.
// instaham_ml_classify_health_json's own per-capability path still passes no region
// (nullptr) -- it has no segmentation output to draw one from.
struct PigRegion {
  int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  bool has_mask = false;
  // mask_w * mask_h, 0/255 (matches stages::PigMask's own convention) -- not owned. In
  // BASE_MASK space, NOT the same space as x0..y1 above; see the resampling note.
  const uint8_t* mask = nullptr;
  int mask_w = 0;
  int mask_h = 0;

  bool valid() const { return x1 > x0 && y1 > y0; }
};

// Fills `out` from a pig mask in BASE_MASK space (the normalized, un-rotated capture --
// segmentation.cpp's single resize_uniform(img, content_scale) before the canvas is
// composed), recovering the bbox into ORIGINAL image coordinates -- the space `out` itself
// is documented in ORIGINAL coordinates above -- by dividing by `content_scale`
// (SegmentationOutput::content_scale). That is the only geometric difference between the
// two spaces: no offset, no padding, no rotation is left to undo by this point
// (docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md). The mask bitmap is passed
// through at its own resolution; prepare_health_input() resamples it against `src`'s
// dimensions using the same ratio, so the box and the bitmap can never disagree about the
// factor applied.
//
// Returns false, leaving `out` untouched, when `content_scale` is not finite and positive,
// or `mask` is null -- callers should leave `region` unset (nullptr) in that case, matching
// pipeline.cpp's own guard before this function existed.
bool pig_region_from_base_mask(int bbox_x, int bbox_y, int bbox_w, int bbox_h,
                                const uint8_t* mask, int mask_w, int mask_h,
                                float content_scale, PigRegion* out);

struct HealthInput {
  RgbImage image;                     // the square crop, ready for tensor conversion
  std::string protocol_requested;     // what the manifest asked for
  std::string protocol_applied;       // what actually ran -- "full_frame" while stubbed
  std::string region_source = "none"; // "none" | "bbox" | "mask"
  bool degraded = false;              // true when applied != requested
};

// Resize-shorter-side then center-crop, the preprocessing every recorded classifier
// metric was produced under (ML/export/common.py::classifier_preprocessing).
// Shared with the view classifier, which has no protocol switch and always uses this.
RgbImage resize_shorter_then_crop(const RgbImage& src, int resize_shorter_side, int crop);

// Produces the health model's input. `region` may be null (no segmentation available, or
// the `health_only` route, which never builds one). `bbox_padding_ratio` and
// `background_fill` come from the manifest (ClassifierCapability::health_bbox_padding_ratio
// / health_background_fill) and only matter for the two region protocols.
// kSegmentationCrop/kSegmentationMasked fall back to the full-frame crop -- `degraded` set
// -- whenever `region` is null, invalid, or its mask (when present) is entirely zero;
// kAbnormalityCrop always does (AGENTS.md rule 4: a health-input problem never blocks the
// health branch).
HealthInput prepare_health_input(const RgbImage& src, HealthInputProtocol requested,
                                  const PigRegion* region, int resize_shorter_side, int crop,
                                  float bbox_padding_ratio = 0.06f,
                                  const std::string& background_fill = "imagenet_mean");

// docs/plan-4.md / docs/plan-phase-4/1-native-cascade.md: whether classifier.cpp's
// run_health_cascade() should run a second pass after the first classification.
enum class HealthSecondStage {
  kNotNeededHealthy,  // first_label == healthy_label -- final result is the first pass
  kRun,               // first_label is not healthy, and a usable region exists -- run it
  kDisabled,          // cascade turned off by the manifest (or a bad manifest cascade block)
  kNoRegion,          // cascade wants to run but there is no usable region to mask with
};

// Pure decision, no ORT and no image -- test_health_input.cpp exercises every branch
// directly. `region` is the same PigRegion pipeline.cpp already builds for the first pass;
// a null region, an invalid box, or has_mask == false all mean "no mask to isolate the pig
// with", so the second (masked) pass would just repeat the first -- kNoRegion, not kRun.
HealthSecondStage decide_health_second_stage(bool cascade_enabled, const std::string& first_label,
                                              const std::string& healthy_label,
                                              const PigRegion* region);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_HEALTH_INPUT_H
