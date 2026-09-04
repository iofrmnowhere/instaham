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

// ref_fix.md F18: like letterbox(), but `scale` is supplied by the caller instead of being
// computed to fit -- used when stages::run_segmentation composes the 640x640 canvas at a
// scale derived from the user-confirmed reference object's cm/pixel, rather than from the
// image's own dimensions (a whole-frame fit is what made the segmenter see a pig at an
// apparent size it does not reliably detect at -- see ref_fix.md section 1). The caller
// MUST ensure round(src.width*scale) <= dst_w and round(src.height*scale) <= dst_h first
// (falling back to letterbox() otherwise) -- this does not clamp or crop, it pads.
RgbImage place_at_scale(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, float scale,
                         int* pad_left_out, int* pad_top_out);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_UTIL_IMAGE_IO_H
