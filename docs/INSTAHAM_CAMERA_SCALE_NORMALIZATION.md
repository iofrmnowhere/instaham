# InstaHAM Camera Scale Normalization Specification

> **Standing note (docs/fix-phase-4/3-constants.md phase 3, 2026-09-19).** This document's
> derived scale target -- `PIGRGB_TARGET_PPM = 304.0` / 0.3289473684210526 cm/px -- is
> **superseded on that one value** by the round-28 host sweep's measured MAE minimum, 0.34
> cm/px (`docs/scale-constant-sweep-results-2.md`, ADR-011/012), which is what
> `capabilities.weight.capture_contract.cm_per_px_target` ships as. This document remains
> **authoritative on the underlying PIGRGB geometry** the 0.34 target and the app's 960x540
> capture canvas both derive from: the 1.88 m training camera height and the 960x540
> released `RGB_9579` frame size below. The sweep changed the target scale; it did not
> change, and could not have changed, the physical setup that scale describes.

## Purpose

This document tells the implementation AI how to normalize photographs taken with cameras other than the camera used for the PIGRGB-Weight training data.

The goal is to make the **floor-plane physical scale** of a new image comparable to the PIGRGB `RGB_9579` images before the InstaHAM segmentation, cutting, feature extraction, and XGBoost weight-prediction pipeline is applied.

This normalization is intended to compensate primarily for differences in:

- camera model;
- RGB field of view / focal length;
- image resolution;
- ordinary camera-to-camera differences in apparent scale; and
- acquisition size, provided a known-length reference is visible on the floor.

It must **not** be treated as a complete correction for perspective caused by large differences in camera height, camera tilt, or the pig being elevated above the floor plane.

---

# 1. PIGRGB Baseline

The InstaHAM weight model is based primarily on the PIGRGB-Weight `RGB_9579` images.

Use the following baseline for scale normalization:

```text
PIGRGB RGB_9579 capture height: approximately 1.88 m
Released RGB image size:        960 x 540
Target floor-plane scale:       approximately 304 pixels per meter
```

Define:

```text
PIGRGB_TARGET_PPM = 304.0
```

where `PPM` means **pixels per meter on the floor plane**.

The approximate original-camera equivalent at 1920 x 1080 is:

```text
approximately 608 pixels per meter
```

However, the application should normalize against the **released 960 x 540 PIGRGB coordinate scale**, so the implementation target is:

```text
304 px/m
```

Do not use `608 px/m` unless the entire pipeline is explicitly operating in the original 1920 x 1080 coordinate system.

---

# 2. Required Reference Object

A new photograph must contain a reference object of known physical length placed on the **same floor plane as the pig's feet**.

Preferred example:

```text
reference length = 1.000 m
```

The implementation must not assume that the reference is always exactly 1 meter. Store or receive its true physical length.

Required inputs:

```text
reference_pixel_length
reference_physical_length_m
```

Example:

```text
reference_pixel_length      = 380 px
reference_physical_length_m = 1.0 m
```

Calculate the observed floor scale as:

```text
observed_ppm =
    reference_pixel_length / reference_physical_length_m
```

For the example:

```text
observed_ppm = 380 / 1.0 = 380 px/m
```

---

# 3. Required Resize Formula

Calculate the scale factor needed to convert the new image to the PIGRGB-equivalent floor scale:

```text
scale_factor =
    PIGRGB_TARGET_PPM / observed_ppm
```

Equivalent expanded formula:

```text
scale_factor =
    PIGRGB_TARGET_PPM /
    (reference_pixel_length / reference_physical_length_m)
```

or:

```text
scale_factor =
    (PIGRGB_TARGET_PPM * reference_physical_length_m) /
    reference_pixel_length
```

For a 1-meter reference measuring 380 pixels:

```text
scale_factor = 304 / 380
             = 0.800
```

The new photograph therefore needs to be resized to 80% of its original linear dimensions.

Example:

```text
original image = 1200 x 900
scale_factor   = 0.800

normalized image =
    round(1200 * 0.800) x round(900 * 0.800)

normalized image = 960 x 720
```

After resizing, the same 1-meter reference should measure approximately:

```text
380 * 0.800 = 304 px
```

---

# 4. Example When the New Camera Makes Objects Smaller

Suppose a 1-meter reference measures only:

```text
250 px
```

Then:

```text
observed_ppm = 250 px/m

scale_factor = 304 / 250
             = 1.216
```

The image must be enlarged by approximately:

```text
121.6%
```

After normalization:

```text
250 * 1.216 approximately equals 304 px
```

---

# 5. Processing Order

Use this order.

```text
1. Load original user photograph
2. Read/detect the known floor reference
3. Measure its pixel length in the ORIGINAL image
4. Read its physical length in meters
5. Calculate observed_ppm
6. Calculate scale_factor
7. Resize the full image uniformly in X and Y
8. Update any already-existing coordinates/masks by the same scale factor
9. Perform the normal InstaHAM image-processing pipeline
10. Letterbox/resize for YOLO only when required by the model
11. Obtain the pig mask
12. Apply quality/posture/truncation gates in their established order
13. Apply the final accepted cutting procedure
14. Extract the final 16 features
15. Run the trained XGBoost weight model
```

## Critical rule

The camera-scale normalization must happen **before feature extraction**.

Do not extract the 16 morphological features from the unnormalized image and then simply resize the visualization afterward.

The feature geometry must correspond to the normalized coordinate system.

---

# 6. Do Not Confuse Physical Normalization With YOLO Letterboxing

The resize described in this document is a **physical-scale normalization step**.

It is not the same thing as resizing or letterboxing an input to:

```text
640 x 640
```

for YOLO.

These are two different transformations.

### Physical normalization

Purpose:

```text
Make 1 meter on the floor approximately equivalent to
304 pixels in PIGRGB 960 x 540 coordinates.
```

### YOLO preprocessing

Purpose:

```text
Convert an image into the network's required tensor/input dimensions.
```

Do not replace physical normalization with YOLO letterboxing.

If YOLO later applies a 640 x 640 letterbox, keep the transformation metadata needed to map the mask back to the physically normalized image coordinate system before extracting morphology features.

---

# 7. Uniform Scaling Only

The physical normalization must preserve aspect ratio.

Use:

```text
new_width  = round(original_width  * scale_factor)
new_height = round(original_height * scale_factor)
```

Do NOT independently force width and height to unrelated target dimensions.

Incorrect:

```text
resize arbitrary image directly to 960 x 540
```

This can distort the pig and corrupt:

- body length;
- body width;
- perimeter;
- area;
- ellipse geometry;
- curvature-related measurements; and
- other derived morphological features.

Correct:

```text
apply one uniform scale_factor to width and height
```

The resulting normalized image does **not** need to be exactly `960 x 540`.

The target is physical scale, not target canvas dimensions.

---

# 8. Reference Measurement

The reference object should be measured using its two physical endpoints.

If the reference has endpoints:

```text
(x1, y1)
(x2, y2)
```

calculate:

```text
reference_pixel_length =
    sqrt((x2 - x1)^2 + (y2 - y1)^2)
```

Then:

```text
observed_ppm =
    reference_pixel_length / reference_physical_length_m
```

The reference measurement must be taken **before physical normalization**.

---

# 9. Recommended Implementation Interface

The normalization logic should be isolated from the rest of the pipeline.

Example C++-style interface:

```cpp
struct ScaleNormalizationResult {
    cv::Mat normalizedImage;
    double observedPixelsPerMeter;
    double scaleFactor;
    bool valid;
};

ScaleNormalizationResult normalizeToPigRGBScale(
    const cv::Mat& inputImage,
    double referencePixelLength,
    double referencePhysicalLengthMeters
);
```

Suggested constant:

```cpp
constexpr double PIGRGB_TARGET_PPM = 304.0;
```

Core calculation:

```cpp
double observedPPM =
    referencePixelLength / referencePhysicalLengthMeters;

double scaleFactor =
    PIGRGB_TARGET_PPM / observedPPM;
```

Uniform resize:

```cpp
cv::resize(
    inputImage,
    normalizedImage,
    cv::Size(),
    scaleFactor,
    scaleFactor,
    interpolation
);
```

Use a suitable interpolation method for shrinking versus enlarging, but do not alter the mathematical scale factor.

---

# 10. Validation

The normalization step must fail safely when any required value is invalid.

Reject normalization when:

```text
reference_pixel_length <= 0
reference_physical_length_m <= 0
image is empty
scale_factor is non-finite
```

Do not silently substitute `304 px/m` when the reference could not actually be measured.

Return an explicit failure/result state to the calling pipeline.

---

# 11. Camera Model Independence

Do not hard-code a list of supported phone models.

The physical reference is intended to make the normalization independent of the exact camera model.

For example:

```text
Camera A:
1 m reference = 380 px

Camera B:
1 m reference = 250 px
```

Both can be normalized toward:

```text
304 px/m
```

using their own measured reference.

Therefore, do not calculate normalization from:

- phone brand;
- megapixel count;
- EXIF focal length alone;
- nominal sensor resolution alone; or
- a hard-coded camera-specific multiplier.

The actual reference visible in the photograph is the preferred source of scale.

---

# 12. Camera Height Requirement

Scale normalization does NOT mean that photographs may be taken at arbitrary heights with no consequences.

The production weight model was trained around the PIGRGB acquisition geometry, with `RGB_9579` captured at approximately:

```text
1.88 m camera-to-floor height
```

For the safest deployment behavior, new weight-estimation photographs should therefore be acquired at or near the validated acquisition height.

Do not claim that floor-reference resizing completely corrects arbitrary camera-height differences.

Why:

```text
The reference is on the floor.
The pig's dorsal surface is above the floor.
```

A change in camera height changes the relative projection of the floor plane and the pig's elevated body plane.

Example concept:

```text
camera
   |
   | distance to pig back
   |
 pig back
   |
 pig body
   |
floor + reference stick
```

Matching the floor reference to `304 px/m` corrects the floor scale, but a pig at a substantial height above the floor can still have residual perspective differences when the camera height changes.

Therefore:

```text
different camera/FOV/resolution:
    reference normalization is appropriate

substantially different camera height:
    reference normalization alone is NOT guaranteed to reproduce
    the PIGRGB pig-body projection
```

---

# 13. Camera Tilt Requirement

The baseline assumes a near top-down photograph with the image plane approximately parallel to the floor.

A tilted camera introduces perspective distortion.

A single scalar resize:

```text
scale_factor
```

cannot correct projective distortion caused by significant tilt.

Therefore the application should either:

1. require an approximately perpendicular/top-down capture; or
2. use a separately validated planar perspective/homography correction.

Do not invent a homography from a single length measurement.

A single 1-meter line provides scale but does not provide enough information to completely rectify an arbitrarily tilted floor plane.

---

# 14. Lens Distortion

If strong wide-angle/barrel/fisheye distortion is present, scalar scale normalization alone is not sufficient.

If the app later adds camera calibration or lens-undistortion support, lens correction should occur before measuring the reference and before physical-scale normalization.

Preferred future order:

```text
raw image
    ->
lens undistortion
    ->
reference measurement
    ->
PIGRGB scale normalization
    ->
segmentation
    ->
feature pipeline
```

Do not introduce camera-specific lens correction unless it has been implemented and validated.

---

# 15. Coordinate Handling

If reference points, ROIs, masks, bounding boxes, landmarks, or other coordinates already exist before the normalization step, transform all of them consistently.

For every point:

```text
x_normalized = x_original * scale_factor
y_normalized = y_original * scale_factor
```

For a bounding box:

```text
x' = x * scale_factor
y' = y * scale_factor
w' = w * scale_factor
h' = h * scale_factor
```

Do not resize the image while leaving associated geometry in original-image coordinates.

---

# 16. Feature Extraction Rule

All final weight-regression features must use one internally consistent coordinate system.

Preferred implementation:

```text
original photo
    ->
physical scale normalization
    ->
segmentation
    ->
mask mapped to normalized-image coordinates
    ->
quality gates / final cut
    ->
16-feature extraction
```

Do not mix:

```text
area from one resolution
perimeter from another resolution
body length from a letterboxed mask
body width from the original image
```

unless the exact transformations are reversed mathematically and all measurements are brought into the same coordinate system.

---

# 17. Area and Linear Quantities

Remember that image resizing affects measurements differently.

If the image is resized by:

```text
scale_factor = s
```

then linear quantities change by:

```text
length' = length * s
perimeter' = perimeter * s
```

while pixel area changes by:

```text
area' = area * s^2
```

This is another reason to normalize the image/mask before computing the 16 final features rather than applying an arbitrary correction to the finished XGBoost prediction.

---

# 18. Do Not Recalculate the Target From the User's Image Dimensions

Do not use formulas such as:

```text
target_ppm = image_width / some_constant
```

unless the physical camera geometry is explicitly known and validated.

The normalization target is:

```text
PIGRGB_TARGET_PPM = 304.0
```

The user's current PPM comes from the known reference object:

```text
observed_ppm =
    reference_pixel_length / reference_physical_length_m
```

The user's raw image dimensions alone do not tell us its physical scale.

---

# 19. Example End-to-End Calculation

Input:

```text
image size                  = 4032 x 3024
reference physical length   = 1.000 m
reference measured length   = 510 px
PIGRGB target               = 304 px/m
```

Calculate:

```text
observed_ppm = 510 / 1.000
             = 510 px/m

scale_factor = 304 / 510
             = 0.596078...
```

New dimensions:

```text
new_width  = round(4032 * 0.596078)
           approximately 2403

new_height = round(3024 * 0.596078)
           approximately 1803
```

Expected reference after resizing:

```text
510 * 0.596078
approximately 304 px
```

The normalized image can then proceed to the existing InstaHAM pipeline.

Do not force the normalized image to `960 x 540`.

---

# 20. Recommended Metadata to Keep

Keep these values with every inference for diagnostics and reproducibility:

```text
original_image_width
original_image_height
reference_pixel_length
reference_physical_length_m
observed_pixels_per_meter
target_pixels_per_meter
physical_scale_factor
normalized_image_width
normalized_image_height
```

Optional if available:

```text
reported_camera_height_m
camera model
capture orientation
reference endpoint coordinates
```

These diagnostic values do not have to become XGBoost features unless the trained model explicitly expects them.

---

# 21. Production Behavior When No Reference Is Available

For weight estimation, do not silently pretend that an arbitrary new-camera image already has PIGRGB scale.

If the required physical reference cannot be measured:

```text
normalization.valid = false
```

The caller should prevent or clearly flag weight prediction according to the application's established UX rules.

Health classification or other modules that do not depend on this physical scale may be handled separately.

---

# 22. Important Separation From Existing InstaHAM Logic

This module is an acquisition/normalization step.

It must not change the already accepted behavior of:

- YOLO segmentation;
- posture/truncation quality gates;
- the current final cutting implementation;
- the final 16-feature definitions; or
- the trained XGBoost model.

Its responsibility is only:

```text
NEW-CAMERA IMAGE
        +
KNOWN FLOOR REFERENCE
        |
        v
MEASURE CURRENT PX/M
        |
        v
UNIFORM RESIZE
        |
        v
PIGRGB-EQUIVALENT FLOOR SCALE
```

Then hand the normalized image to the established downstream pipeline.

---

# 23. Implementation Summary for the AI

Implement the following exactly:

```text
CONSTANT:
    TARGET_PPM = 304.0

INPUT:
    image
    reference endpoints or measured pixel length
    reference physical length in meters

CALCULATE:
    reference_px =
        Euclidean distance between endpoints

    observed_ppm =
        reference_px / reference_length_m

    scale =
        TARGET_PPM / observed_ppm

RESIZE:
    width'  = round(width  * scale)
    height' = round(height * scale)

    resize full image uniformly by scale

VERIFY:
    expected normalized reference size =
        reference_px * scale
        approximately TARGET_PPM * reference_length_m

OUTPUT:
    normalized image
    observed_ppm
    scale
    valid/failure state

THEN:
    send normalized image into the existing InstaHAM pipeline
```

Do not:

```text
- stretch directly to 960 x 540;
- use separate X and Y scale factors;
- treat YOLO 640 x 640 letterboxing as physical calibration;
- assume all cameras have the same px/m;
- infer px/m only from megapixels;
- claim arbitrary camera heights are fully corrected;
- modify the trained 16-feature definitions;
- modify the final cut as part of this task;
- silently proceed when the physical reference is unavailable.
```

---

# 24. Current Status of the 304 px/m Constant

`304 px/m` is a **theoretical PIGRGB floor-plane baseline** derived from the reported PIGRGB acquisition geometry and RGB camera field of view.

Treat it as the current implementation baseline unless the project later obtains a more precise empirical calibration directly from the released PIGRGB images.

If an empirical calibration is later validated, update only:

```text
PIGRGB_TARGET_PPM
```

The normalization architecture and formulas above should remain unchanged.

---

# Final Requirement

The intent of this integration is:

> Photographs from different RGB cameras should not be fed directly into the PIGRGB-trained weight pipeline at their native apparent scale. When a known floor reference is available, first convert the image to the PIGRGB-equivalent floor-plane scale using a uniform resize, then run the existing InstaHAM processing pipeline.

This improves camera-to-camera scale consistency while preserving the important limitation that floor-reference scaling alone does not completely remove perspective differences caused by camera tilt or substantially different camera heights.
