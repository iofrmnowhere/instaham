#include "onnx_runner.h"

#include <onnxruntime_cxx_api.h>

#include <numeric>

namespace instaham_ml {
namespace {

// One process-wide Ort::Env (ORT requires exactly one; creating a second logs a warning
// and is wasteful). Constructed on first use, destroyed at process exit.
Ort::Env& shared_env() {
  static Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "instaham_ml");
  return env;
}

}  // namespace

struct OnnxRunner::Impl {
  std::unique_ptr<Ort::Session> session;
  std::vector<std::string> input_names;
  std::vector<std::string> output_names;
};

OnnxRunner::OnnxRunner() : impl_(std::make_unique<Impl>()) {}
OnnxRunner::~OnnxRunner() = default;

bool OnnxRunner::load(const std::string& model_path, std::string* error) {
  try {
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

#ifdef _WIN32
    std::wstring wpath(model_path.begin(), model_path.end());
    impl_->session = std::make_unique<Ort::Session>(shared_env(), wpath.c_str(), options);
#else
    impl_->session = std::make_unique<Ort::Session>(shared_env(), model_path.c_str(), options);
#endif

    Ort::AllocatorWithDefaultOptions allocator;
    size_t n_in = impl_->session->GetInputCount();
    for (size_t i = 0; i < n_in; ++i) {
      auto name = impl_->session->GetInputNameAllocated(i, allocator);
      impl_->input_names.emplace_back(name.get());
    }
    size_t n_out = impl_->session->GetOutputCount();
    for (size_t i = 0; i < n_out; ++i) {
      auto name = impl_->session->GetOutputNameAllocated(i, allocator);
      impl_->output_names.emplace_back(name.get());
    }
    return true;
  } catch (const Ort::Exception& e) {
    if (error) *error = std::string("ORT session load failed: ") + e.what();
    return false;
  }
}

bool OnnxRunner::run(const std::vector<float>& input_data, const std::vector<int64_t>& input_shape,
                      std::vector<OutputTensor>* outputs, std::string* error) {
  if (!impl_->session) {
    if (error) *error = "session not loaded";
    return false;
  }
  try {
    Ort::MemoryInfo mem_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        mem_info, const_cast<float*>(input_data.data()), input_data.size(), input_shape.data(),
        input_shape.size());

    std::vector<const char*> input_name_ptrs;
    for (auto& n : impl_->input_names) input_name_ptrs.push_back(n.c_str());
    std::vector<const char*> output_name_ptrs;
    for (auto& n : impl_->output_names) output_name_ptrs.push_back(n.c_str());

    auto ort_outputs = impl_->session->Run(Ort::RunOptions{nullptr}, input_name_ptrs.data(),
                                            &input_tensor, 1, output_name_ptrs.data(),
                                            output_name_ptrs.size());

    outputs->clear();
    outputs->reserve(ort_outputs.size());
    for (auto& val : ort_outputs) {
      OutputTensor t;
      auto info = val.GetTensorTypeAndShapeInfo();
      t.shape = info.GetShape();
      size_t count = size_t(info.GetElementCount());
      const float* data = val.GetTensorData<float>();
      t.data.assign(data, data + count);
      outputs->push_back(std::move(t));
    }
    return true;
  } catch (const Ort::Exception& e) {
    if (error) *error = std::string("ORT Run() failed: ") + e.what();
    return false;
  }
}

}  // namespace instaham_ml
