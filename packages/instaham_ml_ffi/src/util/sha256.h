#ifndef INSTAHAM_ML_UTIL_SHA256_H
#define INSTAHAM_ML_UTIL_SHA256_H

#include <cstdint>
#include <string>
#include <vector>

namespace instaham_ml {

// Self-contained SHA-256 (FIPS 180-4), no external dependency. The manifest's sha256
// fields are compared against `hex_digest_of_file`, which is the only entry point that
// matters to callers; `Sha256` is exposed for the (rare) in-memory buffer case.
class Sha256 {
 public:
  Sha256();
  void update(const uint8_t* data, size_t len);
  // Finalizes and returns the 32-byte digest. Calling update() after this is undefined.
  std::vector<uint8_t> digest();

 private:
  void process_block(const uint8_t* block);

  uint32_t state_[8];
  uint64_t bit_len_ = 0;
  uint8_t buffer_[64];
  size_t buffer_len_ = 0;
};

std::string to_hex(const std::vector<uint8_t>& bytes);

// Reads `path` in chunks and returns its lowercase hex sha256 digest, or an empty string
// if the file could not be opened.
std::string hex_digest_of_file(const std::string& path);

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_UTIL_SHA256_H
