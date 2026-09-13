// docs/fix-3.md (round 7), phase 2: stages/construction.cpp's transform_mask_to_training_space()
// -- the single composed 640 -> training-pixel-space transform that replaces the
// construct_pig_mask -> scale_mask_to_training_space chain on the weight path (F55).
//
// Needs OpenCV (construction.cpp includes opencv2/imgproc.hpp), so this is gated behind
// INSTAHAM_ML_WITH_OPENCV in CMakeLists.txt exactly like test_scale_normalization.

#include "stages/construction.h"
#include "stages/segmentation.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <vector>

using instaham_ml::stages::PigMask;
using instaham_ml::stages::SegmentationBox;
using instaham_ml::stages::SegmentationOutput;
using instaham_ml::stages::construct_pig_mask;
using instaham_ml::stages::scale_mask_to_training_space;
using instaham_ml::stages::transform_mask_to_training_space;

namespace {

// A synthetic SegmentationOutput with num_coeffs == 1 whose prototype plane is +8 (sigmoid
// ~1) inside a proto-space rectangle and -8 (sigmoid ~0) outside it. The detection box
// covers the whole frame so decode_binary_640's crop-to-box does not clip the blob -- the
// 640-space blob is then just the proto rectangle scaled by model_imgsz / proto_size.
SegmentationOutput make_seg(int orig_w, int orig_h, float letterbox_scale, int pad_left,
                            int pad_top, int proto_blob_x0, int proto_blob_y0,
                            int proto_blob_x1, int proto_blob_y1) {
  const int proto_size = 160;
  const int model_imgsz = 640;

  SegmentationOutput seg;
  seg.has_detection = true;
  seg.orig_w = orig_w;
  seg.orig_h = orig_h;
  seg.model_imgsz = model_imgsz;
  seg.proto_h = proto_size;
  seg.proto_w = proto_size;
  seg.num_coeffs = 1;
  seg.mask_coeffs = {1.0f};
  seg.letterbox_scale = letterbox_scale;
  seg.letterbox_pad_left = pad_left;
  seg.letterbox_pad_top = pad_top;
  seg.box = SegmentationBox{float(model_imgsz) / 2.f, float(model_imgsz) / 2.f,
                            float(model_imgsz), float(model_imgsz), 0.95f};

  seg.proto.assign(size_t(proto_size) * proto_size, -8.0f);
  for (int y = proto_blob_y0; y < proto_blob_y1; ++y) {
    for (int x = proto_blob_x0; x < proto_blob_x1; ++x) {
      seg.proto[size_t(y) * proto_size + x] = 8.0f;
    }
  }
  return seg;
}

bool approx(double a, double b, double tol) { return std::fabs(a - b) <= tol; }

struct Centroid {
  double x = 0, y = 0;
  long long area = 0;
};

Centroid centroid_of(const PigMask& m) {
  Centroid c;
  for (int y = 0; y < m.height; ++y) {
    for (int x = 0; x < m.width; ++x) {
      if (m.pixels[size_t(y) * m.width + x] > 0) {
        c.x += x;
        c.y += y;
        ++c.area;
      }
    }
  }
  if (c.area > 0) {
    c.x /= double(c.area);
    c.y /= double(c.area);
  }
  return c;
}

double iou(const PigMask& a, const PigMask& b) {
  // Both masks are in the same training coordinate system; compare over the overlapping
  // rectangle (dimensions can differ by a pixel from independent rounding).
  const int w = std::min(a.width, b.width);
  const int h = std::min(a.height, b.height);
  long long inter = 0, uni = 0;
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const bool pa = a.pixels[size_t(y) * a.width + x] > 0;
      const bool pb = b.pixels[size_t(y) * b.width + x] > 0;
      if (pa && pb) ++inter;
      if (pa || pb) ++uni;
    }
  }
  return uni > 0 ? double(inter) / double(uni) : 1.0;
}

}  // namespace

int main() {
  // orig 400x300; letterbox_scale 1.0 is deliberately NOT min(640/400, 640/300) == 1.6, so
  // any regression to recomputing r as min(640/W, 640/H) moves the content and fails the
  // geometry assertions below (docs/fix-3.md F57).
  const int orig_w = 400, orig_h = 300;
  const float lb_scale = 1.0f;
  const int pad_left = 100, pad_top = 150;
  // proto blob [40,80) x [50,90) -> 640-space ~[160,320) x [200,360), centroid ~(240, 280).
  const SegmentationOutput seg =
      make_seg(orig_w, orig_h, lb_scale, pad_left, pad_top, 40, 50, 80, 90);
  const double blob_cx_640 = 240.0, blob_cy_640 = 280.0;

  // ---- guard clauses: never an implicit k = 1.0 (AGENTS.md rule 8) ----
  {
    assert(transform_mask_to_training_space(seg, 0.0).empty());
    assert(transform_mask_to_training_space(seg, -1.0).empty());
    assert(transform_mask_to_training_space(seg, std::nan("")).empty());
    assert(transform_mask_to_training_space(seg, std::numeric_limits<double>::infinity()).empty());
    SegmentationOutput no_det = seg;
    no_det.has_detection = false;
    assert(transform_mask_to_training_space(no_det, 0.5).empty());
  }

  // ---- output dimensions are round(orig * k), and the mask is strictly binary ----
  for (double k : {0.35, 0.5, 1.0, 1.7}) {
    const PigMask m = transform_mask_to_training_space(seg, k);
    assert(!m.empty());
    assert(m.width == int(std::lround(orig_w * k)));
    assert(m.height == int(std::lround(orig_h * k)));
    for (uint8_t v : m.pixels) assert(v == 0 || v == 255);
    assert(m.area_px > 0);
  }

  // ---- geometry: the blob centroid lands at (x_640 - padX) * (k / r), r = letterbox_scale
  // (INSTAHAM_CORRECTED_SEGMENTATION_XGBOOST_PIPELINE.md section 5, docs/fix-3.md F57) ----
  {
    const double k = 0.5;
    const double ratio = k / double(lb_scale);
    const PigMask m = transform_mask_to_training_space(seg, k);
    const Centroid c = centroid_of(m);
    const double expect_x = (blob_cx_640 - pad_left) * ratio;  // (240-100)*0.5 = 70
    const double expect_y = (blob_cy_640 - pad_top) * ratio;   // (280-150)*0.5 = 65
    // 3 px tolerance -- the proto->640 bilinear upsample softens the blob edge by ~1 px
    // before the 0.5 threshold, and INTER_AREA shifts the centroid sub-pixel.
    assert(approx(c.x, expect_x, 3.0));
    assert(approx(c.y, expect_y, 3.0));
    // If r were wrongly recomputed as min(640/400, 640/300) = 1.6, the content rect widens
    // to 540 px and the centroid would land near 51, not 70 -- outside the tolerance.
    assert(!approx(c.x, (blob_cx_640 - pad_left) * (k / 1.6), 3.0));
  }

  // ---- the composed transform tracks the old two-step path closely (it is not identical --
  // that is the point -- but a large disagreement would mean a coordinate error) ----
  {
    const double k = 0.5;
    const PigMask composed = transform_mask_to_training_space(seg, k);
    const PigMask two_step = scale_mask_to_training_space(construct_pig_mask(seg), k);
    assert(!composed.empty() && !two_step.empty());
    assert(std::abs(composed.width - two_step.width) <= 1);
    assert(std::abs(composed.height - two_step.height) <= 1);
    const double overlap = iou(composed, two_step);
    if (overlap < 0.9) {
      std::fprintf(stderr, "composed vs two-step IoU too low: %.4f\n", overlap);
      return 1;
    }
  }

  // ---- a degenerate letterbox (content rect collapses) returns empty, never a crash ----
  {
    SegmentationOutput bad = seg;
    bad.letterbox_pad_left = 640;  // pushes x0 >= x1
    assert(transform_mask_to_training_space(bad, 0.5).empty());
  }

  std::puts("test_mask_transform: OK");
  return 0;
}
