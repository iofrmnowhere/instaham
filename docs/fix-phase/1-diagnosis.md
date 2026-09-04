# Phase 1 — Diagnosis

Status: done

Condensed from `ref_fix.md` §1–§3. Every number here is measured, not inferred: the whole
native weight branch was replicated in Python against the real exported models in
`assets/ml/` and the three photos in `.pig_pictures/`, and the failure reproduced exactly.
The harness is checked in at `ML/tools/replicate_native_weight_branch.py`.

## Symptom, as logged

From `ref_log.md`, device runs before round 4:

| photo | reference | cm/px | result |
|---|---|---|---|
| 92 kg | meter stick, 100 cm | 100.0 / 1545 px = 0.0647 | rejected, `mask_implausibly_small`, 9.5% of frame diagonal |
| 118 kg | porac stick, 131 cm | 131.0 / 2007 px = 0.0653 | rejected, `subject_smaller_than_trained`, BL 140.1, BW 49.9 |
| 96 kg | porac stick, 131 cm | 131.0 / 2070 px = 0.0633 | 139.3 kg |

The reference object was marked correctly in all three — the derived cm/px agrees to within
3% across the set — yet two of the three user-visible messages pointed at it.

## Fidelity of the replication

On the 118 kg photo the harness reproduces the app's `BL` / `BW` / `LC` / `E` to within 5%
(134.0 / 48.6 / 400.9 / 0.942 against 140.1 / 49.9 / 385.3 / 0.945), and it reproduces the
92 kg photo's mask-diagonal fraction to within 0.1 pp (0.096 against 0.095). It mirrors
`ImageService.processRawBytes` plus the picker's 3000 px cap, `letterbox`,
`run_segmentation` including `mask_geometry.h`'s F12 selection, `construct_pig_mask`,
`scale_mask_to_training_space` and `extract_five_features`.

The one place it does **not** agree is `RA` — see F24 in phase 3.

## Defect 1 — the segmenter never sees a pig-shaped thing

Drawing every surviving detection on the 640×640 input the model actually receives:

| photo | above conf 0.25 | what they are | largest box |
|---|---|---|---|
| 92 kg | 34 (5 after NMS) | both ears, two flip-flops | 49×69 px |
| 118 kg | 21 (4 after NMS) | both ears, a person's foot | 78×96 px |
| 96 kg | 20 (2 after NMS) | the feet, another pig's snout through a grate | 72×55 px |

The pig measures roughly 220×400 px in that same input and is never proposed. Confidence on
the ears runs 0.87–0.92, so this is not a marginal miss. The decisive check: across all 8400
anchors on all three photos, **every box larger than about 100×100 px carries a class score
of 0.000.** There is no whole-pig detection sitting under the threshold, so lowering `conf`
cannot recover it.

Placing the same image inside the same canvas at a fraction of its fitted size — padding the
field of view rather than cropping it — recovers the animal:

| photo | content at 100% | 60% | 40% | 30% |
|---|---|---|---|---|
| 92 kg | 49×69 (ear) | 32×33 | 14×17 | **56×140, conf 0.87 — the pig** |
| 96 kg | 72×55 (snout) | **129×301, conf 0.53** | **84×207, conf 0.89** | **63×155, conf 0.67** |
| 118 kg | 78×96 (ear) | 37×29 | none | none |

At the recovered scales the mask is clean and complete — nose to tail, both flanks, no
leakage into the floor or the stick. Expressed in the unit that transfers between photos:
the model detects reliably at roughly **0.9–1.9 cm per canvas pixel**, and fails completely
at the ~0.30 cm/px a full-frame letterbox produces for a 2250×3000 phone photo. A **3–6×
scale mismatch**, and it is the whole of defect 1.

Why the existing scale handling did not catch it: `scale_mask_to_training_space` applies
`k = cm_per_px_actual / cm_per_px_target` to the mask **after** segmentation. That corrects
the measurement space and does nothing for the detection space, because `letterbox()`
normalises the whole frame to 640 either way. Only padding the field of view changes the
apparent object scale.

## Defect 2 — the regressor answers from its ceiling

With a correct whole-pig mask, at the then-shipped `cm_per_px_target = 0.26`:

| photo | RA | LC | BL | BW | E | predicted | true |
|---|---|---|---|---|---|---|---|
| 92 kg | 0.1599 | 1573 | 543 | 203 | 0.948 | **180.7 kg** | 92 |
| 118 kg | 0.1529 | 1942 | 619 | 233 | 0.936 | **173.8 kg** | 118 |
| 96 kg | 0.1704 | 1765 | 624 | 200 | 0.960 | **181.2 kg** | 96 |

All three land within 5% of each other across a 26 kg spread in true weight. `LC` exceeds
the trained maximum of 1540 on all three; `BL` and `BW` sit at or above the top of their
ranges. The ensemble cannot extrapolate, so each is answered from the top leaf — measured
empirically at **≈182 kg**, with a symmetric floor at **≈83.5 kg**.

So fixing the mask alone would have converted two rejections and one +45% number into three
ceiling values. Both defects had to be fixed in the same round.

## Calibration evidence for `cm_per_px_target`

Two independent methods, agreeing. First, comparing the measured vectors above against the
regressor's own eval-row medians by weight bin
(`ML/weight_prediction/fixed_test_predictions_POSTHOC.csv`), dividing out the documented
uncut-cutter inflation (`BW` × 1.10, `LC` × 1.35). `BW` is the minor axis of the
`minAreaRect`, the feature the head barely perturbs:

| photo | measured BW | trained BW | ratio | implied target from BW | from LC |
|---|---|---|---|---|---|
| 92 kg | 203 | 130 | 1.56 | **0.368** | 0.311 |
| 96 kg | 200 | 136 | 1.47 | **0.347** | 0.345 |

Second, sweeping `cm_per_px_target` and reading the regressor's output — a genuinely
separate signal, since it goes through the trees rather than the feature medians:

| target | 92 kg | 118 kg | 96 kg |
|---|---|---|---|
| 0.26 (then shipped) | 180.7 (+96%) | 173.8 (+47%) | 181.2 (+89%) |
| 0.32 | 117.5 (+28%) | 103.6 (−12%) | 104.5 (+9%) |
| **0.35** | **90.0 (−2%)** | **107.7 (−9%)** | **110.3 (+15%)** |
| 0.38 | 87.5 (−5%) | 82.6 (−30%) | 83.8 (−13%) |

Both put the target in the 0.33–0.37 band. The per-row differences between 0.34, 0.35 and
0.36 are **not** signal — three samples through a step function; the whole 0.32–0.36 band is
equivalent on this evidence.

## Standing caveat

This is a field estimate replacing an admitted guess, not the 1.88 m calibration capture. It
partially absorbs the missing cutter rather than separating it: head/neck inflation and
scale error push the same direction, and three photos cannot untangle them. It is right for
today's build and wrong for the build after the cutter lands.
