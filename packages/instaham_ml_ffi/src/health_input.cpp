#include "health_input.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace instaham_ml {
namespace {

// The region's mask arrives in BASE_MASK space (mask_w x mask_h), not `src`'s own
// dimensions -- resample it nearest-neighbour, matching stages::construction's own
// convention for every mask resample it performs (construct_pig_mask,
// scale_mask_to_training_space: cv::INTER_NEAREST throughout, never a soft/antialiased
// mask). Mirrors the reference's PigRegion.interior_mask() resizing `mask` to (h, w) when
// its shape differs from the image's.
std::vector<uint8_t> resample_mask_nearest(const uint8_t* src, int src_w, int src_h, int dst_w,
                                            int dst_h) {
  cv::Mat in(src_h, src_w, CV_8UC1, const_cast<uint8_t*>(src));
  cv::Mat out;
  cv::resize(in, out, cv::Size(dst_w, dst_h), 0, 0, cv::INTER_NEAREST);
  return std::vector<uint8_t>(out.data, out.data + out.total());
}

struct ClampedBox {
  int x0, y0, x1, y1;
};

// PigRegion::_clamped in the reference: clamp to the image, and never collapse to an
// empty box.
ClampedBox clamp_box(int x0, int y0, int x1, int y1, int w, int h) {
  x0 = std::max(0, std::min(x0, w - 1));
  y0 = std::max(0, std::min(y0, h - 1));
  x1 = std::max(x0 + 1, std::min(x1, w));
  y1 = std::max(y0 + 1, std::min(y1, h));
  return ClampedBox{x0, y0, x1, y1};
}

// segmentation_crop/segmentation_masked's shared pre-padding step: pad the already-clamped
// box by `pad_ratio` of its own width/height. The result is handed to crop_to_bbox(),
// which clamps again -- padding can legitimately push back outside the image.
ClampedBox pad_clamped_box(const ClampedBox& clamped, float pad_ratio) {
  const int px = int(std::lround((clamped.x1 - clamped.x0) * double(pad_ratio)));
  const int py = int(std::lround((clamped.y1 - clamped.y0) * double(pad_ratio)));
  return ClampedBox{clamped.x0 - px, clamped.y0 - py, clamped.x1 + px, clamped.y1 + py};
}

// PigRegion.interior_mask(): the region's real mask, resampled to the full (w, h) image,
// when present; otherwise the clamped bbox filled solid. Reference: health_input.py's
// PigRegion.interior_mask(). Always full-image-sized so crop_to_bbox() can crop it exactly
// like the RGB patch it is masking.
std::vector<uint8_t> interior_mask_full(const PigRegion& region, int w, int h) {
  if (region.mask != nullptr && region.mask_w > 0 && region.mask_h > 0) {
    return resample_mask_nearest(region.mask, region.mask_w, region.mask_h, w, h);
  }
  std::vector<uint8_t> out(size_t(w) * h, 0);
  const ClampedBox b = clamp_box(region.x0, region.y0, region.x1, region.y1, w, h);
  for (int y = b.y0; y < b.y1; ++y) {
    std::fill(out.begin() + size_t(y) * w + b.x0, out.begin() + size_t(y) * w + b.x1,
              uint8_t(255));
  }
  return out;
}

bool mask_has_any(const std::vector<uint8_t>& mask) {
  return std::any_of(mask.begin(), mask.end(), [](uint8_t v) { return v > 0; });
}

// round(255 * IMAGENET_MEAN), R/G/B order -- ML/parity/reference_health_input.py's
// _imagenet_mean_rgb_uint8() (ML/export/common.py's IMAGENET_MEAN, the same constant the
// manifest's preprocessing.mean carries for both view and health).
void imagenet_mean_rgb_uint8(uint8_t out_rgb[3]) {
  static constexpr float kImagenetMean[3] = {0.485f, 0.456f, 0.406f};
  for (int c = 0; c < 3; ++c) out_rgb[c] = uint8_t(std::lround(kImagenetMean[c] * 255.0f));
}

// _crop_to_bbox: clamp the box to the image, crop, and -- when `interior_full` is given --
// overwrite every pixel outside it with `fill_rgb`. `interior_full` must already be sized
// to the full (image.width, image.height) frame, matching interior_mask_full()'s output,
// so it can be indexed by the same (x, y) as `image` before the crop.
RgbImage crop_to_bbox(const RgbImage& image, int x0, int y0, int x1, int y1,
                       const std::vector<uint8_t>* interior_full, const uint8_t fill_rgb[3]) {
  const int w = image.width, h = image.height;
  const ClampedBox b = clamp_box(x0, y0, x1, y1, w, h);
  RgbImage patch;
  patch.width = b.x1 - b.x0;
  patch.height = b.y1 - b.y0;
  patch.pixels.resize(size_t(patch.width) * patch.height * 3);
  for (int y = 0; y < patch.height; ++y) {
    const uint8_t* src_row = &image.pixels[(size_t(y + b.y0) * w + b.x0) * 3];
    uint8_t* dst_row = &patch.pixels[size_t(y) * patch.width * 3];
    std::memcpy(dst_row, src_row, size_t(patch.width) * 3);
  }
  if (interior_full != nullptr) {
    for (int y = 0; y < patch.height; ++y) {
      const uint8_t* mask_row = interior_full->data() + size_t(y + b.y0) * w + b.x0;
      uint8_t* dst_row = &patch.pixels[size_t(y) * patch.width * 3];
      for (int x = 0; x < patch.width; ++x) {
        if (mask_row[x] == 0) {
          dst_row[x * 3 + 0] = fill_rgb[0];
          dst_row[x * 3 + 1] = fill_rgb[1];
          dst_row[x * 3 + 2] = fill_rgb[2];
        }
      }
    }
  }
  return patch;
}

}  // namespace

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

// docs/plan-phase-3/2.1-recovery-helper.md: moved verbatim out of pipeline.cpp so
// test_health_input.cpp exercises the same code pipeline.cpp calls, instead of
// re-implementing the arithmetic in the test.
bool pig_region_from_base_mask(int bbox_x, int bbox_y, int bbox_w, int bbox_h,
                                const uint8_t* mask, int mask_w, int mask_h,
                                float content_scale, PigRegion* out) {
  if (mask == nullptr || !(content_scale > 0.0f) || !std::isfinite(content_scale)) return false;
  out->x0 = int(std::lround(bbox_x / double(content_scale)));
  out->y0 = int(std::lround(bbox_y / double(content_scale)));
  out->x1 = int(std::lround((bbox_x + bbox_w) / double(content_scale)));
  out->y1 = int(std::lround((bbox_y + bbox_h) / double(content_scale)));
  out->has_mask = true;
  out->mask = mask;
  out->mask_w = mask_w;
  out->mask_h = mask_h;
  return true;
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

namespace {

// Shared exit for every degradation path: the full-frame crop, reporting what was asked
// for versus what ran. AGENTS.md rule 4 -- a health-input problem never blocks the health
// branch, it only ever falls back to this.
HealthInput full_frame_result(const RgbImage& src, HealthInputProtocol requested,
                               int resize_shorter_side, int crop, std::string region_source) {
  HealthInput out;
  out.protocol_requested = health_input_protocol_name(requested);
  out.region_source = std::move(region_source);
  out.image = resize_shorter_then_crop(src, resize_shorter_side, crop);
  out.protocol_applied = health_input_protocol_name(HealthInputProtocol::kFullFrame);
  out.degraded = (requested != HealthInputProtocol::kFullFrame);
  return out;
}

}  // namespace

HealthInput prepare_health_input(const RgbImage& src, HealthInputProtocol requested,
                                  const PigRegion* region, int resize_shorter_side, int crop,
                                  float bbox_padding_ratio, const std::string& background_fill) {
  // `region` is inspected for reporting purposes even when the requested protocol is
  // full_frame or the stubbed abnormality_crop -- a scan should say what region was
  // available regardless of what actually ran.
  const std::string region_source =
      (region != nullptr && region->valid()) ? (region->has_mask ? "mask" : "bbox") : "none";

  // kAbnormalityCrop remains a stub (health_input.h) -- its proposer measured selecting
  // background and ear rather than lesions, so it always degrades.
  const bool region_protocol_requested = requested == HealthInputProtocol::kSegmentationCrop ||
                                          requested == HealthInputProtocol::kSegmentationMasked;
  if (!region_protocol_requested || region == nullptr || !region->valid()) {
    return full_frame_result(src, requested, resize_shorter_side, crop, region_source);
  }

  const int w = src.width, h = src.height;
  const ClampedBox clamped = clamp_box(region->x0, region->y0, region->x1, region->y1, w, h);
  const ClampedBox padded = pad_clamped_box(clamped, bbox_padding_ratio);

  HealthInput out;
  out.protocol_requested = health_input_protocol_name(requested);
  out.region_source = region_source;

  if (requested == HealthInputProtocol::kSegmentationCrop) {
    // Background retained inside the padded box -- no mask applied.
    const RgbImage patch =
        crop_to_bbox(src, padded.x0, padded.y0, padded.x1, padded.y1, nullptr, nullptr);
    out.image = resize_shorter_then_crop(patch, resize_shorter_side, crop);
    out.protocol_applied = health_input_protocol_name(HealthInputProtocol::kSegmentationCrop);
    out.degraded = false;
    return out;
  }

  // kSegmentationMasked: mean-fill everything outside the interior mask before cropping.
  const std::vector<uint8_t> interior_full = interior_mask_full(*region, w, h);
  if (!mask_has_any(interior_full)) {
    // An all-zero mask (segmentation ran but found nothing usable) degrades exactly like
    // a missing region -- AGENTS.md rule 4.
    return full_frame_result(src, requested, resize_shorter_side, crop, region_source);
  }
  uint8_t fill_rgb[3] = {0, 0, 0};
  if (background_fill == "imagenet_mean") imagenet_mean_rgb_uint8(fill_rgb);
  const RgbImage patch =
      crop_to_bbox(src, padded.x0, padded.y0, padded.x1, padded.y1, &interior_full, fill_rgb);
  out.image = resize_shorter_then_crop(patch, resize_shorter_side, crop);
  out.protocol_applied = health_input_protocol_name(HealthInputProtocol::kSegmentationMasked);
  out.degraded = false;
  return out;
}

HealthSecondStage decide_health_second_stage(bool cascade_enabled, const std::string& first_label,
                                              const std::string& healthy_label,
                                              const PigRegion* region) {
  if (!cascade_enabled) return HealthSecondStage::kDisabled;
  if (first_label == healthy_label) return HealthSecondStage::kNotNeededHealthy;
  // segmentation_masked needs a mask, not just a bbox -- a region with no mask would make
  // the "second pass" identical to the first (crop_to_bbox() with no interior mask), which
  // is not a re-analysis at all.
  if (region == nullptr || !region->valid() || !region->has_mask) {
    return HealthSecondStage::kNoRegion;
  }
  return HealthSecondStage::kRun;
}

}  // namespace instaham_ml
