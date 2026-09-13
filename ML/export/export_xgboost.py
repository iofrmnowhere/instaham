"""Convert the XGBoost weight regressor (model.json) to ONNX + a manifest fragment.

    python -m ML.export.export_xgboost \
        --model ML/weight_prediction_chen16/model.json \
        --feature-family chen16_noheight \
        --test-predictions ML/weight_prediction_chen16/fixed_test_predictions.csv \
        --test-metrics ML/weight_prediction_chen16/fixed_test_metrics.json \
        --params ML/weight_prediction_chen16/selected_params.json \
        --out build/ml_export/weight

Emits:
    weight/xgboost.onnx
    weight/feature_order.json    {"feature_family": ..., "features": [...]}
    weight/xgboost.meta.json     (feature_names, n_estimators, objective, base_score,
                                  source sha256, onnx_max_abs_diff, reproduced_test_mae)
    weight/manifest_fragment.json (weight capability block — see docs/plan-phase/3-manifest-pipeline.md)
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

from ML.export.common import FEATURE_FAMILIES, read_json, sha256_file, write_json

# Per-feature dimension and eligibility-gate flags for chen16_noheight.
# dimension drives the calibration-uncertainty exponent in pipeline.cpp:
#   area -> uncertainty**2, linear -> uncertainty**1, dimensionless -> uncertainty**0.
# gate: only the features k actually scales, and where "the model has never seen a pig
#   this size" is the real question, are gated. The other ten are diagnostics only.
# See docs/plan-phase/3-manifest-pipeline.md.
_CHEN16_FEATURE_META = {
    "mask_area":        {"dimension": "area",          "gate": True},
    "convex_hull_area": {"dimension": "area",          "gate": True},
    "difference":       {"dimension": "area",          "gate": True},
    "dif_mask":         {"dimension": "dimensionless", "gate": False},
    "body_curve":       {"dimension": "dimensionless", "gate": False},
    "perimeter":        {"dimension": "linear",        "gate": True},
    "outline_curve":    {"dimension": "dimensionless", "gate": False},
    "longest":          {"dimension": "linear",        "gate": True},
    "shortest":         {"dimension": "linear",        "gate": True},
    "Hu_1":             {"dimension": "dimensionless", "gate": False},
    "Hu_2":             {"dimension": "dimensionless", "gate": False},
    "Hu_3":             {"dimension": "dimensionless", "gate": False},
    "Hu_4":             {"dimension": "dimensionless", "gate": False},
    "Hu_5":             {"dimension": "dimensionless", "gate": False},
    "Hu_6":             {"dimension": "dimensionless", "gate": False},
    "Hu_7":             {"dimension": "dimensionless", "gate": False},
}

_BASELINE5_FEATURE_META = {
    "RA": {"dimension": "area",   "gate": True},
    "LC": {"dimension": "linear", "gate": True},
    "BL": {"dimension": "linear", "gate": True},
    "BW": {"dimension": "linear", "gate": True},
    "E":  {"dimension": "dimensionless", "gate": False},
}

_FEATURE_META = {
    "chen16_noheight": _CHEN16_FEATURE_META,
    "baseline5": _BASELINE5_FEATURE_META,
}

_FEATURE_EXTRACTOR_PROTOCOL = {
    "chen16_noheight": "chen16_noheight_centerchord_v2",
    "baseline5": "baseline5_v1",
}

_CUT_PROTOCOL_VERSION = (
    "v176_strict_nonprimary_break1_region_meet_v144_fixed_center_bilateral_circle_v1"
)


def _read_base_score(model: Path) -> float:
    raw = read_json(model)["learner"]["learner_model_param"]["base_score"]
    if isinstance(raw, list):
        raw = raw[0]
    # XGBoost 3.x writes this as a JSON string in bracketed vector form, e.g. "[1.21669174E2]".
    if isinstance(raw, str):
        raw = raw.strip().lstrip("[").rstrip("]")
    return float(raw)


def _feature_domain_from_csv(
    test_csv: Path, features: list[str], feature_meta: dict[str, dict]
) -> dict[str, dict]:
    cols: dict[str, list[float]] = {f: [] for f in features}
    with test_csv.open(newline="") as fh:
        for row in csv.DictReader(fh):
            for f in features:
                cols[f].append(float(row[f]))
    domain: dict[str, dict] = {}
    for f in features:
        meta = feature_meta[f]
        domain[f] = {
            "min": min(cols[f]),
            "max": max(cols[f]),
            "dimension": meta["dimension"],
            "gate": meta["gate"],
            # With the real cutter running, the identity-stub widening is gone.
            "upper_multiplier": 1.0,
            "lower_multiplier": 1.0,
        }
    return domain


def export(
    *,
    model: Path,
    feature_family: str,
    test_predictions: Path,
    test_metrics: Path,
    params: Path | None,
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

    if feature_family not in FEATURE_FAMILIES:
        raise SystemExit(f"unknown --feature-family {feature_family!r}; known: {sorted(FEATURE_FAMILIES)}")
    family = FEATURE_FAMILIES[feature_family]
    feature_meta = _FEATURE_META[feature_family]


    out.mkdir(parents=True, exist_ok=True)

    booster = xgb.Booster()
    booster.load_model(str(model))
    feature_names = list(booster.feature_names or family)
    if feature_names != family:
        raise SystemExit(
            f"XGBoost feature order {feature_names} != required {feature_family} order "
            f"{family} (AGENTS.md rule 2)"
        )

    # onnxmltools' tree walker only accepts generic 'f%d' names. The named order is
    # verified above and re-asserted by the CSV reproduction self-check below (which
    # feeds columns in `family` order), so this rename does not relax AGENTS.md rule 2.
    booster.feature_names = [f"f{i}" for i in range(len(family))]

    onnx_model = convert_xgboost(
        booster,
        initial_types=[("input", FloatTensorType([None, len(family)]))],
        target_opset=opset,
    )
    onnx_path = out / "xgboost.onnx"
    onnx_path.write_bytes(onnx_model.SerializeToString())
    sess = ort.InferenceSession(onnx_path.as_posix())

    # --- self-check 1: graph transparency on realistic per-feature ranges ---
    # Random rows sampled from each feature's real [min, max] across the test split,
    # not np.random.rand in [0,1) which is nowhere near this model's input scale.
    with test_predictions.open(newline="") as fh:
        rows_csv = list(csv.DictReader(fh))
    feat_cols = {f: np.array([float(r[f]) for r in rows_csv], dtype="float64") for f in family}
    rng = np.random.default_rng(0)
    sample = np.stack(
        [rng.uniform(feat_cols[f].min(), feat_cols[f].max(), size=64) for f in family],
        axis=1,
    ).astype("float32")
    ref = booster.predict(xgb.DMatrix(sample, feature_names=booster.feature_names))
    got = sess.run(None, {"input": sample})[0].ravel()
    onnx_max_abs_diff = float(np.max(np.abs(ref - got)))
    if onnx_max_abs_diff >= 1e-3:
        raise SystemExit(f"self-check 1 (graph transparency) failed: max_abs {onnx_max_abs_diff:.2e}")

    # --- self-check 2: end-to-end reproduction of the eval CSV ---
    # Feed all held-out rows through the ONNX graph, compare to the CSV's own
    # `prediction` column, and recompute MAE against `fixed_test_metrics.json`. Passing
    # this proves the feature order, base_score, objective, and tree walk simultaneously.
    X = np.stack([feat_cols[f] for f in family], axis=1).astype("float32")
    onnx_pred = sess.run(None, {"input": X})[0].ravel().astype("float64")
    csv_pred = np.array([float(r["prediction"]) for r in rows_csv], dtype="float64")
    repro_max_abs = float(np.max(np.abs(onnx_pred - csv_pred)))
    if repro_max_abs >= 1e-3:
        raise SystemExit(f"self-check 2 (CSV reproduction) failed: max_abs {repro_max_abs:.2e}")

    y_true = np.array([float(r["weight_kg"]) for r in rows_csv], dtype="float64")
    expected_mae = float(read_json(test_metrics)["mae"])
    # The CSV `prediction` column must reproduce fixed_test_metrics.json in float64 —
    # this proves the eval CSV is a consistent oracle before we trust it for parity.
    csv_mae = float(np.mean(np.abs(csv_pred - y_true)))
    if abs(csv_mae - expected_mae) >= 1e-6:
        raise SystemExit(
            f"eval CSV inconsistent: prediction-column MAE {csv_mae!r} vs "
            f"fixed_test_metrics.json {expected_mae!r}"
        )
    # The ONNX graph runs in float32, so its MAE lands within the per-row 1e-3 bound of
    # the float64 reference rather than exactly on it. Record it; assert the loose bound.
    reproduced_test_mae = float(np.mean(np.abs(onnx_pred - y_true)))
    if abs(reproduced_test_mae - expected_mae) >= 1e-3:
        raise SystemExit(
            f"self-check 2 MAE mismatch: reproduced {reproduced_test_mae!r} vs "
            f"fixed_test_metrics.json {expected_mae!r}"
        )

    # --- sidecars ---
    base_score = _read_base_score(model)
    n_estimators = None
    if params is not None and params.exists():
        n_estimators = int(read_json(params).get("n_estimators", 0)) or None
    meta_src = read_json(metadata) if metadata and metadata.exists() else {}

    feature_order_path = write_json(
        out / "feature_order.json",
        {"feature_family": feature_family, "features": family},
    )
    meta_path = write_json(
        out / "xgboost.meta.json",
        {
            "feature_names": family,
            "feature_family": feature_family,
            "n_estimators": n_estimators,
            "objective": "reg:squarederror",
            "base_score": base_score,
            "target": meta_src.get("target", "weight_kg"),
            "source_model_sha256": sha256_file(model),
            "onnx_max_abs_diff": onnx_max_abs_diff,
            "reproduced_test_mae": reproduced_test_mae,
        },
    )

    feature_domain = _feature_domain_from_csv(test_predictions, family, feature_meta)

    # The V176/V144 cutter is ported and runs on every dorsal scan (ADR-009), so neither
    # string below may claim otherwise -- docs/spec.md flagged exactly that false clause.
    # weight.available now stays false only until plan phase 5 re-derives cm_per_px_target
    # from post-cut field masks; pipeline.cpp names that pending work
    # `weight_pending_field_validation`, and this reason matches it deliberately.
    # --enable-for-testing is the one switch that turns the branch on without a rebuild,
    # for on-device verification only.
    weight_block: dict = {"available": bool(enable_for_testing), "stability": "temporary"}
    if enable_for_testing:
        weight_block["note"] = (
            "TEST OVERRIDE: cm_per_px_target is the derived PIGRGB floor-plane value "
            "(ADR-011), unmeasured on the current pipeline, and the regressor cannot predict "
            "below ~73 kg (ADR-010), so a pig under ~85 kg reads high; estimated_kg is not "
            "trustworthy."
        )
    else:
        weight_block["unavailable_reason"] = "weight_pending_field_validation"

    fragment = {
        "weight": {
            **weight_block,
            "feature_family": feature_family,
            "feature_order": family,
            "min_mask_diagonal_fraction": 0.35,
            "regressor": {
                "format": "onnx",
                "path": "weight/xgboost.onnx",
                "sha256": sha256_file(onnx_path),
                "meta_path": "weight/xgboost.meta.json",
                "meta_sha256": sha256_file(meta_path),
                "feature_order_path": "weight/feature_order.json",
                "feature_order_sha256": sha256_file(feature_order_path),
                "feature_family": feature_family,
                "objective": "reg:squarederror",
                "base_score": base_score,
            },
            "feature_extractor": {
                "protocol_version": _FEATURE_EXTRACTOR_PROTOCOL[feature_family],
                "names": family,
                "linear_scale": 1.0,
            },
            "feature_domain": feature_domain,
            "body_mask": {
                "stage": "provisional",
                "cut_protocol_version": _CUT_PROTOCOL_VERSION,
                "cut_required": True,
            },
            "quality_gates": {
                # Ported in phase 2, ship dark until phase 5 measures the real rejection
                # rate. posture_max_bend_deg is a validated research value carried here to
                # be recorded, not casually tuned (README_AI_INTEGRATION.md section 8).
                "truncation": False,
                "posture": False,
                "posture_max_bend_deg": 40.0,
            },
            "capture_contract": {
                "feature_space": "fixed_camera_pixels",
                "training_camera_height_m": 1.88,
                "camera_height_is_xgboost_feature": False,
                # 720x720 recovered exactly: mask_area / RA == 518400 on all 1821 rows.
                "training_frame_px": [720, 720],
                # cm_per_px_target ships as the derived PIGRGB floor-plane value: 100 / 304
                # from INSTAHAM_CAMERA_SCALE_NORMALIZATION.md section 1 (docs/adr/
                # 011-derived-scale-target.md). It replaced the fitted 0.35 that the
                # docs/fix-phase-2/2-scale-target-conflict.md sweep had favoured
                # (docs/scale-constant-sweep-results.md: 0.35 beat 0.3289 on MAE, 11.5% vs
                # 19.0%) -- but that sweep predates round 7's composed
                # transform_mask_to_training_space() and measures a code path the weight
                # branch no longer runs. No accuracy figure supports either value on the
                # current pipeline; a re-run of ML/host_scale_test/ is owed before one is
                # quoted. cm_per_px_target_uncertainty stays 1.30 -- a derivation is not a
                # field calibration.
                "cm_per_px_target": 0.3289473684210526,
                "cm_per_px_target_source": (
                    "pigrgb_floor_plane_304ppm_theoretical_geometry_"
                    "INSTAHAM_CAMERA_SCALE_NORMALIZATION_md"
                ),
                "cm_per_px_target_uncertainty": 1.30,
            },
        }
    }
    return write_json(out / "manifest_fragment.json", fragment)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--feature-family", default="chen16_noheight", choices=sorted(FEATURE_FAMILIES))
    ap.add_argument(
        "--test-predictions",
        type=Path,
        default=Path("ML/weight_prediction_chen16/fixed_test_predictions.csv"),
        help="eval CSV carrying the 16 feature columns and a `prediction` column — the "
        "parity + domain oracle.",
    )
    ap.add_argument(
        "--test-metrics",
        type=Path,
        default=Path("ML/weight_prediction_chen16/fixed_test_metrics.json"),
    )
    ap.add_argument(
        "--params",
        type=Path,
        default=Path("ML/weight_prediction_chen16/selected_params.json"),
    )
    ap.add_argument("--metadata", type=Path, default=None)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--opset", type=int, default=15)  # onnxmltools XGBoost converter caps at opset 15
    ap.add_argument(
        "--enable-for-testing",
        action="store_true",
        help="DEV ONLY: flips weight.available to true for on-device verification before "
        "the real cutter is ported. Never pass this for a build meant to ship.",
    )
    a = ap.parse_args()
    written = export(
        model=a.model,
        feature_family=a.feature_family,
        test_predictions=a.test_predictions,
        test_metrics=a.test_metrics,
        params=a.params,
        metadata=a.metadata,
        out=a.out,
        opset=a.opset,
        enable_for_testing=a.enable_for_testing,
    )
    print(f"wrote {written}")


if __name__ == "__main__":
    main()
