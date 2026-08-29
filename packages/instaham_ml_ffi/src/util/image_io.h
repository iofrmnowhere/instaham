#ifndef INSTAHAM_ML_UTIL_IMAGE_IO_H
#define INSTAHAM_ML_UTIL_IMAGE_IO_H

#include <cstdint>
#include <string>
#include <vector>

namespace instaham_ml {

// A decoded, always-3-channel (RGB, no alpha) image with row-major HWC uint8 pixels.
struct RgbImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> pixels;  // size == width * height * 3
};

// Decodes `path` (JPEG/PNG/BMP -- whatever stb_image supports) into RGB. Never rotates:
// EXIF orientation is normalised Dart-side before the path ever reaches native code
// (AGENTS.md rule 5; see instaham_ml.h's classify_*_json doc comment). Returns false and
// sets *error on any decode failure (unreadable path, corrupt data, zero-size image).
bool decode_image_rgb(const std::string& path, RgbImage* out, std::string* error);

// Bilinear resize to an exact (dst_w, dst_h), no aspect-ratio preservation.
RgbImage resize_exact(const RgbImage& src, int dst_w, int dst_h);

// YOLO-style letterbox: scale preserving aspect ratio so the image fits inside
// (dst_w, dst_h), pad the remainder with `pad_color`, center the image (stride-aligned
// padding is not needed here because dst_w/dst_h are already stride multiples).
// Returns the resized+padded image and, via out params, the scale factor and left/top
// pad actually used (needed if a caller ever maps box coordinates back to source space).
RgbImage letterbox(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, float* scale_out,
                    int* pad_left_out, int* pad_top_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_UTIL_IMAGE_IO_H
