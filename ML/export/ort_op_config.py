"""Emit the ONNX Runtime reduced-build operator allowlist for the exported graphs.

The mobile ORT build is trimmed to only the ops the shipped models use. Re-run whenever a
graph changes; commit the output next to the manifest.

    python -m ML.export.ort_op_config --assets assets/ml --out packages/instaham_ml_ffi/src/third_party/onnxruntime/ort.config

Under the hood this shells out to ORT's own tooling:
    python -m onnxruntime.tools.create_reduced_build_config <onnx files...> <out>
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def collect_onnx(assets: Path) -> list[Path]:
    return sorted(assets.rglob("*.onnx"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--assets", type=Path, default=Path("assets/ml"))
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()

    models = collect_onnx(a.assets)
    if not models:
        raise SystemExit(f"no .onnx files under {a.assets}")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable,
        "-m",
        "onnxruntime.tools.create_reduced_build_config",
        *[str(m) for m in models],
        str(a.out),
    ]
    print("run:", " ".join(cmd))
    subprocess.check_call(cmd)
    print(f"wrote {a.out} for {len(models)} model(s)")


if __name__ == "__main__":
    main()
