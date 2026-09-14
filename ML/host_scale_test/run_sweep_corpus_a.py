"""docs/sweep-phase/4-run-and-record.md, Run 2: corpus A, two arms (0.35 vs
0.3289473684210526), over the four `ML/host_scale_test/corpus_a/*.jpg` field photographs
produced by convert_corpus_a.py (Route 2, see docs/sweep-phase/2-corpus-a-results.md).

Unlike run_sweep.py's corpus B, each corpus A image has its OWN cm_per_px_actual, derived
from a hand-marked reference object per docs/sweep-phase/2-corpus-a-results.md -- there is no
single constant and no k = 1.0 arm here (k differs per image even within one target arm).

Runs under the repository's own Python. Usage:  python run_sweep_corpus_a.py
"""
import csv
import json
import os
import subprocess
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMAGES_DIR = os.path.join(os.path.dirname(__file__), "corpus_a")
MANIFEST_PATH = os.path.join(REPO_ROOT, "assets", "ml", "manifest.json")
CLI_PATH = os.path.join(os.path.dirname(__file__), "build", "weight_branch_cli.exe")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out")

# Per-image cm_per_px_actual, from docs/sweep-phase/2-corpus-a-results.md's reference-mark
# table (reference cm / reference px measured against each photo's hand-marked object).
# 75kg has no recorded device row to cross-check (floor row, ADR-010) but the value is still
# well-defined from its own reference marks and is run for completeness.
IMAGES = [
    ("75kg_pig_meter_stick.jpg", 75.0, 100.0 / 1582.0),
    ("92kg_pig_meter_stick.jpg", 92.0, 100.0 / 1547.62),
    ("96kg_pig_porac_stick.jpg", 96.0, 131.0 / 2066.20),
    ("118kg_pig_porac_stick.jpg", 118.0, 131.0 / 2005.63),
]

TARGETS = [("0350", 0.35), ("03289", 0.3289473684210526)]

INVARIANT_FIELDS = ["canvas_mode", "ladder_rung", "seg_conf", "candidates_kept", "mask_w",
                     "mask_h", "mask_area_px"]

CSV_COLUMNS = [
    "image", "true_kg", "cm_per_px_actual", "cm_per_px_target", "k", "canvas_mode",
    "ladder_rung", "seg_conf", "mask_w", "mask_h", "mask_area_px", "mask_diagonal_fraction",
    "height_ratio", "implied_camera_height_m", "scaled_w", "scaled_h", "cutter_status",
    "kept_fraction", "domain_violations", "extrapolated", "extrapolated_features",
    "gates_would_have_withheld", "predicted_kg", "error_pct",
]


def write_patched_manifest(target_value, suffix):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["capabilities"]["weight"]["capture_contract"]["cm_per_px_target"] = target_value
    patched_path = os.path.join(REPO_ROOT, "assets", "ml", "manifest.test_a%s.json" % suffix)
    with open(patched_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return patched_path


def run_cli(manifest_path, image_path, cm_per_px_actual):
    result = subprocess.run(
        [CLI_PATH, manifest_path, image_path, repr(cm_per_px_actual)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "CLI failed (exit %d) for %s:\nstdout: %s\nstderr: %s"
            % (result.returncode, image_path, result.stdout, result.stderr))
    return json.loads(result.stdout.strip())


def csv_row(image_name, true_kg, cm_per_px_actual, target_value, envelope):
    predicted_kg = envelope.get("predicted_kg")
    error_pct = ((predicted_kg - true_kg) / true_kg * 100.0) if predicted_kg is not None else ""
    domain_violations = envelope.get("domain_violations", [])
    violation_names = ",".join(v.get("feature", "") for v in domain_violations) if domain_violations else ""
    return {
        "image": image_name,
        "true_kg": true_kg,
        "cm_per_px_actual": cm_per_px_actual,
        "cm_per_px_target": target_value,
        "k": envelope.get("k", ""),
        "canvas_mode": envelope.get("canvas_mode", ""),
        "ladder_rung": envelope.get("ladder_rung", ""),
        "seg_conf": envelope.get("seg_conf", ""),
        "mask_w": envelope.get("mask_w", ""),
        "mask_h": envelope.get("mask_h", ""),
        "mask_area_px": envelope.get("mask_area_px", ""),
        "mask_diagonal_fraction": envelope.get("mask_diagonal_fraction", ""),
        "height_ratio": envelope.get("height_ratio", ""),
        "implied_camera_height_m": envelope.get("implied_camera_height_m", ""),
        "scaled_w": envelope.get("scaled_w", ""),
        "scaled_h": envelope.get("scaled_h", ""),
        "cutter_status": envelope.get("cutter_status", ""),
        "kept_fraction": envelope.get("kept_fraction", ""),
        "domain_violations": violation_names,
        "extrapolated": envelope.get("extrapolated", ""),
        "extrapolated_features": ",".join(envelope.get("extrapolated_features", []) or []),
        "gates_would_have_withheld": envelope.get("gates_would_have_withheld", ""),
        "predicted_kg": predicted_kg if predicted_kg is not None else "",
        "error_pct": error_pct,
    }


def main():
    if not os.path.exists(CLI_PATH):
        print("weight_branch_cli.exe not found at %s -- build phase 1 first" % CLI_PATH,
              file=sys.stderr)
        return 2

    for image_name, _, _ in IMAGES:
        if not os.path.exists(os.path.join(IMAGES_DIR, image_name)):
            print("missing corpus A file: %s" % image_name, file=sys.stderr)
            return 2

    os.makedirs(OUT_DIR, exist_ok=True)

    patched_paths = {}
    rows = []
    invariants_by_image = {}

    try:
        for suffix, target_value in TARGETS:
            patched_paths[suffix] = write_patched_manifest(target_value, suffix)

        for image_name, true_kg, cm_per_px_actual in IMAGES:
            image_path = os.path.join(IMAGES_DIR, image_name)
            for suffix, target_value in TARGETS:
                envelope = run_cli(patched_paths[suffix], image_path, cm_per_px_actual)
                out_json_path = os.path.join(OUT_DIR, "envelope_corpusA_%s_%s.json" % (
                    os.path.splitext(image_name)[0], suffix))
                with open(out_json_path, "w", encoding="utf-8") as f:
                    json.dump(envelope, f, indent=2)

                rows.append(csv_row(image_name, true_kg, cm_per_px_actual, target_value, envelope))

                inv = tuple(envelope.get(f) for f in INVARIANT_FIELDS)
                invariants_by_image.setdefault(image_name, {})[suffix] = inv

                print("%s @ %s: k=%s predicted=%s cutter=%s kept_fraction=%s extrapolated=%s" % (
                    image_name, target_value, envelope.get("k"), envelope.get("predicted_kg"),
                    envelope.get("cutter_status"), envelope.get("kept_fraction"),
                    envelope.get("extrapolated")))

        # ---- cross-arm invariance assertions -------------------------------------------
        failures = []
        for image_name, by_suffix in invariants_by_image.items():
            values = list(by_suffix.values())
            if len(set(values)) > 1:
                failures.append("%s: invariant fields differ across arms: %s" % (image_name, by_suffix))
        if failures:
            print("INVARIANCE CHECK FAILED:", file=sys.stderr)
            for f in failures:
                print("  " + f, file=sys.stderr)
            return 1
        print("Cross-arm invariance: OK (%d images, fields: %s)" % (
            len(invariants_by_image), ", ".join(INVARIANT_FIELDS)))

        # ---- write CSV --------------------------------------------------------------------
        csv_path = os.path.join(OUT_DIR, "results_corpus_a.csv")
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
            writer.writeheader()
            for row in rows:
                writer.writerow(row)
        print("Wrote %d rows to %s" % (len(rows), csv_path))

    finally:
        for path in patched_paths.values():
            if os.path.exists(path):
                os.remove(path)
        print("Patched manifests removed.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
