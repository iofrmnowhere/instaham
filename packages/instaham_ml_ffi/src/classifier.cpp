#include "classifier.h"

#include <algorithm>
#include <cmath>

#include "include/instaham_ml.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"
#include "util/image_io.h"

namespace instaham_ml {
namespace {

using json = nlohmann::json;

json error_envelope(const std::string& message) {
  return json{{"status", "error"}, {"message", message}};
}

// Resize-shorter-side then center-crop, matching ML/export/common.py's
// classifier_preprocessing() exactly (section 6.1 / the manifest's "preprocessing" block).
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

std::vector<float> to_nchw_tensor(const RgbImage& img, float scale, const float mean[3],
                                   const float std_dev[3]) {
  const int h = img.height, w = img.width;
  std::vector<float> tensor(size_t(3) * h * w);
  for (int c = 0; c < 3; ++c) {
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        uint8_t v = img.pixels[(size_t(y) * w + x) * 3 + c];
        float normalized = (float(v) * scale - mean[c]) / std_dev[c];
        tensor[size_t(c) * h * w + size_t(y) * w + x] = normalized;
      }
    }
  }
  return tensor;
}

}  // namespace

bool run_classifier(OnnxRunner* runner, const ClassifierCapability& cap,
                     const std::string& image_path, std::string* out_json, int* error_code_out) {
  RgbImage img;
  std::string err;
  if (!decode_image_rgb(image_path, &img, &err)) {
    *out_json = error_envelope("image decode failed: " + err).dump();
    *error_code_out = INSTAHAM_ML_ERR_IO;
    return false;
  }

  RgbImage prepped = resize_shorter_then_crop(img, cap.resize_shorter_side, cap.input_size);
  std::vector<float> tensor = to_nchw_tensor(prepped, cap.scale, cap.mean, cap.std_dev);
  std::vector<int64_t> shape = {1, 3, cap.input_size, cap.input_size};

  std::vector<OutputTensor> outputs;
  if (!runner->run(tensor, shape, &outputs, &err) || outputs.empty()) {
    *out_json = error_envelope("inference failed: " + err).dump();
    *error_code_out = INSTAHAM_ML_ERR_INFERENCE;
    return false;
  }

  const std::vector<float>& logits = outputs[0].data;
  if (logits.size() != cap.class_names.size()) {
    *out_json = error_envelope("class count mismatch: model emits " +
                                std::to_string(logits.size()) + ", classes.json has " +
                                std::to_string(cap.class_names.size()))
                    .dump();
    *error_code_out = INSTAHAM_ML_ERR_CONTRACT;
    return false;
  }

  // softmax
  float max_logit = *std::max_element(logits.begin(), logits.end());
  std::vector<float> exps(logits.size());
  float sum = 0.f;
  for (size_t i = 0; i < logits.size(); ++i) {
    exps[i] = std::exp(logits[i] - max_logit);
    sum += exps[i];
  }
  size_t best = 0;
  json probabilities = json::object();
  for (size_t i = 0; i < logits.size(); ++i) {
    float p = exps[i] / sum;
    probabilities[cap.class_names[i]] = p;
    if (p > exps[best] / sum) best = i;
  }

  json result = {
      {"status", "ok"},
      {"label", cap.class_names[best]},
      {"confidence", exps[best] / sum},
      {"probabilities", probabilities},
      {"class_map_sha256", cap.classes_sha256},
      {"protocol_version", cap.protocol_version},
  };
  *out_json = result.dump();
  return true;
}

}  // namespace instaham_ml
