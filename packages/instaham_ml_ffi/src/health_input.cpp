#include "health_input.h"

#include <algorithm>
#include <cmath>

namespace instaham_ml {

HealthInputProtocol parse_health_input_protocol(const std::string& name) {
  if (name == "segmentation_crop") return HealthInputProtocol::kSegmentationCrop;
  if (name == "segmentation_masked") return HealthInputProtocol::kSegmentationMasked;
  if (name == "abnormality_crop") return HealthInputProtocol::kAbnormalityCrop;
  // "full_frame", empty, or anything unrecognised. Degrading rather than erroring is
  // deliberate -- see the header's note on AGENTS.md rule 4.
  return HealthInputProtocol::kFullFrame;
}

const char* health_input_protocol_name(HealthInputProtocol p) {
  switch (p) {
    case HealthInputProtocol::kSegmentationCrop:   return "segmentation_crop";
    case HealthInputProtocol::kSegmentationMasked: return "segmentation_masked";
    case HealthInputProtocol::kAbnormalityCrop:    return "abnormality_crop";
    case HealthInputProtocol::kFullFrame:
    default:                                       return "full_frame";
  }
}

// Moved verbatim out of classifier.cpp so the view and health paths share one copy.
// The arithmetic is unchanged -- this must stay bit-identical to what produced the
// recorded metrics, and to ML/export/common.py's classifier_preprocessing().
RgbImage resize_shorter_then_crop(const RgbImage& src, int resize_shorter_side, int crop) {
  float scale = float(resize_shorter_side) / float(std::min(src.width, src.height));
  int new_w = std::max(1, int(std::round(src.width * scale)));
  int new_h = std::max(1, int(std::round(src.height * scale)));
  RgbImage resized = resize_exact(src, new_w, new_h);

  int left = std::max(0, (new_w - crop) / 2);
  int top = std::max(0, (new_h - crop) / 2);
  RgbImage cropped;
  cropped.width = crop;
  cropped.height = crop;
  cropped.pixels.resize(size_t(crop) * crop * 3);
  for (int y = 0; y < crop; ++y) {
    int sy = std::min(top + y, resized.height - 1);
    for (int x = 0; x < crop; ++x) {
      int sx = std::min(left + x, resized.width - 1);
      const uint8_t* s = &resized.pixels[(size_t(sy) * resized.width + sx) * 3];
      uint8_t* d = &cropped.pixels[(size_t(y) * crop + x) * 3];
      d[0] = s[0];
      d[1] = s[1];
      d[2] = s[2];
    }
  }
  return cropped;
}

HealthInput prepare_health_input(const RgbImage& src, HealthInputProtocol requested,
                                  const PigRegion* region, int resize_shorter_side, int crop) {
  HealthInput out;
  out.protocol_requested = health_input_protocol_name(requested);

  // ---- STUB ----------------------------------------------------------------
  // The three region protocols are not implemented. Rather than half-doing them, they
  // take the full-frame path and say so. `region` is accepted and inspected only to
  // report what would have been available; nothing reads its pixels yet.
  //
  // When the real implementation lands, replace this block with the dispatch and keep
  // the reporting: a protocol that cannot run (no region, empty mask) must still fall
  // back here rather than fail the health branch.
  if (region != nullptr && region->valid()) {
    out.region_source = region->has_mask ? "mask" : "bbox";
  }

  out.image = resize_shorter_then_crop(src, resize_shorter_side, crop);
  out.protocol_applied = health_input_protocol_name(HealthInputProtocol::kFullFrame);
  out.degraded = (requested != HealthInputProtocol::kFullFrame);
  return out;
}

}  // namespace instaham_ml
