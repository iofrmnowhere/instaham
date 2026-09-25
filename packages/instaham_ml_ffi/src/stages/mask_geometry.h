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

// docs/fix-phase-4/1-normalize-before-segment.md (F60): rotates a single-channel, row-major
// uint8 raster (a PigMask's pixels, or any same-shaped array) 90 degrees. Used to undo the
// normalize_first canvas path's pre-model rotation once the model's mask has been cropped
// back into the normalized image's own coordinate space (which is still in the ROTATED
// orientation at that point). Pure array math, OpenCV-free, matching this header's existing
// pattern -- see test_segmentation_canvas.cpp's round-trip test. The output is
// h x w (dimensions swapped), matching decide_normalize_first_composition()'s
// normalized_w/normalized_h <-> content_w/content_h swap.
inline std::vector<uint8_t> rotate90_cw(const std::vector<uint8_t>& src, int w, int h) {
  std::vector<uint8_t> dst(size_t(w) * size_t(h));
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      dst[size_t(x) * h + (h - 1 - y)] = src[size_t(y) * w + x];
    }
  }
  return dst;
}

inline std::vector<uint8_t> rotate90_ccw(const std::vector<uint8_t>& src, int w, int h) {
  std::vector<uint8_t> dst(size_t(w) * size_t(h));
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      dst[size_t(w - 1 - x) * h + y] = src[size_t(y) * w + x];
    }
  }
  return dst;
}

// ref_fix.md F16/F23: the selected mask's bbox diagonal as a fraction of its own frame's
// diagonal -- pipeline.cpp reads this against manifest.weight.min_mask_diagonal_fraction
// (0.35) to reject an implausibly small mask before the cutter/feature stages run.
// `frame_w`/`frame_h` are the mask's OWN frame (construct_pig_mask() sizes the mask to
// `(seg.orig_w, seg.orig_h)`, which after phase 1.1 is the normalize-first `content`
// rectangle -- the resized, optionally-rotated photo BEFORE it is centred on the 960x540
// canvas, per stages/segmentation.cpp). It is deliberately NOT `manifest.weight
// .training_frame_px` (720x720) or the 960x540 canvas -- neither is read here. Extracted
// to its own function (docs/fix-phase-4/3-constants.md phase 3) so the README's canvas
// change could be checked against it directly: test_segmentation_canvas.cpp measures this
// formula at both the pre-README 720x720-diagonal frame and the README's 960x540 one and
// finds the 0.35 threshold's verdict on real corpus-shaped masks unchanged either way, so
// F62's premise -- that adopting the README's canvas silently reweights this gate -- does
// not hold for this function; training_frame_px stays 720x720 unmodified.
inline double mask_diagonal_fraction(int bbox_w, int bbox_h, int frame_w, int frame_h) {
  const double mask_diag = std::sqrt(double(bbox_w) * bbox_w + double(bbox_h) * bbox_h);
  const double frame_diag = std::sqrt(double(frame_w) * frame_w + double(frame_h) * frame_h);
  return frame_diag > 0.0 ? mask_diag / frame_diag : 0.0;
}

}  // namespace stages
}  // namespace instaham_ml

#endif  // INSTAHAM_ML_STAGES_MASK_GEOMETRY_H
