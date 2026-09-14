"""Sweep cm_per_px_target across a range and report per-image error, to answer whether ANY
single scalar constant brings all five PIGRGB sub_1.88 images into agreement.

Extends docs/test-plan-phase/3-driver-sweep.md's two-arm sweep to N arms. Same method:
patched manifest copies in assets/ml/, deleted afterward; the committed manifest is never
written. Usage:  python sweep_constants.py
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_sweep import (IMAGES_DIR, MANIFEST_PATH, CLI_PATH, REPO_ROOT, OUT_DIR,
                        cm_per_px_actual, parse_true_kg, run_cli)

# docs/sweep-phase/4-run-and-record.md Run 3: dense through the 0.32-0.36 equivalence band
# docs/fix-phase/1-diagnosis.md identified, sparse outside it. 0.3289473684210526 is the
# full-precision derived constant (ADR-011); a truncated 0.3289 would not land k == 1.0 in
# run_sweep.py's derived arm -- see that driver's "Known hazards" for why.
TARGETS = [0.28, 0.30, 0.3289473684210526, 0.34, 0.35, 0.36, 0.38, 0.42]


def write_patched(target_value, idx):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["capabilities"]["weight"]["capture_contract"]["cm_per_px_target"] = target_value
    path = os.path.join(REPO_ROOT, "assets", "ml", "manifest.test_sweep%d.json" % idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return path


def main():
    images = sorted(f for f in os.listdir(IMAGES_DIR) if f.lower().endswith(".png"))
    images.sort(key=parse_true_kg)
    truths = [parse_true_kg(f) for f in images]

    patched = []
    table = {}
    try:
        for i, t in enumerate(TARGETS):
            patched.append(write_patched(t, i))
        for t, mpath in zip(TARGETS, patched):
            row = []
            for img in images:
                env = run_cli(mpath, os.path.join(IMAGES_DIR, img))
                row.append(env.get("predicted_kg"))
            table[t] = row
            errs = [(p - tr) / tr * 100.0 for p, tr in zip(row, truths)]
            mae = sum(abs(e) for e in errs) / len(errs)
            bias = sum(errs) / len(errs)
            spread = max(errs) - min(errs)
            print("target=%.4f  errs%%=[%s]  MAE=%.1f  bias=%+.1f  spread=%.1f" % (
                t, " ".join("%+6.1f" % e for e in errs), mae, bias, spread))

        out_path = os.path.join(OUT_DIR, "constant_sweep.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump({"images": images, "true_kg": truths,
                        "cm_per_px_actual": cm_per_px_actual,
                        "predictions_by_target": table}, f, indent=2)
        print("\nwrote", out_path)
    finally:
        for p in patched:
            if os.path.exists(p):
                os.remove(p)
        print("patched manifests removed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
