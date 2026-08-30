#include "classifier.h"

#include <algorithm>
#include <cmath>

#include "health_input.h"
#include "include/instaham_ml.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"
#include "util/image_io.h"

namespace instaham_ml {
namespace {

using json = nlohmann::json;

json error_envelope(const std::string& message) {
  return json{{"status", "error"}, {"message", message}};
}

// resize_shorter_then_crop moved to health_input.cpp so the view path and the health
// path share one copy of the preprocessing every recorded metric was produced under.
// The arithmetic moved verbatim; this call site is unchanged in behaviour.

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
                     const std::string& image_path, std::string* out_json, int* error_code_out,
                     const HealthInputOptions* health_input) {
  RgbImage img;
  std::string err;
  if (!decode_image_rgb(image_path, &img, &err)) {
    *out_json = error_envelope("image decode failed: " + err).dump();
    *error_code_out = INSTAHAM_ML_ERR_IO;
    return false;
  }

  // The view classifier has no protocol switch (section 1.1(a): it runs on the raw photo,
  // before segmentation), so it passes health_input == nullptr and takes full_frame.
  HealthInput prepared;
  if (health_input != nullptr) {
    prepared = prepare_health_input(img, health_input->protocol, health_input->region,
                                    cap.resize_shorter_side, cap.input_size);
  } else {
    prepared.image = resize_shorter_then_crop(img, cap.resize_shorter_side, cap.input_size);
    prepared.protocol_requested = health_input_protocol_name(HealthInputProtocol::kFullFrame);
    prepared.protocol_applied = prepared.protocol_requested;
  }

  const RgbImage& prepped = prepared.image;
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
  // Additive envelope fields (ABI unchanged -- payloads are JSON). Only emitted for the
  // health path, and only ever reporting what actually ran: while health_input.cpp's
  // region protocols are stubs, `input_protocol_applied` reads "full_frame" and
  // `input_degraded` is true whenever the manifest asked for something else. A scan can
  // therefore never claim a crop that did not happen (AGENTS.md: no invented state).
  if (health_input != nullptr) {
    result["input_protocol_requested"] = prepared.protocol_requested;
    result["input_protocol_applied"] = prepared.protocol_applied;
    result["input_degraded"] = prepared.degraded;
    result["region_source"] = prepared.region_source;
  }
  *out_json = result.dump();
  return true;
}

}  // namespace instaham_ml
