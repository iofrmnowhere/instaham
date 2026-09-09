#include "stages/feature_calculation.h"

#include <algorithm>
#include <cmath>

#include <opencv2/imgproc.hpp>

#include "stages/construction.h"

#include "vendor/instaham_v176/include/instaham/features/BodyCurve.hpp"
#include "vendor/instaham_v176/include/instaham/features/CenterCrossingAxesWork.hpp"
#include "vendor/instaham_v176/include/instaham/features/Chen16Vector.hpp"
#include "vendor/instaham_v176/include/instaham/features/ConvexHullArea.hpp"
#include "vendor/instaham_v176/include/instaham/features/Difference.hpp"
#include "vendor/instaham_v176/include/instaham/features/DifMask.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu1.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu2.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu3.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu4.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu5.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu6.hpp"
#include "vendor/instaham_v176/include/instaham/features/Hu7.hpp"
#include "vendor/instaham_v176/include/instaham/features/HuMomentsWork.hpp"
#include "vendor/instaham_v176/include/instaham/features/Longest.hpp"
#include "vendor/instaham_v176/include/instaham/features/MaskArea.hpp"
#include "vendor/instaham_v176/include/instaham/features/OutlineCurve.hpp"
#include "vendor/instaham_v176/include/instaham/features/Perimeter.hpp"
#include "vendor/instaham_v176/include/instaham/features/Shortest.hpp"

namespace instaham_ml {
namespace stages {

std::optional<FiveFeatures> extract_five_features(const std::vector<uint8_t>& mask, int w, int h,
                                                   double linear_scale,
                                                   bool preserve_processed_mask, int ra_frame_w,
                                                   int ra_frame_h) {
  std::vector<uint8_t> clean = preserve_processed_mask
                                    ? largest_component_fill(mask, w, h)
                                    : clean_binary_mask(mask, w, h);

  cv::Mat clean_mat(h, w, CV_8UC1, clean.data());
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(clean_mat, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_NONE);
  if (contours.empty()) return std::nullopt;

  auto largest = std::max_element(contours.begin(), contours.end(),
                                   [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                                     return cv::contourArea(a) < cv::contourArea(b);
                                   });
  const std::vector<cv::Point>& contour = *largest;
  if (contour.size() < 5) return std::nullopt;  // matches Python: fitEllipse needs >= 5 points

  FiveFeatures out;
  out.area_pixels = double(cv::countNonZero(clean_mat));
  const double denom_w = ra_frame_w > 0 ? double(ra_frame_w) : double(w);
  const double denom_h = ra_frame_h > 0 ? double(ra_frame_h) : double(h);
  out.ra = out.area_pixels / (denom_w * denom_h);
  out.lc = cv::arcLength(contour, true) * linear_scale;

  cv::RotatedRect rect = cv::minAreaRect(contour);
  double side_a = rect.size.width, side_b = rect.size.height;
  out.bl = std::max(side_a, side_b) * linear_scale;
  out.bw = std::min(side_a, side_b) * linear_scale;

  cv::RotatedRect ellipse = cv::fitEllipse(contour);
  double axis_a = ellipse.size.width, axis_b = ellipse.size.height;
  double minor = std::min(axis_a, axis_b), major = std::max(axis_a, axis_b);
  out.e = major > 0 ? std::sqrt(std::max(0.0, 1.0 - (minor / major) * (minor / major))) : 0.0;

  return out;
}

std::optional<Chen16Features> extract_chen16_features(const std::vector<uint8_t>& mask, int w,
                                                        int h) {
  if (mask.empty() || w <= 0 || h <= 0 ||
      mask.size() != static_cast<size_t>(w) * static_cast<size_t>(h)) {
    return std::nullopt;
  }
  // Vendor feature functions threshold internally (binary255 / strictBinary), so the raw
  // 0/1 mask can be wrapped as-is -- no separate binarization step needed here.
  cv::Mat m(h, w, CV_8UC1, const_cast<uint8_t*>(mask.data()));

  double mask_area = instaham::featureMaskArea(m);
  double convex_hull_area = instaham::featureConvexHullArea(m);
  double difference = instaham::featureDifference(convex_hull_area, mask_area);
  double dif_mask = instaham::featureDifMask(difference, mask_area);
  // Recomputed on THIS mask (the final cut mask), independently of any whole-mask
  // postureBodyCurve value the pre-Ji/Duan posture gate may have already computed --
  // the two calls must never share a cached result (phase 2 plan, "Two body-curve calls").
  double body_curve = instaham::computeBodyCurve(m);
  double perimeter = instaham::featurePerimeter(m);
  double outline_curve = instaham::featureOutlineCurve(m);

  instaham::AxisWorkResult axes = instaham::computeCenterCrossingAxes(m);
  double longest = instaham::featureLongest(axes);
  double shortest = instaham::featureShortest(axes);

  instaham::HuWorkResult hu_work = instaham::computeHuMoments(m);
  std::array<double, 7> hu = {
      instaham::featureHu1(hu_work), instaham::featureHu2(hu_work), instaham::featureHu3(hu_work),
      instaham::featureHu4(hu_work), instaham::featureHu5(hu_work), instaham::featureHu6(hu_work),
      instaham::featureHu7(hu_work),
  };

  instaham::Chen16Features assembled = instaham::assembleChen16(
      mask_area, convex_hull_area, difference, dif_mask, body_curve, perimeter, outline_curve,
      longest, shortest, hu);

  Chen16Features out;
  out.values = assembled.values;
  out.valid = assembled.valid;
  if (!out.valid) return std::nullopt;
  return out;
}

}  // namespace stages
}  // namespace instaham_ml
