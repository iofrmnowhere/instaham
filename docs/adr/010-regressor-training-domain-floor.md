# ADR-010: The regressor's training-domain floor, not the scale constant or the cutter, is the weight branch's dominant error

Status: Accepted

Context: [ADR-005](005-identity-cutter-is-the-dominant-error.md) attributed the weight branch's
systematic field bias to the identity cutter and priced it at roughly 16% of mean bias. That
attribution was made by feature substitution on the pre-port app, and its own consequence
section required that no accuracy claim cite the port as evidence until a real run re-measured
it. [ADR-009](009-cutter-ported-after-all.md) then shipped the real V176/V144 cutter and
restated that its closure was unverified in the field. Both ADRs therefore left the same
question open: with the real cutter running, what is actually the largest error term?

That question has now been measured off-device. `ML/host_scale_test/` compiles the app's own
stages — segmentation, construction, the `k`-resample, the vendor V176/V144 cutter, Chen16
feature extraction and XGBoost-via-ONNX — against the shipped `assets/ml/` models, and was run
over five PIGRGB images with known true weights while sweeping `cm_per_px_target` across eight
values from 0.28 to 0.50. `cutter_status` was `cut_applied` on every run, `kept_fraction`
0.80–0.93, so the head and neck were genuinely removed before features were measured. Full
results are in [../scale-constant-sweep-results.md](../scale-constant-sweep-results.md).

Three findings, in order of weight:

1. **The regressor cannot emit a prediction below roughly 73 kg.** Every image in the sweep
   bottoms out near that value. The 60.27 kg pig moves only 74.34 → 80.72 kg across a 79%
   change in the constant, while the 125 kg pig swings 104 kg over the same range. At extreme
   constants the heavy pigs are shrunk below the floor too and collapse onto the same ~73 kg,
   which makes this a property of the ensemble rather than of any one photograph.
2. **The cause is training coverage, checked against the raw trained range.** Both light pigs
   sit below the trained minimum on every gated size feature (the 60.27 kg pig: `mask_area`
   25425 < 36647, `perimeter` 733 < 861, `longest` 290 < 332, `shortest` 90 < 103). The model
   has never seen a pig that small and answers from its floor leaf — the condition
   `pipeline.cpp` already reports as `extrapolated`. The training set's own lightest pig is
   73.36 kg, which is the floor exactly.
3. **The geometry chain is sound.** The two in-domain pigs predict within ±5% at 0.35 (−4.1%,
   +1.1%), so segmentation, the cutter, the resample and the features are not the live error
   term for a pig the model was trained to see.

Decision: Attribute the weight branch's dominant remaining error to the regressor's training
domain at the low end, and treat it as a model-coverage problem rather than a calibration or
stage-porting problem. ADR-005's attribution to the cutter is superseded — not because its
measurement was wrong, but because the stage it named has since been ported and the error it
predicted did not follow. Scaling is explicitly ruled out as a remedy: a feature vector outside
the trained domain cannot be recovered by any value of `cm_per_px_target`, which is why the
sweep's three optima disagree (minimum MAE at 0.35, minimum |bias| at 0.38, minimum spread at
0.30). `cm_per_px_target` stays at 0.35 as an empirical fit on the strength of the same sweep,
and the specification's theoretical 304 px/m is retracted as a shipped value per
`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` §24, which directs that it be replaced once empirical
calibration exists.

Consequences: For any pig under roughly 85 kg the shipped estimate reads high by 20% or more
and no calibration work will fix it; if that is inside the product's intended range, extending
the regressor's training coverage is the next accuracy task and it is a retraining job, not a
pipeline job. The existing `extrapolated` / `extrapolated_features` fields already name this
condition per-prediction and are the right surface to act on — the branch does not currently
withhold or qualify an estimate on that basis, and whether it should is open product work.
[ADR-004](004-calibration-requires-repeat-captures.md)'s rule survives untouched and gains a
second reason: a constant fitted against pigs sitting on the floor leaf is fitting noise, since
those rows barely respond to it.

The measurement's own limits are part of this record. Five images, all PIGRGB — the regressor's
own training distribution — so agreement on the in-domain pigs is partly memorization and does
not predict field accuracy. The capture height of 1.78 m comes from the dataset folder's
description rather than a repository document, and every scale figure moves with it. The host
run links ONNX Runtime 1.29.0 where the device links the Android `.so`: same graphs, not
bit-identical. And `weight_branch_cli.cpp` does not yet record the `extrapolated` fields the app
emits, so the excursion table was reconstructed from envelopes after the fact.
