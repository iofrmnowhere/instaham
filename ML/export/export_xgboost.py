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
