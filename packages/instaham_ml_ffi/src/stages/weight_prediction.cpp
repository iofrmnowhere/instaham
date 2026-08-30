#include "weight_prediction.h"

namespace instaham_ml {
namespace stages {

WeightPredictionResult predict_weight(OnnxRunner* runner, const FiveFeatures& features) {
  WeightPredictionResult result;
  if (!runner) {
    result.error = "weight regressor not loaded";
    return result;
  }

  // Order fixed by AGENTS.md rule 2 / BASELINE5, shape [1,5] matching
  // export_xgboost.py's FloatTensorType([None, 5]).
  std::vector<float> input = {
      static_cast<float>(features.ra), static_cast<float>(features.lc),
      static_cast<float>(features.bl), static_cast<float>(features.bw),
      static_cast<float>(features.e),
  };

  std::vector<OutputTensor> outputs;
  std::string error;
  if (!runner->run(input, {1, 5}, &outputs, &error)) {
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

}  // namespace stages
}  // namespace instaham_ml
