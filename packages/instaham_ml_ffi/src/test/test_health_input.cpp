// docs/plan-phase-3/2-parity-gate-and-tests.md: native unit tests for health_input.{h,cpp}
// covering everything a pixel-parity gate cannot see on its own -- coordinate recovery,
// aspect preservation, degradation, and the reporting fields. Pixel-level agreement with
// ML/parity/reference_health_input.py is health_input_gate_cli.cpp's job, driven by
// ML/parity/test_health_input.py, not this file.
//
// Header-only-adjacent (health_input.cpp is pure array/OpenCV-resize math, no ONNX
// session), so like test_scale_normalization this only needs OpenCV -- it is gated behind
// INSTAHAM_ML_WITH_OPENCV in CMakeLists.txt.

#include "health_input.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <vector>

using instaham_ml::HealthInput;
using instaham_ml::HealthInputProtocol;
using instaham_ml::PigRegion;
using instaham_ml::pig_region_from_base_mask;
using instaham_ml::prepare_health_input;
using instaham_ml::resize_shorter_then_crop;
using instaham_ml::RgbImage;

namespace {

RgbImage make_image(int w, int h, uint8_t r, uint8_t g, uint8_t b) {
  RgbImage img;
  img.width = w;
  img.height = h;
  img.pixels.resize(size_t(w) * h * 3);
  for (size_t i = 0; i < img.pixels.size(); i += 3) {
    img.pixels[i + 0] = r;
    img.pixels[i + 1] = g;
    img.pixels[i + 2] = b;
  }
  return img;
}

// Fills [x0,y0)-[x1,y1) with a distinct colour so a crop's contents (not just its size)
// can be checked against a known source rectangle.
void paint_rect(RgbImage* img, int x0, int y0, int x1, int y1, uint8_t r, uint8_t g,
                 uint8_t b) {
  for (int y = std::max(0, y0); y < std::min(img->height, y1); ++y) {
    for (int x = std::max(0, x0); x < std::min(img->width, x1); ++x) {
      uint8_t* p = &img->pixels[(size_t(y) * img->width + x) * 3];
      p[0] = r;
      p[1] = g;
      p[2] = b;
    }
  }
}

std::vector<uint8_t> make_rect_mask(int w, int h, int x0, int y0, int x1, int y1) {
  std::vector<uint8_t> mask(size_t(w) * h, 0);
  for (int y = std::max(0, y0); y < std::min(h, y1); ++y) {
    for (int x = std::max(0, x0); x < std::min(w, x1); ++x) {
      mask[size_t(y) * w + x] = 255;
    }
  }
  return mask;
}

bool image_matches_solid_color(const RgbImage& img, uint8_t r, uint8_t g, uint8_t b) {
  for (size_t i = 0; i < img.pixels.size(); i += 3) {
    if (img.pixels[i] != r || img.pixels[i + 1] != g || img.pixels[i + 2] != b) return false;
  }
  return true;
}

bool image_has_color(const RgbImage& img, uint8_t r, uint8_t g, uint8_t b) {
  for (size_t i = 0; i < img.pixels.size(); i += 3) {
    if (img.pixels[i] == r && img.pixels[i + 1] == g && img.pixels[i + 2] == b) return true;
  }
  return false;
}

void images_equal(const RgbImage& a, const RgbImage& b) {
  assert(a.width == b.width && a.height == b.height);
  assert(a.pixels == b.pixels);
}

}  // namespace

int main() {
  // ==== 1. Coordinate recovery ==========================================================
  // docs/plan-phase-3/2.1-recovery-helper.md: exercises pig_region_from_base_mask() itself
  // (health_input.cpp), the function pipeline.cpp calls, instead of a copy of its
  // arithmetic. Exercised at a non-1.0 factor, since 1.0 proves nothing about the division.
  {
    const float content_scale = 0.25f;  // BASE_MASK space is 1/4 the original capture.
    const uint8_t mask_px = 255;
    // A mask box at (40, 20)-(120, 100) in BASE_MASK space (bbox_w=80, bbox_h=80)...
    PigRegion region;
    const bool ok = pig_region_from_base_mask(40, 20, 80, 80, &mask_px, 1, 1, content_scale,
                                               &region);
    // ...should recover to (160, 80)-(480, 400) in original coordinates.
    assert(ok);
    assert(region.x0 == 160 && region.y0 == 80 && region.x1 == 480 && region.y1 == 400);
    assert(region.valid());
    assert(region.has_mask);
    assert(region.mask == &mask_px && region.mask_w == 1 && region.mask_h == 1);
  }

  // A box that does not divide evenly at the chosen factor -- checks std::lround rounding
  // on all four edges, which a truncating cast would fail.
  {
    const float content_scale = 0.3f;
    const uint8_t mask_px = 255;
    PigRegion region;
    const bool ok = pig_region_from_base_mask(7, 11, 23, 17, &mask_px, 1, 1, content_scale,
                                               &region);
    assert(ok);
    // 7/0.3 = 23.33.. -> 23; 11/0.3 = 36.66.. -> 37; 30/0.3 = 100; 28/0.3 = 93.33.. -> 93.
    assert(region.x0 == 23 && region.y0 == 37 && region.x1 == 100 && region.y1 == 93);
  }

  // content_scale of zero, negative, NaN and +inf must all fail without touching `out`.
  {
    const uint8_t mask_px = 255;
    for (float bad_scale :
         {0.0f, -0.25f, std::numeric_limits<float>::quiet_NaN(),
          std::numeric_limits<float>::infinity()}) {
      PigRegion region;
      region.x0 = 9;
      region.y0 = 9;
      region.x1 = 9;
      region.y1 = 9;
      const bool ok =
          pig_region_from_base_mask(40, 20, 80, 80, &mask_px, 1, 1, bad_scale, &region);
      assert(!ok);
      assert(region.x0 == 9 && region.y0 == 9 && region.x1 == 9 && region.y1 == 9);
    }
  }

  // A null mask must fail even with an otherwise-valid content_scale.
  {
    PigRegion region;
    const bool ok = pig_region_from_base_mask(40, 20, 80, 80, nullptr, 1, 1, 0.25f, &region);
    assert(!ok);
  }

  // ==== 2. Aspect preservation ===========================================================
  // A mask whose own resolution differs from the capture's must not distort when
  // resampled against it -- check both axes independently against the same factor by
  // recovering a non-square box and confirming width and height each survive the
  // content_scale division exactly (not, e.g., width scaled by one axis' factor and
  // height by another's -- a single scalar covers both axes only because content_scale
  // IS a uniform factor per docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md).
  {
    const float content_scale = 0.4f;
    const uint8_t mask_px = 255;
    const int mask_w = 60, mask_h = 30;  // 2:1 aspect in BASE_MASK space
    PigRegion region;
    const bool ok = pig_region_from_base_mask(0, 0, mask_w, mask_h, &mask_px, 1, 1,
                                               content_scale, &region);
    assert(ok);
    const int recovered_w = region.x1 - region.x0;
    const int recovered_h = region.y1 - region.y0;
    assert(recovered_w == 150 && recovered_h == 75);
    // Aspect ratio preserved: both axes scaled by the exact same 1/content_scale factor.
    assert(std::fabs(double(recovered_w) / recovered_h - double(mask_w) / mask_h) < 1e-9);
  }

  // ==== 2b. Recovery feeds the real crop end to end ======================================
  // docs/plan-phase-3/2.1-recovery-helper.md: pig_region_from_base_mask() output handed
  // straight to prepare_health_input(), on synthetic pixels, so the recovery and the mask
  // resample are checked against each other on the exact code that ships -- not just the
  // arithmetic in isolation (group 1) or the crop's own fallback paths (group 3 below).
  {
    const int src_w = 400, src_h = 400;
    RgbImage img = make_image(src_w, src_h, 5, 5, 5);
    // Pig area in ORIGINAL coordinates: (100, 100)-(300, 300).
    paint_rect(&img, 100, 100, 300, 300, 200, 10, 10);

    // A mask at 1/4 resolution (content_scale = 0.25) covering the same area in BASE_MASK
    // space: (25, 25)-(75, 75) of a 100x100 mask.
    const float content_scale = 0.25f;
    const int mask_w = 100, mask_h = 100;
    std::vector<uint8_t> mask = make_rect_mask(mask_w, mask_h, 25, 25, 75, 75);

    PigRegion region;
    const bool ok = pig_region_from_base_mask(25, 25, 50, 50, mask.data(), mask_w, mask_h,
                                               content_scale, &region);
    assert(ok);
    assert(region.x0 == 100 && region.y0 == 100 && region.x1 == 300 && region.y1 == 300);

    // bbox_padding_ratio explicitly wide (default 0.06 pads by only 12px here, which
    // resize_shorter_then_crop's own centre-crop trims away entirely -- this test needs a
    // fill band wide enough to survive both the upscale to 256 and the crop back to 224).
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                            &region, 256, 224, /*bbox_padding_ratio=*/0.25f);
    assert(!out.degraded);
    assert(out.protocol_applied == "segmentation_masked");
    assert(out.region_source == "mask");
    // The painted pig colour survives into the crop...
    assert(image_has_color(out.image, 200, 10, 10));
    // ...and the crop contains mean-fill outside the mask, not the background colour --
    // confirms the recovered box, not the whole padded rectangle, was masked.
    assert(!image_matches_solid_color(out.image, 200, 10, 10));
    assert(!image_has_color(out.image, 5, 5, 5));
  }

  // ==== 3. Degradation ====================================================================
  const int W = 200, H = 200;
  const int resize_shorter = 256, crop = 224;

  // Null region.
  {
    RgbImage img = make_image(W, H, 10, 20, 30);
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationCrop, nullptr,
                                            resize_shorter, crop);
    assert(out.degraded);
    assert(out.protocol_applied == "full_frame");
    assert(out.region_source == "none");
  }

  // Invalid region (x1 <= x0).
  {
    RgbImage img = make_image(W, H, 10, 20, 30);
    PigRegion region;
    region.x0 = 50;
    region.y0 = 50;
    region.x1 = 50;  // collapsed -- valid() is false
    region.y1 = 80;
    assert(!region.valid());
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                            &region, resize_shorter, crop);
    assert(out.degraded);
    assert(out.protocol_applied == "full_frame");
  }

  // All-zero mask (segmentation ran but found nothing usable) -- degrades exactly like a
  // missing region, and still reports region_source == "mask" since a mask WAS supplied.
  {
    RgbImage img = make_image(W, H, 10, 20, 30);
    std::vector<uint8_t> zero_mask(size_t(W) * H, 0);
    PigRegion region;
    region.x0 = 20;
    region.y0 = 20;
    region.x1 = 180;
    region.y1 = 180;
    region.has_mask = true;
    region.mask = zero_mask.data();
    region.mask_w = W;
    region.mask_h = H;
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                            &region, resize_shorter, crop);
    assert(out.degraded);
    assert(out.protocol_applied == "full_frame");
    assert(out.region_source == "mask");
  }

  // Degenerate padded box: a 1x1 region at the image's own corner, once clamped, still
  // produces a nonzero crop (crop_to_bbox never collapses to empty) -- this is NOT a
  // degradation path, it is proof the clamping floor holds even at the extreme.
  {
    RgbImage img = make_image(W, H, 10, 20, 30);
    PigRegion region;
    region.x0 = 0;
    region.y0 = 0;
    region.x1 = 1;
    region.y1 = 1;
    assert(region.valid());
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationCrop, &region,
                                            resize_shorter, crop);
    assert(!out.degraded);
    assert(out.protocol_applied == "segmentation_crop");
    assert(out.image.width == crop && out.image.height == crop);
  }

  // ==== 4. Full-frame is untouched ========================================================
  // With protocol == kFullFrame, the output must equal resize_shorter_then_crop() exactly,
  // mask present or not -- the regression guard for the shipped default.
  {
    RgbImage img = make_image(320, 180, 5, 100, 200);
    paint_rect(&img, 50, 50, 100, 100, 250, 10, 10);
    const RgbImage reference = resize_shorter_then_crop(img, resize_shorter, crop);

    HealthInput no_region = prepare_health_input(img, HealthInputProtocol::kFullFrame, nullptr,
                                                  resize_shorter, crop);
    images_equal(no_region.image, reference);
    assert(!no_region.degraded);
    assert(no_region.protocol_applied == "full_frame");

    std::vector<uint8_t> mask = make_rect_mask(320, 180, 50, 50, 100, 100);
    PigRegion region;
    region.x0 = 50;
    region.y0 = 50;
    region.x1 = 100;
    region.y1 = 100;
    region.has_mask = true;
    region.mask = mask.data();
    region.mask_w = 320;
    region.mask_h = 180;
    HealthInput with_region = prepare_health_input(img, HealthInputProtocol::kFullFrame, &region,
                                                    resize_shorter, crop);
    images_equal(with_region.image, reference);
    assert(!with_region.degraded);
    assert(with_region.protocol_applied == "full_frame");
  }

  // ==== 5. Mean fill ======================================================================
  // With a mask covering a known rectangle, every pixel outside it in the output crop is
  // the ImageNet mean colour, and pixels inside are not.
  {
    // round(255 * IMAGENET_MEAN) R/G/B -- must match health_input.cpp's
    // imagenet_mean_rgb_uint8() (ML/export/common.py::IMAGENET_MEAN).
    const uint8_t mean_r = uint8_t(std::lround(0.485f * 255.0f));
    const uint8_t mean_g = uint8_t(std::lround(0.456f * 255.0f));
    const uint8_t mean_b = uint8_t(std::lround(0.406f * 255.0f));

    RgbImage img = make_image(W, H, 200, 30, 30);  // background: distinctly NOT the mean
    // Interior: a rectangle painted a colour that is also distinctly not the mean, so
    // "not mean" inside the mask is a real assertion, not a coincidence of the background.
    paint_rect(&img, 60, 60, 140, 140, 30, 200, 30);
    std::vector<uint8_t> mask = make_rect_mask(W, H, 60, 60, 140, 140);

    PigRegion region;
    region.x0 = 60;
    region.y0 = 60;
    region.x1 = 140;
    region.y1 = 140;
    region.has_mask = true;
    region.mask = mask.data();
    region.mask_w = W;
    region.mask_h = H;
    // bbox_padding_ratio = 0 so the padded box equals the mask rectangle exactly --
    // otherwise the padding ring would be background (unmasked at the source) mixed with
    // interior, making "outside mask -> mean" ambiguous at the crop's own edges.
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                            &region, resize_shorter, crop,
                                            /*bbox_padding_ratio=*/0.0f);
    assert(!out.degraded);
    assert(out.protocol_applied == "segmentation_masked");
    // The crop is the 80x80 interior resized/cropped to 224 -- every pixel in the source
    // patch was inside the mask, so the mean fill colour must NOT appear anywhere in the
    // output (nothing outside the mask survived to be resampled into it).
    assert(!image_has_color(out.image, mean_r, mean_g, mean_b));
    assert(image_matches_solid_color(out.image, 30, 200, 30));
  }

  // Same setup but the mask covers only the left half of the padded box: the mean fill
  // colour must appear (right half masked out) while the painted colour still survives
  // (left half kept).
  {
    const uint8_t mean_r = uint8_t(std::lround(0.485f * 255.0f));
    const uint8_t mean_g = uint8_t(std::lround(0.456f * 255.0f));
    const uint8_t mean_b = uint8_t(std::lround(0.406f * 255.0f));

    RgbImage img = make_image(W, H, 30, 200, 30);  // whole box painted the "pig" colour
    paint_rect(&img, 60, 60, 140, 140, 30, 200, 30);
    // Mask only the left half (60..100) of the 60..140 box.
    std::vector<uint8_t> mask = make_rect_mask(W, H, 60, 60, 100, 140);

    PigRegion region;
    region.x0 = 60;
    region.y0 = 60;
    region.x1 = 140;
    region.y1 = 140;
    region.has_mask = true;
    region.mask = mask.data();
    region.mask_w = W;
    region.mask_h = H;
    HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                            &region, resize_shorter, crop,
                                            /*bbox_padding_ratio=*/0.0f);
    assert(!out.degraded);
    assert(image_has_color(out.image, mean_r, mean_g, mean_b));
    assert(image_has_color(out.image, 30, 200, 30));
  }

  // ==== 6. Reporting ======================================================================
  // region_source reads "mask" when a mask was supplied and "bbox" when only a box was,
  // in both the success and the degraded cases.
  {
    RgbImage img = make_image(W, H, 10, 20, 30);

    // Success, bbox only.
    {
      PigRegion region;
      region.x0 = 20;
      region.y0 = 20;
      region.x1 = 180;
      region.y1 = 180;
      HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationCrop,
                                              &region, resize_shorter, crop);
      assert(!out.degraded);
      assert(out.region_source == "bbox");
    }

    // Success, mask present.
    {
      std::vector<uint8_t> mask = make_rect_mask(W, H, 20, 20, 180, 180);
      PigRegion region;
      region.x0 = 20;
      region.y0 = 20;
      region.x1 = 180;
      region.y1 = 180;
      region.has_mask = true;
      region.mask = mask.data();
      region.mask_w = W;
      region.mask_h = H;
      HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                              &region, resize_shorter, crop);
      assert(!out.degraded);
      assert(out.region_source == "mask");
    }

    // Degraded, bbox only (invalid box).
    {
      PigRegion region;
      region.x0 = 50;
      region.y0 = 50;
      region.x1 = 50;
      region.y1 = 80;
      HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationCrop,
                                              &region, resize_shorter, crop);
      assert(out.degraded);
      // region.valid() is false, so prepare_health_input never even inspects has_mask --
      // region_source falls to "none" per its own definition (region == nullptr ||
      // !region->valid() -> "none").
      assert(out.region_source == "none");
    }

    // Degraded, mask present but all-zero (covered in group 3 above too; repeated here
    // to pin the reporting field specifically).
    {
      std::vector<uint8_t> zero_mask(size_t(W) * H, 0);
      PigRegion region;
      region.x0 = 20;
      region.y0 = 20;
      region.x1 = 180;
      region.y1 = 180;
      region.has_mask = true;
      region.mask = zero_mask.data();
      region.mask_w = W;
      region.mask_h = H;
      HealthInput out = prepare_health_input(img, HealthInputProtocol::kSegmentationMasked,
                                              &region, resize_shorter, crop);
      assert(out.degraded);
      assert(out.region_source == "mask");
    }
  }

  // ==== 7. decide_health_second_stage() ===================================================
  // docs/plan-phase-4/1-native-cascade.md: pure decision, no ORT/image, so every branch is
  // reachable directly.
  {
    using instaham_ml::decide_health_second_stage;
    using instaham_ml::HealthSecondStage;

    PigRegion mask_region;
    mask_region.x0 = 10;
    mask_region.y0 = 10;
    mask_region.x1 = 90;
    mask_region.y1 = 90;
    mask_region.has_mask = true;
    std::vector<uint8_t> some_mask(64 * 64, 255);
    mask_region.mask = some_mask.data();
    mask_region.mask_w = 64;
    mask_region.mask_h = 64;

    PigRegion bbox_only_region;
    bbox_only_region.x0 = 10;
    bbox_only_region.y0 = 10;
    bbox_only_region.x1 = 90;
    bbox_only_region.y1 = 90;
    bbox_only_region.has_mask = false;

    // Cascade disabled: every other input is irrelevant.
    assert(decide_health_second_stage(false, "Sunburn", "Healthy", &mask_region) ==
           HealthSecondStage::kDisabled);
    assert(decide_health_second_stage(false, "Healthy", "Healthy", &mask_region) ==
           HealthSecondStage::kDisabled);

    // Enabled, first label is exactly the healthy label: no re-analysis.
    assert(decide_health_second_stage(true, "Healthy", "Healthy", &mask_region) ==
           HealthSecondStage::kNotNeededHealthy);
    // Case must match exactly -- a near-miss is not healthy (no silent normalization of the
    // manifest-declared label).
    assert(decide_health_second_stage(true, "healthy", "Healthy", &mask_region) ==
           HealthSecondStage::kRun);
    // Empty healthy_label never matches a real label.
    assert(decide_health_second_stage(true, "Healthy", "", &mask_region) ==
           HealthSecondStage::kRun);

    // Enabled, not healthy, usable mask region: run it.
    assert(decide_health_second_stage(true, "Sunburn", "Healthy", &mask_region) ==
           HealthSecondStage::kRun);

    // Enabled, not healthy, no region at all.
    assert(decide_health_second_stage(true, "Sunburn", "Healthy", nullptr) ==
           HealthSecondStage::kNoRegion);
    // Enabled, not healthy, a region with only a bbox (no mask) -- the masked protocol needs
    // a real mask, not just a box, so this is "no usable region" too.
    assert(decide_health_second_stage(true, "Sunburn", "Healthy", &bbox_only_region) ==
           HealthSecondStage::kNoRegion);
    // Enabled, not healthy, an invalid box (x1 <= x0).
    PigRegion invalid_region = mask_region;
    invalid_region.x1 = invalid_region.x0;
    assert(decide_health_second_stage(true, "Sunburn", "Healthy", &invalid_region) ==
           HealthSecondStage::kNoRegion);
  }

  std::puts("test_health_input: all assertions passed");
  return 0;
}
