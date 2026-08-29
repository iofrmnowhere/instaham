#ifndef INSTAHAM_ML_ONNX_RUNNER_H
#define INSTAHAM_ML_ONNX_RUNNER_H

#include <memory>
#include <string>
#include <vector>

// Forward-declare rather than pull onnxruntime_cxx_api.h into every translation unit that
// only needs to hold an OnnxRunner by pointer.
namespace Ort {
struct Env;
struct Session;
}  // namespace Ort

namespace instaham_ml {

// A single named output tensor, copied out of ORT-owned memory immediately after Run() so
// the caller does not need to reason about Ort::Value lifetime.
struct OutputTensor {
  std::vector<float> data;
  std::vector<int64_t> shape;
};

// Thin wrapper: one ORT session, tensors in, tensors out. Knows nothing about what the
// tensors mean (section 3 of the plan: models/ layer, not capabilities/).
class OnnxRunner {
 public:
  OnnxRunner();
  ~OnnxRunner();
  OnnxRunner(const OnnxRunner&) = delete;
  OnnxRunner& operator=(const OnnxRunner&) = delete;

  bool load(const std::string& model_path, std::string* error);

  // Runs the (single-input) session on `input_data` reshaped to `input_shape`, returning
  // every output tensor in declaration order. Returns false and sets *error on failure.
  bool run(const std::vector<float>& input_data, const std::vector<int64_t>& input_shape,
           std::vector<OutputTensor>* outputs, std::string* error);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace instaham_ml

#endif  // INSTAHAM_ML_ONNX_RUNNER_H
