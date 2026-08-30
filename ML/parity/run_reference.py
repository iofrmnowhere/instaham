"""Run the frozen Python reference pipeline over fixture images and write expected.json.

    python -m ML.parity.run_reference \
        --fixtures test/fixtures/parity \
        --view-checkpoint ML/mobilenetv4/best.pt \
        --view-arch mobilenetv4_conv_small.e2400_r224_in1k \
        --view-classes ML/mobilenetv4/classes.json \
        --health-checkpoint ML/ghostnetv3__.../best.pt \
        --health-arch ghostnetv3_100 \
        --health-classes ML/ghostnetv3__.../classes.json \
        --out test/fixtures/parity/expected.json

Scope now (slices 2-4):
  * view  probabilities   -- timm + checkpoint, mirrors ML/export preprocessing
  * health probabilities  -- same
  * five features         -- ML.pipeline.feature_calculation.extract_five_features on
                             each fixture's mask.npy
Weight end-to-end (segmentation + construction + cutter) is Phase 2 -- it needs
configs/project.yaml + src/.

Each fixture is a directory:  test/fixtures/parity/<name>/{image.jpg, mask.npy?}
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent.parent

from ML.export.common import IMAGENET_MEAN, IMAGENET_STD, RESIZE_RATIO  # noqa: E402


def _classifier_probs(checkpoint: Path, arch: str, classes: Path, image: Path, crop: int = 224):
    import numpy as np
    import torch
    import torchvision.transforms as T
    from PIL import Image, ImageOps
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
            T.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
        ]
    )
    img = ImageOps.exif_transpose(Image.open(image)).convert("RGB")
    with torch.no_grad():
        logits = model(tf(img).unsqueeze(0))
        probs = torch.softmax(logits, dim=1).squeeze(0).tolist()
    return {idx_to_name[i]: float(p) for i, p in enumerate(probs)}


def _five_features(mask_path: Path):
    import numpy as np

    from ML.pipeline.feature_calculation import extract_five_features  # gate B reference

    mask = np.load(mask_path)
    feats = extract_five_features(mask, linear_scale=1.0, preserve_processed_mask=True)
    if not feats:
        return None
    return {k: float(feats[k]) for k in ("RA", "LC", "BL", "BW", "E")}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fixtures", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--view-checkpoint", type=Path)
    ap.add_argument("--view-arch")
    ap.add_argument("--view-classes", type=Path)
    ap.add_argument("--health-checkpoint", type=Path)
    ap.add_argument("--health-arch")
    ap.add_argument("--health-classes", type=Path)
    a = ap.parse_args()

    results: dict[str, dict] = {}
    for fixture in sorted(p for p in a.fixtures.iterdir() if p.is_dir()):
        entry: dict[str, object] = {}
        image = next((fixture / n for n in ("image.jpg", "image.png", "image.jpeg") if (fixture / n).exists()), None)

        if image and a.view_checkpoint and a.view_arch and a.view_classes:
            entry["view"] = {
                "probabilities": _classifier_probs(a.view_checkpoint, a.view_arch, a.view_classes, image)
            }
        if image and a.health_checkpoint and a.health_arch and a.health_classes:
            entry["health"] = {
                "probabilities": _classifier_probs(
                    a.health_checkpoint, a.health_arch, a.health_classes, image
                )
            }
        mask = fixture / "mask.npy"
        if mask.exists():
            feats = _five_features(mask)
            if feats:
                entry["features"] = feats

        if entry:
            results[fixture.name] = entry

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {a.out} ({len(results)} fixture(s))")


if __name__ == "__main__":
    main()
