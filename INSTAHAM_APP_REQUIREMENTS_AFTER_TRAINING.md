# INSTAHAM App Requirements After Model Training

This document describes what the future INSTAHAM application will need **after the nine training notebooks have been completed and the final research models have been selected**.

It is a deployment and application-development guide. It does not replace the training README and does not mean the app must be built during the current training stage.

---

## 1. Intended app behavior

The application should route every submitted pig image into one of three outcomes:

| Image outcome | Weight estimation | Visual health assessment |
|---|---:|---:|
| Valid dorsal/top-down image | Allowed only after all weight checks pass | Allowed |
| Rejected or unusable image | Not allowed | Not allowed; request another image |

The central rule is:

```text
Weight prediction requires a valid dorsal image and a valid physical scale.
Health assessment may use dorsal or non-dorsal images when the image is usable.
```

The app must never force a weight estimate when the capture is unsuitable.

---

## 2. Files expected from the training pipeline

After all notebooks are run, the application team should receive a separate deployment package containing the selected artifacts below.

### 2.1 Final selection file

```text
artifacts/final/selected_models.json
```

This identifies the selected:

- segmentation model;
- health-classification model;
- weight-regression experiment.

This file is a research-stage selection record. The app must still verify that all referenced model files exist and that their preprocessing metadata is included in the deployment package.

### 2.2 View-suitability model

Expected files:

```text
artifacts/view_model/mobilenetv4/best.pt
artifacts/view_model/mobilenetv4/classes.json
artifacts/view_model/mobilenetv4/metrics.json
```

The current view model is trained to distinguish:

- `dorsal_valid`
- `health_only`
- `reject`

Do not hardcode numeric class indices. Read the class-to-index mapping from `classes.json` or the checkpoint.

### 2.3 Segmentation model

The selected Ultralytics checkpoint will normally be located under:

```text
artifacts/yolo_runs/<run_name>/weights/best.pt
```

The final checkpoint path is recorded in:

```text
artifacts/final/selected_models.json
```

The model is responsible for producing pig instances and masks. The app should use the mask output for geometric checks and the weight-feature branch.

### 2.4 Health-classification model

Expected files for the selected run:

```text
artifacts/health_runs/<architecture>__seed<seed>/best.pt
artifacts/health_runs/<architecture>__seed<seed>/classes.json
artifacts/health_runs/<architecture>__seed<seed>/metrics.json
```

The selected model will be one of:

- MobileNetV4-Conv-Small;
- ShuffleNetV2 x1.0;
- GhostNetV3 1.0x.

The class mapping must be loaded from `classes.json`. Do not assume alphabetical order inside the app.

### 2.5 Weight-regression model

The XGBoost models are saved as:

```text
artifacts/xgboost/<experiment_name>/model.json
```

The final selection record identifies the selected experiment name. For the deployable branch, prefer the experiment trained from **predicted YOLO masks**, not the oracle experiment trained from ground-truth masks.

The app deployment package must also include the exact feature order:

```text
RA, LC, BL, BW, E
```

The feature order must never be changed when calling the XGBoost model.

---

## 3. A deployment package still needs to be created

The notebooks save research checkpoints. They do not yet create mobile-ready files.

Before app development, create a versioned folder such as:

```text
instaham_deployment_v1/
├── manifest.json
├── view_model/
│   ├── model.<mobile-format>
│   └── classes.json
├── segmentation_model/
│   └── model.<mobile-format>
├── health_model/
│   ├── model.<mobile-format>
│   └── classes.json
├── weight_model/
│   └── model.json
├── thresholds.json
├── preprocessing.json
└── model_card.md
```

`manifest.json` should record at least:

```json
{
  "deployment_version": "1.0.0",
  "view_architecture": "selected after training",
  "segmentation_architecture": "selected after training",
  "health_architecture": "selected after training",
  "weight_experiment": "selected predicted-mask experiment",
  "view_input_size": 224,
  "health_input_size": 224,
  "segmentation_input_size": 640,
  "weight_features": ["RA", "LC", "BL", "BW", "E"],
  "reference_unit": "cm"
}
```

The mobile export format should be chosen later based on the actual app framework and target devices. Exported models must be compared against their original checkpoints to confirm that conversion or quantization does not materially reduce accuracy.

---

## 4. Required inference flow

The recommended app pipeline is:

```text
Input image
    │
    ▼
Basic file and image checks
    │
    ▼
View-suitability classifier
    │
    ├── reject
    │     └── Stop and request another image
    │
    ├── health_only
    │     └── Run visual health classification only
    │
    └── dorsal_valid
          │
          ├── Run visual health classification
          │
          └── Run segmentation and weight-eligibility checks
                    │
                    ├── Any check fails
                    │     └── Do not estimate weight
                    │
                    └── All checks pass
                          ├── Obtain reference length and endpoints
                          ├── Calculate scale
                          ├── Extract RA, LC, BL, BW, E
                          └── Run XGBoost weight prediction
```

The health and weight results should be independent. A failed weight branch must not automatically block health assessment when the health image remains usable.

---

## 5. Image preprocessing that must match training

### 5.1 View and health classifiers

The current notebooks use:

- RGB input;
- resize to approximately `1.14 × 224`;
- center crop to `224 × 224` during validation and inference;
- conversion to tensor;
- ImageNet normalization.

Normalization values:

```text
mean = [0.485, 0.456, 0.406]
std  = [0.229, 0.224, 0.225]
```

The app must reproduce the selected model's final preprocessing exactly. Any later change must be treated as a new model version and revalidated.

### 5.2 Segmentation

The current training size is:

```text
640 × 640 target size
```

The app should preserve the image aspect ratio and use the same letterboxing behavior used by the exported YOLO model. Do not stretch the image in a way that changes the pig's body proportions.

The predicted mask must be mapped back to the original image coordinate system before measuring the pig or the reference object.

### 5.3 Color and orientation

The app must:

- correct EXIF orientation before inference;
- use RGB channel order for the classifiers;
- use the channel order required by the exported segmentation model;
- avoid silently resizing or rotating images after the reference endpoints have been selected.

---

## 6. View routing and confidence handling

The notebooks record probabilities but intentionally do not finalize an app threshold.

The app will need validated thresholds for:

- accepting `dorsal_valid`;
- accepting `health_only`;
- treating a low-confidence result as `reject` or manual review.

A reasonable product behavior is:

```text
High-confidence dorsal_valid → continue to both branches
High-confidence health_only  → health branch only
Reject or low confidence     → request another image
```

Do not use an arbitrary threshold as a final value. Select thresholds from held-out validation results and document them in `thresholds.json`.

---

## 7. Weight-eligibility checks

A `dorsal_valid` view prediction is necessary but not sufficient for estimating weight.

The app should permit weight prediction only when all of the following pass:

1. Exactly one usable pig instance is detected.
2. The full pig body is inside the frame.
3. The pig mask does not show severe truncation or occlusion.
4. The pig posture is suitable for dorsal morphology.
5. A valid reference object is available.
6. The reference object has a known positive real-world length.
7. The two reference endpoints are valid and sufficiently far apart in pixels.
8. The reference object is on approximately the same floor plane as the pig.
9. The predicted mask and extracted features pass sanity ranges.

Suggested programmatic checks include:

- number of detected pig instances;
- segmentation confidence;
- mask area ratio;
- whether the mask touches image boundaries;
- minimum contour size;
- nonzero BL and BW;
- plausible eccentricity range;
- valid reference pixel length;
- finite values for all five features.

When a check fails, show a specific retake instruction rather than generating a low-quality estimate.

---

## 8. Reference-object support

The future app must **not be restricted to a one-meter stick**.

The training pipeline already stores reference dimensions per image. The app should support a known reference length supplied at inference time.

For the first app version, the most practical workflow is:

1. The user selects a preset or enters a custom reference length.
2. The user marks the two endpoints of the visible straight reference object.
3. The app validates the selected points.
4. The app calculates centimeters per pixel.

Supported examples can include:

```text
1-meter stick: 100 cm
Porac rectangular stick: 131 cm
Custom straight object: user-entered positive length in cm
```

Scale calculation:

```text
reference_pixels = distance between selected endpoints
cm_per_pixel = reference_length_cm / reference_pixels
```

The app must not derive scale from the pig's own body width.

### Required reference UI later

The future app will need:

- preset selection;
- custom positive length entry;
- unit handling, preferably stored internally in centimeters;
- two-point endpoint selection and adjustment;
- a confirmation overlay;
- validation that the entire reference is visible;
- a clear option to switch between reference mode and height mode.

Automatic reference-object recognition is not produced by the current notebooks. Unless a separate reference detector is trained later, endpoint marking must remain manual.

---

## 9. Weight feature extraction in the app

After segmentation and scale calculation, the app must reproduce the training feature extraction logic.

Current feature definitions:

- `RA`: pig dorsal-core area divided by the image area;
- `LC`: dorsal-core contour perimeter, scaled to the active feature space;
- `BL`: longer side of the minimum-area rotated rectangle;
- `BW`: shorter side of the minimum-area rotated rectangle;
- `E`: fitted-ellipse eccentricity.

For variable smartphone images with a reference object:

```text
LC, BL, and BW use centimeters.
Area scaling uses square centimeters when needed for diagnostics.
E and RA remain dimensionless.
```

The app must use the same mask cleanup and dorsal-core isolation procedure used during training. Changing that procedure changes the XGBoost input distribution and requires retraining or revalidation.

### Feature-space warning

The training package intentionally distinguishes:

- `fixed_camera_pixels` for PIGRGB-style fixed-camera experiments;
- `physical_cm` for reference-scaled Porac images.

The app uses variable smartphone capture, so it should use a weight model trained for the **physical-centimeter feature space**. It should not silently deploy a fixed-camera pixel model to arbitrary phone images.

If training does not produce an adequately validated physical-centimeter XGBoost model, the first app release must disable weight estimation rather than use an incompatible regression model.

---

## 10. Health-assessment behavior

The health model returns one of the trained visual classes and a probability distribution.

The app should display:

- predicted visual class;
- confidence or a user-friendly confidence category;
- an uncertain result when the confidence is below the validated threshold;
- a statement that the result is a visual screening output, not a veterinary diagnosis.

Recommended result wording:

```text
Possible visual indicator: <class>
Confidence: <value or category>
This is not a veterinary diagnosis. Seek professional assessment when the pig is ill or the result is uncertain.
```

The application should not promise that a camera image can rule out disease. A healthy prediction only means the selected model did not identify one of its trained visible classes with sufficient confidence.

---

## 11. User-facing capture guidance

### Weight and health mode

The app should instruct the user to:

- photograph one pig at a time;
- capture the whole pig from above;
- keep the phone approximately parallel to the ground;
- place the known reference object flat near the pig;
- keep both reference endpoints visible;
- avoid severe shadows, blur, and obstruction;
- avoid cutting off the head, tail, or body.

### General capture guidelines

- The app uses a single capture flow for both weight and health.
- Instruct users to capture the whole pig from above when possible, but allow side angles if the primary goal is a health assessment (weight will simply be skipped if the view is not suitable).

---

## 12. Error and fallback states

The app needs explicit handling for at least:

- no pig detected;
- multiple pigs detected;
- low-confidence view result;
- unusable or corrupt image;
- pig partly outside the frame;
- no reference object for weight mode;
- invalid custom reference length;
- reference endpoints too close or outside the image;
- segmentation failure;
- feature-extraction failure;
- unsupported model version;
- model loading failure;
- low-confidence health result.

The safest fallback is:

```text
Do not show a forced prediction.
Explain what failed.
Ask for another image or proceed with health processing if the image is still usable for visual assessment.
```

---

## 13. Results and data model

A suggested internal result object is:

```json
{
  "request_id": "unique-id",
  "model_version": "1.0.0",
  "view": {
    "label": "dorsal_valid",
    "confidence": 0.91
  },
  "segmentation": {
    "pig_count": 1,
    "confidence": 0.94,
    "mask_available": true
  },
  "weight": {
    "eligible": true,
    "value_kg": 82.4,
    "reference_length_cm": 100.0,
    "reference_pixel_length": 431.2,
    "cm_per_pixel": 0.2319,
    "features": {
      "RA": 0.21,
      "LC": 246.8,
      "BL": 121.3,
      "BW": 44.1,
      "E": 0.87
    },
    "failure_reason": null
  },
  "health": {
    "eligible": true,
    "class_name": "Healthy",
    "confidence": 0.74,
    "uncertain": false
  }
}
```

Do not store or display numerical fields that were not actually computed. When weight is blocked, set `eligible=false`, omit the prediction, and include a clear failure reason.

---

## 14. Testing required before release

### Model-parity testing

For a fixed set of images, compare app outputs against the Python pipeline for:

- view probabilities;
- segmentation masks and confidence;
- health probabilities;
- extracted RA, LC, BL, BW, and E;
- final weight predictions.

Define numerical tolerances before release.

### Functional testing

Test at least:

- valid dorsal image with 100 cm reference;
- valid dorsal image with 131 cm reference;
- valid custom reference length;
- dorsal image without reference;
- side-view health image;
- close-up lesion image;
- multiple-pig image;
- blurry image;
- partially cropped pig;
- partially hidden reference;
- HEIC/JPEG/PNG inputs where supported.

### Device testing

Measure on the actual target phones:

- cold-start time;
- median and P95 inference latency;
- memory use;
- model file sizes;
- battery and thermal behavior during repeated use;
- accuracy after model export or quantization.

GPU or desktop latency from the notebooks must not be reported as phone latency.

---

## 15. Privacy and offline behavior

The product team must decide whether inference runs:

- fully on-device;
- on a server;
- or through a hybrid approach.

For farm use, on-device inference may improve availability and privacy, but feasibility depends on the selected models and tested phones.

The app should clearly state:

- whether images leave the device;
- how long images and results are stored;
- whether users can delete records;
- whether data may be used for future model improvement;
- that explicit permission is required before uploading user images for research.

Do not silently add captured images to the training dataset.

---

## 16. Versioning and reproducibility

Every prediction should be traceable to:

- app version;
- deployment package version;
- view-model version;
- segmentation-model version;
- health-model version;
- XGBoost-model version;
- preprocessing version;
- threshold version;
- reference length used.

When any model, threshold, feature extractor, or preprocessing rule changes, increment the deployment version and rerun parity and device tests.

---

## 17. Minimum viable app versus later improvements

### Minimum viable app after training

- upload or capture one image;
- run the view-suitability model;
- run health classification when eligible;
- run YOLO segmentation;
- allow custom reference length entry;
- allow manual endpoint selection;
- calculate the five features;
- run the compatible physical-centimeter XGBoost model;
- show clear blocked, uncertain, and retake states;
- store model-version metadata.

### Later improvements

- live camera guidance;
- automatic phone-angle feedback;
- automatic reference-object detection;
- rectangular-marker perspective correction;
- temporal averaging from short video;
- multi-image health assessment;
- model updates and rollback;
- on-device quantization and acceleration;
- optional farm and pig record management.

---

## 18. App-development readiness checklist

Do not begin final app integration until these are available:

- [ ] All nine notebooks have completed successfully.
- [ ] `selected_models.json` has been reviewed by the research team.
- [ ] The selected view checkpoint and class mapping are available.
- [ ] The selected YOLO checkpoint is available.
- [ ] The selected health checkpoint and class mapping are available.
- [ ] A deployable predicted-mask XGBoost experiment has been selected.
- [ ] The selected weight model uses a feature space compatible with smartphone reference scaling.
- [ ] View, health, segmentation, and routing thresholds have been validated.
- [ ] Exact preprocessing and feature definitions have been frozen.
- [ ] The research checkpoints have been exported to the selected mobile runtime.
- [ ] Exported-model parity tests have passed.
- [ ] Target-phone benchmarks have been completed.
- [ ] User-facing medical and uncertainty wording has been approved.

---

## 19. Important current limitation

The notebooks do not train an automatic detector for arbitrary reference objects. They use known dimensions and manually approved reference endpoints for Porac feature extraction.

Therefore, the first app should either:

- ask the user to enter/select the known reference length and mark two endpoints; or
- wait until a separate reference-object detector has been collected, trained, and validated.

The manual-endpoint approach is the most direct way to support different known reference lengths without restricting users to a one-meter stick.
