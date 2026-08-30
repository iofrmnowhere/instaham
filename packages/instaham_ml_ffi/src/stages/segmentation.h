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
};

// Runs the segmenter over `image_path`, decodes + letterboxes it, runs the ORT session,
// and selects the highest-confidence detection above `cap.conf_threshold` (single-class
// NMS is a no-op with one surviving box, but ties are broken by confidence regardless).
// Returns false (with has_detection left false) on decode/inference failure or when no
// detection survives -- never a fabricated instance.
bool run_segmentation(OnnxRunner* runner, const SegmentationCapability& cap,
                      const std::string& image_path, SegmentationOutput* out, std::string* error);

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_SEGMENTATION_H
