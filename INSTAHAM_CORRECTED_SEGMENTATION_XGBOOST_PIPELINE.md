# InstaHAM — Corrected Segmentation-to-XGBoost Pipeline

## Purpose

This document defines the corrected **deployment pipeline and processing order** for InstaHAM.

This is a **pipeline fix only**.

- **Do not retrain YOLO.**
- **Do not retrain XGBoost.**
- **Do not change the 16-feature definitions.**
- **Do not change the Ji Duan cutting logic.**
- **Do not move the posture/truncation gates into a different coordinate system.**

The main issue being fixed is the unnecessary double-resizing of an already-binarized YOLO mask.

---

# 1. Current Problem

The current app-side mask path effectively does:

```text
160×160 FLOAT prototype
    ↓
crop at prototype resolution
    ↓
INTER_LINEAR → 640×640 FLOAT
    ↓
threshold > 0.5
    ↓
640×640 BINARY
    ↓
INTER_NEAREST → original phone resolution
    ↓
INTER_NEAREST / scale k → training-equivalent scale
    ↓
cutting
    ↓
16 features
    ↓
XGBoost
```

For a high-resolution phone image, this can become approximately:

```text
640 binary
    ↓
~3000 px binary
    ↓
~400–1000 px calibrated mask
```

This is undesirable because the binary contour is rasterized multiple times.

The first large nearest-neighbor resize turns the 640-pixel contour into large staircase blocks. The second resize then operates on that already-quantized contour.

For geometry-sensitive features such as perimeter, curvature, contour shape, moments, body width, and other derived measurements, this can introduce instability.

---

# 2. Corrected High-Level Pipeline

Use the following order:

```text
ORIGINAL RGB IMAGE
    ↓
Save original width and height
    ↓
Letterbox RGB → 640×640
    ↓
YOLO segmentation
    ↓
160×160 FLOAT prototype mask
    ↓
Crop to detected box while still FLOAT
    ↓
INTER_LINEAR → 640×640 FLOAT
    ↓
Threshold > 0.5
    ↓
640×640 BINARY MASK
    │
    ├──────────── QUALITY-GATE BRANCH ────────────┐
    │                                             │
    │  map to ORIGINAL capture coordinates        │
    │  ↓                                          │
    │  posture gate                               │
    │  ↓                                          │
    │  truncation gate                            │
    │  ↓                                          │
    │  accept / reject only                       │
    │                                             │
    └─────────────────────────────────────────────┘
    │
    │ MAIN WEIGHT PATH
    ↓
ONE DIRECT GEOMETRIC TRANSFORM
    ↓
remove letterbox padding
+ undo YOLO resize
+ apply reference/camera scale k
    ↓
FINAL CALIBRATED WORKING MASK
    ↓
Ji Duan / cutting
    ↓
Final post-cut mask
    ↓
16-feature extraction
    ↓
EXISTING XGBOOST
    ↓
Weight prediction
```

---

# 3. Important Rule

## Do not do this

```text
640×640 binary
    ↓
resize to original phone resolution
    ↓
resize again by scale k
    ↓
final calibrated mask
```

Example:

```text
640
→ 3024
→ 500
```

or:

```text
640
→ 4032
→ 700
```

The full-resolution phone raster is an unnecessary intermediate stage for the **weight-estimation branch**.

---

# 4. Correct Weight-Branch Transform

Instead, directly transform from the YOLO mask coordinate system to the final calibrated working coordinate system.

Conceptually:

```text
640×640 binary
    ↓
remove letterbox
+ undo YOLO scale
+ apply physical/reference scale k
    ↓
FINAL calibrated mask
```

This should be done as **one geometric resampling operation**.

---

# 5. Coordinate Mapping

Let:

```text
W = original image width
H = original image height
```

The YOLO letterbox scale is:

```text
r = min(640 / W, 640 / H)
```

Let:

```text
padX = horizontal letterbox padding
padY = vertical letterbox padding
```

Let:

```text
k = deployment normalization factor
```

where `k` converts the new camera geometry into the PigRGB-equivalent working scale expected by the existing weight pipeline.

Then a point in the 640×640 mask maps directly to the calibrated coordinate system as:

```text
x_final = (x_640 - padX) * (k / r)
y_final = (y_640 - padY) * (k / r)
```

The final dimensions are:

```text
finalWidth  = round(W * k)
finalHeight = round(H * k)
```

This avoids constructing an intermediate binary mask at the original phone resolution.

---

# 6. Letterbox Handling

Do not blindly resize the entire padded 640×640 mask.

The mask contains the actual image content plus possible padding:

```text
┌───────────────────────────┐
│        padding            │
├───────────────────────────┤
│                           │
│   original image content  │
│                           │
├───────────────────────────┤
│        padding            │
└───────────────────────────┘
```

The transform must account for:

- `padX`
- `padY`
- YOLO letterbox scale `r`
- deployment/reference scale `k`

These can be composed into one transform.

---

# 7. YOLO Mask Decoding Must Stay the Same

Keep the YOLO-compatible mask decoding path unchanged:

```text
160×160 FLOAT prototype
    ↓
crop to detected box at prototype resolution
    ↓
INTER_LINEAR
    ↓
640×640 FLOAT mask
    ↓
threshold > 0.5
    ↓
640×640 BINARY mask
```

Do not change this part simply to smooth the mask.

The pipeline fix is **after the 640×640 binary mask is produced**.

---

# 8. Quality Gates Must Stay in Original Capture Coordinates

The posture and truncation gates currently depend on the original capture coordinate system.

Therefore, preserve their current behavior.

Use a separate branch:

```text
                    → original-coordinate mask → posture gate
640 binary ────────┤
                    →                        → truncation gate
                    │
                    └→ direct calibrated mask → cutting → features
```

The original-resolution mask generated for the gates is **not** passed into the weight feature pipeline.

It exists only to preserve gate behavior and determine:

```text
ACCEPT
or
REJECT
```

---

# 9. Gate Ordering

The order remains:

```text
posture gate
    ↓
truncation gate
    ↓
Ji Duan / cutting
```

The gates must still happen **before Ji Duan**.

Do not reorder these.

---

# 10. Interpolation for the Direct Final Transform

For the direct 640 → calibrated working mask transform:

## If shrinking

Use:

```cpp
cv::INTER_AREA
```

This allows area-weighted resampling from the original crisp 640×640 binary mask instead of averaging a staircase that has already been enlarged.

## If enlarging

Use:

```cpp
cv::INTER_LINEAR
```

Then threshold the resampled mask back into binary form.

Example:

```cpp
cv::Mat resampledMask;

int interpolation =
    (finalWidth < sourceWidth || finalHeight < sourceHeight)
        ? cv::INTER_AREA
        : cv::INTER_LINEAR;

cv::resize(
    sourceMask,
    resampledMask,
    finalSize,
    0.0,
    0.0,
    interpolation
);

cv::threshold(
    resampledMask,
    finalBinaryMask,
    127.5,
    255,
    cv::THRESH_BINARY
);
```

If the transformation includes translation/cropping from letterbox removal, use an equivalent single `warpAffine` / coordinate transform rather than performing multiple separate image resizes.

---

# 11. Why INTER_AREA Did Not Fix the Previous Version

Changing only the second resize to `INTER_AREA` does not solve the main problem if the pipeline has already done:

```text
640 binary
    ↓
INTER_NEAREST
    ↓
~3000 px staircase
```

At that point the original 640 boundary has already been converted into large nearest-neighbor blocks.

Then:

```text
~3000 px staircase
    ↓
INTER_AREA
    ↓
smaller image
```

can only average the staircase that already exists.

It cannot reconstruct the original contour.

The correct approach is:

```text
640 crisp binary
    ↓
ONE direct resampling operation
    ↓
final calibrated mask
```

---

# 12. Correct C++ Processing Order

Pseudo-code:

```cpp
// --------------------------------------------------
// 1. Original RGB image
// --------------------------------------------------

int origW = image.cols;
int origH = image.rows;


// --------------------------------------------------
// 2. Letterbox to YOLO input size
// --------------------------------------------------

// Output:
// - input640
// - letterboxScale r
// - padX
// - padY

LetterboxResult lb = letterbox(image, 640, 640);


// --------------------------------------------------
// 3. YOLO inference
// --------------------------------------------------

YoloOutput output = runYolo(lb.image);


// --------------------------------------------------
// 4. Reconstruct FLOAT segmentation prototype
// --------------------------------------------------

cv::Mat protoMask = reconstructPrototypeMask(output);


// --------------------------------------------------
// 5. Crop at prototype resolution
// --------------------------------------------------

cv::Mat croppedProto =
    cropPrototypeToDetectionBox(protoMask, output.box);


// --------------------------------------------------
// 6. Upsample to 640×640 while still FLOAT
// --------------------------------------------------

cv::Mat mask640Float;

cv::resize(
    croppedProto,
    mask640Float,
    cv::Size(640, 640),
    0.0,
    0.0,
    cv::INTER_LINEAR
);


// --------------------------------------------------
// 7. Threshold exactly once at YOLO 640 stage
// --------------------------------------------------

cv::Mat mask640Binary;

cv::threshold(
    mask640Float,
    mask640Binary,
    0.5,
    255.0,
    cv::THRESH_BINARY
);

mask640Binary.convertTo(mask640Binary, CV_8U);


// ==================================================
// BRANCH A — QUALITY GATES
// ==================================================

cv::Mat originalCoordinateMask =
    map640MaskToOriginalCoordinates(
        mask640Binary,
        origW,
        origH,
        lb.scale,
        lb.padX,
        lb.padY
    );

bool postureOK =
    postureGate(originalCoordinateMask);

bool truncationOK =
    truncationGate(originalCoordinateMask);

if (!postureOK || !truncationOK) {
    return REJECT;
}


// ==================================================
// BRANCH B — WEIGHT PIPELINE
// ==================================================

// Compute deployment/reference normalization.
float k = computeReferenceScale(...);

// Directly map from YOLO coordinates to the final
// PigRGB-equivalent working coordinate system.
//
// DO NOT create an origW × origH binary mask first.

cv::Mat calibratedMask =
    transform640DirectlyToCalibratedScale(
        mask640Binary,
        origW,
        origH,
        lb.scale,
        lb.padX,
        lb.padY,
        k
    );


// --------------------------------------------------
// Ji Duan / cutting
// --------------------------------------------------

cv::Mat finalMask =
    jiDuanCut(calibratedMask);


// --------------------------------------------------
// Extract the existing 16 winning features
// --------------------------------------------------

FeatureVector features =
    extract16Features(finalMask);


// --------------------------------------------------
// Existing XGBoost model
// --------------------------------------------------

float predictedWeight =
    xgboostPredict(features);

return predictedWeight;
```

---

# 13. Required Branch Behavior

The two branches have different purposes.

## Gate branch

```text
640 binary
→ original capture coordinates
→ posture/truncation checks
→ accept/reject
```

This branch preserves existing gate assumptions.

## Weight branch

```text
640 binary
→ directly to calibrated coordinate system
→ cutting
→ 16 features
→ XGBoost
```

This branch avoids the damaging full-resolution detour.

---

# 14. What Must NOT Change

Do not change:

```text
YOLO model
YOLO weights
imgsz = 640
160×160 prototype behavior
YOLO mask crop behavior
INTER_LINEAR 160 → 640
0.5 threshold at 640
posture gate logic
truncation gate logic
Ji Duan logic
16 feature definitions
XGBoost model
XGBoost weights
```

This task is strictly a **pipeline/order and mask-resampling correction**.

---

# 15. Final Locked Order

```text
1. Original RGB
2. Save original width/height

3. Letterbox RGB → 640×640
4. YOLO inference
5. Reconstruct 160×160 FLOAT prototype
6. Crop prototype while FLOAT
7. INTER_LINEAR → 640×640 FLOAT
8. Threshold > 0.5 → 640×640 BINARY

9A. QUALITY GATE BRANCH
    640 → original capture coordinates
    → posture gate
    → truncation gate
    → accept/reject

9B. WEIGHT BRANCH
    640 → direct composed transform
    composed transform includes:
        - remove letterbox padding
        - undo YOLO resize
        - apply reference/camera scale k

10. Produce final calibrated binary mask

11. Ji Duan / cutting

12. Final post-cut mask

13. Extract existing 16 features

14. Existing XGBoost prediction
```

---

# 16. Core Fix in One Line

Replace:

```text
640 binary
→ original phone resolution
→ scale by k
→ final mask
```

with:

```text
640 binary
→ ONE composed transform
→ final calibrated mask
```

while keeping a **separate original-coordinate branch only for posture and truncation gates**.

---

# 17. No Retraining

This correction does **not** require:

```text
YOLO retraining
XGBoost retraining
feature regeneration
new feature definitions
new cutting logic
```

It only removes an unnecessary deployment-side rasterization detour and fixes the processing order.
