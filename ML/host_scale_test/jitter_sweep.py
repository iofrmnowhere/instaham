"""Measure how much predicted weight moves from reference-marking jitter alone, without a
sideload. Opened for docs/fix-phase-2/2.1-reference-length-sensitivity.md; now the primary
instrument for docs/fix-3.md (round 7), which replaces the weight branch's double mask
rasterization with one composed transform.

F53 measured this on-device: marking the same reference object one pixel differently changed
cm_per_px_actual by about 0.32% and moved predicted weight by 5-13%. This script cannot
reproduce that exactly -- the PIGRGB images here carry no marked reference object, only a true
weight in the filename -- so it sweeps cm_per_px_actual by a band of percentage deltas centered
on each image's baseline value instead. That is a proxy for marking noise, not a re-derivation
of it: it isolates how much the DOWNSTREAM pipeline (resample -> cutter -> features ->
regressor) amplifies a small scale-input change. It does not reproduce item 1 (the reference
also re-composes the segmentation canvas, ref_fix.md F18) -- that path only exists on-device,
where the reference is marked before segmentation runs, not after.

Resolution and the --upscale-long-edge option (docs/fix-phase-3/1-harness-baseline.md, F56)
--------------------------------------------------------------------------------------------
The defect round 7 fixes scales with the size of the intermediate full-resolution raster
(construction.cpp:97) relative to the 640x640 mask it comes from. The PIGRGB images here are
960x540, so that detour is only about 1.5x. A real phone capture reaches the pipeline at
1280x720 (live camera) or 2250x3000 (gallery import), where the detour is 2x to 4.7x, so a
baseline taken at 960x540 UNDERSTATES both the defect and any fix.

--upscale-long-edge N resamples each source image so its long edge is N px before the sweep,
and scales cm_per_px_actual by the same factor so the pig lands at the same physical scale in
the model input. This reproduces the resolution, and therefore the raster-detour magnitude,
of a real capture. It does NOT reproduce the live path's crop, aspect ratio or lens, and the
upscaled source is a soft interpolation of an already-downscaled image rather than real
sensor detail -- so YOLO sees a blurrier pig than a native capture would. Treat an upscaled
sweep as "the raster detour at real-capture magnitude", not as a full field-capture replica.

Without --upscale-long-edge the behavior is unchanged from the round 6 baselines, so
out/jitter_sweep{,_1.88}.json stay reproducible.

Usage:
  python jitter_sweep.py [--images-dir DIR] [--height METERS] [--deltas D1,D2,...]
                         [--upscale-long-edge N] [--interp cubic|linear|lanczos]
                         [--native-long-edge N] [--out PATH]

Before/after for a mask-path change: run once now (before), apply the change and rebuild
weight_branch_cli.exe, run again (after) with the same args, diff spread_pct per image.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_sweep import (IMAGES_DIR as DEFAULT_IMAGES_DIR, MANIFEST_PATH, CLI_PATH, OUT_DIR,
                        FNAME_RE)

# Matches the order of magnitude F53 measured on device (~0.32% input change from one pixel
# of marking on a meter-stick-length reference). Centered on 0 so the baseline (delta 0) is
# always included and comparable to the other two drivers' cm_per_px_actual.
DEFAULT_DELTAS_PCT = [-1.0, -0.5, -0.32, -0.16, 0.0, 0.16, 0.32, 0.5, 1.0]

# PIGRGB frames here are 960x540. cm_per_px_actual below is derived for that width; an
# upscale is expressed relative to it.
DEFAULT_NATIVE_LONG_EDGE = 960

INTERP = {
    "cubic": cv2.INTER_CUBIC,
    "linear": cv2.INTER_LINEAR,
    "lanczos": cv2.INTER_LANCZOS4,
}


def ppm_for_height(height_m):
    # Same derivation run_sweep.py uses: docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md's
    # 304 px/m at 1.88 m, rescaled to the given capture height.
    PIGRGB_TARGET_PPM_AT_188 = 304.0
    BASELINE_HEIGHT_M = 1.88
    return PIGRGB_TARGET_PPM_AT_188 * BASELINE_HEIGHT_M / height_m


def try_parse_true_kg(filename):
    m = FNAME_RE.match(filename)
    return float(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--images-dir", default=DEFAULT_IMAGES_DIR,
                     help="folder of <kg>kg_*.png images (default: run_sweep.py's sub_1.78)")
    ap.add_argument("--height", type=float, default=1.78,
                     help="capture height in meters for this folder (default: 1.78)")
    ap.add_argument("--deltas", default=",".join(str(d) for d in DEFAULT_DELTAS_PCT),
                     help="comma-separated cm_per_px_actual deltas in percent")
    ap.add_argument("--upscale-long-edge", type=int, default=0,
                     help="resample each image so its long edge is this many px before the "
                          "sweep, and scale cm_per_px_actual to match (F56). 0 = no upscale, "
                          "the round 6 behavior.")
    ap.add_argument("--native-long-edge", type=int, default=DEFAULT_NATIVE_LONG_EDGE,
                     help="long edge the folder's cm_per_px_actual derivation assumes "
                          "(default: 960, PIGRGB). Only used with --upscale-long-edge.")
    ap.add_argument("--interp", choices=sorted(INTERP), default="cubic",
                     help="interpolation for --upscale-long-edge (default: cubic)")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "jitter_sweep.json"))
    args = ap.parse_args()

    if not os.path.exists(CLI_PATH):
        print("weight_branch_cli.exe not found at %s -- build phase 2 first" % CLI_PATH,
              file=sys.stderr)
        return 2

    deltas_pct = [float(x) for x in args.deltas.split(",")]
    base_actual = 100.0 / ppm_for_height(args.height)

    upscale = args.upscale_long_edge
    scale_factor = 1.0
    if upscale:
        scale_factor = upscale / float(args.native_long_edge)
        # More pixels per meter -> smaller cm per pixel, by the same factor.
        base_actual /= scale_factor

    images = sorted(f for f in os.listdir(args.images_dir) if f.lower().endswith(".png"))
    if not images:
        print("no PNG images found in %s" % args.images_dir, file=sys.stderr)
        return 2

    print("cm_per_px_actual baseline: %.7f (height=%.2fm)" % (base_actual, args.height))
    if upscale:
        print("upscale: long edge -> %d px (x%.3f, %s), cm_per_px_actual scaled to match"
              % (upscale, scale_factor, args.interp))
    print("deltas (%%): %s\n" % deltas_pct)

    results = {"images_dir": args.images_dir, "height_m": args.height,
               "cm_per_px_actual_baseline": base_actual, "deltas_pct": deltas_pct,
               "upscale_long_edge": upscale or None,
               "upscale_interp": args.interp if upscale else None,
               "upscale_scale_factor": scale_factor if upscale else None,
               "native_long_edge": args.native_long_edge if upscale else None,
               "per_image": {}}
    worst_spread_pct = 0.0
    worst_image = None

    tmpdir = tempfile.mkdtemp(prefix="jitter_upscale_") if upscale else None
    try:
        for image_name in images:
            true_kg = try_parse_true_kg(image_name)
            src_path = os.path.join(args.images_dir, image_name)

            src = cv2.imread(src_path, cv2.IMREAD_COLOR)
            if src is None:
                print("could not read %s" % src_path, file=sys.stderr)
                return 1
            src_h, src_w = src.shape[:2]
            source_resolution = [src_w, src_h]

            if upscale:
                long_edge = max(src_w, src_h)
                f = upscale / float(long_edge)
                dst_w, dst_h = int(round(src_w * f)), int(round(src_h * f))
                resized = cv2.resize(src, (dst_w, dst_h), interpolation=INTERP[args.interp])
                image_path = os.path.join(tmpdir, image_name)
                cv2.imwrite(image_path, resized)
                swept_resolution = [dst_w, dst_h]
            else:
                image_path = src_path
                swept_resolution = source_resolution

            predictions = []
            for delta in deltas_pct:
                actual = base_actual * (1.0 + delta / 100.0)
                result = subprocess.run(
                    [CLI_PATH, MANIFEST_PATH, image_path, "%.10f" % actual],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print("CLI failed (exit %d) for %s @ delta %+.2f%%:\n%s" % (
                        result.returncode, image_name, delta, result.stderr), file=sys.stderr)
                    return 1
                env = json.loads(result.stdout.strip())
                predicted_kg = env.get("predicted_kg")
                predictions.append({
                    "delta_pct": delta, "cm_per_px_actual": actual, "predicted_kg": predicted_kg,
                    "extrapolated": env.get("extrapolated", False),
                    "domain_violations": [v.get("feature") for v in env.get("domain_violations", [])],
                })

            values = [p["predicted_kg"] for p in predictions if p["predicted_kg"] is not None]
            if values:
                spread_kg = max(values) - min(values)
                mean_kg = sum(values) / len(values)
                spread_pct = (spread_kg / mean_kg * 100.0) if mean_kg else 0.0
            else:
                spread_kg = spread_pct = 0.0

            results["per_image"][image_name] = {
                "true_kg": true_kg,
                "source_resolution": source_resolution,
                "swept_resolution": swept_resolution,
                "predictions": predictions,
                "spread_kg": spread_kg, "spread_pct": spread_pct,
            }
            if spread_pct > worst_spread_pct:
                worst_spread_pct, worst_image = spread_pct, image_name

            print("%s (true=%s): predicted=[%s]  spread=%.2fkg (%.1f%%)" % (
                image_name, "%.2fkg" % true_kg if true_kg is not None else "n/a",
                " ".join("%.1f" % v for v in values), spread_kg, spread_pct))
    finally:
        if tmpdir:
            for f in os.listdir(tmpdir):
                os.remove(os.path.join(tmpdir, f))
            os.rmdir(tmpdir)

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print("\nworst spread: %s at %.1f%%" % (worst_image, worst_spread_pct))
    print("wrote", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
