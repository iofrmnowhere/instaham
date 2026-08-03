# Inference Pipeline Flow Reference

Detailed breakdown of the orchestrated pipeline as defined in Section 4 of the requirements.

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
    ├── label == 'reject' → PipelineResultEntity { eligible=false, failureReason }
    │
    ├── label == 'health_only'
    │     └── [3a] HealthClassifyUseCase → HealthResultEntity
    │
    └── label == 'dorsal_valid'
          ├── [3a] HealthClassifyUseCase → HealthResultEntity
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
