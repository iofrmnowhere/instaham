// ref_fix.md F12: the load-bearing test for the fix. `proto_box_bounds()` +
// `cropped_mask_area()` (stages/mask_geometry.h) are pure array math -- no OpenCV, no ONNX
// Runtime session -- so this builds and runs unconditionally, unlike test_scale_normalization
// (OpenCV-gated) or a full segmentation.cpp/construction.cpp integration test (which would
// need a real .onnx model and a real photo).
//
// The bug this guards against: segmentation.cpp's old candidate-selection scoring summed
// sigmoid(coeffs . proto) over the WHOLE 160x160 proto plane with no box crop, while
// construction.cpp's construct_pig_mask() (which builds the mask the winning candidate is
// actually reported with) DOES crop to the candidate's own box before thresholding. A small
// detection whose coefficients happen to respond strongly OUTSIDE its own box can therefore
// outscore the true, large detection on this uncropped measure, get selected, and then get
// cropped down to its own small box anyway -- producing a mask a fraction of the real
// animal's size. This is exactly what ref_log.md's three real photos showed: two of three
// failed with BL 8x-45x smaller than physically measured, and both had more than one
// surviving detection.

#include "stages/mask_geometry.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

using instaham_ml::stages::cropped_mask_area;
using instaham_ml::stages::proto_box_bounds;
using instaham_ml::stages::ProtoBoxBounds;
using instaham_ml::stages::SegmentationBox;

namespace {

inline float sigmoidf(float x) { return 1.0f / (1.0f + std::exp(-x)); }

// A single coefficient (num_coeffs == 1) whose proto plane is a `size x size` field. Every
// cell inside [in_x0,in_x1) x [in_y0,in_y1) gets a large positive activation (sigmoid well
// above 0.5); everything else gets a large negative one (sigmoid well below 0.5). This
// reproduces the actual failure shape: a candidate whose TRUE response region need not
// coincide with its OWN detection box at all -- exactly the "responds strongly outside its
// own box" case the crop is meant to reject.
std::vector<float> make_proto(int size, int in_x0, int in_y0, int in_x1, int in_y1) {
  std::vector<float> proto(size_t(size) * size, -8.0f);  // sigmoid(-8) ~= 0.0003
  for (int y = in_y0; y < in_y1; ++y) {
    for (int x = in_x0; x < in_x1; ++x) {
      proto[size_t(y) * size + x] = 8.0f;  // sigmoid(8) ~= 0.9997
    }
  }
  return proto;
}

}  // namespace

int main() {
  const int proto_size = 160;
  const int model_imgsz = 640;

  // ---- proto_box_bounds(): the downsample from model-space to proto-space is exact and
  // linear -- assert it directly before trusting the selection test above it. ----
  {
    SegmentationBox box{320.f, 320.f, 320.f, 320.f, 0.9f};  // full-frame-ish box, model space
    ProtoBoxBounds b = proto_box_bounds(box, proto_size, proto_size, model_imgsz);
    // scale = 160/640 = 0.25; box spans [160,480] model-space -> [40,120] proto-space.
    assert(std::fabs(b.x0 - 40.0f) < 1e-3f);
    assert(std::fabs(b.x1 - 120.0f) < 1e-3f);
    assert(std::fabs(b.y0 - 40.0f) < 1e-3f);
    assert(std::fabs(b.y1 - 120.0f) < 1e-3f);
  }

  // ---- the actual bug scenario ----
  // Candidate A: a SMALL detection box (model-space 40x40 at the corner) whose single
  // coefficient's proto response is a LARGE region covering most of the plane -- exactly
  // what a coefficient vector unrelated to this candidate's true, small extent would
  // produce. Its own box, once cropped to, would be tiny.
  {
    const std::vector<float> proto_a = make_proto(proto_size, 0, 0, 150, 150);  // huge response
    SegmentationBox small_box{20.f, 20.f, 40.f, 40.f, 0.5f};  // model-space corner, small
    ProtoBoxBounds bounds_a = proto_box_bounds(small_box, proto_size, proto_size, model_imgsz);
    const long long area_uncropped =
        cropped_mask_area({1.0f}, proto_a, proto_size, proto_size,
                           ProtoBoxBounds{0, 0, float(proto_size), float(proto_size)});
    const long long area_cropped_to_own_box =
        cropped_mask_area({1.0f}, proto_a, proto_size, proto_size, bounds_a);

    // The bug: scoring uncropped, this "small" candidate looks enormous.
    assert(area_uncropped > 20000);  // ~150*150 = 22500
    // The fix: cropped to its OWN box (proto-space [5,15]x[5,15], 10x10), it is tiny --
    // matching what construction.cpp would actually build for it.
    assert(area_cropped_to_own_box <= 100);  // 10*10 = 100 at most
  }

  // ---- Candidate B: a LARGE detection box (model-space, most of the frame) whose
  // coefficient's proto response is locally confined to roughly its own box -- the true
  // pig. Selecting on the CROPPED area must prefer B over the small-but-globally-loud A. ----
  {
    // A: small box, loud everywhere (the bug's spurious winner under uncropped scoring).
    const std::vector<float> proto_a = make_proto(proto_size, 0, 0, 150, 150);
    SegmentationBox box_a{20.f, 20.f, 40.f, 40.f, 0.5f};
    ProtoBoxBounds bounds_a = proto_box_bounds(box_a, proto_size, proto_size, model_imgsz);
    const long long area_a = cropped_mask_area({1.0f}, proto_a, proto_size, proto_size, bounds_a);

    // B: large box, response locally confined to roughly its own box.
    SegmentationBox box_b{320.f, 320.f, 560.f, 560.f, 0.4f};  // near-full-frame, model space
    ProtoBoxBounds bounds_b = proto_box_bounds(box_b, proto_size, proto_size, model_imgsz);
    const int bx0 = int(std::floor(bounds_b.x0)), by0 = int(std::floor(bounds_b.y0));
    const int bx1 = int(std::ceil(bounds_b.x1)), by1 = int(std::ceil(bounds_b.y1));
    const std::vector<float> proto_b = make_proto(proto_size, bx0, by0, bx1, by1);
    const long long area_b = cropped_mask_area({1.0f}, proto_b, proto_size, proto_size, bounds_b);

    // The fix's whole point: B (the true, large pig) wins on cropped area, not A (the
    // small detection that would have won on F12's pre-fix uncropped scoring).
    assert(area_b > area_a);
    assert(area_b > 100 * area_a);  // not a near-tie -- B is the obviously right answer
  }

  // ---- sanity: cropped_mask_area respects the 0.5 threshold, not raw activation sign ----
  {
    // sigmoid(0.05) ~= 0.5125 > 0.5; sigmoid(-0.05) ~= 0.4875 < 0.5 -- a coefficient of 1.0
    // against a proto value of exactly the boundary should land on the expected side.
    assert(sigmoidf(0.05f) > 0.5f);
    assert(sigmoidf(-0.05f) < 0.5f);
    std::vector<float> proto = {0.05f, -0.05f, 0.05f, -0.05f};  // 2x2 plane
    long long area =
        cropped_mask_area({1.0f}, proto, 2, 2, ProtoBoxBounds{0, 0, 2, 2});
    assert(area == 2);  // exactly the two >0.5-sigmoid cells
  }

  std::puts("test_mask_selection: all assertions passed");
  return 0;
}
