#include "util/sha256.h"

#include <cstdio>
#include <cstring>

namespace instaham_ml {
namespace {

constexpr uint32_t kK[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
    0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
    0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
    0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2};

inline uint32_t rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

}  // namespace

Sha256::Sha256() {
  state_[0] = 0x6a09e667;
  state_[1] = 0xbb67ae85;
  state_[2] = 0x3c6ef372;
  state_[3] = 0xa54ff53a;
  state_[4] = 0x510e527f;
  state_[5] = 0x9b05688c;
  state_[6] = 0x1f83d9ab;
  state_[7] = 0x5be0cd19;
}

void Sha256::process_block(const uint8_t* block) {
  uint32_t w[64];
  for (int i = 0; i < 16; ++i) {
    w[i] = (uint32_t(block[i * 4]) << 24) | (uint32_t(block[i * 4 + 1]) << 16) |
           (uint32_t(block[i * 4 + 2]) << 8) | uint32_t(block[i * 4 + 3]);
  }
  for (int i = 16; i < 64; ++i) {
    uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }

  uint32_t a = state_[0], b = state_[1], c = state_[2], d = state_[3];
  uint32_t e = state_[4], f = state_[5], g = state_[6], h = state_[7];

  for (int i = 0; i < 64; ++i) {
    uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t temp1 = h + s1 + ch + kK[i] + w[i];
    uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t temp2 = s0 + maj;
    h = g;
    g = f;
    f = e;
    e = d + temp1;
    d = c;
    c = b;
    b = a;
    a = temp1 + temp2;
  }

  state_[0] += a;
  state_[1] += b;
  state_[2] += c;
  state_[3] += d;
  state_[4] += e;
  state_[5] += f;
  state_[6] += g;
  state_[7] += h;
}

void Sha256::update(const uint8_t* data, size_t len) {
  bit_len_ += uint64_t(len) * 8;
  size_t offset = 0;
  if (buffer_len_ > 0) {
    size_t to_copy = 64 - buffer_len_;
    if (to_copy > len) to_copy = len;
    std::memcpy(buffer_ + buffer_len_, data, to_copy);
    buffer_len_ += to_copy;
    offset += to_copy;
    if (buffer_len_ == 64) {
      process_block(buffer_);
      buffer_len_ = 0;
    }
  }
  while (offset + 64 <= len) {
    process_block(data + offset);
    offset += 64;
  }
  if (offset < len) {
    std::memcpy(buffer_, data + offset, len - offset);
    buffer_len_ = len - offset;
  }
}

std::vector<uint8_t> Sha256::digest() {
  // Capture the true message length before appending padding -- padding bytes must
  // never flow through update() (that would inflate bit_len_ with the padding's own
  // length), so they are written directly into buffer_ here instead.
  const uint64_t bit_len = bit_len_;

  buffer_[buffer_len_++] = 0x80;
  if (buffer_len_ > 56) {
    while (buffer_len_ < 64) buffer_[buffer_len_++] = 0x00;
    process_block(buffer_);
    buffer_len_ = 0;
  }
  while (buffer_len_ < 56) buffer_[buffer_len_++] = 0x00;

  for (int i = 0; i < 8; ++i) {
    buffer_[56 + i] = uint8_t(bit_len >> (56 - i * 8));
  }
  process_block(buffer_);

  std::vector<uint8_t> out(32);
  for (int i = 0; i < 8; ++i) {
    out[i * 4] = uint8_t(state_[i] >> 24);
    out[i * 4 + 1] = uint8_t(state_[i] >> 16);
    out[i * 4 + 2] = uint8_t(state_[i] >> 8);
    out[i * 4 + 3] = uint8_t(state_[i]);
  }
  return out;
}

std::string to_hex(const std::vector<uint8_t>& bytes) {
  static const char* kHex = "0123456789abcdef";
  std::string out;
  out.reserve(bytes.size() * 2);
  for (uint8_t b : bytes) {
    out.push_back(kHex[b >> 4]);
    out.push_back(kHex[b & 0x0f]);
  }
  return out;
}

std::string hex_digest_of_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return "";
  Sha256 sha;
  uint8_t buf[65536];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    sha.update(buf, n);
  }
  std::fclose(f);
  return to_hex(sha.digest());
}

}  // namespace instaham_ml
