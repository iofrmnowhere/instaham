# InstaHAM App Fix — Weight Pipeline Scaling, Rotation, and YOLO Framing

## Purpose

This README is a handoff for the next AI/developer fixing the **InstaHAM mobile/native weight-prediction pipeline**.

The current problem was not the XGBoost model itself. The issue was how a new Porac camera image was being prepared for YOLO segmentation.

The app must preserve the **0.34 cm/pixel physical scale used by the weight pipeline**, while also presenting the image to YOLO in framing that is closer to the segmentation training images.

The final chosen behavior is:

```text
Original camera image
→ EXIF/orientation correction
→ reference-object scale normalization to 0.34 cm/px
→ if portrait: rotate 90° clockwise
→ center unchanged on a 960×540 temporary canvas
→ YOLO segmentation at imgsz=640
→ remove the temporary canvas
→ inverse-rotate the selected whole-pig mask if needed
→ BASE MASK at 0.34 cm/px
→ quality gates / Ji-Duan / final V176 + V144 body isolation
→ FINAL MASK at 0.34 cm/px
→ 16 image-derived features
→ frozen XGBoost weight prediction
```

The **960×540 canvas and YOLO 640×640 tensor must never become the coordinate system used for the weight features**.

---

# 1. Locked Physical Scale

The weight branch must use:

```text
TARGET_CM_PER_PX = 0.34
```

This is the authoritative physical scale for the final app implementation.

Do **not** switch the weight pipeline to 304 px/m. A test comparing the two showed that the existing **0.34 cm/px** normalization produced better segmentation behavior for the current Porac images.

Equivalent approximate pixels per meter:

```text
100 cm / 0.34 cm/px ≈ 294.1176 px/m
```

The weight model/features must remain based on the `0.34 cm/px` normalized coordinate space.

---

# 2. Reference-Object Scale Calculation

The app uses a known reference object visible on the same floor plane as the pig.

Current reference lengths:

```text
Porac stick = 131 cm
Meter reference = 100 cm
```

The reference annotation contains two image points:

```text
(x1, y1)
(x2, y2)
```

The reference can be diagonal. Always use Euclidean distance:

```text
reference_px =
    sqrt(
        (x2 - x1)^2 +
        (y2 - y1)^2
    )
```

Observed physical scale:

```text
observed_cm_per_px =
    reference_length_cm /
    reference_px
```

Required image resize factor:

```text
scale_factor =
    observed_cm_per_px /
    0.34
```

Then resize **both image dimensions by the same factor**:

```text
new_width  = round(original_width  * scale_factor)
new_height = round(original_height * scale_factor)
```

Use aspect-ratio-preserving scaling only.

Recommended interpolation:

```text
scale_factor < 1:
    INTER_AREA

scale_factor >= 1:
    INTER_LINEAR
```

Do not stretch width and height independently.

---

# 3. Why the Previous YOLO Scaling Was Wrong

Scaling the new camera image to `0.34 cm/px` correctly normalizes the physical dimensions for XGBoost.

However, feeding the resulting portrait image directly to YOLO caused an additional whole-image resize inside YOLO.

Example:

```text
0.34-normalized Porac image:
approximately 400×533
```

If passed directly to YOLO with `imgsz=640`, the long side becomes:

```text
533 → 640
```

approximately:

```text
1.20× enlargement
```

This makes the pig appear much larger in network space than it did in the training-style frame.

This produced segmentation failures including unnatural **hard straight mask cutoffs**.

The selected fix is to temporarily restore training-like image framing **without changing the 0.34 cm/px pig scale**.

---

# 4. Orientation Rule

The app assumes that for a portrait weight capture:

```text
pig head = toward the TOP of the normalized image
```

The exact orientation rule is:

```cpp
if (normalizedHeight > normalizedWidth) {
    rotate 90 degrees CLOCKWISE;
} else {
    do not rotate;
}
```

This means a portrait pig whose head starts at the top will point:

```text
RIGHT
```

after the clockwise rotation.

Do not rotate counterclockwise.

Do not try to infer head direction dynamically in this preprocessing stage.

Store:

```text
wasRotatedClockwise = true / false
```

because the mask must later be transformed back.

---

# 5. Temporary 960×540 YOLO Canvas

After physical normalization and optional clockwise rotation, place the RGB image **unchanged** in the center of a:

```text
960 × 540
```

canvas.

Recommended neutral padding value:

```text
114
```

for all RGB channels:

```text
RGB/BGR = (114, 114, 114)
```

Do not resize the normalized pig again.

Given:

```text
rotatedWidth
rotatedHeight
```

calculate:

```text
xOffset = (960 - rotatedWidth)  / 2
yOffset = (540 - rotatedHeight) / 2
```

using integer positioning consistent with the implementation.

Copy the entire rotated normalized image into:

```text
canvas[
    yOffset : yOffset + rotatedHeight,
    xOffset : xOffset + rotatedWidth
]
```

The physical pig remains at exactly the same `0.34 cm/px` scale.

The surrounding blank area exists only to control the framing seen by YOLO.

---

# 6. Expected Fit Invariant

With the current acquisition setup and orientation rule, the normalized image is expected to fit inside `960×540`.

After optional portrait rotation:

```text
rotatedWidth  <= 960
rotatedHeight <= 540
```

This is considered an invariant for the current app.

Do **not** silently shrink the normalized image to make it fit, because doing so would alter the locked physical `0.34 cm/px` scale.

If this invariant is ever violated in future data, stop and investigate the acquisition/reference pipeline instead of introducing another resize.

---

# 7. YOLO Inference

Use the frozen final segmentation model already used by InstaHAM.

Current final model family:

```text
YOLO11s-seg + LDConv + ACmix
```

Expected YOLO inference size:

```text
imgsz = 640
```

Confidence currently used in the test pipeline:

```text
conf = 0.25
```

The source passed into YOLO must be the:

```text
960×540 temporary canvas
```

YOLO may internally letterbox this to its `640×640` tensor.

That internal YOLO representation is temporary.

Do not extract weight features in YOLO tensor coordinates.

---

# 8. Base Mask Restoration

YOLO returns/selects the whole-pig mask in temporary canvas coordinates.

Call this:

```text
canvasMask
```

First remove the temporary canvas padding:

```text
rotatedBaseMask =
    canvasMask[
        yOffset : yOffset + rotatedHeight,
        xOffset : xOffset + rotatedWidth
    ]
```

Now:

```text
rotatedBaseMask.shape
==
rotatedNormalizedImage.shape
```

If the RGB input had been rotated clockwise, inverse-transform the mask:

```text
BASE_MASK =
    rotate(rotatedBaseMask, 90 degrees COUNTERCLOCKWISE)
```

Otherwise:

```text
BASE_MASK = rotatedBaseMask
```

The resulting base mask must have:

```text
BASE_MASK.shape
==
normalized0p34Image.shape
```

This is the **whole-pig base mask** used by the downstream weight-processing pipeline.

At this point the temporary `960×540` canvas is completely gone.

---

# 9. Meaning of the Base Mask

`BASE_MASK` means:

```text
selected whole-pig YOLO mask
```

in:

```text
0.34 cm/px
original capture orientation
no 960×540 padding
no YOLO 640×640 coordinates
```

This is the mask that should be given to the existing weight-quality and body-isolation pipeline.

For debugging, the app/development build should make it easy to save or display this mask.

---

# 10. Downstream Weight Mask Order

After restoring the base mask to its proper `0.34 cm/px` coordinates, keep the existing production processing order.

The intended high-level order is:

```text
BASE whole-pig mask
→ posture / body-curve gate
→ truncation gate
→ Ji-Duan preprocessing
→ V176 shoulder selection
→ accepted V144 bilateral circle cutter
→ FINAL body-only mask
```

Do not run Ji-Duan before the posture/truncation gates if the current production implementation already follows the quality-gate-first order.

Do not use old discarded cut versions.

The final production cutting behavior is the current **V176 selector with the accepted V144 bilateral circle cutter**.

---

# 11. Meaning of the Final Mask

`FINAL_MASK` means the post-cut body-only mask after the frozen V176/V144 pipeline.

It must remain in:

```text
0.34 cm/px
original capture orientation
same width/height as BASE_MASK
```

Required checks:

```text
FINAL_MASK.shape == BASE_MASK.shape
```

and:

```text
FINAL_MASK must not contain foreground
outside BASE_MASK
```

Conceptually:

```text
FINAL_MASK ⊆ BASE_MASK
```

The final mask is the one used for the winning 16-feature weight representation.

---

# 12. XGBoost Coordinate Rule

This is critical.

The XGBoost features must be calculated from:

```text
FINAL_MASK at 0.34 cm/px
```

They must **not** be calculated from:

```text
960×540 temporary canvas coordinates
640×640 YOLO tensor coordinates
rotated YOLO orientation
original full-resolution camera coordinates
```

The selected winning weight model uses the final **16 image-derived features** from the final V176 mask.

The temporary YOLO framing exists only to improve segmentation.

It must not change the physical coordinate system of the weight features.

---

# 13. Correct Full Weight Pipeline

The application implementation should follow this exact sequence:

```text
1. Acquire RGB image.

2. Apply correct image orientation / EXIF handling.

3. Obtain known reference endpoints.

4. Compute Euclidean reference length in pixels.

5. Determine known reference length:
      meter       = 100 cm
      Porac stick = 131 cm

6. Calculate:
      observed_cm_per_px =
          reference_cm / reference_px

7. Calculate:
      resizeFactor =
          observed_cm_per_px / 0.34

8. Uniformly resize the RGB image by resizeFactor.

9. This normalized RGB image is now the authoritative
   0.34 cm/px weight coordinate space.

10. Orientation rule:
      if height > width:
          rotate image 90° clockwise
          rotated = true
      else:
          leave unchanged
          rotated = false

11. Center this image UNCHANGED on a 960×540
    neutral canvas.

12. Save:
      xOffset
      yOffset
      rotatedWidth
      rotatedHeight
      rotated flag

13. Run final YOLO segmentation:
      imgsz = 640

14. Select the intended whole-pig instance.

15. Restore YOLO mask to 960×540 canvas coordinates
    using the production YOLO mask-restoration logic.

16. Crop out the temporary canvas:
      mask =
          canvasMask[
              yOffset:yOffset+rotatedHeight,
              xOffset:xOffset+rotatedWidth
          ]

17. If rotated == true:
      rotate mask 90° counterclockwise.

18. Verify:
      BASE_MASK dimensions
      ==
      normalized RGB dimensions.

19. Run existing quality gates.

20. Run Ji-Duan.

21. Run frozen V176 shoulder selection.

22. Run accepted V144 bilateral circle cutter.

23. Produce FINAL_MASK.

24. Verify FINAL_MASK is still in the same
    0.34 cm/px coordinate space.

25. Extract the final winning 16 features.

26. Feed features in the frozen feature order
    to the final XGBoost model.

27. Return predicted live weight.
```

---

# 14. Pseudocode for the App

```cpp
Image original = loadAndOrientImage(...);

double refPx = euclideanDistance(
    referencePoint1,
    referencePoint2
);

double observedCmPerPx =
    referenceLengthCm / refPx;

double physicalScale =
    observedCmPerPx / 0.34;

Image normalized =
    resizeUniform(original, physicalScale);

// From here onward, normalized coordinates are the
// authoritative weight-coordinate system.

bool rotatedClockwise =
    normalized.height > normalized.width;

Image yoloSourceImage;

if (rotatedClockwise) {
    yoloSourceImage =
        rotate90Clockwise(normalized);
} else {
    yoloSourceImage =
        normalized;
}

assert(yoloSourceImage.width  <= 960);
assert(yoloSourceImage.height <= 540);

int xOffset =
    (960 - yoloSourceImage.width) / 2;

int yOffset =
    (540 - yoloSourceImage.height) / 2;

Image canvas =
    makeSolidImage(
        width = 960,
        height = 540,
        value = 114
    );

copyInto(
    canvas,
    yoloSourceImage,
    xOffset,
    yOffset
);

Mask canvasMask =
    runFinalYoloAndSelectPig(
        canvas,
        imgsz = 640,
        conf = 0.25
    );

Mask rotatedBaseMask =
    crop(
        canvasMask,
        xOffset,
        yOffset,
        yoloSourceImage.width,
        yoloSourceImage.height
    );

Mask baseMask;

if (rotatedClockwise) {
    baseMask =
        rotate90CounterClockwise(
            rotatedBaseMask
        );
} else {
    baseMask =
        rotatedBaseMask;
}

assert(
    baseMask.width ==
    normalized.width
);

assert(
    baseMask.height ==
    normalized.height
);

Mask finalMask =
    runFrozenV176Pipeline(
        baseMask
    );

assert(
    finalMask.width ==
    baseMask.width
);

assert(
    finalMask.height ==
    baseMask.height
);

Features16 features =
    extractChen16NoHeight(
        finalMask
    );

double predictedWeight =
    runFrozenXGBoost(
        features
    );
```

---

# 15. Things the Next AI Must NOT Do

Do **not** reintroduce any of the following:

### Do not run YOLO on the original full-resolution camera image first

Bad:

```text
full-resolution camera image
→ YOLO
→ resize mask to 0.34 afterward
```

The chosen pipeline normalizes the RGB image physically **before YOLO**.

---

### Do not feed the narrow portrait 0.34 image directly into YOLO

Bad:

```text
400×533 normalized image
→ YOLO imgsz=640
```

This changes the apparent object size inside the network because YOLO scales the long side directly toward 640.

Use the `960×540` temporary canvas first.

---

### Do not resize the 0.34-normalized image again to fill 960×540

Bad:

```text
normalized image
→ resize to 960×540
```

This destroys the physical scale.

Correct:

```text
normalized image
→ optional 90° CW rotation
→ center unchanged inside 960×540
```

---

### Do not stretch to 640×640

YOLO should perform its normal aspect-ratio-preserving letterboxing.

Never distort the pig to force a square source image.

---

### Do not use 960×540 or 640×640 for weight features

These are YOLO presentation spaces, not weight-feature spaces.

---

### Do not forget to inverse-rotate the mask

If RGB was rotated clockwise before YOLO:

```text
mask must be rotated counterclockwise afterward
```

before any weight processing.

---

### Do not change 0.34 cm/px to 304 px/m in the final app

The comparison test showed `0.34 cm/px` behaved better with the current local Porac images.

Keep:

```text
0.34 cm/px
```

unless the project team deliberately reruns and approves a new calibration experiment.

---

### Do not retrain YOLO or XGBoost to solve this app bug

The current issue is preprocessing / coordinate handling.

The selected models remain frozen unless the project team explicitly decides otherwise.

---

# 16. Debug Outputs Recommended During Integration

While fixing the app, expose or save the following for one test image:

```text
1. Original EXIF-corrected RGB
2. 0.34 cm/px normalized RGB
3. Rotated RGB used for YOLO
4. 960×540 temporary canvas
5. YOLO whole-pig mask in canvas coordinates
6. Canvas-cropped mask
7. BASE_MASK after inverse rotation
8. FINAL_MASK after V176/V144
9. Extracted 16 features
10. Final XGBoost weight
```

These stages make coordinate bugs immediately visible.

The most important visual comparison is:

```text
normalized RGB
BASE_MASK
FINAL_MASK
```

All three should align pixel-for-pixel.

---

# 17. Required Assertions

The app should explicitly verify these invariants during development:

```text
reference_px > 0

scale_factor > 0

normalized_width  > 0
normalized_height > 0

after orientation:
    width  <= 960
    height <= 540

canvas size:
    exactly 960×540

cropped mask size:
    equals rotated normalized RGB size

after inverse rotation:
    BASE_MASK size
    equals original normalized RGB size

FINAL_MASK size:
    equals BASE_MASK size

FINAL_MASK foreground:
    subset of BASE_MASK foreground
```

If any of these fail, treat it as a pipeline/coordinate error rather than silently applying another resize.

---

# 18. Final App Behavior to Preserve

The final conceptual separation is:

```text
PHYSICAL NORMALIZATION
0.34 cm/px
        │
        ├── authoritative coordinate system for weight
        │
        ↓
TEMPORARY YOLO PRESENTATION
optional CW rotation
+ 960×540 canvas
+ YOLO 640 letterboxing
        │
        ↓
undo canvas + undo rotation
        │
        ↓
BACK TO 0.34 cm/px
        │
        ↓
BASE MASK
        │
        ↓
V176/V144
        │
        ↓
FINAL MASK
        │
        ↓
16 FEATURES
        │
        ↓
XGBOOST
```

The key requirement is:

> **YOLO framing may temporarily change how the image is presented to the segmentation network, but it must never change the physical 0.34 cm/px coordinate system used for weight estimation.**

---

# 19. Current Locked Decisions

As of this handoff:

```text
Physical target:
    0.34 cm/px

Portrait detection:
    normalizedHeight > normalizedWidth

Portrait rotation:
    90° clockwise

Portrait capture assumption:
    pig head starts at top

YOLO-facing pig orientation after rotation:
    head points right

Temporary canvas:
    960×540

Canvas padding:
    neutral value 114

YOLO inference:
    imgsz=640

After YOLO:
    remove canvas
    inverse-rotate if needed

Base mask:
    whole-pig mask at 0.34 cm/px

Final mask:
    V176 selector + accepted V144 bilateral cutter
    at the same 0.34 cm/px coordinates

Weight features:
    final winning 16 image-derived features

Weight prediction:
    frozen final XGBoost model
```

Do not reinterpret these choices during app integration unless the project team explicitly changes them.
