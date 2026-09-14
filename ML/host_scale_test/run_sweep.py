"""docs/test-plan-phase/3-driver-sweep.md: run weight_branch_cli.exe over the five
PIGRGB sub_1.88 images x two cm_per_px_target constants (0.35, 0.3289473684210526),
collecting one CSV plus ten per-image envelope JSON files under ML/host_scale_test/out/.

Runs under the repository's own Python (no xgboost/onnxruntime needed -- the CLI owns all
inference). Usage:  python run_sweep.py
"""
import csv
import json
import os
import re
import shutil
import subprocess
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMAGES_DIR = os.path.join(REPO_ROOT, "Instaham", "PIGRGB-Weight", "sub_1.88")
MANIFEST_PATH = os.path.join(REPO_ROOT, "assets", "ml", "manifest.json")
CLI_PATH = os.path.join(os.path.dirname(__file__), "build", "weight_branch_cli.exe")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out")

# ---- cm_per_px_actual, derived from acquisition geometry, not from the manifest --------
# docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md is the authority for the 304 px/m figure at
# the 1.88 m baseline height -- NOT assets/ml/manifest.json, which carries a fitted value
# under test here. sub_1.88 is shot AT the baseline height, so no 1.78/1.88 m rescaling is
# needed (the retired sub_1.78 path multiplied by 1.88/1.78, an extra assumption on top of
# a figure docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md section 24 already calls theoretical).
PIGRGB_TARGET_PPM_AT_188 = 304.0
# 100.0 / PIGRGB_TARGET_PPM_AT_188 is the derivation, but is written out as a literal because
# it must be bit-identical to both the derived arm's target below and to the value already
# committed in assets/ml/manifest.json's cm_per_px_target -- 100.0/304.0 as a live division
# rounds to the adjacent double (0.32894736842105265, 1 ULP off), which left the k = 1.0 arm
# at 1.0000000000000002 instead of exactly 1.0.
assert 100.0 / PIGRGB_TARGET_PPM_AT_188 == 0.32894736842105265  # sanity: confirms the ULP gap
cm_per_px_actual = 0.3289473684210526

# The derived arm's target must be bit-identical to cm_per_px_actual, not a re-derived value.
TARGETS = [("0350", 0.35), ("03289", cm_per_px_actual)]

INVARIANT_FIELDS = ["canvas_mode", "ladder_rung", "seg_conf", "candidates_kept", "mask_w",
                     "mask_h", "mask_area_px"]

CSV_COLUMNS = [
    "image", "true_kg", "cm_per_px_actual", "cm_per_px_target", "k", "canvas_mode",
    "ladder_rung", "seg_conf", "mask_w", "mask_h", "mask_area_px", "mask_diagonal_fraction",
    "height_ratio", "implied_camera_height_m", "scaled_w", "scaled_h", "cutter_status",
    "kept_fraction", "mask_area", "convex_hull_area", "difference", "dif_mask", "body_curve",
    "perimeter", "outline_curve", "longest", "shortest", "Hu_1", "Hu_2", "Hu_3", "Hu_4",
    "Hu_5", "Hu_6", "Hu_7", "domain_violations", "gates_would_have_withheld", "predicted_kg",
    "error_pct",
]

FNAME_RE = re.compile(r"^([0-9.]+)kg_")


def parse_true_kg(filename):
    m = FNAME_RE.match(filename)
    if not m:
        raise ValueError("cannot parse true weight from filename: %s" % filename)
    return float(m.group(1))


def write_patched_manifest(target_value, suffix):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["capabilities"]["weight"]["capture_contract"]["cm_per_px_target"] = target_value
    patched_path = os.path.join(REPO_ROOT, "assets", "ml", "manifest.test_%s.json" % suffix)
    with open(patched_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return patched_path


def run_cli(manifest_path, image_path):
    # repr()/%.17g round-trips the double exactly; %.10f truncated it and made the k = 1.0
    # arm land at 0.9999999999360001 instead of 1.0 -- see phase 3 hazard notes.
    result = subprocess.run(
        [CLI_PATH, manifest_path, image_path, repr(cm_per_px_actual)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "CLI failed (exit %d) for %s:\nstdout: %s\nstderr: %s"
            % (result.returncode, image_path, result.stdout, result.stderr))
    return json.loads(result.stdout.strip())


def csv_row(image_name, true_kg, target_value, envelope):
    predicted_kg = envelope.get("predicted_kg")
    error_pct = ((predicted_kg - true_kg) / true_kg * 100.0) if predicted_kg is not None else ""
    domain_violations = envelope.get("domain_violations", [])
    violation_names = ",".join(v.get("feature", "") for v in domain_violations) if domain_violations else ""
    row = {
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
        "gates_would_have_withheld": envelope.get("gates_would_have_withheld", ""),
        "predicted_kg": predicted_kg if predicted_kg is not None else "",
        "error_pct": error_pct,
    }
    for feat in ["mask_area", "convex_hull_area", "difference", "dif_mask", "body_curve",
                 "perimeter", "outline_curve", "longest", "shortest", "Hu_1", "Hu_2", "Hu_3",
                 "Hu_4", "Hu_5", "Hu_6", "Hu_7"]:
        row[feat] = envelope.get(feat, "")
    return row


def main():
    if not os.path.exists(CLI_PATH):
        print("weight_branch_cli.exe not found at %s -- build phase 2 first" % CLI_PATH,
              file=sys.stderr)
        return 2

    os.makedirs(OUT_DIR, exist_ok=True)
    images = sorted(f for f in os.listdir(IMAGES_DIR) if f.lower().endswith(".png"))
    if len(images) != 5:
        print("expected 5 images in %s, found %d" % (IMAGES_DIR, len(images)), file=sys.stderr)
        return 2

    # cm_per_px_actual above is only correct at the resolution the 304 px/m baseline was
    # quoted for -- assert it before running rather than silently mis-scaling.
    from PIL import Image
    for image_name in images:
        with Image.open(os.path.join(IMAGES_DIR, image_name)) as im:
            if im.size != (960, 540):
                print("expected 960x540, got %s for %s" % (im.size, image_name), file=sys.stderr)
                return 2

    patched_paths = {}
    rows = []
    invariants_by_image = {}
    baseline_envelope_by_image = {}  # 03289 arm envelope, for the "matches unpatched" check

    try:
        for suffix, target_value in TARGETS:
            patched_paths[suffix] = write_patched_manifest(target_value, suffix)

        for image_name in images:
            true_kg = parse_true_kg(image_name)
            image_path = os.path.join(IMAGES_DIR, image_name)
            for suffix, target_value in TARGETS:
                envelope = run_cli(patched_paths[suffix], image_path)
                out_json_path = os.path.join(OUT_DIR, "envelope_%s_%s.json" % (
                    os.path.splitext(image_name)[0], suffix))
                with open(out_json_path, "w", encoding="utf-8") as f:
                    json.dump(envelope, f, indent=2)

                rows.append(csv_row(image_name, true_kg, target_value, envelope))

                inv = tuple(envelope.get(f) for f in INVARIANT_FIELDS)
                invariants_by_image.setdefault(image_name, {})[suffix] = inv
                if suffix == "03289":
                    baseline_envelope_by_image[image_name] = envelope
                    # k = 1.0 arm: cm_per_px_actual == cm_per_px_target exactly at sub_1.88,
                    # so the resample step must be a genuine no-op. A silent near-1.0 would
                    # make this arm look like it proved something it did not.
                    k = envelope.get("k")
                    if k != 1.0:
                        print("K != 1.0 CHECK FAILED for %s: k=%r target=%.16f actual=%.16f" % (
                            image_name, k, target_value, cm_per_px_actual), file=sys.stderr)
                        return 1

                print("%s @ %s: predicted=%s cutter=%s kept_fraction=%s" % (
                    image_name, target_value, envelope.get("predicted_kg"),
                    envelope.get("cutter_status"), envelope.get("kept_fraction")))

        # ---- step 5: cross-arm invariance assertions ----------------------------------
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

        # ---- assert the 0.3289 arm matches the unpatched committed manifest -----------
        unpatched_mismatches = []
        for image_name in images:
            image_path = os.path.join(IMAGES_DIR, image_name)
            unpatched_envelope = run_cli(MANIFEST_PATH, image_path)
            patched_envelope = baseline_envelope_by_image[image_name]
            if unpatched_envelope != patched_envelope:
                unpatched_mismatches.append(image_name)
        if unpatched_mismatches:
            print("UNPATCHED-MATCH CHECK FAILED for: %s" % unpatched_mismatches, file=sys.stderr)
            return 1
        print("0.3289 arm matches unpatched committed manifest: OK")

        # ---- write CSV ------------------------------------------------------------------
        csv_path = os.path.join(OUT_DIR, "results.csv")
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
