"""Convert the final XGBoost weight regressor (model.json) to ONNX + a manifest fragment.

    python -m ML.export.export_xgboost \
        --model ML/weight_prediction/model.json \
        --metadata ML/weight_prediction/model.metadata.json \
        --out build/ml_export/weight

Emits:
    weight/xgboost.onnx
    weight/feature_order.json   {"feature_family": "baseline5", "features": ["RA","LC","BL","BW","E"]}
    weight/xgboost.meta.json    (feature_names, n_estimators, objective, source sha256)
    weight/manifest_fragment.json
"""
from __future__ import annotations

import argparse
from pathlib import Path

from ML.export.common import BASELINE5, read_json, sha256_file, write_json


def export(
    *,
    model: Path,
    metadata: Path | None,
    out: Path,
    opset: int = 15,
    enable_for_testing: bool = False,
) -> Path:
    import numpy as np
    import onnxruntime as ort
    import xgboost as xgb
    from onnxmltools import convert_xgboost
    from onnxmltools.convert.common.data_types import FloatTensorType

    out.mkdir(parents=True, exist_ok=True)

    booster = xgb.Booster()
    booster.load_model(str(model))
    feature_names = list(booster.feature_names or BASELINE5)
    if feature_names != BASELINE5:
        raise SystemExit(
            f"XGBoost feature order {feature_names} != required {BASELINE5} (AGENTS.md rule 2)"
        )

    # onnxmltools' tree walker only accepts generic 'f%d' feature names. The named
    # order is verified above (AGENTS.md rule 2) and re-asserted in the self-check
    # below by feeding rows in BASELINE5 order; renaming here does not relax the rule.
    booster.feature_names = [f"f{i}" for i in range(len(BASELINE5))]

    onnx_model = convert_xgboost(
        booster,
        initial_types=[("input", FloatTensorType([None, len(BASELINE5)]))],
        target_opset=opset,
    )
    onnx_path = out / "xgboost.onnx"
    onnx_path.write_bytes(onnx_model.SerializeToString())

    # self-check: xgboost vs ORT on random rows
    rows = np.random.rand(8, len(BASELINE5)).astype("float32")
    ref = booster.predict(xgb.DMatrix(rows, feature_names=booster.feature_names))
    got = ort.InferenceSession(onnx_path.as_posix()).run(None, {"input": rows})[0].ravel()
    max_abs = float(np.max(np.abs(ref - got)))
    if max_abs >= 1e-3:
        raise SystemExit(f"XGBoost/ONNX divergence too large: {max_abs:.2e}")

    meta_src = read_json(metadata) if metadata and metadata.exists() else {}
    write_json(
        out / "feature_order.json",
        {"feature_family": "baseline5", "features": BASELINE5},
    )
    write_json(
        out / "xgboost.meta.json",
        {
            "feature_names": BASELINE5,
            "n_estimators": int(meta_src.get("params", {}).get("n_estimators", 0)) or None,
            "objective": "reg:squarederror",
            "target": meta_src.get("target", "weight_kg"),
            "source_model_sha256": sha256_file(model),
        },
    )

    # --enable-for-testing (default False) is a deliberate, opt-in override of
    # ML_implementation_plan.md revision 7 section 3.4's rule that weight.available must
    # stay false while the cutter is a permanent identity dummy. It exists ONLY to let a
    # developer manually verify the C++ weight_prediction stage end-to-end on a real
    # device -- estimated_kg will read heavy because the head/neck were never removed
    # from the mask. Never pass this flag when building a manifest meant to ship.
    weight_block: dict = {
        "available": bool(enable_for_testing),
        "stability": "temporary",
    }
    if enable_for_testing:
        weight_block["note"] = (
            "TEST OVERRIDE: cutter is the identity stub (head/neck not removed). "
            "estimated_kg overestimates the research protocol's number."
        )
    else:
        weight_block["unavailable_reason"] = "cutter_identity_stub"

    fragment = {
        "weight": {
            **weight_block,
            # ref_fix.md F16/F23: minimum fraction (of the image's own diagonal) the
            # constructed mask's bounding-box diagonal must reach before the
            # cutter/feature/domain gate stages even run on it -- a mask smaller than
            # this isn't a pig. Raised from 0.15 to 0.35 in F23: measured against the
            # three ground-truth photos in .pig_pictures/, every CORRECT whole-pig mask
            # (once F18 fixes detection) came in at 0.62-0.74, and every WRONG mask (an
            # ear, a foot, a snippet of another pig through a grate) came in at 0.06-0.15
            # -- the old 0.15 threshold sat exactly on the wrong edge of that gap and let
            # a 0.149 junk mask (the 118kg photo, pre-F18) through. Also the threshold
            # pipeline.cpp's F19 retry ladder tests each rung against, so raising it here
            # makes the ladder retry rather than settle for the first junk mask. Tunable
            # here rather than a compiled-in native constant; a manifest that predates
            # this field falls back to manifest.h's own 0.15 default.
            "min_mask_diagonal_fraction": 0.35,
            "regressor": {
                "format": "onnx",
                "path": "weight/xgboost.onnx",
                "sha256": sha256_file(onnx_path),
                "meta_path": "weight/xgboost.meta.json",
                "meta_sha256": sha256_file(out / "xgboost.meta.json"),
                "feature_order_path": "weight/feature_order.json",
                "feature_order_sha256": sha256_file(out / "feature_order.json"),
                "feature_family": "baseline5",
                "objective": "reg:squarederror",
            },
            "feature_extractor": {
                "protocol_version": "baseline5_v1",
                "names": BASELINE5,
                "linear_scale": 1.0,
            },
            "body_mask": {
                "stage": "provisional",
                "protocol_version": "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26",
                "ported_functions": [
                    "clean_binary_mask",
                    "isolate_dorsal_core_ji_duan",
                    "extract_five_features",
                    "unletterbox_native_mask",
                ],
            },
            "capture_contract": {
                "feature_space": "fixed_camera_pixels",
                "training_camera_height_m": 1.88,
                "camera_height_is_xgboost_feature": False,
                # TASKS.md W1: cm/px this regressor's features were trained at, and the
                # frame (px) RA's denominator was measured against -- 720x720 is recovered
                # exactly (body_mask_area_px / RA on every row of
                # ML/weight_prediction/fixed_test_predictions_POSTHOC.csv). cm_per_px_target
                # is NOT recoverable from anything in this repo and the value below is an
                # unmeasured order-of-magnitude seed (see TASKS.md section 3.2/4) -- replace
                # it with the median of several 1.88m calibration captures (TASKS.md W1)
                # before trusting a predicted weight. packages/instaham_ml_ffi's
                # load_manifest() refuses to load a weight-available manifest missing
                # either field, so this contract must travel with every export.
                # ref_fix.md F21 (round 4): replaces the round-1 0.26 seed above. Derived
                # two independent ways against the three ground-truth photos in
                # .pig_pictures/ (ref_fix.md section 3, F21):
                #   1. BW (the minAreaRect minor axis, the feature the identity-stub cutter
                #      perturbs least) measured on the uncut mask, divided by the trained
                #      BW median for each photo's true-weight bin in
                #      fixed_test_predictions_POSTHOC.csv, implies 0.347-0.368.
                #   2. Sweeping cm_per_px_target and reading the regressor's own output
                #      lands all three photos within +/-15% of true weight in the
                #      0.32-0.36 band, independently of (1).
                # Both land in the same place. 0.35 is a three-sample field estimate, NOT
                # the 1.88m calibration capture TASKS.md W1 still asks for -- retune
                # (downward) the moment the real cutter lands, since this value currently
                # absorbs some of the cutter's head/neck inflation as well as the scale
                # error, and three photos cannot separate the two.
                "cm_per_px_target": 0.35,
                "cm_per_px_target_source": (
                    "three_sample_field_estimate_pending_1p88m_calibration_capture"
                ),
                # ref_fix.md F9/F21: how far cm_per_px_target above might be off, expressed
                # as a multiplicative bound (>= 1.0). Widens (pipeline.cpp's
                # feature_in_domain), never tightens, the SIZE feature_domain bounds below,
                # so the eligibility gate is never stricter than the calibration it rests on
                # (ref_fix.md section 1.5). Set to 1.0 the moment a real 1.88m calibration
                # capture replaces the field estimate above -- this is the MANIFEST's
                # uncertainty about itself, not a per-photo tolerance. Raised from 1.15 to
                # 1.30 alongside F21's retune: a three-sample field estimate carries more
                # uncertainty than the allometric guess it replaced.
                "cm_per_px_target_uncertainty": 1.30,
                "training_frame_px": [720, 720],
            },
            # ref_fix.md F3/F8: the [min, max] each feature actually took across the
            # regressor's own eval set (ML/weight_prediction/fixed_test_predictions_POSTHOC.csv,
            # 2014 rows) -- a normalized feature vector outside this range is rejected by
            # the native pipeline rather than fed to the regressor (AGENTS.md rule 8),
            # replacing a resolution-blind k-range check with a check on the thing that
            # actually determines whether the model has ever seen anything like this input.
            #
            # `upper_multiplier` / `lower_multiplier` widen the max / min respectively, to
            # allow for the identity-stub cutter leaving the head/neck in the mask. Unlike
            # the flat 1.5x this replaced, each multiplier here is measured, not guessed:
            # the same CSV also carries `whole_mask_area_px` (uncut, i.e. exactly what the
            # identity-stub cutter produces) alongside `body_mask_area_px` (head-removed).
            # Their ratio across all 2014 rows is min=1.0148, p50=1.1210, p99=1.3400,
            # max=1.4121 -- so:
            #   - RA is an AREA ratio and whole_mask_area_px/720^2 is directly the uncut
            #     domain (min=0.0760, max=0.2042); no multiplier is needed at all.
            #   - LC/BL are LENGTHS: an area inflation of up to 1.34 (p99) bounds their
            #     linear inflation from above; 1.35 is used, deliberately conservative since
            #     the head mostly adds length, not width.
            #   - BW is the MINOR axis of minAreaRect, which the head barely perturbs; 1.10
            #     reflects that rather than reusing the LC/BL figure.
            #   - E (eccentricity) is a shape ratio the cutter can move in EITHER direction,
            #     so unlike the others it also gets a lower_multiplier (0.97) -- the only
            #     feature where "smaller than trained" has no such excuse does not apply.
            # Retune (tighten toward 1.0) once the real cutter lands.
            "feature_domain": {
                "RA": {"min": 0.0760, "max": 0.2042, "upper_multiplier": 1.0, "lower_multiplier": 1.0},
                "LC": {"min": 811.5605, "max": 1540.2884, "upper_multiplier": 1.35, "lower_multiplier": 1.0},
                "BL": {"min": 312.4134, "max": 638.0170, "upper_multiplier": 1.35, "lower_multiplier": 1.0},
                "BW": {"min": 118.4502, "max": 207.9156, "upper_multiplier": 1.10, "lower_multiplier": 1.0},
                "E": {"min": 0.8888, "max": 0.9773, "upper_multiplier": 1.05, "lower_multiplier": 0.97},
            },
        }
    }
    return write_json(out / "manifest_fragment.json", fragment)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--metadata", type=Path, default=None)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--opset", type=int, default=15)  # onnxmltools XGBoost converter caps at opset 15
    ap.add_argument(
        "--enable-for-testing",
        action="store_true",
        help=(
            "DEV ONLY: flips weight.available to true so instaham_ml_predict_weight_json "
            "and the pipeline's weight branch return a real (uncut-mask, overestimated) "
            "kg number instead of ERR_UNAVAILABLE. Overrides ML_implementation_plan.md "
            "revision 7 section 3.4's rule. Never pass this for a build meant to ship."
        ),
    )
    a = ap.parse_args()
    written = export(
        model=a.model,
        metadata=a.metadata,
        out=a.out,
        opset=a.opset,
        enable_for_testing=a.enable_for_testing,
    )
    print(f"wrote {written}")


if __name__ == "__main__":
    main()
