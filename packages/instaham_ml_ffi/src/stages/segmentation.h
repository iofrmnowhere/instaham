#ifndef INSTAHAM_ML_STAGES_SEGMENTATION_H
#define INSTAHAM_ML_STAGES_SEGMENTATION_H

#include <cstdint>
#include <string>
#include <vector>

#include "manifest.h"
#include "onnx_runner.h"

namespace instaham_ml {
namespace stages {

// (1) SEGMENTATION -- run YOLO11s-seg, select the largest instance.
// Ports ML/pipeline/segmentation.py (ML_implementation_plan.md revision 7, section 4.2).
// Consumed by stages::construction, which is a separate file/stage on purpose (section
// 3.2's five-stage rule): this unit only runs the model and hands over its raw output.

struct SegmentationBox {
  float cx = 0, cy = 0, w = 0, h = 0, conf = 0;
};

// The stage 1 -> stage 2 contract (mirrors ML.pipeline.segmentation.SegmentationOutput).
// `proto` and `mask_coeffs` are in LETTERBOXED (imgsz x imgsz) model space; `construction`
// owns turning them into a mask in ORIGINAL image coordinates. The letterbox parameters
// are carried through verbatim rather than recomputed (AGENTS.md rule 9).
struct SegmentationOutput {
  bool has_detection = false;
  SegmentationBox box;
  std::vector<float> mask_coeffs;  // size == num_coeffs (32)
  std::vector<float> proto;        // size == num_coeffs * proto_h * proto_w
  int proto_h = 0, proto_w = 0;
  int num_coeffs = 0;

  float letterbox_scale = 1.0f;
  int letterbox_pad_left = 0, letterbox_pad_top = 0;
  int model_imgsz = 640;
  int orig_w = 0, orig_h = 0;

  // ref_fix.md F15: diagnostics for the mask-selection stage -- unrelated to what
  // construction/weight consume, but what pipeline.cpp's envelope["segmentation"] now
  // surfaces so a future selection bug (like F12) is visible without a code read.
  int candidates_kept = 0;              // detections surviving NMS
  long long selected_mask_area_proto = 0;
  long long runner_up_mask_area_proto = 0;  // 0 when candidates_kept <= 1
  // The selected box in ORIGINAL image pixel coordinates, and its area as a fraction of
  // the whole frame -- what F16's plausibility gate reads.
  float selected_box_orig_x0 = 0, selected_box_orig_y0 = 0;
  float selected_box_orig_x1 = 0, selected_box_orig_y1 = 0;
  float selected_box_frame_fraction = 0;

  // ref_fix.md F18/F20: how the 640x640 canvas for THIS call was actually composed, so a
  // future scale bug is visible in the envelope without a code read, the way F15 did for
  // mask selection. `content_scale` is the resize factor applied before padding (equals
  // `letterbox_scale` above always -- kept separate so a caller never needs to reason about
  // which field means what). `input_cm_per_px_used` is what this call was given for
  // `cm_per_px_target`.
  // `clamped_to_letterbox` is a round-4 field from the withdrawn canvas_scale path
  // (docs/fix-phase-4/1.1-readme-is-the-path.md); run_segmentation() no longer sets it and
  // it reads permanently false. `pipeline.cpp` still reads it in its own (not yet rewired)
  // envelope -- remove both sides together once phase 4 lands.
  double input_cm_per_px_used = 0.0;
  float content_scale = 1.0f;
  bool clamped_to_letterbox = false;

  // docs/fix-phase-4/1.1-readme-is-the-path.md: this is now the only composition
  // run_segmentation performs. `used_normalize_first` stays for one release as an
  // always-true envelope field, so a stale build (still reporting `false`, or missing the
  // field) is identifiable from an envelope alone without a code read. `orig_w`/`orig_h`
  // above are the ROTATED normalized content's dimensions -- not the captured photo's --
  // because that is the coordinate space construct_pig_mask() /
  // transform_mask_to_training_space() crop back into unchanged (see run_segmentation's doc
  // comment); `was_rotated_clockwise` says a caller must rotate the resulting PigMask 90
  // degrees counter-clockwise (stages::rotate_pig_mask_90_ccw) to undo that before the mask
  // matches the normalized image's own (un-rotated) orientation. `canvas_w`/`canvas_h` equal
  // `canvas_w_requested`/`canvas_h_requested` (960x540) always -- phase 1.1 withdrew F61's
  // enlargement fallback, so there is no longer a case where they differ.
  bool used_normalize_first = false;
  bool was_rotated_clockwise = false;
  int canvas_w = 0, canvas_h = 0;
  int canvas_w_requested = 0, canvas_h_requested = 0;

  // docs/fix-phase-4/5-debug-and-assertions.md: the content rectangle's placement on the
  // canvas -- its top-left corner. Set on every successful (non-oversize) run, not only on
  // a halt, so a future coordinate bug in the offset arithmetic itself is visible in the
  // envelope without a code read, the way candidates_kept/selected_box_* already are for
  // mask selection.
  int x_offset = 0, y_offset = 0;

  // docs/fix-phase-4/1.1-readme-is-the-path.md (F61): true when README section 6's fit
  // invariant failed -- the normalized, rotated content did not fit the 960x540 canvas.
  // `run_segmentation` returns false with this set; the caller must report a declared
  // failure carrying `normalized_w`/`normalized_h` below and the 960x540 bound, and must
  // never enlarge the canvas or shrink the content to force a fit. This is the one failure
  // mode this stage predicts will fire on ordinary full-resolution phone captures -- see
  // the parent fix document's open flags.
  bool oversize = false;
  // docs/fix-phase-4/5-debug-and-assertions.md: set on EVERY run (oversize or not), not
  // only on the halt path -- the pre-rotation size of the resized-to-scale content, before
  // README section 4's fixed rotation swaps width/height. `resize_factor` (below) times
  // this pair recovers the source dimensions; the pair itself is what a caller checks
  // against `check_composition_positive()`/`check_mask_matches_rgb_dimensions()`
  // (stages/invariants.h).
  int normalized_w = 0, normalized_h = 0;
};

// Runs the segmenter over `image_path`, decodes it, composes the 640x640 canvas, runs the
// ORT session, and selects the highest-confidence-area detection above `conf_threshold`
// (single-class NMS is a no-op with one surviving box, but ties are broken by confidence
// regardless). Returns false (with has_detection left false) on decode/inference failure
// or when no detection survives -- never a fabricated instance.
//
// docs/fix-phase-4/1.1-readme-is-the-path.md: `cm_per_px_actual` and `input_cm_per_px`
// (read here as `cm_per_px_target`) must both be > 0 and finite -- this stage requires a
// user-confirmed reference and a declared training scale, per AGENTS.md rule 7. Both
// missing/invalid is a declared failure, never a plain-letterbox fallback (README section
// 15 forbids treating this as optional). See run_segmentation's doc comment below for the
// composition itself.
//
// `conf_threshold_override`: > 0 uses this instead of `cap.conf_threshold`. <= 0 (the
// default) uses `cap.conf_threshold` unchanged. README section 13 is a single pass at one
// scale; any retry ladder over this parameter is the caller's choice, not this stage's.
//
// docs/fix-phase-4/1.1-readme-is-the-path.md: `input_cm_per_px` is read as
// `cm_per_px_target` (the weight regressor's training scale,
// WeightCapability::cm_per_px_target) -- this is the only composition run_segmentation
// performs, per INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md sections 2-8
// and 13. `cm_per_px_actual` keeps its one meaning (the user-confirmed reference object's
// measured cm/pixel). If the normalized, rotated content does not fit the 960x540 canvas,
// this returns false with `out->oversize = true` (README section 6's halt) -- never an
// enlarged canvas or a shrunk image. See SegmentationOutput::used_normalize_first and
// ::oversize for what this path additionally records.
bool run_segmentation(OnnxRunner* runner, const SegmentationCapability& cap,
                      const std::string& image_path, double cm_per_px_actual,
                      double input_cm_per_px, float conf_threshold_override,
                      SegmentationOutput* out, std::string* error);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_SEGMENTATION_H
