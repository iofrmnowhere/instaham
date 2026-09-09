#include "weight_prediction.h"

namespace instaham_ml {
namespace stages {

WeightPredictionResult predict_weight(OnnxRunner* runner, const std::vector<float>& features) {
  WeightPredictionResult result;
  if (!runner) {
    result.error = "weight regressor not loaded";
    return result;
  }
  if (features.empty()) {
    result.error = "weight regressor received an empty feature vector";
    return result;
  }

  // Shape [1, N] -- N is whatever width the caller's manifest.weight.feature_order declares
  // (5 for baseline5, 16 for chen16_noheight). A width the loaded ONNX graph does not
  // actually accept fails inside runner->run() rather than being silently truncated or
  // padded (AGENTS.md rule 8): the graph and the caller disagreeing about feature count is
  // a contract error, not something to paper over.
  std::vector<OutputTensor> outputs;
  std::string error;
  if (!runner->run(features, {1, static_cast<int64_t>(features.size())}, &outputs, &error)) {
    result.error = error;
    return result;
  }
  if (outputs.empty() || outputs.front().data.empty()) {
    result.error = "weight regressor produced no output";
    return result;
  }

  result.ok = true;
  result.weight_kg = static_cast<double>(outputs.front().data.front());
  return result;
}

WeightPredictionResult predict_weight(OnnxRunner* runner, const FiveFeatures& features) {
  // AGENTS.md rule 2 / BASELINE5's fixed order -- unchanged from before this stage was
  // generalized to an arbitrary-width vector.
  return predict_weight(runner, std::vector<float>{
                                     static_cast<float>(features.ra),
                                     static_cast<float>(features.lc),
                                     static_cast<float>(features.bl),
                                     static_cast<float>(features.bw),
                                     static_cast<float>(features.e),
                                 });
}

}  // namespace stages
}  // namespace instaham_ml
