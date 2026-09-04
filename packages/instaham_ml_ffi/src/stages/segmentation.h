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
  // mask selection. `content_scale` is the resize factor applied to the source image
  // before padding (equals `letterbox_scale` above always -- kept separate so a caller
  // never needs to reason about which field means what under which mode).
  // `input_cm_per_px_used` is the manifest input_cm_per_px x ladder multiplier this
  // attempt requested; 0.0 when scale-aware composition was not requested at all (no
  // reference marked, or manifest.segmentation.input_cm_per_px == 0.0 -- an older
  // manifest). `clamped_to_letterbox` is true when a requested scale-aware composition
  // would have overflowed the canvas and this call fell back to the plain whole-frame fit
  // instead (never silently -- see run_segmentation's doc comment).
  double input_cm_per_px_used = 0.0;
  float content_scale = 1.0f;
  bool clamped_to_letterbox = false;
};

// Runs the segmenter over `image_path`, decodes it, composes the 640x640 canvas, runs the
// ORT session, and selects the highest-confidence-area detection above `conf_threshold`
// (single-class NMS is a no-op with one surviving box, but ties are broken by confidence
// regardless). Returns false (with has_detection left false) on decode/inference failure
// or when no detection survives -- never a fabricated instance.
//
// ref_fix.md F18: when `cm_per_px_actual` and `input_cm_per_px` are both > 0 and finite,
// the canvas is composed at `content_scale = cm_per_px_actual / input_cm_per_px` via
// place_at_scale() instead of the whole-frame-fit letterbox() -- so the pig's apparent
// size in the model's input reflects its real-world size rather than the capture's pixel
// resolution (section 1.3/1.4: a plain letterbox makes a typical phone photo's pig too
// small in the model's input for it to detect reliably). If that scale would overflow the
// 640x640 canvas, this call falls back to the plain letterbox and sets
// `out->clamped_to_letterbox = true` rather than clipping content. Pass 0.0 for either
// argument (no reference marked, or an older manifest with input_cm_per_px == 0.0) to
// always use the plain letterbox, exactly as before F18.
//
// `conf_threshold_override`: > 0 uses this instead of `cap.conf_threshold` -- ref_fix.md
// F19's retry pass at a lower confidence after every scale-ladder rung has failed at the
// manifest's normal threshold. <= 0 (the default) uses `cap.conf_threshold` unchanged.
bool run_segmentation(OnnxRunner* runner, const SegmentationCapability& cap,
                      const std::string& image_path, double cm_per_px_actual,
                      double input_cm_per_px, float conf_threshold_override,
                      SegmentationOutput* out, std::string* error);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_SEGMENTATION_H
