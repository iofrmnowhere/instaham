#include "stages/cutter.h"

#include <algorithm>
#include <cstddef>
#include <stdexcept>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include "vendor/instaham_v176/include/instaham/Common.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/Break1Fit.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/CircleCutterV144.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/CutterTypes.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/OutlineBuilder.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/SelleFilter.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/ShoulderSelectorV176.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/ShrinkingBall.hpp"
#include "vendor/instaham_v176/include/instaham/cutter/TerminalGeometry.hpp"
#include "vendor/instaham_v176/include/instaham/preprocess/JiDuan.hpp"

namespace instaham_ml {
namespace stages {
namespace {

// mat is CV_8U, 0/1 -- matches the app's mask convention. Vendor functions binarize
// internally where they need 0/255, so no separate conversion is needed here.
std::vector<uint8_t> mat_to_mask(const cv::Mat& m) {
  cv::Mat b;
  m.convertTo(b, CV_8U);
  cv::threshold(b, b, 0, 1, cv::THRESH_BINARY);
  std::vector<uint8_t> out(static_cast<size_t>(b.rows) * b.cols);
  for (int y = 0; y < b.rows; ++y) {
    std::copy(b.ptr<uint8_t>(y), b.ptr<uint8_t>(y) + b.cols, out.begin() + y * b.cols);
  }
  return out;
}

CutterResult decline(const cv::Mat& fallback_mask, const std::string& status) {
  CutterResult out;
  out.width = fallback_mask.cols;
  out.height = fallback_mask.rows;
  out.mask = mat_to_mask(fallback_mask);
  out.head_removal_applied = false;
  out.status = status;
  return out;
}

}  // namespace

CutterResult cut_body_mask(const MaskView& in) {
  CutterResult out;
  if (!in.valid()) {
    out.status = "invalid_input";
    return out;
  }

  cv::Mat whole(in.height, in.width, CV_8UC1, const_cast<uint8_t*>(in.data));

  // ---- Ji/Duan cleanup ------------------------------------------------------
  // docs/fix-phase-2/1-cutter-freeze.md F44: applyJiDuan is not documented as exception-free
  // the way the three calls below are guarded, so it gets its own try/catch rather than
  // relying on an unhandled throw aborting the process. On a throw there is no ji.mask yet,
  // so the raw input mask is the only fallback available.
  instaham::JiDuanResult ji;
  try {
    ji = instaham::applyJiDuan(whole);
  } catch (const std::exception&) {
    return decline(whole, "jiduan_threw");
  }
  if (ji.fallback) {
    return decline(ji.mask, "jiduan_failed");
  }

  // ---- outline -> shrinking ball -> Selle filter -> terminal trunk ----------
  // These three throw std::runtime_error on degenerate geometry (too-short contour, too
  // few retained medial points, etc); bucketed together because they all feed toward the
  // same question -- is there a usable medial-axis trunk at all.
  instaham::TerminalResult term;
  try {
    instaham::OutlineResult outline = instaham::buildOutline(ji.mask);
    instaham::ShrinkingBallResult sb = instaham::runShrinkingBall(outline);
    instaham::SelleResult selle = instaham::applySelleFilter(sb, outline);
    term = instaham::buildTerminalTrunk(selle, ji.mask);
  } catch (const std::exception&) {
    return decline(ji.mask, "no_terminal_balls");
  }
  if (!term.valid) {
    return decline(ji.mask, "no_terminal_balls");
  }

  // ---- break1 fit -------------------------------------------------------------
  instaham::Break1Result break1 = instaham::fitBreak1(term.trunk);
  if (!break1.valid) {
    return decline(ji.mask, "break1_unfit");
  }

  // ---- V176 shoulder selection ------------------------------------------------
  instaham::ShoulderDecision shoulder = instaham::selectShoulderV176(term.trunk, break1);
  if (!shoulder.valid) {
    return decline(ji.mask, "shoulder_undecided");
  }
  if (!shoulder.cutRequired) {
    return decline(ji.mask, "cut_not_required");
  }

  // ---- V144 circle cut ----------------------------------------------------------
  instaham::CircleCutResult circle;
  try {
    circle = instaham::cutWithV144Circle(ji.mask, term.trunk, shoulder);
  } catch (const std::exception&) {
    return decline(ji.mask, "circle_cut_failed");
  }

  out.width = circle.finalMask.cols;
  out.height = circle.finalMask.rows;
  out.mask = mat_to_mask(circle.finalMask);
  out.head_removal_applied = true;
  out.status = "cut_applied";
  return out;
}

}  // namespace stages
}  // namespace instaham_ml
