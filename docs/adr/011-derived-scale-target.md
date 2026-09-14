# ADR-011: `cm_per_px_target` returns to the derived PIGRGB floor-plane value

Status: Superseded by [012](012-measured-scale-target.md) — the validation this ADR left
outstanding was run on 2026-09-14 and ranked this constant last of three candidates on both
corpora. ADR-012 supersedes the constant choice below only; the reasoning about the pre-F55
sweep's obsolescence stands.

Context: [ADR-010](010-regressor-training-domain-floor.md) decided that
`weight.cm_per_px_target` would stay at **0.35** as an empirical fit, and explicitly retracted
the specification's theoretical 304 px/m as a shipped value. That decision rested on one
measurement: the host sweep of 2026-09-09
([../scale-constant-sweep-results.md](../scale-constant-sweep-results.md)), in which 0.35 beat
0.3289 on MAE (11.5% against 19.0%) and on all five PIGRGB images individually.

Two things have changed since.

1. **The sweep predates round 7's composed transform.** It was measured on the
   `construct_pig_mask` → `scale_mask_to_training_space` chain, which rasterized the mask twice
   with `INTER_NEAREST` and grid-snapped in a way that depended on `k` — and therefore on the
   constant being swept. F55 replaced that with a single composed crop-and-scale
   (`transform_mask_to_training_space()`, [../pipeline/segmentation-2.md](../pipeline/segmentation-2.md)),
   so the eight boundary-derived features of `chen16_noheight` no longer see the staircase the
   sweep's arms were compared through. Every number in that sweep was produced by a code path
   the weight branch no longer runs.
2. **0.35's provenance was never independent of a defect.** The sweep document's own
   "Why the fitted 0.35 beat the theoretical 0.3289" section records it: 0.35 was introduced in
   round 4 (F21) to absorb head-and-neck area while the cutter was an identity stub, 304 px/m
   was never measured against a pig either, and the three optimization criteria disagree
   (MAE at 0.35, |bias| at 0.38, spread at 0.30) — the signature of a constant that is not the
   live error term.

Decision: Ship `cm_per_px_target = 0.3289473684210526`, derived as `100 / 304` from the PIGRGB
floor-plane baseline of 304 px/m in the released `RGB_9579` coordinate system, and tag its
`_source` field accordingly. [INSTAHAM_CAMERA_SCALE_NORMALIZATION.md](../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md)
is the authority for that baseline; the manifest carries a value derived from it rather than an
independent estimate. The constant is now a *derived* quantity with a written derivation, not a
fit against five photographs, which is the property ADR-004 asked for and no fitted value has
ever had.

This supersedes ADR-010's constant retention only. ADR-010's primary finding — the regressor's
~73 kg training-domain floor, and the conclusion that no value of this constant can recover a
feature vector outside the trained domain — is untouched and still governs.

Consequences: On the 2026-09-09 sweep's own numbers this basis was the worse of the two arms,
and nothing has yet re-measured it on the post-F55 path, so **the accuracy consequence of this
change is presently unknown and must not be stated either way.** A re-run of
`ML/host_scale_test/` over the same five PIGRGB images, on the current pipeline, is owed before
any weight figure is quoted against this constant; until it exists,
[../scale-constant-sweep-results.md](../scale-constant-sweep-results.md) describes a
superseded code path and a value that no longer ships.

`cm_per_px_target_uncertainty` stays at 1.30 and the domain gate stays correspondingly wide —
a derivation is not a field calibration, and [ADR-004](004-calibration-requires-repeat-captures.md)'s
requirement for repeat captures at a measured 1.88 m is unmet and unchanged by this ADR.
[ADR-010](010-regressor-training-domain-floor.md)'s floor still means no constant helps below
roughly 85 kg. Two host-side artifacts still name 0.35 as the shipped arm —
`ML/host_scale_test/run_sweep.py`'s two-arm driver and the `envelope_*_0350.json` outputs — and
are historical records, not current configuration.
