from __future__ import annotations

"""
InstaHAM final weight-inference wrapper.

This file intentionally does NOT reimplement the research pipeline. It imports
and executes the frozen project modules under src/:

RGB image
  -> selected YOLO checkpoint
  -> src.yolo_inference.predict_largest_mask()
  -> src.body_mask.isolate_body_only_mask()
  -> selected 5- or 16-feature extractor
  -> final XGBoost model
  -> estimated weight (kg)
"""

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

EXPECTED_MASK_PROTOCOL = "original_coordinate_polygon_v1"
EXPECTED_BODY_MASK_PROTOCOL = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"
EXPECTED_BODY_MASK_METHOD = "ji_duan_residual_06q_v9_headfit_exact_twotangent"
EXPECTED_EXTENDED_PROTOCOL = "chen16_noheight_centerchord_v2"
DEFAULT_TRAINING_CAMERA_HEIGHT_M = 1.88


class WeightRuntimeError(RuntimeError):
    """Raised when the frozen weight-pipeline contract is violated."""


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _find_project_root(explicit: str | Path | None = None) -> Path:
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(Path(explicit).expanduser())

    here = Path(__file__).resolve().parent
    cwd = Path.cwd()
    candidates.extend([
        here,
        cwd,
        Path(r"C:\instaham"),
        Path("/Instaham"),
        Path("/workspace/Instaham"),
        Path("/workspace/INSTAHAM-training"),
        Path("/root/INSTAHAM-training"),
    ])

    checked: set[Path] = set()
    for candidate in candidates:
        try:
            candidate = candidate.resolve()
        except OSError:
            candidate = candidate.absolute()

        for p in [candidate, *candidate.parents]:
            if p in checked:
                continue
            checked.add(p)
            if (p / "configs" / "project.yaml").exists() and (p / "src").is_dir():
                return p

    raise FileNotFoundError(
        "Could not locate the InstaHAM project root. Pass project_root=... explicitly."
    )


def _resolve_recorded_project_path(raw: str | Path, project_root: Path) -> Path:
    """Relocate artifact paths recorded on another machine/server."""
    p = Path(str(raw)).expanduser()
    if p.exists():
        return p.resolve()

    s = str(raw).replace("\\", "/")
    lower = s.lower()

    for marker in ("/artifacts/", "/configs/", "/src/"):
        if marker in lower:
            i = lower.index(marker)
            candidate = project_root / Path(s[i + 1 :])
            if candidate.exists():
                return candidate.resolve()

    for marker in ("/instaham/", "/instaham-training/"):
        if marker in lower:
            i = lower.index(marker)
            candidate = project_root / Path(s[i + len(marker) :])
            if candidate.exists():
                return candidate.resolve()

    candidate = project_root / p
    if candidate.exists():
        return candidate.resolve()

    return p


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise WeightRuntimeError(f"Expected a JSON object in {path}")
    return data


class WeightEstimator:
    """Small app-facing wrapper around the frozen InstaHAM weight pipeline."""

    def __init__(
        self,
        *,
        project_root: str | Path | None = None,
        xgb_candidate_path: str | Path | None = None,
        xgb_model_path: str | Path | None = None,
        feature_order_path: str | Path | None = None,
        yolo_checkpoint_path: str | Path | None = None,
        device: str | None = None,
        yolo_conf: float = 0.25,
        verify_hashes: bool = True,
    ) -> None:
        self.project_root = _find_project_root(project_root)
        if str(self.project_root) not in sys.path:
            sys.path.insert(0, str(self.project_root))

        from ultralytics import YOLO
        from xgboost import XGBRegressor
        from src.config import load_project_config, resolve_path
        from src.common import get_device, to_yolo_device
        import src.yolo_modifications as yolo_modifications
        from src.yolo_inference import MASK_COORDINATE_PROTOCOL, predict_largest_mask
        from src.body_mask import (
            BODY_MASK_PROTOCOL_VERSION,
            BODY_MASK_METHOD,
            isolate_body_only_mask,
        )
        from src.mask_features import extract_five_features
        from src.extended_mask_features import (
            BASELINE5,
            CHEN16_NOHEIGHT,
            EXTENDED_FEATURE_PROTOCOL_VERSION,
            extract_chen16_features,
        )

        self._predict_largest_mask = predict_largest_mask
        self._isolate_body_only_mask = isolate_body_only_mask
        self._extract_five_features = extract_five_features
        self._extract_chen16_features = extract_chen16_features

        self.mask_protocol = str(MASK_COORDINATE_PROTOCOL)
        self.body_mask_protocol = str(BODY_MASK_PROTOCOL_VERSION)
        self.body_mask_method = str(BODY_MASK_METHOD)
        self.extended_feature_protocol = str(EXTENDED_FEATURE_PROTOCOL_VERSION)
        self.baseline5 = list(BASELINE5)
        self.chen16_noheight = list(CHEN16_NOHEIGHT)
        self._verify_runtime_protocols()

        self.project_root, self.cfg = load_project_config(self.project_root)
        artifacts = Path(resolve_path(
            self.project_root,
            self.cfg["project"]["artifacts_root"],
        ))

        default_candidate = (
            artifacts
            / "weight_final_v1"
            / "metrics"
            / "xgboost_final_candidate.json"
        )
        self.candidate_path = (
            _resolve_recorded_project_path(xgb_candidate_path, self.project_root)
            if xgb_candidate_path is not None
            else default_candidate
        )
        if not self.candidate_path.exists():
            raise FileNotFoundError(
                "Missing FINAL XGBoost candidate metadata: "
                f"{self.candidate_path}\n"
                "Run the FINAL Notebook 7 first, or pass xgb_candidate_path=... explicitly."
            )

        self.candidate = _load_json(self.candidate_path)

        model_raw = xgb_model_path or self.candidate.get("model_path")
        order_raw = feature_order_path or self.candidate.get("feature_order_path")
        yolo_raw = yolo_checkpoint_path or self.candidate.get("yolo_checkpoint")

        if model_raw is None:
            model_raw = artifacts / "weight_final_v1" / "xgboost" / "selected_final" / "model.json"
        if order_raw is None:
            order_raw = artifacts / "weight_final_v1" / "xgboost" / "selected_final" / "feature_order.json"
        if yolo_raw is None:
            yolo_candidate = _load_json(artifacts / "metrics" / "yolo_candidate.json")
            yolo_raw = yolo_candidate.get("candidate_weights")
        if yolo_raw is None:
            raise WeightRuntimeError("Could not resolve the selected YOLO checkpoint.")

        self.xgb_model_path = _resolve_recorded_project_path(model_raw, self.project_root)
        self.feature_order_path = _resolve_recorded_project_path(order_raw, self.project_root)
        self.yolo_checkpoint_path = _resolve_recorded_project_path(yolo_raw, self.project_root)

        for label, path in {
            "XGBoost model": self.xgb_model_path,
            "feature order": self.feature_order_path,
            "YOLO checkpoint": self.yolo_checkpoint_path,
        }.items():
            if not path.exists():
                raise FileNotFoundError(f"Missing {label}: {path}")

        order_payload = _load_json(self.feature_order_path)
        self.feature_family = str(
            order_payload.get(
                "feature_family",
                self.candidate.get("selected_feature_family", ""),
            )
        )
        self.feature_order = list(
            order_payload.get(
                "features",
                self.candidate.get("selected_features", []),
            )
        )

        self._verify_feature_contract()
        self._verify_candidate_protocol_binding()

        if verify_hashes:
            self._verify_artifact_hashes()
            self._verify_runtime_source_hashes()

        if hasattr(yolo_modifications, "register_checkpoint_safe_globals"):
            yolo_modifications.register_checkpoint_safe_globals()

        self.yolo = YOLO(str(self.yolo_checkpoint_path))

        configured_device = (
            device
            if device is not None
            else self.cfg.get("runtime", {}).get("device", "auto")
        )
        self.device = get_device(configured_device)
        self.yolo_device = to_yolo_device(self.device)
        self.yolo_imgsz = int(self.cfg.get("yolo", {}).get("image_size", 640))
        self.yolo_conf = float(yolo_conf)

        self.ji_config = (
            self.cfg.get("weight_features", {})
            .get("appendage_method_experiment", {})
            .get("ji_duan_adaptive_opening", {})
        ) or None

        self.xgb = XGBRegressor()
        self.xgb.load_model(str(self.xgb_model_path))
        self._verify_loaded_xgb_feature_contract()

    def _verify_runtime_protocols(self) -> None:
        if self.mask_protocol != EXPECTED_MASK_PROTOCOL:
            raise WeightRuntimeError(
                f"Wrong YOLO mask protocol: {self.mask_protocol!r}"
            )
        if self.body_mask_protocol != EXPECTED_BODY_MASK_PROTOCOL:
            raise WeightRuntimeError(
                f"Wrong body-mask protocol: {self.body_mask_protocol!r}"
            )
        if self.body_mask_method != EXPECTED_BODY_MASK_METHOD:
            raise WeightRuntimeError(
                f"Wrong body-mask method: {self.body_mask_method!r}"
            )
        if self.extended_feature_protocol != EXPECTED_EXTENDED_PROTOCOL:
            raise WeightRuntimeError(
                f"Wrong Chen16 feature protocol: {self.extended_feature_protocol!r}"
            )
        if self.baseline5 != ["RA", "LC", "BL", "BW", "E"]:
            raise WeightRuntimeError(f"Unexpected baseline5 definition: {self.baseline5}")
        if len(self.chen16_noheight) != 16:
            raise WeightRuntimeError(
                f"Expected exactly 16 Chen no-height features; found {len(self.chen16_noheight)}."
            )

    def _verify_feature_contract(self) -> None:
        if self.feature_family == "baseline5":
            expected = self.baseline5
        elif self.feature_family == "chen16_noheight":
            expected = self.chen16_noheight
        else:
            raise WeightRuntimeError(
                f"Unsupported selected feature family: {self.feature_family!r}"
            )

        if self.feature_order != expected:
            raise WeightRuntimeError(
                "feature_order.json disagrees with the frozen source definition.\n"
                f"Recorded: {self.feature_order}\nExpected: {expected}"
            )

        candidate_family = self.candidate.get("selected_feature_family")
        if candidate_family is not None and str(candidate_family) != self.feature_family:
            raise WeightRuntimeError(
                "Candidate metadata and feature_order.json disagree on feature family."
            )

        candidate_features = self.candidate.get("selected_features")
        if candidate_features is not None and list(candidate_features) != self.feature_order:
            raise WeightRuntimeError(
                "Candidate metadata and feature_order.json disagree on feature order."
            )

    def _verify_candidate_protocol_binding(self) -> None:
        checks = {
            "yolo_mask_coordinate_protocol": self.mask_protocol,
            "body_mask_protocol_version": self.body_mask_protocol,
            "body_mask_method": self.body_mask_method,
            "extended_feature_protocol_version": self.extended_feature_protocol,
        }
        for key, current in checks.items():
            recorded = self.candidate.get(key)
            if recorded is not None and str(recorded) != str(current):
                raise WeightRuntimeError(
                    f"FINAL candidate protocol mismatch for {key}: "
                    f"candidate={recorded!r}, runtime={current!r}"
                )

    def _verify_artifact_hashes(self) -> None:
        expected_model = self.candidate.get("model_sha256")
        if expected_model and _sha256_file(self.xgb_model_path) != str(expected_model):
            raise WeightRuntimeError(
                "XGBoost model SHA-256 does not match FINAL candidate metadata."
            )

        expected_yolo = self.candidate.get("yolo_checkpoint_sha256")
        if expected_yolo and _sha256_file(self.yolo_checkpoint_path) != str(expected_yolo):
            raise WeightRuntimeError(
                "YOLO checkpoint SHA-256 does not match FINAL candidate metadata."
            )

    def _verify_runtime_source_hashes(self) -> None:
        recorded = self.candidate.get("source_hashes")
        if not isinstance(recorded, dict):
            return

        runtime_sources = {
            "yolo_inference": self.project_root / "src" / "yolo_inference.py",
            "body_mask": self.project_root / "src" / "body_mask.py",
            "mask_features": self.project_root / "src" / "mask_features.py",
            "extended_mask_features": self.project_root / "src" / "extended_mask_features.py",
        }
        for key, path in runtime_sources.items():
            expected = recorded.get(key)
            if expected is None:
                continue
            if not path.exists():
                raise FileNotFoundError(path)
            if _sha256_file(path) != str(expected):
                raise WeightRuntimeError(
                    f"Frozen runtime source hash mismatch: {key} ({path})"
                )

    def _verify_loaded_xgb_feature_contract(self) -> None:
        booster = self.xgb.get_booster()
        model_feature_names = booster.feature_names
        if model_feature_names is not None and list(model_feature_names) != self.feature_order:
            raise WeightRuntimeError(
                "Loaded XGBoost feature names do not match feature_order.json."
            )
        if int(booster.num_features()) != len(self.feature_order):
            raise WeightRuntimeError(
                "Loaded XGBoost feature count does not match feature_order.json."
            )

    def _failure(
        self,
        code: str,
        message: str,
        *,
        segmentation_confidence: float | None = None,
    ) -> dict[str, Any]:
        return {
            "status": "pipeline_failure",
            "error_code": code,
            "message": message,
            "estimated_kg": None,
            "segmentation_confidence": segmentation_confidence,
            "feature_family": self.feature_family,
            "feature_order": list(self.feature_order),
            "features": None,
            "protocols": {
                "mask_coordinate_protocol": self.mask_protocol,
                "body_mask_protocol": self.body_mask_protocol,
                "body_mask_method": self.body_mask_method,
                "extended_feature_protocol": self.extended_feature_protocol,
            },
        }

    def predict(
        self,
        image_path: str | Path,
        *,
        sample_id: str | None = None,
        raise_on_error: bool = False,
    ) -> dict[str, Any]:
        """
        Estimate pig weight from one dorsal RGB image.

        The separate view-suitability model should decide whether the weight
        branch is allowed to run. This method fails closed if segmentation,
        body-mask QC, feature extraction, or model compatibility fails.
        """
        image_path = Path(image_path)
        if not image_path.exists():
            error = FileNotFoundError(image_path)
            if raise_on_error:
                raise error
            return self._failure("image_not_found", str(error))

        sid = str(sample_id) if sample_id is not None else image_path.stem
        segmentation_confidence: float | None = None

        try:
            whole_mask, confidence = self._predict_largest_mask(
                self.yolo,
                image_path,
                imgsz=self.yolo_imgsz,
                conf=self.yolo_conf,
                device=self.yolo_device,
            )
            segmentation_confidence = float(confidence)
            if whole_mask is None:
                raise WeightRuntimeError("YOLO returned no mask.")

            body = self._isolate_body_only_mask(
                whole_mask,
                sample_id=sid,
                ji_config=self.ji_config,
            )
            if str(body.get("status")) != "ok":
                raise WeightRuntimeError(f"body_mask_status={body.get('status')}")
            if not bool(body.get("pair_valid", False)):
                raise WeightRuntimeError("No valid body-circle pair.")
            if not bool(body.get("head_removal_applied", False)):
                raise WeightRuntimeError("Required head removal was not applied.")

            body_mask = body.get("mask")
            if body_mask is None or np.count_nonzero(body_mask) == 0:
                raise WeightRuntimeError("Final body mask is empty.")

            if self.feature_family == "baseline5":
                extracted = self._extract_five_features(
                    body_mask,
                    linear_scale=1.0,
                    preserve_processed_mask=True,
                )
            else:
                extracted = self._extract_chen16_features(body_mask)

            if not extracted:
                raise WeightRuntimeError(
                    f"{self.feature_family} feature extraction failed."
                )

            missing = [name for name in self.feature_order if name not in extracted]
            if missing:
                raise WeightRuntimeError(f"Missing required feature(s): {missing}")

            ordered_values = np.asarray(
                [float(extracted[name]) for name in self.feature_order],
                dtype=np.float64,
            )
            if not np.isfinite(ordered_values).all():
                raise WeightRuntimeError("Feature vector contains non-finite values.")

            x = pd.DataFrame([ordered_values], columns=self.feature_order)
            estimated_kg = float(self.xgb.predict(x)[0])
            if not np.isfinite(estimated_kg):
                raise WeightRuntimeError("XGBoost returned a non-finite prediction.")

            features = {
                name: float(extracted[name])
                for name in self.feature_order
            }

            return {
                "status": "ok",
                "estimated_kg": estimated_kg,
                "segmentation_confidence": segmentation_confidence,
                "feature_family": self.feature_family,
                "feature_order": list(self.feature_order),
                "features": features,
                "qc": {
                    "body_mask_status": str(body.get("status")),
                    "pair_valid": bool(body.get("pair_valid")),
                    "head_removal_applied": bool(body.get("head_removal_applied", False)),
                    "preview_mode": body.get("preview_mode"),
                    "head_side": body.get("head_side"),
                    "rump_side": body.get("rump_side"),
                    "head_selection_mode": body.get("head_selection_mode"),
                    "head_circle_refinement_applied": bool(
                        body.get("head_circle_refinement_applied", False)
                    ),
                    "head_circle_contained": bool(
                        body.get("head_circle_contained", False)
                    ),
                    "head_crop_geometry_source": body.get("head_crop_geometry_source"),
                    "pair_selection_tier": body.get("pair_selection_tier"),
                    "radius_similarity": body.get("radius_similarity"),
                    "centerline_gap_ratio_to_smaller_radius": body.get(
                        "centerline_gap_ratio_to_smaller_radius"
                    ),
                    "used_radius_similarity_relaxation": bool(
                        body.get("used_radius_similarity_relaxation", False)
                    ),
                    "used_gap_relaxation": bool(body.get("used_gap_relaxation", False)),
                    "removed_head_fraction": body.get("removed_head_fraction"),
                    "whole_mask_area_px": body.get("whole_mask_area_px"),
                    "body_mask_area_px": body.get("body_mask_area_px"),
                },
                "protocols": {
                    "mask_coordinate_protocol": self.mask_protocol,
                    "body_mask_protocol": self.body_mask_protocol,
                    "body_mask_method": self.body_mask_method,
                    "extended_feature_protocol": self.extended_feature_protocol,
                },
                "capture_contract": {
                    "feature_space": "fixed_camera_pixels",
                    "training_camera_height_m": DEFAULT_TRAINING_CAMERA_HEIGHT_M,
                    "camera_height_is_xgboost_feature": False,
                },
                "artifacts": {
                    "xgboost_model": str(self.xgb_model_path),
                    "feature_order": str(self.feature_order_path),
                    "yolo_checkpoint": str(self.yolo_checkpoint_path),
                    "candidate": str(self.candidate_path),
                },
            }

        except Exception as exc:
            if raise_on_error:
                raise
            return self._failure(
                "weight_pipeline_failure",
                f"{type(exc).__name__}: {exc}",
                segmentation_confidence=segmentation_confidence,
            )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Run InstaHAM weight inference on one image."
    )
    parser.add_argument("image", help="Path to a dorsal pig image.")
    parser.add_argument(
        "--project-root",
        default=None,
        help="InstaHAM project root. Auto-detected when omitted.",
    )
    parser.add_argument(
        "--device",
        default=None,
        help="Optional device override, e.g. cuda or cpu.",
    )
    parser.add_argument(
        "--no-hash-check",
        action="store_true",
        help="Disable model/source SHA-256 verification.",
    )
    args = parser.parse_args()

    estimator = WeightEstimator(
        project_root=args.project_root,
        device=args.device,
        verify_hashes=not args.no_hash_check,
    )
    result = estimator.predict(args.image)
    print(json.dumps(result, indent=2, default=str))
