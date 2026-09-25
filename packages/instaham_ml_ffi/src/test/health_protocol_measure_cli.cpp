// docs/plan-phase-3/3-measurement.md: runs the health classifier three times -- full_frame,
// segmentation_crop, segmentation_masked -- over the SAME real capture and the SAME
// segmentation mask, through the actual shipped stages (stages::run_segmentation,
// stages::construct_pig_mask, stages::rotate_pig_mask_90_ccw, pig_region_from_base_mask,
// classifier.cpp's run_classifier), not a Python reimplementation. This is what phase 3's
// own doc requires: "the whole point is to measure the shipped code."
//
// This mirrors ML/host_scale_test/weight_branch_cli.cpp's pattern (same segmentation call,
// same manifest loading) but for the health branch instead of the weight branch, and reuses
// health_input.h's pig_region_from_base_mask() (docs/plan-phase-3/2.1-recovery-helper.md)
// rather than re-deriving the BASE_MASK-to-original recovery a third time.
//
// Usage: health_protocol_measure_cli <manifest_path> <image_path> <cm_per_px_actual>
//                                     [dump_dir]
// Prints one JSON object to stdout. Diagnostics go to stderr. Exit 0 once an envelope was
// produced (even with mask_available=false -- that is itself a result, not a failure this
// CLI reports); exit 2 on argument/load failure.
//
// `dump_dir`, if given (user question, 2026-09-24 -- "let me see if the recovered mask
// matches"): writes viewable BMPs so mask alignment and each protocol's actual model input
// can be inspected by eye, not just by number. See dump_debug_images() below for the file
// list. This is the one place in this CLI that needs opencv_imgcodecs (cv::imwrite) -- no
// other target in this tree writes images, since the app itself has no image encoder
// (health_input_gate_cli.cpp's header comment).

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "classifier.h"
#include "health_input.h"
#include "manifest.h"
#include "onnx_runner.h"
#include "stages/construction.h"
#include "stages/segmentation.h"
#include "third_party/nlohmann_json/single_include/nlohmann/json.hpp"
#include "util/image_io.h"

using json = nlohmann::json;
using namespace instaham_ml;

namespace {

// ImageNet-mean fill, same constant health_input.cpp's imagenet_mean_rgb_uint8() uses -- the
// manifest's own default background_fill.
void imagenet_mean_rgb_uint8(uint8_t out_rgb[3]) {
  static constexpr float kImagenetMean[3] = {0.485f, 0.456f, 0.406f};
  for (int c = 0; c < 3; ++c) out_rgb[c] = uint8_t(std::lround(kImagenetMean[c] * 255.0f));
}

// Resamples `region`'s mask (its own mask_w x mask_h, BASE_MASK space) up to `w` x `h` --
// used both by run_masked_no_crop() below and by dump_debug_images() for the visual
// overlay, so the two use the exact same resample, not two copies that could drift apart.
cv::Mat resample_mask_to_size(const PigRegion& region, int w, int h) {
  cv::Mat mask_in(region.mask_h, region.mask_w, CV_8UC1, const_cast<uint8_t*>(region.mask));
  cv::Mat mask_full;
  cv::resize(mask_in, mask_full, cv::Size(w, h), 0, 0, cv::INTER_NEAREST);
  return mask_full;
}

// Paints every pixel outside `mask_full` (0/255, already resampled to img's own size)
// `fill_rgb`, leaving pixels inside the mask at their original colour and coordinates --
// no crop, no padding, no resize. This is background-removal in isolation, independent of
// segmentation_masked's crop.
RgbImage build_masked_full(const RgbImage& img, const cv::Mat& mask_full,
                            const uint8_t fill_rgb[3]) {
  RgbImage out = img;
  for (int y = 0; y < img.height; ++y) {
    const uint8_t* mask_row = mask_full.ptr<uint8_t>(y);
    for (int x = 0; x < img.width; ++x) {
      if (mask_row[x] == 0) {
        uint8_t* p = &out.pixels[(size_t(y) * img.width + x) * 3];
        p[0] = fill_rgb[0];
        p[1] = fill_rgb[1];
        p[2] = fill_rgb[2];
      }
    }
  }
  return out;
}

// Writes `img` (RGB, health_input.h's own convention) as a BMP -- cv::imwrite expects BGR.
// BMP, not PNG: this vcpkg OpenCV build has no PNG encoder registered
// (ML/host_scale_test/weight_branch_cli.cpp's --dump-stages hit the same limit first).
bool save_rgb_bmp(const std::string& path, const RgbImage& img) {
  if (img.width <= 0 || img.height <= 0) return false;
  cv::Mat rgb(img.height, img.width, CV_8UC3, const_cast<uint8_t*>(img.pixels.data()));
  cv::Mat bgr;
  cv::cvtColor(rgb, bgr, cv::COLOR_RGB2BGR);
  return cv::imwrite(path, bgr);
}

// User question, 2026-09-24: "let me see if the recovered mask matches" / "what the image
// looks like if background was only removed". Writes, for one capture, into `dump_dir`
// (created if missing):
//   <stem>_00_original.bmp              -- the decoded photo, untouched
//   <stem>_01_mask_overlay.bmp          -- original with everything OUTSIDE the recovered
//                                          mask tinted red at half strength -- the direct
//                                          answer to "does the recovered mask match the
//                                          pig": a correct recovery leaves the pig itself
//                                          untinted and tints everything else.
//   <stem>_02_background_removed_full.bmp -- background painted imagenet_mean, full
//                                          captured-frame size, NOT cropped -- what
//                                          run_masked_no_crop() actually classifies.
//   <stem>_03_crop_full_frame.bmp       -- the 224x224 the model gets under full_frame.
//   <stem>_04_crop_segmentation_crop.bmp   -- ditto, segmentation_crop.
//   <stem>_05_crop_segmentation_masked.bmp -- ditto, segmentation_masked.
// The three "crop" files are prepare_health_input()'s own output -- the exact pixels
// run_classifier() feeds the model for each protocol, not a re-derivation.
void dump_debug_images(const std::string& dump_dir, const std::string& stem,
                        const RgbImage& img, const PigRegion* region,
                        const ClassifierCapability& cap) {
  std::error_code ec;
  std::filesystem::create_directories(dump_dir, ec);
  const std::string prefix = dump_dir + "/" + stem;

  save_rgb_bmp(prefix + "_00_original.bmp", img);

  if (region != nullptr && region->has_mask && region->mask != nullptr) {
    cv::Mat mask_full = resample_mask_to_size(*region, img.width, img.height);

    RgbImage overlay = img;
    for (int y = 0; y < img.height; ++y) {
      const uint8_t* mask_row = mask_full.ptr<uint8_t>(y);
      for (int x = 0; x < img.width; ++x) {
        if (mask_row[x] == 0) {
          uint8_t* p = &overlay.pixels[(size_t(y) * img.width + x) * 3];
          p[0] = uint8_t(std::min(255, p[0] + (255 - p[0]) / 2));  // tint red
          p[1] = uint8_t(p[1] / 2);
          p[2] = uint8_t(p[2] / 2);
        }
      }
    }
    save_rgb_bmp(prefix + "_01_mask_overlay.bmp", overlay);

    uint8_t fill_rgb[3];
    imagenet_mean_rgb_uint8(fill_rgb);
    save_rgb_bmp(prefix + "_02_background_removed_full.bmp",
                 build_masked_full(img, mask_full, fill_rgb));
  }

  const HealthInput full = prepare_health_input(img, HealthInputProtocol::kFullFrame, nullptr,
                                                 cap.resize_shorter_side, cap.input_size);
  save_rgb_bmp(prefix + "_03_crop_full_frame.bmp", full.image);

  if (region != nullptr) {
    const HealthInput crop =
        prepare_health_input(img, HealthInputProtocol::kSegmentationCrop, region,
                              cap.resize_shorter_side, cap.input_size,
                              cap.health_bbox_padding_ratio, cap.health_background_fill);
    save_rgb_bmp(prefix + "_04_crop_segmentation_crop.bmp", crop.image);

    const HealthInput masked =
        prepare_health_input(img, HealthInputProtocol::kSegmentationMasked, region,
                              cap.resize_shorter_side, cap.input_size,
                              cap.health_bbox_padding_ratio, cap.health_background_fill);
    save_rgb_bmp(prefix + "_05_crop_segmentation_masked.bmp", masked.image);
  }

  std::fprintf(stderr, "dumped debug images to %s/%s_*.bmp\n", dump_dir.c_str(), stem.c_str());
}

// Runs one protocol and folds classifier.cpp's own JSON envelope down to the fields phase
// 3's doc asks for (label, confidence, P(Healthy), the full probability vector) plus the
// reporting fields AGENTS.md requires never be papered over (protocol_applied, degraded,
// region_source) -- never re-deriving them, only reading what run_classifier already says
// actually ran.
json run_one_protocol(OnnxRunner* health_runner, const ClassifierCapability& health_cap,
                       const std::string& image_path, HealthInputProtocol protocol,
                       const PigRegion* region) {
  HealthInputOptions opts;
  opts.protocol = protocol;
  opts.region = region;

  std::string raw;
  int err = 0;
  const bool ok = run_classifier(health_runner, health_cap, image_path, &raw, &err, &opts);
  json parsed = json::parse(raw, /*cb=*/nullptr, /*allow_exceptions=*/false);
  json out;
  out["protocol_requested"] = health_input_protocol_name(protocol);
  out["classifier_ok"] = ok;
  if (!ok || parsed.is_discarded()) {
    out["error"] = parsed.is_discarded() ? raw : parsed.value("message", raw);
    return out;
  }
  out["label"] = parsed.value("label", "");
  out["confidence"] = parsed.value("confidence", 0.0);
  const json& probs = parsed["probabilities"];
  out["p_healthy"] = probs.contains("Healthy") ? probs["Healthy"].get<double>() : -1.0;
  out["probabilities"] = probs;
  out["protocol_applied"] = parsed.value("input_protocol_applied", "");
  out["degraded"] = parsed.value("input_degraded", false);
  out["region_source"] = parsed.value("region_source", "");
  return out;
}

// Ad hoc follow-up (user question, 2026-09-24): remove the background but do NOT crop to
// the pig's box -- keep the full captured frame's own dimensions (so the model's usual
// resize-shorter-then-crop still runs over the whole scene, background masked out), rather
// than segmentation_masked's crop+mask combination. No protocol in health_input.h does
// this, so it is hand-assembled here from the same exported pieces prepare_health_input()
// and classifier.cpp use (resize_shorter_then_crop, decode_image_rgb, the runner), not by
// adding a fourth protocol to the shipped enum for a one-off question.
json run_masked_no_crop(OnnxRunner* health_runner, const ClassifierCapability& cap,
                         const std::string& image_path, const PigRegion* region) {
  json out;
  out["protocol_requested"] = "segmentation_masked_no_crop (ad hoc, not a shipped protocol)";
  if (region == nullptr || !region->has_mask || region->mask == nullptr) {
    out["error"] = "no mask available";
    out["classifier_ok"] = false;
    return out;
  }

  RgbImage img;
  std::string err;
  if (!decode_image_rgb(image_path, &img, &err)) {
    out["error"] = "decode failed: " + err;
    out["classifier_ok"] = false;
    return out;
  }

  // Resample the mask up to the FULL captured image's own dimensions -- not the padded pig
  // box, unlike crop_to_bbox()'s interior_mask_full(). Same helper dump_debug_images() uses
  // for its overlay/background-removed-full images, so the two stay in agreement.
  cv::Mat mask_full = resample_mask_to_size(*region, img.width, img.height);
  uint8_t fill_rgb[3];
  imagenet_mean_rgb_uint8(fill_rgb);
  RgbImage masked_full = build_masked_full(img, mask_full, fill_rgb);

  // From here on, the SAME preprocessing/tensor/softmax classifier.cpp's run_classifier()
  // uses for every other protocol (resize-shorter-then-crop, NCHW normalize, argmax).
  RgbImage prepped = resize_shorter_then_crop(masked_full, cap.resize_shorter_side, cap.input_size);
  std::vector<float> tensor(size_t(3) * cap.input_size * cap.input_size);
  for (int c = 0; c < 3; ++c) {
    for (int y = 0; y < cap.input_size; ++y) {
      for (int x = 0; x < cap.input_size; ++x) {
        uint8_t v = prepped.pixels[(size_t(y) * cap.input_size + x) * 3 + c];
        tensor[size_t(c) * cap.input_size * cap.input_size + size_t(y) * cap.input_size + x] =
            (float(v) * cap.scale - cap.mean[c]) / cap.std_dev[c];
      }
    }
  }
  std::vector<int64_t> shape = {1, 3, cap.input_size, cap.input_size};
  std::vector<OutputTensor> outputs;
  if (!health_runner->run(tensor, shape, &outputs, &err) || outputs.empty()) {
    out["error"] = "inference failed: " + err;
    out["classifier_ok"] = false;
    return out;
  }
  const std::vector<float>& logits = outputs[0].data;
  float max_logit = *std::max_element(logits.begin(), logits.end());
  std::vector<float> exps(logits.size());
  float sum = 0.f;
  for (size_t i = 0; i < logits.size(); ++i) {
    exps[i] = std::exp(logits[i] - max_logit);
    sum += exps[i];
  }
  size_t best = 0;
  json probabilities = json::object();
  for (size_t i = 0; i < logits.size() && i < cap.class_names.size(); ++i) {
    float p = exps[i] / sum;
    probabilities[cap.class_names[i]] = p;
    if (p > exps[best] / sum) best = i;
  }
  out["classifier_ok"] = true;
  out["label"] = cap.class_names[best];
  out["confidence"] = double(exps[best] / sum);
  out["p_healthy"] = probabilities.contains("Healthy") ? probabilities["Healthy"].get<double>() : -1.0;
  out["probabilities"] = probabilities;
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 4) {
    std::fprintf(stderr,
                  "usage: %s <manifest_path> <image_path> <cm_per_px_actual>\n", argv[0]);
    return 2;
  }
  const std::string manifest_path = argv[1];
  const std::string image_path = argv[2];
  const double cm_per_px_actual = std::atof(argv[3]);

  json envelope;
  envelope["image"] = image_path;

  Manifest manifest;
  std::string error;
  int error_code = 0;
  if (!load_manifest(manifest_path, &manifest, &error, &error_code)) {
    std::fprintf(stderr, "load_manifest failed: %s (code %d)\n", error.c_str(), error_code);
    return 2;
  }
  if (!manifest.health.available) {
    std::fprintf(stderr, "manifest.health is not available\n");
    return 2;
  }

  OnnxRunner seg_runner;
  std::string seg_load_error;
  if (!seg_runner.load(manifest.segmentation.model_path, &seg_load_error)) {
    std::fprintf(stderr, "segmentation model load failed: %s\n", seg_load_error.c_str());
    return 2;
  }
  OnnxRunner health_runner;
  std::string health_load_error;
  if (!health_runner.load(manifest.health.model_path, &health_load_error)) {
    std::fprintf(stderr, "health model load failed: %s\n", health_load_error.c_str());
    return 2;
  }

  // ---- segmentation: the SAME call pipeline.cpp makes for the dorsal route (README
  // section 13's single normalize-first pass; see weight_branch_cli.cpp's identical use).
  stages::SegmentationOutput seg;
  std::string seg_error;
  bool mask_available = false;
  PigRegion region;
  // Declared here, not inside the block below: region.mask (set a few lines down) points
  // into pig_mask.pixels' storage, and region is read by run_one_protocol() further down,
  // after that block would otherwise have ended -- pig_mask must outlive every use of
  // region, or region.mask dangles.
  stages::PigMask pig_mask;

  const bool seg_ok = run_segmentation(&seg_runner, manifest.segmentation, image_path,
                                        cm_per_px_actual, manifest.weight.cm_per_px_target,
                                        /*conf_threshold_override=*/0.0f, &seg, &seg_error);
  if (!seg_ok) {
    envelope["segmentation_status"] = seg.oversize ? "oversize" : "no_detection_or_error";
    envelope["segmentation_error"] = seg_error;
  } else if (!seg.has_detection) {
    envelope["segmentation_status"] = "no_detection";
  } else {
    stages::PigMask raw_mask = stages::construct_pig_mask(seg);
    pig_mask = stages::rotate_pig_mask_90_ccw(raw_mask, seg.was_rotated_clockwise);
    if (pig_mask.empty()) {
      envelope["segmentation_status"] = "empty_mask";
    } else {
      // docs/plan-phase-3/2.1-recovery-helper.md: the same helper pipeline.cpp calls, not
      // a copy of its arithmetic.
      mask_available = pig_region_from_base_mask(
          pig_mask.bbox_x, pig_mask.bbox_y, pig_mask.bbox_w, pig_mask.bbox_h,
          pig_mask.pixels.data(), pig_mask.width, pig_mask.height, seg.content_scale, &region);
      if (mask_available && !region.valid()) mask_available = false;
      envelope["segmentation_status"] = mask_available ? "ok" : "recovery_failed";
      envelope["content_scale"] = seg.content_scale;
      envelope["recovered_bbox"] = {region.x0, region.y0, region.x1, region.y1};
      // Diagnostic only (docs/plan-phase-3/3-measurement.md investigation): how much of
      // its own bounding box the mask actually fills, in BASE_MASK space -- a near-1.0
      // fill ratio means the silhouette is close to its own bbox rectangle, which is the
      // one condition under which segmentation_crop and segmentation_masked can end up
      // visually identical after mean-fill + resize.
      envelope["mask_area_px"] = pig_mask.area_px;
      envelope["mask_bbox_area_px"] = (long long)pig_mask.bbox_w * pig_mask.bbox_h;
      envelope["mask_fill_ratio"] = pig_mask.bbox_w > 0 && pig_mask.bbox_h > 0
                                         ? double(pig_mask.area_px) /
                                               (double(pig_mask.bbox_w) * pig_mask.bbox_h)
                                         : -1.0;
      envelope["region_has_mask"] = region.has_mask;
      envelope["region_mask_w"] = region.mask_w;
      envelope["region_mask_h"] = region.mask_h;
    }
  }
  envelope["mask_available"] = mask_available;

  const PigRegion* region_ptr = mask_available ? &region : nullptr;

  // Ad hoc follow-up (user question, 2026-09-24): does the fill colour matter, not just the
  // masking itself? health_input.cpp's crop_to_bbox() defaults fill_rgb to {0,0,0} for any
  // background_fill string other than "imagenet_mean" -- so a plain capability copy with
  // "black" exercises the real code path, no health_input.cpp change needed.
  ClassifierCapability health_black = manifest.health;
  health_black.health_background_fill = "black";

  envelope["results"] = {
      {"full_frame",
       run_one_protocol(&health_runner, manifest.health, image_path,
                         HealthInputProtocol::kFullFrame, region_ptr)},
      {"segmentation_crop",
       run_one_protocol(&health_runner, manifest.health, image_path,
                         HealthInputProtocol::kSegmentationCrop, region_ptr)},
      {"segmentation_masked",
       run_one_protocol(&health_runner, manifest.health, image_path,
                         HealthInputProtocol::kSegmentationMasked, region_ptr)},
      {"segmentation_masked_black",
       run_one_protocol(&health_runner, health_black, image_path,
                         HealthInputProtocol::kSegmentationMasked, region_ptr)},
      {"segmentation_masked_no_crop",
       run_masked_no_crop(&health_runner, manifest.health, image_path, region_ptr)},
  };

  // docs/plan-phase-4/2-host-verification.md: exercises the SAME run_health_cascade()
  // pipeline.cpp now calls -- not a re-derivation of its decision logic. Three checks:
  //
  //   "cascade_natural"      -- the manifest exactly as shipped. On the three real dorsal
  //                             captures this always resolves not_needed_healthy, so the
  //                             top-level label/confidence/probabilities here must equal
  //                             "results.full_frame" above (check 1: healthy results are
  //                             unchanged).
  //   "cascade_forced"       -- a plain capability copy (no health_input.cpp/classifier.cpp
  //                             change, same trick health_black above uses) whose
  //                             healthy_label matches no real class, so the cascade always
  //                             runs its second stage when a mask is available. The final
  //                             label/probabilities here must equal "results.
  //                             segmentation_masked" above (check 2: the cascade's second
  //                             pass reproduces round 3's own masked measurement).
  //   "cascade_forced_no_region" -- the same forced-healthy-label capability, but with a
  //                             null region, matching exactly what pipeline.cpp passes on
  //                             the health_only route (no segmentation at all). Must report
  //                             second_stage == "no_region" and fall back to the first
  //                             pass's own label (check 3).
  auto run_cascade = [&](const ClassifierCapability& cap, const PigRegion* r) {
    std::string raw;
    int err = 0;
    run_health_cascade(&health_runner, cap, image_path, r, &raw, &err);
    json parsed = json::parse(raw, /*cb=*/nullptr, /*allow_exceptions=*/false);
    json out;
    out["classifier_ok"] = !parsed.is_discarded() && parsed.value("status", "") == "ok";
    if (parsed.is_discarded()) {
      out["error"] = raw;
      return out;
    }
    out["label"] = parsed.value("label", "");
    out["confidence"] = parsed.value("confidence", 0.0);
    const json probs = parsed.value("probabilities", json::object());
    out["p_healthy"] = probs.contains("Healthy") ? probs["Healthy"].get<double>() : -1.0;
    out["probabilities"] = probs;
    out["cascade"] = parsed.value("cascade", json::object());
    return out;
  };

  ClassifierCapability health_cascade_forced = manifest.health;
  health_cascade_forced.health_cascade_enabled = true;
  health_cascade_forced.health_healthy_label = "__no_such_class__";
  health_cascade_forced.health_second_stage_protocol = "segmentation_masked";

  envelope["cascade_natural"] = run_cascade(manifest.health, region_ptr);
  envelope["cascade_forced"] = run_cascade(health_cascade_forced, region_ptr);
  envelope["cascade_forced_no_region"] = run_cascade(health_cascade_forced, nullptr);

  if (argc >= 5) {
    RgbImage img;
    std::string decode_err;
    if (decode_image_rgb(image_path, &img, &decode_err)) {
      std::string stem = std::filesystem::path(image_path).stem().string();
      dump_debug_images(argv[4], stem, img, region_ptr, manifest.health);
      envelope["dump_dir"] = argv[4];
    } else {
      std::fprintf(stderr, "dump requested but decode failed: %s\n", decode_err.c_str());
    }
  }

  std::printf("%s\n", envelope.dump().c_str());
  return 0;
}
