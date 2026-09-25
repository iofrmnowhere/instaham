// docs/plan-phase-3/2-parity-gate-and-tests.md: the C++ side of the health-input parity
// gate. Given a decoded photo, a protocol name, and an optional pig region (bbox or
// bbox+mask, both in ORIGINAL image coordinates -- the same contract health_input.h
// documents for PigRegion), runs prepare_health_input() and dumps the prepared crop as
// raw RGB so the Python driver (ML/parity/test_health_input.py) can compare it pixel-for-
// pixel against ML/parity/reference_health_input.py's own output over the SAME inputs.
// No add_test() -- Python is the driver, matching chen16_feature_gate_cli's own comment.
//
// Output format (uint8 crop, not the normalized tensor -- a mismatch stays inspectable as
// an image): a tiny raw dump, not PNG (no image-encode dependency exists in this tree):
//   int32 width, int32 height, then width*height*3 raw RGB bytes, all little-endian.
//
// Usage:
//   health_input_gate_cli <image_path> <protocol> <out_path> none
//   health_input_gate_cli <image_path> <protocol> <out_path> bbox <x0> <y0> <x1> <y1>
//       [padding_ratio] [background_fill]
//   health_input_gate_cli <image_path> <protocol> <out_path> mask <mask_raw_path>
//       <x0> <y0> <x1> <y1> [padding_ratio] [background_fill]
// `mask_raw_path` is a raw dump with the SAME header format as the output above (int32
// mask_w, int32 mask_h, then mask_w*mask_h single-channel 0/255 bytes) -- the mask's own
// resolution, independent of the image's; health_input.cpp resamples it. `protocol` is
// one of full_frame / segmentation_crop / segmentation_masked (abnormality_crop is still
// a stub -- see health_input.h -- so the gate does not cover it).

#include "health_input.h"
#include "util/image_io.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace {

bool write_raw_image(const std::string& path, const instaham_ml::RgbImage& img) {
  FILE* f = std::fopen(path.c_str(), "wb");
  if (f == nullptr) return false;
  int32_t w = img.width, h = img.height;
  bool ok = std::fwrite(&w, sizeof(w), 1, f) == 1 && std::fwrite(&h, sizeof(h), 1, f) == 1 &&
            std::fwrite(img.pixels.data(), 1, img.pixels.size(), f) == img.pixels.size();
  std::fclose(f);
  return ok;
}

bool read_raw_mask(const std::string& path, std::vector<uint8_t>* mask, int* w, int* h) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (f == nullptr) return false;
  int32_t width = 0, height = 0;
  bool ok = std::fread(&width, sizeof(width), 1, f) == 1 &&
            std::fread(&height, sizeof(height), 1, f) == 1;
  if (ok) {
    mask->resize(size_t(width) * height);
    ok = std::fread(mask->data(), 1, mask->size(), f) == mask->size();
  }
  std::fclose(f);
  if (ok) {
    *w = width;
    *h = height;
  }
  return ok;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 5) {
    std::fprintf(stderr,
                  "usage: %s <image_path> <protocol> <out_path> "
                  "none|bbox <x0> <y0> <x1> <y1> [pad] [fill]|mask <mask_raw_path> <x0> <y0> "
                  "<x1> <y1> [pad] [fill]\n",
                  argv[0]);
    return 2;
  }

  const std::string image_path = argv[1];
  const std::string protocol_name = argv[2];
  const std::string out_path = argv[3];
  const std::string region_mode = argv[4];

  instaham_ml::RgbImage img;
  std::string error;
  if (!instaham_ml::decode_image_rgb(image_path, &img, &error)) {
    std::fprintf(stderr, "decode failed: %s\n", error.c_str());
    return 2;
  }

  instaham_ml::PigRegion region;
  const instaham_ml::PigRegion* region_ptr = nullptr;
  std::vector<uint8_t> mask_bytes;
  float padding_ratio = 0.06f;
  std::string background_fill = "imagenet_mean";
  int next = 5;

  if (region_mode == "bbox" || region_mode == "mask") {
    if (region_mode == "mask") {
      if (argc < next + 5) {
        std::fprintf(stderr, "mask mode needs <mask_raw_path> <x0> <y0> <x1> <y1>\n");
        return 2;
      }
      const std::string mask_path = argv[next++];
      int mask_w = 0, mask_h = 0;
      if (!read_raw_mask(mask_path, &mask_bytes, &mask_w, &mask_h)) {
        std::fprintf(stderr, "failed to read mask raw dump: %s\n", mask_path.c_str());
        return 2;
      }
      region.has_mask = true;
      region.mask = mask_bytes.data();
      region.mask_w = mask_w;
      region.mask_h = mask_h;
    } else {
      if (argc < next + 4) {
        std::fprintf(stderr, "bbox mode needs <x0> <y0> <x1> <y1>\n");
        return 2;
      }
    }
    region.x0 = std::atoi(argv[next++]);
    region.y0 = std::atoi(argv[next++]);
    region.x1 = std::atoi(argv[next++]);
    region.y1 = std::atoi(argv[next++]);
    region_ptr = &region;
  }
  if (argc > next) padding_ratio = float(std::atof(argv[next++]));
  if (argc > next) background_fill = argv[next++];

  const instaham_ml::HealthInputProtocol protocol =
      instaham_ml::parse_health_input_protocol(protocol_name);
  // 255, not 256 -- assets/ml/manifest.json's capabilities.health.preprocessing.
  // resize_shorter_side, i.e. round(224 * RESIZE_RATIO) where RESIZE_RATIO == 1.14
  // (ML/export/common.py). classifier.cpp reads this from the manifest at runtime; the
  // gate hardcodes it because it drives prepare_health_input() directly, bypassing the
  // manifest entirely -- a real classifier run is unaffected by this constant either way.
  const instaham_ml::HealthInput result = instaham_ml::prepare_health_input(
      img, protocol, region_ptr, /*resize_shorter_side=*/255, /*crop=*/224, padding_ratio,
      background_fill);

  if (!write_raw_image(out_path, result.image)) {
    std::fprintf(stderr, "failed to write output: %s\n", out_path.c_str());
    return 2;
  }

  // Report what actually ran on stdout so the Python driver can assert it matches its own
  // expectation before even comparing pixels (a silent full_frame degradation must never
  // be mistaken for a passing region-protocol comparison).
  std::printf("%s,%s,%s,%d\n", result.protocol_requested.c_str(),
              result.protocol_applied.c_str(), result.region_source.c_str(),
              int(result.degraded));
  return 0;
}
