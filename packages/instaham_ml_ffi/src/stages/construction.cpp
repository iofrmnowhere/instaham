#include "stages/construction.h"

#include <algorithm>
#include <cmath>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include "stages/mask_geometry.h"

namespace instaham_ml {
namespace stages {
namespace {

inline float sigmoidf(float x) { return 1.0f / (1.0f + std::exp(-x)); }

// The 640x640 (model_imgsz) binary mask decoded from one segmentation output: coefficients x
// prototype, sigmoid, crop to the detection box in proto space, bilinear upsample to imgsz,
// threshold at 0.5 -- ultralytics' process_mask order. Cropping BEFORE the upsample matches
// the reference (ML.pipeline.construction, gated at IoU >= 0.95, gate B). Factored out so
// construct_pig_mask() (the gate branch) and transform_mask_to_training_space() (the weight
// branch, docs/fix-3.md F55) decode the mask through the exact same code and can never
// diverge. Returns an empty Mat if `seg` carries no usable prototype.
cv::Mat decode_binary_640(const SegmentationOutput& seg) {
  if (seg.proto_h <= 0 || seg.proto_w <= 0 || seg.num_coeffs <= 0 ||
      int(seg.mask_coeffs.size()) < seg.num_coeffs ||
      seg.proto.size() < size_t(seg.num_coeffs) * seg.proto_h * seg.proto_w) {
    return cv::Mat();
  }

  cv::Mat proto_mask(seg.proto_h, seg.proto_w, CV_32FC1);
  for (int y = 0; y < seg.proto_h; ++y) {
    float* row = proto_mask.ptr<float>(y);
    for (int x = 0; x < seg.proto_w; ++x) {
      float acc = 0.f;
      const int p = y * seg.proto_w + x;
      const int hw = seg.proto_h * seg.proto_w;
      for (int k = 0; k < seg.num_coeffs; ++k) {
        acc += seg.mask_coeffs[k] * seg.proto[size_t(k) * hw + p];
      }
      row[x] = sigmoidf(acc);
    }
  }

  // Downsample the model-space (imgsz x imgsz) box into proto space and zero everything
  // outside it -- crop_mask(), applied before the upsample. ref_fix.md F12: shared with
  // segmentation.cpp's candidate-selection scoring via mask_geometry.h, so the box a
  // candidate is picked for and the box its mask is actually cropped to can never diverge
  // again.
  const ProtoBoxBounds bounds =
      proto_box_bounds(seg.box, seg.proto_w, seg.proto_h, seg.model_imgsz);
  for (int y = 0; y < seg.proto_h; ++y) {
    float* row = proto_mask.ptr<float>(y);
    for (int x = 0; x < seg.proto_w; ++x) {
      if (float(x) < bounds.x0 || float(x) >= bounds.x1 || float(y) < bounds.y0 ||
          float(y) >= bounds.y1) {
        row[x] = 0.f;
      }
    }
  }

  // Upsample (bilinear, matching F.interpolate(mode='bilinear')) to the model's letterboxed
  // input resolution, then threshold at 0.5 -- ultralytics thresholds AFTER the upsample.
  cv::Mat model_space_mask;
  cv::resize(proto_mask, model_space_mask, cv::Size(seg.model_imgsz, seg.model_imgsz), 0, 0,
             cv::INTER_LINEAR);

  cv::Mat binary_640(model_space_mask.size(), CV_8UC1);
  for (int y = 0; y < model_space_mask.rows; ++y) {
    const float* src_row = model_space_mask.ptr<float>(y);
    uint8_t* dst_row = binary_640.ptr<uint8_t>(y);
    for (int x = 0; x < model_space_mask.cols; ++x) dst_row[x] = src_row[x] > 0.5f ? 255 : 0;
  }
  return binary_640;
}

// The rectangle inside the 640x640 canvas that holds real image content (letterbox padding
// removed). ref_fix.md F14: `left`/`top` are the pad letterbox() actually applied, carried
// through on `seg` verbatim (AGENTS.md rule 9) -- not re-derived. `new_w`/`new_h` reproduce
// letterbox()'s own `round(dim * scale)` EXACTLY (same formula, same carried `scale`), so
// `right`/`bottom` -- which letterbox() doesn't return -- derive from them with no
// independent rounding. Left/top inclusive, right/bottom exclusive. `valid` is false for a
// degenerate (empty) rectangle.
struct LetterboxRect {
  int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  bool valid = false;
};

LetterboxRect letterbox_content_rect(const SegmentationOutput& seg) {
  const int native_w = seg.model_imgsz, native_h = seg.model_imgsz;
  const int new_w = std::max(1, int(std::round(seg.orig_w * seg.letterbox_scale)));
  const int new_h = std::max(1, int(std::round(seg.orig_h * seg.letterbox_scale)));
  const int left = seg.letterbox_pad_left;
  const int top = seg.letterbox_pad_top;
  const int right = native_w - new_w - left;
  const int bottom = native_h - new_h - top;

  LetterboxRect r;
  r.x0 = std::max(0, left);
  r.y0 = std::max(0, top);
  r.x1 = std::min(native_w, native_w - std::max(0, right));
  r.y1 = std::min(native_h, native_h - std::max(0, bottom));
  r.valid = r.x1 > r.x0 && r.y1 > r.y0;
  return r;
}

// bbox + nonzero pixel count of a finished PigMask -- section 7's instaham_ml_segment_json
// and pipeline.cpp's "construction" envelope field both read these.
void fill_bbox_area(PigMask& out) {
  int min_x = out.width, min_y = out.height, max_x = -1, max_y = -1;
  long long area = 0;
  for (int y = 0; y < out.height; ++y) {
    const uint8_t* row = out.pixels.data() + size_t(y) * out.width;
    for (int x = 0; x < out.width; ++x) {
      if (row[x] > 0) {
        ++area;
        min_x = std::min(min_x, x);
        min_y = std::min(min_y, y);
        max_x = std::max(max_x, x);
        max_y = std::max(max_y, y);
      }
    }
  }
  out.area_px = area;
  if (max_x >= min_x) {
    out.bbox_x = min_x;
    out.bbox_y = min_y;
    out.bbox_w = max_x - min_x + 1;
    out.bbox_h = max_y - min_y + 1;
  }
}

}  // namespace

PigMask construct_pig_mask(const SegmentationOutput& seg) {
  PigMask out;
  if (!seg.has_detection || seg.orig_w <= 0 || seg.orig_h <= 0) return out;

  const cv::Mat binary_640 = decode_binary_640(seg);
  if (binary_640.empty()) return out;

  // ---- unletterbox: remove the pad, resize (nearest) to the original image dimensions --
  // Mirrors ML.pipeline.construction._unletterbox_native_mask. Unchanged by docs/fix-3.md:
  // this remains the gate branch's mask, in original capture coordinates.
  const LetterboxRect rect = letterbox_content_rect(seg);
  if (!rect.valid) return out;  // empty crop -- report no mask, never a crash

  const cv::Mat cropped =
      binary_640(cv::Rect(rect.x0, rect.y0, rect.x1 - rect.x0, rect.y1 - rect.y0));
  cv::Mat restored;
  cv::resize(cropped, restored, cv::Size(seg.orig_w, seg.orig_h), 0, 0, cv::INTER_NEAREST);

  out.width = seg.orig_w;
  out.height = seg.orig_h;
  out.pixels.assign(restored.data, restored.data + size_t(restored.total()));
  fill_bbox_area(out);
  return out;
}

PigMask transform_mask_to_training_space(const SegmentationOutput& seg, double k) {
  PigMask out;
  if (!seg.has_detection || seg.orig_w <= 0 || seg.orig_h <= 0) return out;
  if (!std::isfinite(k) || k <= 0.0) return out;  // no implicit k = 1.0 (AGENTS.md rule 8)

  const cv::Mat binary_640 = decode_binary_640(seg);
  if (binary_640.empty()) return out;

  const LetterboxRect rect = letterbox_content_rect(seg);
  if (!rect.valid) return out;

  // Compose letterbox removal + undo-YOLO-resize + scale k into ONE crop-and-scale.
  // INSTAHAM_CORRECTED_SEGMENTATION_XGBOOST_PIPELINE.md section 5 gives
  // x_final = (x_640 - padX) * (k / r): the crop below subtracts padX (an integer pixel
  // count -- segmentation.cpp's pad_left/pad_top are int -- so no sub-pixel rounding), and
  // resizing the (orig_w * r)-wide crop to (orig_w * k) applies exactly k / r. `r` is
  // seg.letterbox_scale, used verbatim via letterbox_content_rect() -- NOT recomputed as
  // min(640/W, 640/H), which differs whenever the canvas was composed scale-aware
  // (docs/fix-3.md F57). The crop is a view, not a resample, so the single cv::resize is
  // the only rasterization -- this is the whole point of F55.
  const int final_w = std::max(1, int(std::lround(double(seg.orig_w) * k)));
  const int final_h = std::max(1, int(std::lround(double(seg.orig_h) * k)));

  const cv::Mat cropped =
      binary_640(cv::Rect(rect.x0, rect.y0, rect.x1 - rect.x0, rect.y1 - rect.y0));

  // Section 10: area-weighted when shrinking the crisp 640 mask, bilinear when enlarging,
  // then re-threshold -- both interpolations produce grey values from a 0/255 source and
  // every downstream stage (clean_binary_mask, the cutter) assumes strict 0/255.
  const bool shrinking = final_w < cropped.cols || final_h < cropped.rows;
  cv::Mat resampled;
  cv::resize(cropped, resampled, cv::Size(final_w, final_h), 0, 0,
             shrinking ? cv::INTER_AREA : cv::INTER_LINEAR);

  cv::Mat final_binary;
  cv::threshold(resampled, final_binary, 127.5, 255.0, cv::THRESH_BINARY);

  out.width = final_w;
  out.height = final_h;
  out.pixels.assign(final_binary.data, final_binary.data + size_t(final_binary.total()));
  fill_bbox_area(out);
  return out;
}

PigMask scale_mask_to_training_space(const PigMask& mask, double k) {
  PigMask out;
  if (mask.empty() || !std::isfinite(k) || k <= 0.0) return out;

  const int scaled_w = std::max(1, int(std::lround(mask.width * k)));
  const int scaled_h = std::max(1, int(std::lround(mask.height * k)));

  // docs/fix-phase-2/2.1-reference-length-sensitivity.md "The decided fix" tried replacing
  // this INTER_NEAREST with an area-weighted INTER_AREA resize (plus a mandatory re-threshold
  // back to binary) on the theory that nearest-neighbour's pixel-snapping was the dominant
  // source of reference-marking jitter. ML/host_scale_test/jitter_sweep.py measured it
  // directly, before and after, on the same ten images: the worst-case spread got WORSE
  // (133.42 kg: 11.9% -> 14.4%), and the direction was mixed across the rest (5 up, 4 down,
  // 1 flat). Reverted 2026-09-09; see that doc's "Rejected fix" section for the full
  // before/after table and what it implies about where the real dominant term is.
  cv::Mat src(mask.height, mask.width, CV_8UC1, const_cast<uint8_t*>(mask.pixels.data()));
  cv::Mat resized;
  cv::resize(src, resized, cv::Size(scaled_w, scaled_h), 0, 0, cv::INTER_NEAREST);

  out.width = scaled_w;
  out.height = scaled_h;
  out.pixels.assign(resized.data, resized.data + size_t(resized.total()));

  int min_x = out.width, min_y = out.height, max_x = -1, max_y = -1;
  long long area = 0;
  for (int y = 0; y < out.height; ++y) {
    const uint8_t* row = out.pixels.data() + size_t(y) * out.width;
    for (int x = 0; x < out.width; ++x) {
      if (row[x] > 0) {
        ++area;
        min_x = std::min(min_x, x);
        min_y = std::min(min_y, y);
        max_x = std::max(max_x, x);
        max_y = std::max(max_y, y);
      }
    }
  }
  out.area_px = area;
  if (max_x >= min_x) {
    out.bbox_x = min_x;
    out.bbox_y = min_y;
    out.bbox_w = max_x - min_x + 1;
    out.bbox_h = max_y - min_y + 1;
  }
  return out;
}

std::vector<uint8_t> largest_component_fill(const std::vector<uint8_t>& mask, int w, int h) {
  cv::Mat binary(h, w, CV_8UC1, const_cast<uint8_t*>(mask.data()));
  cv::Mat thresholded;
  cv::threshold(binary, thresholded, 0, 255, cv::THRESH_BINARY);

  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(thresholded, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

  cv::Mat clean = cv::Mat::zeros(h, w, CV_8UC1);
  if (!contours.empty()) {
    auto largest = std::max_element(contours.begin(), contours.end(),
                                     [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                                       return cv::contourArea(a) < cv::contourArea(b);
                                     });
    std::vector<std::vector<cv::Point>> one = {*largest};
    cv::drawContours(clean, one, -1, cv::Scalar(255), cv::FILLED);
  }
  return std::vector<uint8_t>(clean.data, clean.data + size_t(clean.total()));
}

std::vector<uint8_t> clean_binary_mask(const std::vector<uint8_t>& mask, int w, int h) {
  std::vector<uint8_t> clean = largest_component_fill(mask, w, h);
  bool any = std::any_of(clean.begin(), clean.end(), [](uint8_t v) { return v != 0; });
  if (!any) return clean;

  cv::Mat clean_mat(h, w, CV_8UC1, clean.data());
  int short_side = std::max(3, int(std::round(std::min(w, h) * 0.006)));
  if (short_side % 2 == 0) short_side += 1;
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(short_side, short_side));
  cv::Mat closed;
  cv::morphologyEx(clean_mat, closed, cv::MORPH_CLOSE, kernel);

  std::vector<uint8_t> closed_vec(closed.data, closed.data + size_t(closed.total()));
  return largest_component_fill(closed_vec, w, h);
}

}  // namespace stages
}  // namespace instaham_ml
