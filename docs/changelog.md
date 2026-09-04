# Changelog

Entries before 2026-09-05 are backfilled from `ref_fix.md` and git history; all three landed
in a single commit (`c198456`), which is why they share a date.

- 2026-09-04 [fix] Round 2 (F6–F11): persist the feature vector on every run, so a domain rejection is diagnosable from a log rather than a code read
- 2026-09-04 [fix] Round 3 (F12–F17): score candidate masks cropped to their own detection box, add the mask-plausibility gate, and name why a feature vector left the trained domain
- 2026-09-04 [fix] Round 4 (F18–F23): compose the segmenter canvas from the reference scale with a retry ladder, persist segmentation/construction telemetry, recalibrate `cm_per_px_target` to 0.35, and flag extrapolated predictions (ADR-003)
