#include "stages/feature_calculation.h"

#include <algorithm>
#include <cmath>

#include <opencv2/imgproc.hpp>

#include "stages/construction.h"

namespace instaham_ml {
namespace stages {

std::optional<FiveFeatures> extract_five_features(const std::vector<uint8_t>& mask, int w, int h,
                                                   double linear_scale,
                                                   bool preserve_processed_mask) {
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
  out.ra = out.area_pixels / (double(w) * double(h));
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

}  // namespace stages
}  // namespace instaham_ml
