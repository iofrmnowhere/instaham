"""Run the Python reference pipeline over the scenario fixture corpus and write
test/fixtures/parity/expected.json (docs/metrics-phase/5-parity-tests.md task 3).

Rewritten for phase 5. The pre-phase-5 version of this file could not produce the goldens
the plan needs, in four ways (see the phase 5 document's finding 4): wrong checkpoint
paths, baseline5 features instead of the shipped chen16_noheight family, no weight leg,
and no segmentation leg. This version fixes the first three; the fourth (segmentation)
stays out of scope -- see "Segmentation is intentionally absent" below.

    python -m ML.parity.run_reference --fixtures test/fixtures/scenarios --out test/fixtures/parity/expected.json

Reference choice: onnxruntime on the SHIPPED assets/ml/*/model.onnx, not the .pt
checkpoint under timm/torch. A .pt-based reference would fold the C++ port's error and
the export/quantization error into one number, and the export error is already a
separate §14 device bullet (6), covered by phase 6 against the manifest's own recorded
onnx_max_abs_diff / fusion_max_abs_diff. Using onnxruntime on the same .onnx the app
ships isolates the port error, which is what this phase measures. --pt-checkpoint-dir
below runs the .pt path as a diagnostic when a mismatch needs to be attributed.

Segmentation is intentionally absent. Reproducing the trained YOLO segmentation model
independently would need either (a) the training-time `src/` package that
ML/weight_runtime.py's WeightEstimator imports on sys.path -- not present in this repo,
only the deployed C++ port under model_and_cutter/ is -- or (b) a from-scratch Python
YOLO postprocessor (letterbox undo, NMS, proto-mask decode) written for this phase alone,
with nothing to check IT against. Writing (b) risks shipping a second unverified
implementation and calling disagreements against it "port bugs" when they might be gate
bugs. Recorded as blocked in docs/metrics-phase/5-parity-tests.md; the honest path
forward is native-side mask export (subphase 5.1), not a hand-rolled oracle here.

Weight: WeightEstimator (ML/weight_runtime.py) is also not used, for the same missing-
`src/`-package reason (it imports ultralytics.YOLO AND src.config). Instead this script
runs assets/ml/weight/xgboost.onnx directly under onnxruntime, feeding the SAME 16
feature values a fixture's own envelope reports -- the "hold the feature vector equal"
design task 8 in the phase document calls for, consistent with the onnxruntime-on-shipped-
artifact choice above.

Each scenario fixture is `test/fixtures/scenarios/<id>/{image.jpg, meta.json}`; the
features golden is read out of that fixture's own `meta.json.observed_phase4.envelope`,
not recomputed, since recomputing them independently is exactly what task 7's chen16 gate
already does over a completely different (larger, ground-truth) corpus -- doing it again
here over eight production photos with no separate ground truth would be circular.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

ML_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = ML_DIR.parent

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
RESIZE_RATIO = 1.14


def _resize_shorter_then_crop(img: Image.Image, resize_shorter_side: int, crop: int) -> Image.Image:
    w, h = img.size
    if w <= h:
        new_w = resize_shorter_side
        new_h = round(h * resize_shorter_side / w)
    else:
        new_h = resize_shorter_side
        new_w = round(w * resize_shorter_side / h)
    img = img.resize((new_w, new_h), Image.BILINEAR)
    left = (new_w - crop) // 2
    top = (new_h - crop) // 2
    return img.crop((left, top, left + crop, top + crop))


def _classifier_input(image_path: Path, preprocessing: dict) -> np.ndarray:
    img = ImageOps.exif_transpose(Image.open(image_path)).convert("RGB")
    crop = int(preprocessing["center_crop"])
    resize_shorter_side = int(preprocessing["resize_shorter_side"])
    img = _resize_shorter_then_crop(img, resize_shorter_side, crop)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    mean = np.array(preprocessing["mean"], dtype=np.float32)
    std = np.array(preprocessing["std"], dtype=np.float32)
    arr = (arr - mean) / std
    arr = arr.transpose(2, 0, 1)[np.newaxis, ...].astype(np.float32)
    return arr


def _softmax(logits: np.ndarray) -> np.ndarray:
    e = np.exp(logits - logits.max())
    return e / e.sum()


class OnnxClassifier:
    def __init__(self, model_path: Path, classes_path: Path, preprocessing_path: Path):
        self.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        name_to_idx = json.loads(classes_path.read_text())
        self.idx_to_name = {v: k for k, v in name_to_idx.items()}
        self.preprocessing = json.loads(preprocessing_path.read_text())
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name

    def probabilities(self, image_path: Path) -> dict[str, float]:
        x = _classifier_input(image_path, self.preprocessing)
        (logits,) = self.session.run([self.output_name], {self.input_name: x})
        probs = _softmax(logits[0])
        return {self.idx_to_name[i]: float(p) for i, p in enumerate(probs)}


class OnnxWeightRegressor:
    def __init__(self, model_path: Path, feature_order_path: Path):
        self.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.order = json.loads(feature_order_path.read_text())["features"]
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name

    def predict_kg(self, features: dict[str, float]) -> float:
        # AGENTS.md rule 2: order comes from feature_order.json, never a literal list.
        x = np.array([[float(features[name]) for name in self.order]], dtype=np.float32)
        (out,) = self.session.run([self.output_name], {self.input_name: x})
        return float(np.asarray(out).reshape(-1)[0])


def _pt_classifier_probs(checkpoint: Path, arch: str, classes: Path, image: Path, crop: int = 224):
    """Diagnostic-only path: the .pt checkpoint under timm/torch, for attributing a
    mismatch between the shipped .onnx and the trained model, never the default
    reference (see module docstring)."""
    import torch
    import torchvision.transforms as T
    from timm import create_model

    name_to_idx = json.loads(classes.read_text())
    idx_to_name = {v: k for k, v in name_to_idx.items()}
    model = create_model(arch, pretrained=False, num_classes=len(name_to_idx)).eval()
    obj = torch.load(checkpoint, map_location="cpu", weights_only=False)
    state = obj.get("model_state", obj.get("state_dict", obj)) if isinstance(obj, dict) else obj
    model.load_state_dict(state, strict=True)
    tf = T.Compose(
        [
            T.Resize(round(crop * RESIZE_RATIO)),
            T.CenterCrop(crop),
            T.ToTensor(),
            T.Normalize(mean=IMAGENET_MEAN.tolist(), std=IMAGENET_STD.tolist()),
        ]
    )
    img = ImageOps.exif_transpose(Image.open(image)).convert("RGB")
    with torch.no_grad():
        logits = model(tf(img).unsqueeze(0))
        probs = torch.softmax(logits, dim=1).squeeze(0).tolist()
    return {idx_to_name[i]: float(p) for i, p in enumerate(probs)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--fixtures",
        type=Path,
        default=REPO_ROOT / "test" / "fixtures" / "scenarios",
        help="directory of <id>/{image.jpg,meta.json} fixtures (default: the phase 3.1 scenario corpus)",
    )
    ap.add_argument("--out", type=Path, default=REPO_ROOT / "test" / "fixtures" / "parity" / "expected.json")
    ap.add_argument(
        "--pt-checkpoint-dir",
        type=Path,
        default=None,
        help="diagnostic only: run the .pt/timm path too and record it under "
        "'view_pt'/'health_pt' for attributing a mismatch; needs "
        "ML/view_model_mnv4/{best.pt,classes.json} and ML/health_cnn/{best.pt,classes.json}",
    )
    a = ap.parse_args()

    view_dir = REPO_ROOT / "assets" / "ml" / "view"
    health_dir = REPO_ROOT / "assets" / "ml" / "health"
    weight_dir = REPO_ROOT / "assets" / "ml" / "weight"

    view_clf = OnnxClassifier(view_dir / "model.onnx", view_dir / "classes.json", view_dir / "preprocessing.json")
    health_clf = OnnxClassifier(
        health_dir / "model.onnx", health_dir / "classes.json", health_dir / "preprocessing.json"
    )
    weight_reg = OnnxWeightRegressor(weight_dir / "xgboost.onnx", weight_dir / "feature_order.json")

    results: dict[str, dict] = {}
    for fixture in sorted(p for p in a.fixtures.iterdir() if p.is_dir()):
        meta_path = fixture / "meta.json"
        image_path = fixture / "image.jpg"
        if not meta_path.exists() or not image_path.exists():
            continue
        meta = json.loads(meta_path.read_text())
        envelope = meta.get("observed_phase4", {}).get("envelope", {})

        entry: dict[str, object] = {
            "view": {"probabilities": view_clf.probabilities(image_path)},
            "health": {"probabilities": health_clf.probabilities(image_path)},
        }

        features = envelope.get("features", {}).get("values")
        if features:
            entry["features"] = features
            # AGENTS.md rule 8 (never force a prediction after a failed quality/
            # eligibility check) applies here too: a fixture with no confirmed reference
            # object (e.g. 11_container_formats -- endpoints not yet hand-marked) still
            # runs feature extraction on the UNCUT, un-scale-normalized mask
            # ("measured_on": "uncut_mask_unnormalized"), but the native pipeline
            # correctly withholds weight for it (envelope["weight"]["status"] ==
            # "unavailable"). Feeding those un-normalized features to the XGBoost
            # regressor would produce a number the real pipeline never claims and the
            # golden must not either -- only compute the weight leg when the native
            # envelope's OWN recorded run actually produced one.
            if envelope.get("weight", {}).get("status") == "ok":
                entry["weight"] = {"estimated_kg": weight_reg.predict_kg(features)}

        if a.pt_checkpoint_dir:
            view_pt = a.pt_checkpoint_dir / "view_model_mnv4"
            health_pt = a.pt_checkpoint_dir / "health_cnn"
            if (view_pt / "best.pt").exists():
                entry["view_pt"] = {
                    "probabilities": _pt_classifier_probs(
                        view_pt / "best.pt",
                        "mobilenetv4_conv_small.e2400_r224_in1k",
                        view_pt / "classes.json",
                        image_path,
                    )
                }
            if (health_pt / "best.pt").exists():
                entry["health_pt"] = {
                    "probabilities": _pt_classifier_probs(
                        health_pt / "best.pt", "ghostnetv3_100", health_pt / "classes.json", image_path
                    )
                }

        results[fixture.name] = entry

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {a.out} ({len(results)} fixture(s))")


if __name__ == "__main__":
    main()
