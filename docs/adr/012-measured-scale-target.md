# ADR-012: `cm_per_px_target` ships the measured plateau minimum 0.34

Status: Accepted

Context: [ADR-011](011-derived-scale-target.md) shipped `cm_per_px_target = 0.3289473684210526`
(`100 / 304`, the PIGRGB floor-plane derivation) and stated plainly that the accuracy consequence
of doing so was "presently unknown and must not be stated either way", owing a re-run of
`ML/host_scale_test/` on the post-F55 composed-transform path before any weight figure could be
quoted against the constant. That re-run is now done
([../scale-constant-sweep-results-2.md](../scale-constant-sweep-results-2.md), 2026-09-14;
primary record [../sweep-phase/4-run-and-record.md](../sweep-phase/4-run-and-record.md)).

It measured two corpora separately — corpus B, `PIGRGB-Weight/sub_1.88/` (5 images, the
regressor's own training distribution, floor row `74.4kg_9.png` excluded by
`extrapolated_features`), and corpus A, `.pig_pictures/` (4 field photographs, one excluded for
having no device row to cross-check) — for seven informative rows in total. Three findings
decide this ADR:

1. **Both corpora independently minimize MAE at `0.34`**, a value neither previously-shipped
   candidate: corpus B 2.1% (bias +0.2%), corpus A 4.0%. `0.3289473684210526` is the *worst* of
   the three candidates on both corpora (5.4% and 7.7%); the fitted `0.35` sits between them
   (4.1% and 7.4%) with a consistent underestimation bias.
2. **The surface through 0.32–0.36 is a shallow bowl, not a step**, confirming the equivalence
   region `../fix-phase/1-diagnosis.md` predicted. The choice between any two candidates *inside*
   the plateau is worth a few points of MAE; the choice to stay inside it is worth tens.
3. **A `k = 1.0` arm — the scale step proven a genuine no-op, `mask_area_px` unchanged, not
   merely close — still leaves corpus B at 5.42% MAE, +5.35% bias, one image at +14.29%.** That
   error belongs to segmentation, the cutter, feature extraction, the regressor, or the 304 px/m
   geometric theory, and bounds how good *any* choice of this constant can make corpus B look.

Decision: Ship `cm_per_px_target = 0.34`, tagged
`host_scale_sweep_round28_f59_measured_mae_minimum_scale_constant_sweep_results_2_md`, in
`assets/ml/manifest.json` and in `ML/export/export_xgboost.py`, which emits it. This supersedes
ADR-011's constant choice only.

The constant is once again *measured* rather than *derived*, which reverses the property ADR-011
chose it for. That is accepted deliberately: ADR-011's preference for a derivation was made in
the explicit absence of any measurement on the live path, as a tie-break between two unmeasured
arms. A measurement on the current pipeline now exists, it ranks the derived value last on both
corpora, and it is not the round-4 failure mode ADR-011 and
[ADR-004](004-calibration-requires-repeat-captures.md) guard against — that was a single fitted
constant absorbing a known stage defect (the identity cutter, [ADR-005](005-identity-cutter-is-the-dominant-error.md)),
whereas 0.34 is an agreement between two corpora, one of which the regressor never trained on,
against a ported cutter ([ADR-009](009-cutter-ported-after-all.md)).

Consequences:

- **The PIGRGB floor-plane derivation survives as the baseline, not as the shipped value.**
  [../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md](../INSTAHAM_CAMERA_SCALE_NORMALIZATION.md) remains
  the authority for 304 px/m and for corpus B's `cm_per_px_actual`; the shipped target simply no
  longer equals it. One consequence is concrete: because corpus B's actual scale *is* the derived
  value bit-for-bit, shipping 0.34 means the `k = 1.0` self-consistency arm is no longer the
  shipping configuration on that corpus, and the resample step is live again on every image.
- **`cm_per_px_target_uncertainty` stays 1.30 and the domain gate stays correspondingly wide.**
  Seven informative rows, host-side, is not a field calibration. ADR-004's requirement for repeat
  captures at a measured 1.88 m is unmet and untouched by this ADR, and
  `docs/conversion-justification.md` §6 action 1 still stands.
- **The "do not quote an accuracy figure" rule of ADR-011 is partially lifted.** Host MAE figures
  from this round may now be quoted *as host figures on seven rows*, with the corpora reported
  separately. They are not device numbers — host ONNX Runtime 1.29.0 against the Android `.so` is
  the same graph, not bit-identical — and corpus B's agreement is partly memorisation.
- **The 0.34-over-0.35 margin is not durable.** 2.0 points on corpus B and 3.4 on corpus A, over
  seven rows, inside corpus A's 5.18–12.55% hand-marking jitter band. A larger corpus may reorder
  the plateau's interior. What the round establishes durably is the plateau's *extent*, not its
  exact minimum.
- **This ADR does not address the `k = 1.0` residual**, which is now the largest identified error
  term in the weight branch and has no owning document. It is not a calibration problem and will
  not be fixed by any value of this constant.
- [ADR-010](010-regressor-training-domain-floor.md)'s ~73 kg regressor floor is untouched and
  still governs: below roughly 85 kg no constant helps, and `extrapolated_features` must be
  checked before attributing a low-end error to scale.
- Host-side artifacts naming other constants — `ML/host_scale_test/`'s `envelope_*_0350.json` and
  `envelope_*_03289.json` outputs and the two-arm drivers — are historical records of this
  measurement, not current configuration.
