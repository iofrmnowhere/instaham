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

// docs/fix-phase-4/1-normalize-before-segment.md (F60): resizes `src` uniformly (both axes
// by the same `factor`, no letterboxing) so it is `cm_per_px_target` cm/pixel -- the first
// step of SegmentationInputScaleMode::kNormalizeFirst, before rotation or canvas placement.
// Uses a box filter (INTER_AREA's equivalent for this project's stb_image_resize2-based
// resizer -- there is no OpenCV dependency in this file, unlike stages/construction.cpp)
// when shrinking (`factor` < 1) and a triangle/bilinear filter when enlarging, matching the
// README's INTER_AREA/INTER_LINEAR split. `factor` must be finite and > 0.
RgbImage resize_uniform(const RgbImage& src, float factor);

// docs/fix-phase-4/1-normalize-before-segment.md (F60): rotates `src` 90 degrees clockwise.
// The output is height x width (dimensions swapped). Used before canvas placement when the
// normalized image is portrait -- see stages/canvas_scale.h's
// decide_normalize_first_composition().
RgbImage rotate90_cw(const RgbImage& src);

// docs/fix-phase-4/1-normalize-before-segment.md (F60): centers `src` on a `dst_w` x `dst_h`
// canvas filled with `pad_color`, at the caller-supplied `x_offset`/`y_offset` -- unlike
// place_at_scale() above, this never resizes `src`. Used to place the already-normalized,
// already-rotated content onto the (possibly oversized, F61) canvas at the offset
// decide_normalize_first_composition() computed.
RgbImage place_at_offset(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, int x_offset,
                          int y_offset);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_UTIL_IMAGE_IO_H
