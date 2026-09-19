"""docs/fix-phase-4/2-measurement.md: two-arm host measurement of the segmentation input
composition -- `canvas_scale` (shipped) vs `normalize_first` (docs/fix-phase-4/1) -- over
corpus A (`.pig_pictures/`, via the already-converted `corpus_a/*.jpg`) and corpus B
(`Instaham/PIGRGB-Weight/sub_1.88/`). `assets/ml/manifest.json` itself is never edited; each
arm runs against its own `manifest.test_mode_<suffix>.json` copy, deleted afterward.

Three measurements, one process:
  1. Corpus A + corpus B detection/MAE table, one row per image per arm.
  2. Corpus A re-mark jitter, replaying remark_replay.py's 18 recorded marks (3 photos x 6
     marks) through both arms, so the jitter band is compared arm-to-arm rather than against
     the old device numbers.
  3. Per-image composition geometry (rotated_w/h, canvas size actually used) so a reviewer can
     see directly whether F61's oversize fallback ever fires on these corpora (it does not, by
     hand computation -- this records that rather than asserting it).

Runs under the repository's own Python. Usage:  python run_phase2_mode_ab.py
"""
import csv
import json
import os
import subprocess
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFEST_PATH = os.path.join(REPO_ROOT, "assets", "ml", "manifest.json")
CLI_PATH = os.path.join(os.path.dirname(__file__), "build", "weight_branch_cli.exe")
BUILD_DIR = os.path.join(os.path.dirname(__file__), "build")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out")

CORPUS_A_DIR = os.path.join(os.path.dirname(__file__), "corpus_a")
CORPUS_B_DIR = os.path.join(REPO_ROOT, "Instaham", "PIGRGB-Weight", "sub_1.88")

# docs/sweep-phase/2-corpus-a-results.md's reference-mark table (same values already used by
# run_sweep_corpus_a.py).
CORPUS_A_IMAGES = [
    ("75kg_pig_meter_stick.jpg", 75.0, 100.0 / 1582.0),
    ("92kg_pig_meter_stick.jpg", 92.0, 100.0 / 1547.62),
    ("96kg_pig_porac_stick.jpg", 96.0, 131.0 / 2066.20),
    ("118kg_pig_porac_stick.jpg", 118.0, 131.0 / 2005.63),
]

# docs/scale-constant-sweep-results-2.md: sub_1.88, 100/304, no rescaling needed.
CORPUS_B_CM_PER_PX_ACTUAL = 0.3289473684210526

# docs/logs/recorded.md round 2 -- same 18 marks as remark_replay.py, reused here so the
# jitter band is measured on both arms instead of only against old device numbers.
JITTER_PHOTOS = [
    {"name": "92kg", "file": "92kg_pig_meter_stick.jpg", "true_kg": 92.0, "reference_cm": 100.0,
     "recorded_band_pct": 5.18,
     "marks": [1547.62, 1550.52, 1553.90, 1556.80, 1559.69, 1563.28]},
    {"name": "96kg", "file": "96kg_pig_porac_stick.jpg", "true_kg": 96.0, "reference_cm": 131.0,
     "recorded_band_pct": 12.04,
     "marks": [2066.20, 2069.18, 2072.14, 2074.68, 2078.34, 2081.48]},
    {"name": "118kg", "file": "118kg_pig_porac_stick.jpg", "true_kg": 118.0, "reference_cm": 131.0,
     "recorded_band_pct": 12.55,
     "marks": [2005.63, 2009.47, 2012.31, 2014.96, 2017.86, 2021.44]},
]

ARMS = [("canvas_scale", None), ("normalize_first", "normalize_first")]

CSV_COLUMNS = [
    "corpus", "image", "arm", "true_kg", "cm_per_px_actual", "orientation",
    "segmentation_status", "canvas_mode", "ladder_rung", "seg_conf", "candidates_kept",
    "mask_w", "mask_h", "mask_area_px", "mask_diagonal_fraction",
    "selected_box_frame_fraction", "selected_mask_area_proto", "runner_up_mask_area_proto",
    "used_normalize_first", "was_rotated_clockwise",
    "canvas_w", "canvas_h", "canvas_w_requested", "canvas_h_requested",
    "predicted_kg", "error_pct", "gates_would_have_withheld",
]


def write_patched_manifest(mode, suffix):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    if mode is not None:
        manifest["capabilities"]["segmentation"]["input_scale"]["mode"] = mode
    patched_path = os.path.join(REPO_ROOT, "assets", "ml", "manifest.test_mode_%s.json" % suffix)
    with open(patched_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return patched_path


def run_cli(manifest_path, image_path, cm_per_px_actual):
    result = subprocess.run(
        [CLI_PATH, manifest_path, image_path, repr(cm_per_px_actual)],
        capture_output=True, text=True, cwd=BUILD_DIR,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "CLI failed (exit %d) for %s:\nstdout: %s\nstderr: %s"
            % (result.returncode, image_path, result.stdout, result.stderr))
    return json.loads(result.stdout.strip())


def csv_row(corpus, image_name, arm, true_kg, cm_per_px_actual, orientation, envelope):
    predicted_kg = envelope.get("predicted_kg")
    error_pct = ((predicted_kg - true_kg) / true_kg * 100.0) if predicted_kg is not None else ""
    row = {
        "corpus": corpus, "image": image_name, "arm": arm, "true_kg": true_kg,
        "cm_per_px_actual": cm_per_px_actual, "orientation": orientation,
        "predicted_kg": predicted_kg if predicted_kg is not None else "",
        "error_pct": error_pct,
    }
    for field in ["segmentation_status", "canvas_mode", "ladder_rung", "seg_conf",
                  "candidates_kept", "mask_w", "mask_h", "mask_area_px",
                  "mask_diagonal_fraction", "selected_box_frame_fraction",
                  "selected_mask_area_proto", "runner_up_mask_area_proto",
                  "used_normalize_first", "was_rotated_clockwise",
                  "canvas_w", "canvas_h", "canvas_w_requested", "canvas_h_requested",
                  "gates_would_have_withheld"]:
        row[field] = envelope.get(field, "")
    return row


def main():
    if not os.path.exists(CLI_PATH):
        print("weight_branch_cli.exe not found at %s -- build phase 1 first" % CLI_PATH,
              file=sys.stderr)
        return 2
    os.makedirs(OUT_DIR, exist_ok=True)

    patched = {}
    rows = []
    jitter_results = {}

    try:
        for mode, suffix in ARMS:
            patched[suffix if suffix else "canvas_scale"] = write_patched_manifest(
                mode, suffix if suffix else "canvas_scale")

        # ---- 1. Corpus A: detection/MAE table --------------------------------------------
        for image_name, true_kg, cm_per_px_actual in CORPUS_A_IMAGES:
            image_path = os.path.join(CORPUS_A_DIR, image_name)
            if not os.path.exists(image_path):
                print("missing corpus A file: %s" % image_path, file=sys.stderr)
                return 2
            for mode, suffix in ARMS:
                key = suffix if suffix else "canvas_scale"
                envelope = run_cli(patched[key], image_path, cm_per_px_actual)
                out_path = os.path.join(OUT_DIR, "phase2_corpusA_%s_%s.json" % (
                    os.path.splitext(image_name)[0], key))
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(envelope, f, indent=2)
                rows.append(csv_row("A", image_name, key, true_kg, cm_per_px_actual,
                                     "portrait", envelope))
                print("A/%s @ %s: status=%s predicted=%s canvas_mode=%s" % (
                    image_name, key, envelope.get("segmentation_status"),
                    envelope.get("predicted_kg"), envelope.get("canvas_mode")))

        # ---- 2. Corpus B: detection/MAE table ---------------------------------------------
        b_images = sorted(f for f in os.listdir(CORPUS_B_DIR) if f.lower().endswith(".png"))
        for image_name in b_images:
            true_kg = float(image_name.split("kg_")[0])
            image_path = os.path.join(CORPUS_B_DIR, image_name)
            for mode, suffix in ARMS:
                key = suffix if suffix else "canvas_scale"
                envelope = run_cli(patched[key], image_path, CORPUS_B_CM_PER_PX_ACTUAL)
                out_path = os.path.join(OUT_DIR, "phase2_corpusB_%s_%s.json" % (
                    os.path.splitext(image_name)[0], key))
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(envelope, f, indent=2)
                rows.append(csv_row("B", image_name, key, true_kg, CORPUS_B_CM_PER_PX_ACTUAL,
                                     "landscape", envelope))
                print("B/%s @ %s: status=%s predicted=%s canvas_mode=%s" % (
                    image_name, key, envelope.get("segmentation_status"),
                    envelope.get("predicted_kg"), envelope.get("canvas_mode")))

        # ---- write CSV ---------------------------------------------------------------------
        csv_path = os.path.join(OUT_DIR, "phase2_results.csv")
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
            writer.writeheader()
            for row in rows:
                writer.writerow(row)
        print("Wrote %d rows to %s" % (len(rows), csv_path))

        # ---- 3. Corpus A jitter, both arms ---------------------------------------------
        for photo in JITTER_PHOTOS:
            image_path = os.path.join(CORPUS_A_DIR, photo["file"])
            entry = {"true_kg": photo["true_kg"], "recorded_device_band_pct": photo["recorded_band_pct"]}
            for mode, suffix in ARMS:
                key = suffix if suffix else "canvas_scale"
                kgs = []
                for ref_px in photo["marks"]:
                    cm_per_px = photo["reference_cm"] / ref_px
                    env = run_cli(patched[key], image_path, cm_per_px)
                    kgs.append(env.get("predicted_kg"))
                usable = [k for k in kgs if k is not None]
                if usable:
                    spread_pct = (max(usable) - min(usable)) / min(usable) * 100.0 if min(usable) > 0 else None
                else:
                    spread_pct = None
                entry[key] = {"predicted_kg_per_mark": kgs, "spread_pct": spread_pct}
                print("jitter %s/%s: %s" % (photo["name"], key, entry[key]))
            jitter_results[photo["name"]] = entry

        jitter_path = os.path.join(OUT_DIR, "phase2_jitter.json")
        with open(jitter_path, "w", encoding="utf-8") as f:
            json.dump(jitter_results, f, indent=2)
        print("Wrote %s" % jitter_path)

    finally:
        for path in patched.values():
            if os.path.exists(path):
                os.remove(path)
        print("Patched manifests removed.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
