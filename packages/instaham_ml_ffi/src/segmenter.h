#ifndef INSTAHAM_ML_SEGMENTER_H
#define INSTAHAM_ML_SEGMENTER_H

#include <string>

#include "manifest.h"
#include "onnx_runner.h"

namespace instaham_ml {

// Runs the YOLO11s-seg (LDConv/ACmix) detector far enough to answer "is there a pig, how
// confident, how many": decode -> letterbox(640) -> ORT session -> per-anchor confidence
// decode -> greedy NMS. Does NOT decode the 32 mask coefficients against the 160x160
// prototype into a pixel mask -- that (plus the unletterbox coordinate mapping) is the
// geometry-port work deferred to the section-3.5 decision point; `mask_available` here
// only means "a detection survived, so a mask exists in principle."
bool run_segmenter(OnnxRunner* runner, const SegmentationCapability& cap,
                    const std::string& image_path, std::string* out_json, int* error_code_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_SEGMENTER_H
