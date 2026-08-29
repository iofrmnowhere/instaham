#include "segmenter.h"

#include <algorithm>
#include <vector>

#include "include/instaham_ml.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"
#include "util/image_io.h"

namespace instaham_ml {
namespace {

using json = nlohmann::json;

json error_envelope(const std::string& message) {
  return json{{"status", "error"}, {"message", message}};
}

struct Detection {
  float cx, cy, w, h, conf;
};

float iou(const Detection& a, const Detection& b) {
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

// Greedy NMS over a single class (nc=1, per section 6.2). `conf_threshold`/`iou_threshold`
// come from the manifest, never hardcoded.
std::vector<Detection> non_max_suppression(std::vector<Detection> dets, float iou_threshold) {
  std::sort(dets.begin(), dets.end(), [](const Detection& a, const Detection& b) {
    return a.conf > b.conf;
  });
  std::vector<Detection> kept;
  std::vector<bool> suppressed(dets.size(), false);
  for (size_t i = 0; i < dets.size(); ++i) {
    if (suppressed[i]) continue;
    kept.push_back(dets[i]);
    for (size_t j = i + 1; j < dets.size(); ++j) {
      if (!suppressed[j] && iou(dets[i], dets[j]) > iou_threshold) suppressed[j] = true;
    }
  }
  return kept;
}

}  // namespace

bool run_segmenter(OnnxRunner* runner, const SegmentationCapability& cap,
                    const std::string& image_path, std::string* out_json, int* error_code_out) {
  RgbImage img;
  std::string err;
  if (!decode_image_rgb(image_path, &img, &err)) {
    *out_json = error_envelope("image decode failed: " + err).dump();
    *error_code_out = INSTAHAM_ML_ERR_IO;
    return false;
  }

  float scale;
  int pad_left, pad_top;
  RgbImage lb = letterbox(img, cap.imgsz, cap.imgsz, cap.letterbox_color, &scale, &pad_left, &pad_top);

  // NCHW float32, scale 1/255, no mean/std normalization (ultralytics' own contract).
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
  if (!runner->run(tensor, shape, &outputs, &err) || outputs.empty()) {
    *out_json = error_envelope("inference failed: " + err).dump();
    *error_code_out = INSTAHAM_ML_ERR_INFERENCE;
    return false;
  }

  // outputs[0]: [1, 4+nc+32, num_anchors] = [1, 37, 8400] for nc=1 (section 6.2).
  const OutputTensor& box_mask = outputs[0];
  if (box_mask.shape.size() != 3 || box_mask.shape[1] < 5) {
    *out_json = error_envelope("unexpected segmentation output shape").dump();
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }
  int64_t channels = box_mask.shape[1];
  int64_t num_anchors = box_mask.shape[2];
  const float* data = box_mask.data.data();

  std::vector<Detection> candidates;
  for (int64_t a = 0; a < num_anchors; ++a) {
    float conf = data[4 * num_anchors + a];
    if (conf < cap.conf_threshold) continue;
    Detection d;
    d.cx = data[0 * num_anchors + a];
    d.cy = data[1 * num_anchors + a];
    d.w = data[2 * num_anchors + a];
    d.h = data[3 * num_anchors + a];
    d.conf = conf;
    candidates.push_back(d);
  }
  (void)channels;

  std::vector<Detection> kept = non_max_suppression(std::move(candidates), cap.iou_threshold);

  json result;
  if (kept.empty()) {
    result = {
        {"status", "ok"},
        {"pig_count", 0},
        {"confidence", 0.0},
        {"mask_available", false},
        {"protocol_version", cap.protocol_version},
    };
  } else {
    result = {
        {"status", "ok"},
        {"pig_count", int(kept.size())},
        {"confidence", kept.front().conf},  // sorted descending by non_max_suppression
        {"mask_available", true},
        {"protocol_version", cap.protocol_version},
    };
  }
  *out_json = result.dump();
  return true;
}

}  // namespace instaham_ml
