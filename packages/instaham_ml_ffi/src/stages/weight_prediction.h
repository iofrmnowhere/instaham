#ifndef INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H
#define INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H

#include <string>
#include <vector>

#include "../onnx_runner.h"
#include "feature_calculation.h"

namespace instaham_ml {
namespace stages {

// (5) WEIGHT PREDICTION -- feature vector to kilograms. Ports
// ML.pipeline.weight_prediction.predict() (ML_implementation_plan.md revision 7, section
// 5, "5 weight prediction"). The regressor is XGBoost exported to ONNX
// (ML/export/export_xgboost.py); this stage is nothing more than "run that ONNX graph",
// same as the view/health classifiers reuse OnnxRunner for their own graphs.
struct WeightPredictionResult {
  bool ok = false;
  double weight_kg = 0.0;
  std::string error;
};

// docs/plan-phase/3-manifest-pipeline.md: generalized to an N-wide vector now that the
// manifest can declare either the 5-feature baseline5 graph or the 16-feature
// chen16_noheight graph. `features` MUST already be in the manifest's `feature_order` --
// the caller (pipeline.cpp) is responsible for that ordering; this stage only refuses a
// width mismatch against the ONNX graph it is about to run rather than truncating or
// padding (AGENTS.md rule 8: never force a prediction after a failed check, and a width
// mismatch here means the caller and the loaded graph disagree about what model this is).
WeightPredictionResult predict_weight(OnnxRunner* runner, const std::vector<float>& features);

// baseline5 convenience overload -- kept for the rollback path (phase 5 open question);
// forwards to the vector overload in AGENTS.md rule 2's fixed RA/LC/BL/BW/E order.
WeightPredictionResult predict_weight(OnnxRunner* runner, const FiveFeatures& features);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_WEIGHT_PREDICTION_H
