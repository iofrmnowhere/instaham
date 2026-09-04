#ifndef INSTAHAM_ML_STAGES_MASK_GEOMETRY_H
#define INSTAHAM_ML_STAGES_MASK_GEOMETRY_H

#include <algorithm>
#include <cmath>
#include <vector>

#include "stages/segmentation.h"

namespace instaham_ml {
namespace stages {

// ref_fix.md F12: the detection box (model-space, imgsz x imgsz, from SegmentationBox)
// downsampled into prototype-plane coordinates (proto_w x proto_h). This is the crop
// construct_pig_mask() applies before upsampling the decoded mask -- and it is now also
// what segmentation.cpp's mask-area candidate selection uses, so the two can never
// silently diverge again the way they did: selection was scoring each candidate's
// UNCROPPED response over the whole 160x160 proto plane (which responds well outside a
// small/wrong detection's own box), while construction cropped to that same small box --
// so a small, wrong detection could outscore the real pig and then get built from its own
// tiny box, producing a mask a fraction of the animal's true size. Header-only and
// OpenCV-free so segmentation.cpp (which links no OpenCV) can share it with
// construction.cpp without picking up a new dependency.
//
// Left/top inclusive, right/bottom exclusive -- callers test `x < x0 || x >= x1`.
struct ProtoBoxBounds {
  float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
};

inline ProtoBoxBounds proto_box_bounds(const SegmentationBox& box, int proto_w, int proto_h,
                                        int model_imgsz) {
  const float scale_x = float(proto_w) / float(model_imgsz);
  const float scale_y = float(proto_h) / float(model_imgsz);
  return ProtoBoxBounds{
      (box.cx - box.w / 2.f) * scale_x,
      (box.cy - box.h / 2.f) * scale_y,
      (box.cx + box.w / 2.f) * scale_x,
      (box.cy + box.h / 2.f) * scale_y,
  };
}

// ref_fix.md F12: the sigmoid-thresholded area of one candidate's decoded mask (one
// coefficient vector x `proto`), restricted to `bounds` -- the SAME crop
// construct_pig_mask() applies before its own upsample/threshold. This is the actual fix:
// segmentation.cpp's candidate selection used to score the coefficients' response over the
// WHOLE proto plane (no crop), while construction then built the kept candidate's mask
// from its own small box -- so a small, wrong detection whose coefficients happened to
// respond strongly outside its own box could win selection on that spurious area, and then
// get cropped down to its own tiny box anyway, producing a mask a fraction of the true
// animal's size (ref_fix.md section 1/2, the 92kg and 118kg samples in ref_log.md).
//
// Pure array math -- no OpenCV, no ONNX Runtime session -- so this is unit-testable
// (test_mask_selection.cpp) without either dependency, unlike the rest of stages/.
inline long long cropped_mask_area(const std::vector<float>& coeffs, const std::vector<float>& proto,
                                    int proto_h, int proto_w, const ProtoBoxBounds& bounds) {
  const int num_coeffs = int(coeffs.size());
  const int y_start = std::max(0, int(std::floor(bounds.y0)));
  const int y_end = std::min(proto_h, int(std::ceil(bounds.y1)));
  const int x_start = std::max(0, int(std::floor(bounds.x0)));
  const int x_end = std::min(proto_w, int(std::ceil(bounds.x1)));
  const int hw = proto_h * proto_w;
  long long area = 0;
  for (int y = y_start; y < y_end; ++y) {
    if (float(y) < bounds.y0 || float(y) >= bounds.y1) continue;
    for (int x = x_start; x < x_end; ++x) {
      if (float(x) < bounds.x0 || float(x) >= bounds.x1) continue;
      const int p = y * proto_w + x;
      float acc = 0.f;
      for (int k = 0; k < num_coeffs; ++k) acc += coeffs[k] * proto[size_t(k) * hw + p];
      if (1.0f / (1.0f + std::exp(-acc)) > 0.5f) ++area;
    }
  }
  return area;
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_MASK_GEOMETRY_H
