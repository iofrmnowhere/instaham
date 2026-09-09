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
// V176 SELECTOR + V144 CIRCLE CUT -- ported from the vendor package, not the identity
// stub ADR-001 shipped
// ---------------------------------------------------------------------------------
// ADR-001 declined to port ML/pipeline/cutter.py directly: ~9,900 lines coupled to SciPy
// and scikit-image, with no fixture to prove equivalence. That reasoning does not extend to
// this cutter -- the Chen16 model was trained on masks cut by a DIFFERENT protocol
// (`v176_..._v144_..._v1`, not `ML/pipeline/cutter.py`'s
// `ji_duan_residual_06q_v9_headfit_exact_twotangent_v26`), and the vendor package
// (`vendor/instaham_v176/`) is an existing, small (31 translation units) C++
// implementation of exactly that protocol, with every SciPy/skimage call already replaced
// by OpenCV or hand-rolled equivalents. See docs/plan-phase/2-native-cutter-chen16.md.
// Phase 5 writes the ADR that formally supersedes ADR-001.
//
// This stage wraps the mask in a cv::Mat and runs, in order:
//   Ji/Duan cleanup -> outline build -> shrinking-ball medial candidates -> Selle filter
//   -> terminal trunk geometry -> break1 fit -> V176 shoulder selection -> V144 circle cut.
// `head_removal_applied` is true only when the circle cut actually ran (status
// "cut_applied"); every other status leaves the mask uncut and the field false, because a
// weight computed from an uncut mask includes the head and neck and is not a valid
// estimate under the research protocol (AGENTS.md rule 8: never emit a number after a
// check that did not pass).
struct MaskView {
  const uint8_t* data = nullptr;  // width * height, 0/1, row-major, not owned
  int width = 0;
  int height = 0;

  bool valid() const { return data != nullptr && width > 0 && height > 0; }
};

struct CutterResult {
  std::vector<uint8_t> mask;          // width * height, 0/1 -- the (possibly cut) mask
  int width = 0;
  int height = 0;
  bool head_removal_applied = false;  // true only when status == "cut_applied"

  // "cut_applied"       -- the V144 circle cut ran; `mask` is the final cut body mask.
  // "cut_not_required"  -- the V176 selector decided no cut was needed; `mask` is the
  //                        Ji/Duan-cleaned mask, unmodified further.
  // "invalid_input"     -- the incoming mask was empty or null.
  // "jiduan_failed"      -- Ji/Duan cleanup could not retain a plausible silhouette
  //                        (JiDuanResult::fallback) -- no reliable body shape to cut.
  // "no_terminal_balls"  -- outline build, shrinking-ball, Selle filtering, or terminal
  //                        trunk assembly failed to produce a usable medial-axis trunk.
  // "break1_unfit"       -- the break1 (shoulder-region) piecewise fit did not converge.
  // "shoulder_undecided" -- the V176 selector could not decide a cut point on a valid
  //                        trunk/break1 fit.
  // "circle_cut_failed"  -- the V144 circle cut geometry failed on an otherwise valid,
  //                        cut-required shoulder decision (e.g. no transverse mask exit).
  std::string status;

  bool ok() const { return status == "cut_applied" || status == "cut_not_required"; }
};

// Runs the ported V176/V144 cutter over `in`. Never fails on a valid mask -- every decline
// path returns the best mask available (uncut) with a status naming which stage declined,
// so phase 4 can tell the user why and phase 5 can attribute parity failures to a stage.
CutterResult cut_body_mask(const MaskView& in);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_CUTTER_H
