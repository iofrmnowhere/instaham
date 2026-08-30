#ifndef INSTAHAM_ML_STAGES_CUTTER_H
#define INSTAHAM_ML_STAGES_CUTTER_H

#include <cstdint>
#include <string>
#include <vector>

namespace instaham_ml {
namespace stages {

// (3) CUTTER -- the head/neck cut-off stage of the weight branch: raw segmentation mask
// in, body-only mask out (ML/pipeline/cutter.py's isolate_body_only_mask).
//
// ---------------------------------------------------------------------------------
// IDENTITY STUB -- AND, PER ML_implementation_plan.md REVISION 7, PERMANENT
// ---------------------------------------------------------------------------------
// This returns the input mask unchanged. Revision 7 section 3.4 settles the question
// revision 6 deferred: ML/pipeline/cutter.py is NOT ported to C++, and it is NOT shipped
// as on-device Python either (the Chaquopy programme -- section 3.5's options A/B/C -- is
// deleted). This stage is a permanent C++ identity dummy (refactor_plan.md: "whenever it
// gets called it would just return the same image"), because re-implementing ~9,900 lines
// of SciPy/scikit-image-coupled geometry would risk silently changing the research weight
// numbers, and shipping the real Python on device costs 65-85 MB per ABI for a regressor
// already flagged temporary.
//
// Because the cut does not happen, `head_removal_applied` is false and `status` says so.
// Callers MUST propagate both into the result envelope: a weight computed from an uncut
// mask includes the head and neck and is therefore NOT a valid estimate under the research
// protocol. AGENTS.md rule 8 forbids emitting a number after a check that did not pass, so
// pipeline.cpp keeps weight.available == false (and instaham_ml_predict_weight_json keeps
// returning ERR_UNAVAILABLE / "cutter_identity_stub") for as long as this file is what
// runs -- passing the mask through is a structural convenience for stages 4 (feature
// calculation) to exercise on real photos, never a licence to publish a weight from it.
struct MaskView {
  const uint8_t* data = nullptr;  // width * height, 0/1, row-major, not owned
  int width = 0;
  int height = 0;

  bool valid() const { return data != nullptr && width > 0 && height > 0; }
};

struct CutterResult {
  std::vector<uint8_t> mask;          // width * height, 0/1 -- the body-only mask
  int width = 0;
  int height = 0;
  bool head_removal_applied = false;  // false while this identity stub is what runs
  // "identity_stub"  -- passed through unchanged (the only value this stub emits)
  // "invalid_input"  -- the incoming mask was empty or null
  std::string status;

  bool ok() const { return status == "identity_stub"; }
};

// Copies `in` through unchanged. Never fails on a valid mask; an invalid one yields an
// empty result with status "invalid_input" rather than a crash or a fabricated mask.
CutterResult cut_body_mask(const MaskView& in);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_CUTTER_H
