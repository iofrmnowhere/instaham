"""docs/sweep-phase/4-run-and-record.md Run 3, corpus A half: sweep cm_per_px_target across a
range for the four corpus A field photographs (each with its own cm_per_px_actual), to see
whether any single scalar constant brings all of them into agreement.

Same method and target list as sweep_constants.py's corpus B sweep. Usage:
  python sweep_constants_corpus_a.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_sweep_corpus_a import (IMAGES, IMAGES_DIR, MANIFEST_PATH, REPO_ROOT, OUT_DIR, run_cli)

TARGETS = [0.28, 0.30, 0.3289473684210526, 0.34, 0.35, 0.36, 0.38, 0.42]


def write_patched(target_value, idx):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["capabilities"]["weight"]["capture_contract"]["cm_per_px_target"] = target_value
    path = os.path.join(REPO_ROOT, "assets", "ml", "manifest.test_asweep%d.json" % idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return path


def main():
    names = [n for n, _, _ in IMAGES]
    truths = [t for _, t, _ in IMAGES]
    actuals = [a for _, _, a in IMAGES]

    patched = []
    table = {}
    try:
        for i, t in enumerate(TARGETS):
            patched.append(write_patched(t, i))
        for t, mpath in zip(TARGETS, patched):
            row = []
            for name, actual in zip(names, actuals):
                env = run_cli(mpath, os.path.join(IMAGES_DIR, name), actual)
                row.append(env.get("predicted_kg"))
            table[t] = row
            errs = [(p - tr) / tr * 100.0 for p, tr in zip(row, truths)]
            mae = sum(abs(e) for e in errs) / len(errs)
            bias = sum(errs) / len(errs)
            spread = max(errs) - min(errs)
            print("target=%.4f  errs%%=[%s]  MAE=%.1f  bias=%+.1f  spread=%.1f" % (
                t, " ".join("%+6.1f" % e for e in errs), mae, bias, spread))

        out_path = os.path.join(OUT_DIR, "constant_sweep_corpus_a.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump({"images": names, "true_kg": truths, "cm_per_px_actual": actuals,
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
