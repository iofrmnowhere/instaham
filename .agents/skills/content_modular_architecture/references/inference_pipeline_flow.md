# Inference Pipeline Flow Reference

Detailed breakdown of the orchestrated pipeline as defined in `run_inference_pipeline_use_case.dart`.
The view-suitability model uses two labels: `dorsal_valid` and `reject`.
A low-confidence result (below `viewConfidenceThreshold`, default 0.70) is treated as `reject`.

## Step-by-step

```
CapturedImageEntity
    │
    ▼
[1] BasicFileChecksUseCase
    │ - Verifies file is readable, non-corrupt, supported format (JPEG/PNG/HEIC)
    │ - Corrects EXIF orientation
    │
    ▼
[2] ViewSuitabilityClassifyUseCase
    │ - Input: 224×224 center-cropped, ImageNet normalized
    │ - Returns: ViewResultEntity { label, confidence }
    │
    ├── label == 'reject' OR confidence < viewConfidenceThreshold
    │     └── PipelineResultEntity { view: reject, health: null, weight: null }
    │
    └── label == 'dorsal_valid' (high-confidence)
          ├── [3a] HealthClassifyUseCase → HealthResultEntity
          │       (runs independently; failure sets eligible=false but does not block weight)
          │
          └── [3b] SegmentationUseCase → SegmentationResultEntity
                      │
                      ├── Any eligibility check fails
                      │     └── WeightResultEntity { eligible=false, failureReason }
                      │
                      └── All checks pass
                            ├── [4] ComputeScaleUseCase (from reference endpoints)
                            ├── [5] ExtractWeightFeaturesUseCase → [RA, LC, BL, BW, E]
                            └── [6] RunXGBoostUseCase → WeightResultEntity { value_kg }
```

## Eligibility Checks (all must pass for weight prediction)

| # | Check | Failure Reason Key |
|---|---|---|
| 1 | Exactly one pig detected | `multiple_pigs` / `no_pig` |
| 2 | Full body within frame | `pig_truncated` |
| 3 | No severe occlusion | `pig_occluded` |
| 4 | Suitable dorsal posture | `unsuitable_posture` |
| 5 | Valid reference object present | `no_reference` |
| 6 | Reference has positive real-world length | `invalid_reference_length` |
| 7 | Endpoints sufficiently far apart | `endpoints_too_close` |
| 8 | Reference on same floor plane as pig | `reference_plane_mismatch` |
| 9 | Features pass sanity ranges + finite | `feature_extraction_failure` |
