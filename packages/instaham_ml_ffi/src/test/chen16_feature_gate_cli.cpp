// docs/plan-phase/2-native-cutter-chen16.md, "Add the feature-port gate test": a standalone
// CLI, not a ctest assertion, because the oracle side lives in Python
// (ML/pipeline/feature_calculation.py::extract_chen16_features) and the comparison driver
// is therefore also Python (ML/parity/chen16_feature_port_gate.py). This binary's only job
// is: given a mask image path, decode it, run the C++ extract_chen16_features, and print
// the 16 values (or a failure marker) as one CSV line so the Python driver can diff them
// against its own reference computation over the SAME mask file.
//
// Usage: chen16_feature_gate_cli <mask_png_path>
// Output (stdout, one line): either
//   valid,<mask_area>,<convex_hull_area>,<difference>,<dif_mask>,<body_curve>,<perimeter>,
//   <outline_curve>,<longest>,<shortest>,<Hu_1>,...,<Hu_7>
// or
//   invalid
// printed with enough decimal digits (17 significant, round-trippable for a double) that
// the Python side compares the real computed value, not a truncated one.

#include <cstdio>
#include <string>

#include "stages/feature_calculation.h"
#include "util/image_io.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <mask_png_path>\n", argv[0]);
    return 2;
  }

  instaham_ml::RgbImage img;
  std::string error;
  if (!instaham_ml::decode_image_rgb(argv[1], &img, &error)) {
    std::fprintf(stderr, "decode failed: %s\n", error.c_str());
    return 2;
  }

  // Ground-truth masks in Instaham/PIGRGB-Weight/MASK_3394/ are binary 0/255. Any
  // nonzero-ish pixel (using the red channel; decode_image_rgb expands grayscale to RGB
  // identically across channels) becomes mask value 1.
  std::vector<uint8_t> mask(static_cast<size_t>(img.width) * img.height);
  for (size_t i = 0; i < mask.size(); ++i) {
    mask[i] = img.pixels[i * 3] > 127 ? 1 : 0;
  }

  auto result = instaham_ml::stages::extract_chen16_features(mask, img.width, img.height);
  if (!result.has_value() || !result->valid) {
    std::printf("invalid\n");
    return 0;
  }

  std::printf("valid");
  for (double v : result->values) {
    std::printf(",%.17g", v);
  }
  std::printf("\n");
  return 0;
}
