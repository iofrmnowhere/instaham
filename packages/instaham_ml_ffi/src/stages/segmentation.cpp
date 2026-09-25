#include "stages/segmentation.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "stages/canvas_scale.h"
#include "stages/mask_geometry.h"
#include "util/image_io.h"

namespace instaham_ml {
namespace stages {
namespace {

struct Candidate {
  SegmentationBox box;
  std::vector<float> coeffs;
};

float iou(const SegmentationBox& a, const SegmentationBox& b) {
  float ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2, ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
  float bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2, bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;
  float ix1 = std::max(ax1, bx1), iy1 = std::max(ay1, by1);
  float ix2 = std::min(ax2, bx2), iy2 = std::min(ay2, by2);
  float iw = std::max(0.f, ix2 - ix1), ih = std::max(0.f, iy2 - iy1);
  float inter = iw * ih;
  float area_a = std::max(0.f, ax2 - ax1) * std::max(0.f, ay2 - ay1);
  float area_b = std::max(0.f, bx2 - bx1) * std::max(0.f, by2 - by1);
  float uni = area_a + area_b - inter;
  return uni <= 0.f ? 0.f : inter / uni;
}

std::vector<Candidate> non_max_suppression(std::vector<Candidate> dets, float iou_threshold) {
  std::sort(dets.begin(), dets.end(),
            [](const Candidate& a, const Candidate& b) { return a.box.conf > b.box.conf; });
  std::vector<Candidate> kept;
  std::vector<bool> suppressed(dets.size(), false);
  for (size_t i = 0; i < dets.size(); ++i) {
    if (suppressed[i]) continue;
    kept.push_back(dets[i]);
    for (size_t j = i + 1; j < dets.size(); ++j) {
      if (!suppressed[j] && iou(dets[i].box, dets[j].box) > iou_threshold) suppressed[j] = true;
    }
  }
  return kept;
}

// Area (in proto-resolution pixels, threshold 0.5) of one candidate's mask -- the same
// selection criterion as ML.pipeline.segmentation._largest_mask_index (area of the
// thresholded native mask, not confidence). ref_fix.md F12: the Python reference measures
// this on ultralytics' `result.masks.data`, which by that point has already been CROPPED to
// the candidate's own detection box (process_mask's crop_mask(), before the upsample). This
// crops identically, via mask_geometry.h's proto_box_bounds() + cropped_mask_area() --
// exactly what construct_pig_mask() (construction.cpp) uses to build the mask it keeps --
// so selection and construction can never silently diverge on which pixels count again.
long long mask_area(const Candidate& c, const std::vector<float>& proto, int proto_h,
                     int proto_w, int model_imgsz) {
  const ProtoBoxBounds bounds = proto_box_bounds(c.box, proto_w, proto_h, model_imgsz);
  return cropped_mask_area(c.coeffs, proto, proto_h, proto_w, bounds);
}

}  // namespace

bool run_segmentation(OnnxRunner* runner, const SegmentationCapability& cap,
                      const std::string& image_path, double cm_per_px_actual,
                      double input_cm_per_px, float conf_threshold_override,
                      SegmentationOutput* out, std::string* error) {
  out->has_detection = false;

  RgbImage img;
  if (!decode_image_rgb(image_path, &img, error)) return false;
  out->orig_w = img.width;
  out->orig_h = img.height;

  float scale;
  int pad_left, pad_top;
  RgbImage lb;

  // docs/fix-phase-4/1.1-readme-is-the-path.md: normalize the photograph to
  // `input_cm_per_px` (here meaning cm_per_px_target -- see run_segmentation's doc
  // comment) BEFORE the canvas is composed, per README sections 2-8 and 13. This is the
  // only composition run_segmentation performs; there is no fallback and no ladder here --
  // a caller wanting a retry ladder builds it by calling this function again (README
  // section 13 is a single pass at one scale per call).
  // decide_normalize_first_composition() is the pure arithmetic (offsets, rotation, the
  // README section 6 fit check); this just executes it.
  const NormalizeFirstComposition comp =
      decide_normalize_first_composition(img.width, img.height, cm_per_px_actual, input_cm_per_px);
  if (!comp.valid) {
    if (comp.oversize) {
      out->oversize = true;
      out->normalized_w = comp.normalized_w;
      out->normalized_h = comp.normalized_h;
      out->canvas_w_requested = comp.canvas_w_requested;
      out->canvas_h_requested = comp.canvas_h_requested;
      if (error) {
        *error = "oversize: normalized content " + std::to_string(comp.content_w) + "x" +
                 std::to_string(comp.content_h) + " exceeds the " +
                 std::to_string(comp.canvas_w_requested) + "x" +
                 std::to_string(comp.canvas_h_requested) +
                 " canvas (README section 6 halt, not enlarged or shrunk)";
      }
    } else if (error) {
      *error = "normalize_first: missing or non-finite cm_per_px_actual/cm_per_px_target";
    }
    return false;
  }
  RgbImage normalized = resize_uniform(img, float(comp.resize_factor));
  RgbImage content = comp.rotated_clockwise ? rotate90_cw(normalized) : std::move(normalized);
  RgbImage canvas = place_at_offset(content, comp.canvas_w, comp.canvas_h, cap.letterbox_color,
                                     comp.x_offset, comp.y_offset);

  // The canvas is already at the target physical scale, so it only needs a plain
  // whole-frame fit into the model's imgsz x imgsz input -- composing that fit with the
  // content's offset on the canvas collapses to one scale + one translated pad, exactly
  // the affine construct_pig_mask() / transform_mask_to_training_space() already expect
  // (they read `letterbox_scale`/`letterbox_pad_left`/`letterbox_pad_top`/`orig_w`/
  // `orig_h` generically): model_x = canvas_scale * (x_offset + content_x) + canvas_pad
  //                               = canvas_scale * content_x + (canvas_scale * x_offset + canvas_pad)
  float canvas_scale;
  int canvas_pad_left, canvas_pad_top;
  lb = letterbox(canvas, cap.imgsz, cap.imgsz, cap.letterbox_color, &canvas_scale, &canvas_pad_left,
                  &canvas_pad_top);
  scale = canvas_scale;
  pad_left = int(std::round(canvas_scale * comp.x_offset)) + canvas_pad_left;
  pad_top = int(std::round(canvas_scale * comp.y_offset)) + canvas_pad_top;

  out->orig_w = content.width;
  out->orig_h = content.height;
  out->used_normalize_first = true;
  out->was_rotated_clockwise = comp.rotated_clockwise;
  out->canvas_w = comp.canvas_w;
  out->canvas_h = comp.canvas_h;
  out->canvas_w_requested = comp.canvas_w_requested;
  out->canvas_h_requested = comp.canvas_h_requested;
  out->input_cm_per_px_used = input_cm_per_px;
  out->content_scale = float(comp.resize_factor);
  // docs/fix-phase-4/5-debug-and-assertions.md: set on every run, not only the oversize
  // halt path above -- see SegmentationOutput::normalized_w/h's own doc comment.
  out->normalized_w = comp.normalized_w;
  out->normalized_h = comp.normalized_h;
  out->x_offset = comp.x_offset;
  out->y_offset = comp.y_offset;
  out->letterbox_scale = scale;
  out->letterbox_pad_left = pad_left;
  out->letterbox_pad_top = pad_top;
  out->model_imgsz = cap.imgsz;

  const float conf_threshold = conf_threshold_override > 0.0f ? conf_threshold_override
                                                                : cap.conf_threshold;

  std::vector<float> tensor(size_t(3) * cap.imgsz * cap.imgsz);
  for (int c = 0; c < 3; ++c) {
    for (int y = 0; y < cap.imgsz; ++y) {
      for (int x = 0; x < cap.imgsz; ++x) {
        uint8_t v = lb.pixels[(size_t(y) * cap.imgsz + x) * 3 + c];
        tensor[size_t(c) * cap.imgsz * cap.imgsz + size_t(y) * cap.imgsz + x] = float(v) / 255.0f;
      }
    }
  }
  std::vector<int64_t> shape = {1, 3, cap.imgsz, cap.imgsz};

  std::vector<OutputTensor> outputs;
  if (!runner->run(tensor, shape, &outputs, error) || outputs.size() < 2) {
    if (error && error->empty()) *error = "segmentation model did not return a proto tensor";
    return false;
  }

  // outputs[0]: [1, 4+nc+32, num_anchors]; outputs[1]: [1, 32, proto_h, proto_w]. ref_fix.md
  // F13: `nc` (class count) is derived, not assumed to be 1 -- the current pig model IS
  // single-class, so this was not the cause of the mask-shrink bug F12 fixes, but the old
  // hardcoded "conf at channel 4, coeffs at channel 5+k" would silently misread both
  // class-score and coefficient channels for any future multi-class export, producing
  // exactly the same kind of nonsense mask with no error raised.
  const OutputTensor& box_mask = outputs[0];
  const OutputTensor& proto_t = outputs[1];
  if (box_mask.shape.size() != 3 || proto_t.shape.size() != 4) {
    if (error) *error = "unexpected segmentation output shape";
    return false;
  }
  int64_t channels = box_mask.shape[1];
  int64_t num_anchors = box_mask.shape[2];
  int num_coeffs = int(proto_t.shape[1]);
  int proto_h = int(proto_t.shape[2]);
  int proto_w = int(proto_t.shape[3]);
  const int64_t num_classes = channels - 4 - int64_t(num_coeffs);
  if (num_classes < 1) {
    if (error) *error = "segmentation output channel count disagrees with proto coefficient count";
    return false;
  }
  const float* data = box_mask.data.data();

  std::vector<Candidate> candidates;
  for (int64_t a = 0; a < num_anchors; ++a) {
    float conf = data[4 * num_anchors + a];
    for (int64_t cls = 1; cls < num_classes; ++cls) {
      conf = std::max(conf, data[(4 + cls) * num_anchors + a]);
    }
    if (conf < conf_threshold) continue;
    Candidate c;
    c.box.cx = data[0 * num_anchors + a];
    c.box.cy = data[1 * num_anchors + a];
    c.box.w = data[2 * num_anchors + a];
    c.box.h = data[3 * num_anchors + a];
    c.box.conf = conf;
    c.coeffs.resize(num_coeffs);
    for (int k = 0; k < num_coeffs; ++k) {
      c.coeffs[k] = data[size_t(4 + num_classes + k) * num_anchors + a];
    }
    candidates.push_back(std::move(c));
  }

  std::vector<Candidate> kept = non_max_suppression(std::move(candidates), cap.iou_threshold);
  out->candidates_kept = int(kept.size());
  if (kept.empty()) return true;  // has_detection stays false -- not an error, no instance

  // Select by mask area, not confidence -- matches
  // ML.pipeline.segmentation._largest_mask_index's selection criterion. ref_fix.md F15:
  // the winning and runner-up areas are recorded (out->selected_mask_area_proto /
  // out->runner_up_mask_area_proto below) so a near-tie -- the shape F12's bug takes --
  // is visible in the envelope without a code read.
  size_t best = 0;
  long long best_area = -1;
  long long runner_up_area = -1;
  for (size_t i = 0; i < kept.size(); ++i) {
    long long a = mask_area(kept[i], proto_t.data, proto_h, proto_w, cap.imgsz);
    if (a > best_area) {
      runner_up_area = best_area;
      best_area = a;
      best = i;
    } else if (a > runner_up_area) {
      runner_up_area = a;
    }
  }

  out->has_detection = true;
  out->box = kept[best].box;
  out->mask_coeffs = std::move(kept[best].coeffs);
  out->proto = proto_t.data;
  out->proto_h = proto_h;
  out->proto_w = proto_w;
  out->num_coeffs = num_coeffs;
  out->selected_mask_area_proto = best_area;
  out->runner_up_mask_area_proto = std::max<long long>(0, runner_up_area);

  // ref_fix.md F15: the selected box in ORIGINAL image pixels, and its area as a fraction
  // of the whole frame -- the number F16's plausibility gate reads, and the one that would
  // have immediately named F12's bug (~0.6% and ~9% of frame for the two broken photos,
  // vs. ~55% for the one that worked).
  const float x0_model = out->box.cx - out->box.w / 2.f;
  const float y0_model = out->box.cy - out->box.h / 2.f;
  const float x1_model = out->box.cx + out->box.w / 2.f;
  const float y1_model = out->box.cy + out->box.h / 2.f;
  auto to_orig_x = [&](float v) {
    return std::clamp((v - float(out->letterbox_pad_left)) / out->letterbox_scale, 0.f,
                       float(out->orig_w));
  };
  auto to_orig_y = [&](float v) {
    return std::clamp((v - float(out->letterbox_pad_top)) / out->letterbox_scale, 0.f,
                       float(out->orig_h));
  };
  out->selected_box_orig_x0 = to_orig_x(x0_model);
  out->selected_box_orig_y0 = to_orig_y(y0_model);
  out->selected_box_orig_x1 = to_orig_x(x1_model);
  out->selected_box_orig_y1 = to_orig_y(y1_model);
  const double box_area = double(out->selected_box_orig_x1 - out->selected_box_orig_x0) *
                           double(out->selected_box_orig_y1 - out->selected_box_orig_y0);
  const double frame_area = double(out->orig_w) * double(out->orig_h);
  out->selected_box_frame_fraction = frame_area > 0.0 ? float(box_area / frame_area) : 0.f;
  return true;
}

}  // namespace stages
}  // namespace instaham_ml
