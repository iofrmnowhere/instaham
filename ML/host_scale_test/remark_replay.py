"""Replay the 18 real reference marks recorded on device through the host weight branch.

docs/fix-phase-3/3.1-host-remark-replay.md. `docs/logs/recorded.md` round 2 recorded, for
three field photos x six marks each, the exact reference pixel length the user marked
(`ref_px`, back-computed from the envelope as reference_cm / scale.cm_per_px_actual) together
with the resulting segmentation area, cutter kept_fraction and predicted weight. Those 18
marks are replayable off-device: cm_per_px_actual = reference_cm / ref_px reconstructs each
one exactly, and weight_branch_cli.exe runs the same C++ stages the app ships.

This measures the F53 reference-marking jitter band on the corpus where it was actually
observed, instead of jitter_sweep.py's percentage-delta proxy on PIGRGB stock images.

The device numbers are only comparable if the host is segmenting the same pig: recorded
`segArea` and `seg conf` are checked per mark and reported as a validity gate BEFORE any
band comparison. See the subphase document for what breaks the gate and why.

Usage:  python remark_replay.py [--keep-prepared DIR] [--out PATH]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFEST_PATH = os.path.join(REPO_ROOT, "assets", "ml", "manifest.json")
BUILD_DIR = os.path.join(os.path.dirname(__file__), "build")
CLI_PATH = os.path.join(BUILD_DIR, "weight_branch_cli.exe")
OUT_DIR = os.path.join(os.path.dirname(__file__), "out")
PHOTO_DIR = os.path.join(REPO_ROOT, ".pig_pictures")

# The gallery-import path (`pickFromGallery`) caps the long edge at 3000 px, which is how the
# recorded scans reached the pipeline -- docs/fix-phase-2/2.1-reference-length-sensitivity.md,
# "Three capture paths, three input resolutions". The sources are 3024x4032, so this is a
# 2250x3000 downscale, matching the resolution the recorded ref_px values were marked at.
LONG_EDGE_CAP = 3000

# docs/logs/recorded.md round 2 -- 18 scans at cm_per_px_target 0.35, ladder_rung 0,
# cutter.status cut_applied. `device` fields are what the phone reported for that same mark.
PHOTOS = [
    {
        "name": "92kg",
        "file": "92kg_pig_meter_stick.HEIC",
        "true_kg": 92.0,
        "reference_cm": 100.0,          # meter stick
        "recorded_band_pct": 5.18,
        "marks": [
            # ref_px,  device segArea, device seg conf, device est kg
            (1547.62, 1356422, 0.9190, 83.54),
            (1550.52, 1356422, 0.9190, 88.03),
            (1553.90, 1356422, 0.9190, 87.36),
            (1556.80, 1397606, 0.9200, 87.00),
            (1559.69, 1397606, 0.9200, 87.14),
            (1563.28, 1403010, 0.9219, 86.19),
        ],
    },
    {
        "name": "96kg",
        "file": "96kg_pig_porac_stick.HEIC",
        "true_kg": 96.0,
        "reference_cm": 131.0,          # porac stick
        "recorded_band_pct": 12.04,
        "marks": [
            (2066.20, 1512523, 0.9166, 85.24),
            (2069.18, 1497791, 0.9156, 84.91),
            (2072.14, 1501254, 0.9153, 78.53),
            (2074.68, 1501254, 0.9153, 88.84),
            (2078.34, 1501254, 0.9153, 88.22),
            (2081.48, 1501254, 0.9153, 88.07),
        ],
    },
    {
        "name": "118kg",
        "file": "118kg_pig_porac_stick.jpg",
        "true_kg": 118.0,
        "reference_cm": 131.0,
        "recorded_band_pct": 12.55,
        "marks": [
            (2005.63, 1820661, 0.9196, 118.49),
            (2009.47, 1813602, 0.9184, 112.88),
            (2012.31, 1813602, 0.9184, 107.04),
            (2014.96, 1816902, 0.9198, 106.40),
            (2017.86, 1816902, 0.9198, 105.01),
            (2021.44, 1816902, 0.9198, 104.80),
        ],
    },
]

RECORD_FIELDS = ["ladder_rung", "canvas_mode", "seg_conf", "mask_w", "mask_h", "mask_area_px",
                 "mask_diagonal_fraction", "k", "scaled_w", "scaled_h", "cutter_status",
                 "kept_fraction", "mask_area", "perimeter", "longest", "shortest",
                 "extrapolated", "domain_violations", "predicted_kg"]


def prepare_image(src_path, dst_path):
    """Decode (HEIC via pillow_heif, others via OpenCV), cap the long edge, write lossless PNG.

    OpenCV 5.0.0 on this machine returns None for HEIC, so HEIC cannot go to the CLI directly.
    PNG is lossless, so no image data is lost relative to the decoded source -- the only
    divergence from the device is the decoder itself and the resize kernel.
    """
    ext = os.path.splitext(src_path)[1].lower()
    if ext in (".heic", ".heif"):
        import pillow_heif
        from PIL import Image
        pillow_heif.register_heif_opener()
        pil = Image.open(src_path)
        orientation = pil.getexif().get(274, 1)
        if orientation != 1:
            # AGENTS rule 5: EXIF orientation must be corrected before any model sees the
            # image. Assert rather than silently mis-handle -- these three sources are all
            # orientation 1, so a non-1 value means the corpus changed and the recorded
            # ref_px values may no longer describe this pixel grid.
            raise RuntimeError("%s has EXIF orientation %d; replay assumes 1"
                               % (os.path.basename(src_path), orientation))
        img = cv2.cvtColor(np.array(pil.convert("RGB")), cv2.COLOR_RGB2BGR)
    else:
        img = cv2.imread(src_path, cv2.IMREAD_COLOR)   # applies EXIF orientation itself
        if img is None:
            raise RuntimeError("cv2 could not decode %s" % src_path)

    h, w = img.shape[:2]
    long_edge = max(w, h)
    if long_edge > LONG_EDGE_CAP:
        scale = LONG_EDGE_CAP / float(long_edge)
        img = cv2.resize(img, (int(round(w * scale)), int(round(h * scale))),
                         interpolation=cv2.INTER_AREA)
    if not cv2.imwrite(dst_path, img):
        raise RuntimeError("could not write %s" % dst_path)
    return (img.shape[1], img.shape[0]), (w, h)


def run_cli(image_path, cm_per_px_actual):
    result = subprocess.run(
        [CLI_PATH, MANIFEST_PATH, image_path, "%.10f" % cm_per_px_actual],
        capture_output=True, text=True, cwd=BUILD_DIR,   # local onnxruntime.dll must win
    )
    if result.returncode != 0:
        raise RuntimeError("CLI failed (exit %d) for %s at cm_per_px %.6f:\n%s\n%s"
                           % (result.returncode, image_path, cm_per_px_actual,
                              result.stdout, result.stderr))
    return json.loads(result.stdout.strip())


def spread_pct(values):
    lo, hi = min(values), max(values)
    return (hi - lo) / lo * 100.0 if lo > 0 else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep-prepared", default=None,
                    help="directory to keep the prepared PNGs in (default: temp, deleted)")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "remark_replay.json"))
    args = ap.parse_args()

    if not os.path.isfile(CLI_PATH):
        sys.exit("weight_branch_cli.exe not built: %s" % CLI_PATH)
    os.makedirs(OUT_DIR, exist_ok=True)

    tmpdir = args.keep_prepared or tempfile.mkdtemp(prefix="remark_replay_")
    os.makedirs(tmpdir, exist_ok=True)

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    target = manifest["capabilities"]["weight"]["capture_contract"]["cm_per_px_target"]

    results = {"cm_per_px_target": target, "long_edge_cap": LONG_EDGE_CAP, "per_photo": {}}

    for photo in PHOTOS:
        src = os.path.join(PHOTO_DIR, photo["file"])
        png = os.path.join(tmpdir, photo["name"] + ".png")
        prepared_size, source_size = prepare_image(src, png)
        print("[%s] %dx%d -> %dx%d" % (photo["name"], source_size[0], source_size[1],
                                        prepared_size[0], prepared_size[1]))

        rows = []
        for ref_px, dev_area, dev_conf, dev_kg in photo["marks"]:
            cm_per_px = photo["reference_cm"] / ref_px
            env = run_cli(png, cm_per_px)
            row = {"ref_px": ref_px, "cm_per_px_actual": cm_per_px,
                   "device_seg_area": dev_area, "device_seg_conf": dev_conf,
                   "device_kg": dev_kg}
            for field in RECORD_FIELDS:
                row[field] = env.get(field)
            if env.get("segmentation_status"):
                row["segmentation_status"] = env["segmentation_status"]
            rows.append(row)
            print("  ref_px %.2f  cm_per_px %.6f  host %s kg (device %.2f)  segArea %s (device %d)"
                  % (ref_px, cm_per_px, row["predicted_kg"], dev_kg, row["mask_area_px"],
                     dev_area))

        host_kg = [r["predicted_kg"] for r in rows if r["predicted_kg"] is not None]
        entry = {
            "true_kg": photo["true_kg"],
            "reference_cm": photo["reference_cm"],
            "source_size": source_size,
            "prepared_size": prepared_size,
            "recorded_band_pct": photo["recorded_band_pct"],
            "marks": rows,
        }
        if len(host_kg) == len(rows):
            entry["host_band_kg"] = [min(host_kg), max(host_kg)]
            entry["host_spread_pct"] = spread_pct(host_kg)
        results["per_photo"][photo["name"]] = entry

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print("\nwrote %s" % args.out)

    print("\n| photo | device band | device spread | host band | host spread |")
    print("|---|---|---|---|---|")
    for photo in PHOTOS:
        e = results["per_photo"][photo["name"]]
        if "host_spread_pct" not in e:
            print("| %s | \u2014 | %.2f%% | FAILED | \u2014 |" % (photo["name"],
                                                                  e["recorded_band_pct"]))
            continue
        dev_kg = [m[3] for m in photo["marks"]]
        print("| %s | %.2f\u2013%.2f | %.2f%% | %.2f\u2013%.2f | %.2f%% |"
              % (photo["name"], min(dev_kg), max(dev_kg), e["recorded_band_pct"],
                 e["host_band_kg"][0], e["host_band_kg"][1], e["host_spread_pct"]))


if __name__ == "__main__":
    main()
