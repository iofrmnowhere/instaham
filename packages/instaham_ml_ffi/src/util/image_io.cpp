#include "util/image_io.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#include "third_party/stb/stb_image.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "third_party/stb/stb_image_resize2.h"

#include <algorithm>
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

RgbImage letterbox(const RgbImage& src, int dst_w, int dst_h, uint8_t pad_color, float* scale_out,
                    int* pad_left_out, int* pad_top_out) {
  float scale = std::min(float(dst_w) / float(src.width), float(dst_h) / float(src.height));
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

  if (scale_out) *scale_out = scale;
  if (pad_left_out) *pad_left_out = pad_left;
  if (pad_top_out) *pad_top_out = pad_top;
  return dst;
}

}  // namespace instaham_ml
