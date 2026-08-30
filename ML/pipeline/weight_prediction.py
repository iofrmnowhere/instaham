"""ML/pipeline/weight_prediction.py -- (5) feature vector to kilograms.

Consolidated from ML/weight_runtime.py (ML_implementation_plan.md revision 7,
section 5.2(5)). Only the two functions that verify the feature vector / the
loaded model's own contract move here; the protocol-binding and artifact-hash
checks stay in ML/weight_runtime.py, because those compare *other* stages'
protocol strings against expectations and belong to the orchestrator, not to this
stage (section 5.2's Leave column).

DEFERRED: predict_weight() below is not wired to XGBoost (ML_implementation_plan.md
revision 7, slice R4b -- "execute the revised plan, stop before the xgboost
implementation"). It raises NotImplementedError rather than a partial
implementation, per AGENTS.md rule 8: a stage that has not been built must say so,
not return a plausible-looking number. ML/weight_runtime.py's reference
orchestrator still loads and calls XGBRegressor directly today; this function is
the seam R4b fills in without changing that call site's shape.
"""
from __future__ import annotations

from typing import Any


class WeightPredictionError(RuntimeError):
    """Raised when the feature contract or the loaded model disagree with what the
    manifest / feature_order.json declare."""


def verify_feature_contract(
    feature_family: str,
    feature_order: list[str],
    baseline5: list[str],
    chen16_noheight: list[str],
    candidate: dict[str, Any] | None = None,
) -> None:
    """Moved verbatim from WeightEstimator._verify_feature_contract
    (ML/weight_runtime.py, pre-refactor). Fails closed if feature_order.json does
    not match the frozen definition for the selected family, or disagrees with the
    FINAL candidate metadata (AGENTS.md rule 2: features are RA, LC, BL, BW, E,
    exactly, never reordered)."""
    if feature_family == "baseline5":
        expected = baseline5
    elif feature_family == "chen16_noheight":
        expected = chen16_noheight
    else:
        raise WeightPredictionError(
            f"Unsupported selected feature family: {feature_family!r}"
        )

    if feature_order != expected:
        raise WeightPredictionError(
            "feature_order.json disagrees with the frozen source definition.\n"
            f"Recorded: {feature_order}\nExpected: {expected}"
        )

    candidate = candidate or {}
    candidate_family = candidate.get("selected_feature_family")
    if candidate_family is not None and str(candidate_family) != feature_family:
        raise WeightPredictionError(
            "Candidate metadata and feature_order.json disagree on feature family."
        )

    candidate_features = candidate.get("selected_features")
    if candidate_features is not None and list(candidate_features) != feature_order:
        raise WeightPredictionError(
            "Candidate metadata and feature_order.json disagree on feature order."
        )


def verify_loaded_xgb_feature_contract(
    booster_feature_names: list[str] | None,
    booster_num_features: int,
    feature_order: list[str],
) -> None:
    """Moved verbatim from WeightEstimator._verify_loaded_xgb_feature_contract
    (ML/weight_runtime.py, pre-refactor). Takes the booster's own reported names
    and count rather than the booster object itself, so this stage never imports
    xgboost -- the orchestrator still owns the load (section 5.2(5))."""
    if booster_feature_names is not None and list(booster_feature_names) != feature_order:
        raise WeightPredictionError(
            "Loaded XGBoost feature names do not match feature_order.json."
        )
    if int(booster_num_features) != len(feature_order):
        raise WeightPredictionError(
            "Loaded XGBoost feature count does not match feature_order.json."
        )


def predict_weight(
    features: dict[str, float],
    feature_order: list[str],
    model_path: str,
) -> float:
    """(5) WEIGHT PREDICTION -- features -> kg via XGBoost.

    NOT YET WIRED. See module docstring. Native mirror: stages/weight_prediction.cpp
    is likewise not yet written (ML_implementation_plan.md section 13, slice R4b).
    """
    raise NotImplementedError(
        "ML.pipeline.weight_prediction.predict_weight is deferred to slice R4b -- "
        "see ML_implementation_plan.md section 13. It is intentionally not called "
        "anywhere yet; weight.available stays false regardless (section 3.4, the "
        "identity cutter), so this stage being unwired changes no shipped behaviour."
    )
