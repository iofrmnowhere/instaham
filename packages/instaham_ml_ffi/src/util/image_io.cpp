#include "util/image_io.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#include "third_party/stb/stb_image.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "third_party/stb/stb_image_resize2.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace instaham_ml {

bool decode_image_rgb(const std::string& path, RgbImage* out, std::string* error) {
  int w = 0, h = 0, channels_in_file = 0;
  // Force 3 channels: stb_image drops alpha / expands grayscale for us.
  uint8_t* data = stbi_load(path.c_str(), &w, &h, &channels_in_file, 3);
  if (!data) {
    if (error) *error = stbi_failure_reason() ? stbi_failure_reason() : "decode failed";
    return false;
  }
  if (w <= 0 || h <= 0) {
    stbi_image_free(data);
    if (error) *error = "decoded image has zero dimension";
    return false;
  }
  out->width = w;
  out->height = h;
  out->pixels.assign(data, data + (size_t(w) * h * 3));
  stbi_image_free(data);
  return true;
}

RgbImage resize_exact(const RgbImage& src, int dst_w, int dst_h) {
  RgbImage dst;
  dst.width = dst_w;
  dst.height = dst_h;
  dst.pixels.resize(size_t(dst_w) * dst_h * 3);
  stbir_resize_uint8_linear(src.pixels.data(), src.width, src.height, 0, dst.pixels.data(), dst_w,
                             dst_h, 0, STBIR_RGB);
  return dst;
}

RgbImage place_at_scale(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, float scale,
                         int* pad_left_out, int* pad_top_out) {
  int new_w = std::max(1, int(std::round(src.width * scale)));
  int new_h = std::max(1, int(std::round(src.height * scale)));

  RgbImage resized;
  resized.width = new_w;
  resized.height = new_h;
  resized.pixels.resize(size_t(new_w) * new_h * 3);
  stbir_resize_uint8_linear(src.pixels.data(), src.width, src.height, 0, resized.pixels.data(),
                             new_w, new_h, 0, STBIR_RGB);

  int pad_left = (dst_w - new_w) / 2;
  int pad_top = (dst_h - new_h) / 2;

  RgbImage dst;
  dst.width = dst_w;
  dst.height = dst_h;
  dst.pixels.assign(size_t(dst_w) * dst_h * 3, pad_color);
  for (int y = 0; y < new_h; ++y) {
    const uint8_t* src_row = resized.pixels.data() + size_t(y) * new_w * 3;
    uint8_t* dst_row = dst.pixels.data() + (size_t(y + pad_top) * dst_w + pad_left) * 3;
    std::memcpy(dst_row, src_row, size_t(new_w) * 3);
  }

  if (pad_left_out) *pad_left_out = pad_left;
  if (pad_top_out) *pad_top_out = pad_top;
  return dst;
}

RgbImage letterbox(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, float* scale_out,
                    int* pad_left_out, int* pad_top_out) {
  float scale = std::min(float(dst_w) / float(src.width), float(dst_h) / float(src.height));
  RgbImage dst = place_at_scale(src, dst_w, dst_h, pad_color, scale, pad_left_out, pad_top_out);
  if (scale_out) *scale_out = scale;
  return dst;
}

RgbImage resize_uniform(const RgbImage& src, float factor) {
  RgbImage dst;
  if (!(factor > 0.0f) || !std::isfinite(factor)) return dst;
  const int new_w = std::max(1, int(std::round(src.width * factor)));
  const int new_h = std::max(1, int(std::round(src.height * factor)));
  dst.width = new_w;
  dst.height = new_h;
  dst.pixels.resize(size_t(new_w) * new_h * 3);
  const stbir_filter filter = factor < 1.0f ? STBIR_FILTER_BOX : STBIR_FILTER_TRIANGLE;
  stbir_resize(src.pixels.data(), src.width, src.height, 0, dst.pixels.data(), new_w, new_h, 0,
               STBIR_RGB, STBIR_TYPE_UINT8, STBIR_EDGE_CLAMP, filter);
  return dst;
}

RgbImage rotate90_cw(const RgbImage& src) {
  RgbImage dst;
  dst.width = src.height;
  dst.height = src.width;
  dst.pixels.resize(size_t(dst.width) * dst.height * 3);
  for (int y = 0; y < src.height; ++y) {
    for (int x = 0; x < src.width; ++x) {
      const size_t src_i = (size_t(y) * src.width + x) * 3;
      const size_t dst_i = (size_t(x) * dst.width + (src.height - 1 - y)) * 3;
      dst.pixels[dst_i] = src.pixels[src_i];
      dst.pixels[dst_i + 1] = src.pixels[src_i + 1];
      dst.pixels[dst_i + 2] = src.pixels[src_i + 2];
    }
  }
  return dst;
}

RgbImage place_at_offset(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, int x_offset,
                          int y_offset) {
  RgbImage dst;
  dst.width = dst_w;
  dst.height = dst_h;
  dst.pixels.assign(size_t(dst_w) * dst_h * 3, pad_color);
  const int copy_w = std::min(src.width, dst_w - x_offset);
  const int copy_h = std::min(src.height, dst_h - y_offset);
  for (int y = 0; y < copy_h; ++y) {
    const uint8_t* src_row = src.pixels.data() + size_t(y) * src.width * 3;
    uint8_t* dst_row = dst.pixels.data() + (size_t(y + y_offset) * dst_w + x_offset) * 3;
    std::memcpy(dst_row, src_row, size_t(copy_w) * 3);
  }
  return dst;
}

}  // namespace instaham_ml
