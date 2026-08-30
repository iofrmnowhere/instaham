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
// STUB STATUS -- READ BEFORE ADDING A PROTOCOL
// ---------------------------------------------------------------------------------
// Only kFullFrame is implemented. The three region protocols are accepted, then
// deliberately fall through to the full-frame path, so behaviour is byte-identical to
// the pre-existing inline preprocessing in classifier.cpp no matter what the manifest
// asks for. This is the documented degradation route, not a silent one:
// `HealthInput::protocol_applied` reports what actually ran, and it is surfaced in the
// classify_health_json envelope alongside the requested protocol, so a scan can never
// claim a crop it did not perform (AGENTS.md: never display invented model state).
//
// Why a stub rather than the real thing: measurement on real phone photos
// (TASKS.md P5 execution log) showed the classical abnormality proposer selecting
// background and ear rather than lesions, and showed the shipped health checkpoint
// returning P(disease) = 0.937 on a visibly healthy pig. Porting the proposer before
// that is resolved would ship a wrong answer faster. This file exists so the seam is
// real -- the signature, the manifest plumbing, and the envelope fields are all in
// place -- and the implementation can drop in behind it without touching callers.
//
// The C ABI is unaffected either way: instaham_ml.h's payloads are JSON, so
// `input_protocol_requested` / `input_protocol_applied` / `region_source` are additive
// and INSTAHAM_ML_ABI_VERSION does not move.
//
// Python reference for the real implementation: ML/parity/reference_health_input.py.
// That file is what gate B measures this unit against once it is written.
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

// The pig's location in ORIGINAL image coordinates, as stages::construction would supply
// it. `has_mask == false` means only a bounding box is known (no segmentation this call, or
// segmentation failed) -- pipeline.cpp is the only caller that currently ever sets
// has_mask=true, over the mask stages::construction::construct_pig_mask() produces.
// instaham_ml_classify_health_json's own per-capability path still passes no region
// (nullptr) -- it has no segmentation output to draw one from.
struct PigRegion {
  int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  bool has_mask = false;
  const uint8_t* mask = nullptr;  // optional, mask_w * mask_h, 0/1, not owned
  int mask_w = 0;
  int mask_h = 0;

  bool valid() const { return x1 > x0 && y1 > y0; }
};

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

// Produces the health model's input. `region` may be null (no segmentation available).
// While the region protocols are stubs this always returns the full-frame crop, with
// `degraded` set whenever the manifest asked for something else.
HealthInput prepare_health_input(const RgbImage& src, HealthInputProtocol requested,
                                  const PigRegion* region, int resize_shorter_side, int crop);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_HEALTH_INPUT_H
