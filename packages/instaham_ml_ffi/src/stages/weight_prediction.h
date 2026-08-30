#ifndef INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H
#define INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H

#include <string>

#include "../onnx_runner.h"
#include "feature_calculation.h"

namespace instaham_ml {
namespace stages {

// (5) WEIGHT PREDICTION -- feature vector to kilograms. Ports
// ML.pipeline.weight_prediction.predict() (ML_implementation_plan.md revision 7, section
// 5, "5 weight prediction"). The regressor is XGBoost exported to ONNX
// (ML/export/export_xgboost.py); this stage is nothing more than "run that ONNX graph",
// same as the view/health classifiers reuse OnnxRunner for their own graphs.
//
// AGENTS.md rule 2: features MUST be passed in exactly this order -- RA, LC, BL, BW, E --
// because that is the order ML/export/export_xgboost.py asserts against BASELINE5 before
// exporting the graph (manifest.cpp's load_weight() re-asserts the same order against
// feature_order.json at manifest-load time, not here).
struct WeightPredictionResult {
  bool ok = false;
  double weight_kg = 0.0;
  std::string error;
};

WeightPredictionResult predict_weight(OnnxRunner* runner, const FiveFeatures& features);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H
