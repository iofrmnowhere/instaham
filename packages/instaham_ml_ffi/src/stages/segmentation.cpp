#include "stages/segmentation.h"

#include <algorithm>
#include <cmath>

#include "util/image_io.h"

namespace instaham_ml {
namespace stages {
namespace {

struct Candidate {
  SegmentationBox box;
  std::vector<float> coeffs;
};

float iou(const SegmentationBox& a, const SegmentationBox& b) {
  float ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2, ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
  float bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2, bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;
  float ix1 = std::max(ax1, bx1), iy1 = std::max(ay1, by1);
  float ix2 = std::min(ax2, bx2), iy2 = std::min(ay2, by2);
  float iw = std::max(0.f, ix2 - ix1), ih = std::max(0.f, iy2 - iy1);
  float inter = iw * ih;
  float area_a = std::max(0.f, ax2 - ax1) * std::max(0.f, ay2 - ay1);
  float area_b = std::max(0.f, bx2 - bx1) * std::max(0.f, by2 - by1);
  float uni = area_a + area_b - inter;
  return uni <= 0.f ? 0.f : inter / uni;
}

std::vector<Candidate> non_max_suppression(std::vector<Candidate> dets, float iou_threshold) {
  std::sort(dets.begin(), dets.end(),
            [](const Candidate& a, const Candidate& b) { return a.box.conf > b.box.conf; });
  std::vector<Candidate> kept;
  std::vector<bool> suppressed(dets.size(), false);
  for (size_t i = 0; i < dets.size(); ++i) {
    if (suppressed[i]) continue;
    kept.push_back(dets[i]);
    for (size_t j = i + 1; j < dets.size(); ++j) {
      if (!suppressed[j] && iou(dets[i].box, dets[j].box) > iou_threshold) suppressed[j] = true;
    }
  }
  return kept;
}

inline float sigmoidf(float x) { return 1.0f / (1.0f + std::exp(-x)); }

// Area (in proto-resolution pixels, threshold 0.5) of one candidate's mask -- the same
// selection criterion as ML.pipeline.segmentation._largest_mask_index (area of the
// thresholded native mask, not confidence). Cheap: proto_h*proto_w*num_coeffs multiply-add,
// 160x160x32 by default.
long long mask_area(const Candidate& c, const std::vector<float>& proto, int proto_h,
                     int proto_w, int num_coeffs) {
  long long area = 0;
  const int hw = proto_h * proto_w;
  for (int p = 0; p < hw; ++p) {
    float acc = 0.f;
    for (int k = 0; k < num_coeffs; ++k) acc += c.coeffs[k] * proto[size_t(k) * hw + p];
    if (sigmoidf(acc) > 0.5f) ++area;
  }
  return area;
}

}  // namespace

bool run_segmentation(OnnxRunner* runner, const SegmentationCapability& cap,
                      const std::string& image_path, SegmentationOutput* out, std::string* error) {
  out->has_detection = false;

  RgbImage img;
  if (!decode_image_rgb(image_path, &img, error)) return false;
  out->orig_w = img.width;
  out->orig_h = img.height;

  float scale;
  int pad_left, pad_top;
  RgbImage lb = letterbox(img, cap.imgsz, cap.imgsz, cap.letterbox_color, &scale, &pad_left, &pad_top);
  out->letterbox_scale = scale;
  out->letterbox_pad_left = pad_left;
  out->letterbox_pad_top = pad_top;
  out->model_imgsz = cap.imgsz;

  std::vector<float> tensor(size_t(3) * cap.imgsz * cap.imgsz);
  for (int c = 0; c < 3; ++c) {
    for (int y = 0; y < cap.imgsz; ++y) {
      for (int x = 0; x < cap.imgsz; ++x) {
        uint8_t v = lb.pixels[(size_t(y) * cap.imgsz + x) * 3 + c];
        tensor[size_t(c) * cap.imgsz * cap.imgsz + size_t(y) * cap.imgsz + x] = float(v) / 255.0f;
      }
    }
  }
  std::vector<int64_t> shape = {1, 3, cap.imgsz, cap.imgsz};

  std::vector<OutputTensor> outputs;
  if (!runner->run(tensor, shape, &outputs, error) || outputs.size() < 2) {
    if (error && error->empty()) *error = "segmentation model did not return a proto tensor";
    return false;
  }

  // outputs[0]: [1, 4+nc+32, num_anchors]; outputs[1]: [1, 32, proto_h, proto_w].
  const OutputTensor& box_mask = outputs[0];
  const OutputTensor& proto_t = outputs[1];
  if (box_mask.shape.size() != 3 || proto_t.shape.size() != 4) {
    if (error) *error = "unexpected segmentation output shape";
    return false;
  }
  int64_t channels = box_mask.shape[1];
  int64_t num_anchors = box_mask.shape[2];
  int num_coeffs = int(proto_t.shape[1]);
  int proto_h = int(proto_t.shape[2]);
  int proto_w = int(proto_t.shape[3]);
  if (channels < 5 + num_coeffs) {
    if (error) *error = "segmentation output channel count disagrees with proto coefficient count";
    return false;
  }
  const float* data = box_mask.data.data();

  std::vector<Candidate> candidates;
  for (int64_t a = 0; a < num_anchors; ++a) {
    float conf = data[4 * num_anchors + a];
    if (conf < cap.conf_threshold) continue;
    Candidate c;
    c.box.cx = data[0 * num_anchors + a];
    c.box.cy = data[1 * num_anchors + a];
    c.box.w = data[2 * num_anchors + a];
    c.box.h = data[3 * num_anchors + a];
    c.box.conf = conf;
    c.coeffs.resize(num_coeffs);
    for (int k = 0; k < num_coeffs; ++k) {
      c.coeffs[k] = data[size_t(5 + k) * num_anchors + a];
    }
    candidates.push_back(std::move(c));
  }

  std::vector<Candidate> kept = non_max_suppression(std::move(candidates), cap.iou_threshold);
  if (kept.empty()) return true;  // has_detection stays false -- not an error, no instance

  // Select by mask area, not confidence -- matches
  // ML.pipeline.segmentation._largest_mask_index's selection criterion.
  size_t best = 0;
  long long best_area = -1;
  for (size_t i = 0; i < kept.size(); ++i) {
    long long a = mask_area(kept[i], proto_t.data, proto_h, proto_w, num_coeffs);
    if (a > best_area) {
      best_area = a;
      best = i;
    }
  }

  out->has_detection = true;
  out->box = kept[best].box;
  out->mask_coeffs = std::move(kept[best].coeffs);
  out->proto = proto_t.data;
  out->proto_h = proto_h;
  out->proto_w = proto_w;
  out->num_coeffs = num_coeffs;
  return true;
}

}  // namespace stages
}  // namespace instaham_ml
