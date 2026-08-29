"""Assemble assets/ml/manifest.json from the per-capability fragments and stage the ONNX files.

    # full build
    python -m ML.export.build_manifest \
        --view build/ml_export/view \
        --health build/ml_export/health \
        --weight build/ml_export/weight \
        --segmentation build/ml_export/segmentation \
        --assets assets/ml

    # CI determinism gate (re-run export, diff sha256s)
    python -m ML.export.build_manifest --check --assets assets/ml
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from ML.export.common import MANIFEST_SCHEMA_VERSION, read_json, sha256_file, write_json

_CAPABILITY_FILES = {
    "view": ["model.onnx", "classes.json", "preprocessing.json"],
    "health": ["model.onnx", "classes.json", "preprocessing.json"],
    "weight": ["xgboost.onnx", "feature_order.json", "xgboost.meta.json"],
    "segmentation": ["yolo.onnx", "classes.json"],
}


def _git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:  # noqa: BLE001
        return "unknown"


def _stage(cap: str, src: Path, assets: Path) -> None:
    dst = assets / cap
    dst.mkdir(parents=True, exist_ok=True)
    for fname in _CAPABILITY_FILES[cap]:
        s = src / fname
        if s.exists():
            shutil.copy(s, dst / fname)


def _validate(manifest: dict) -> None:
    """Validate against manifest.schema.json. Fatal on any violation."""
    import jsonschema

    schema = read_json(Path(__file__).with_name("manifest.schema.json"))
    jsonschema.validate(manifest, schema)


def build(*, fragments: dict[str, Path], assets: Path, platform: str | None = None) -> Path:
    assets.mkdir(parents=True, exist_ok=True)
    capabilities: dict[str, dict] = {}
    for cap, frag_dir in fragments.items():
        frag = read_json(frag_dir / "manifest_fragment.json")
        # health.input is decided by ML.export.probe_health_input, not written by hand
        # (section 1.1(c)) — merge it in when the probe has run against this export dir.
        input_protocol_path = frag_dir / "input_protocol.json"
        if cap == "health" and input_protocol_path.exists():
            frag["health"]["input"] = read_json(input_protocol_path)["health"]["input"]
        capabilities.update(frag)
        _stage(cap, frag_dir, assets)

    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "bundle_id": f"instaham-ml-{_git_sha()}",
        "reference_commit": _git_sha(),
        "runtime": {"engine": "onnxruntime", "min_abi_version": 1},
        "capabilities": capabilities,
    }
    if platform is not None:
        manifest["platform"] = platform
    _validate(manifest)
    return write_json(assets / "manifest.json", manifest)


def check(assets: Path) -> int:
    """Verify every sha256 recorded in the manifest still matches the staged file."""
    manifest = read_json(assets / "manifest.json")
    problems: list[str] = []
    for cap, block in manifest.get("capabilities", {}).items():
        for key in ("model", "regressor", "class_map"):
            entry = block.get(key)
            if not isinstance(entry, dict) or "path" not in entry or "sha256" not in entry:
                continue
            f = assets / entry["path"]
            if not f.exists():
                problems.append(f"{cap}.{key}: missing {f}")
            elif sha256_file(f) != entry["sha256"]:
                problems.append(f"{cap}.{key}: sha256 mismatch for {f}")
    for p in problems:
        print(f"FAIL {p}")
    print("manifest check OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--assets", type=Path, default=Path("assets/ml"))
    ap.add_argument("--view", type=Path)
    ap.add_argument("--health", type=Path)
    ap.add_argument("--weight", type=Path)
    ap.add_argument("--segmentation", type=Path)
    ap.add_argument("--check", action="store_true")
    ap.add_argument(
        "--platform",
        choices=["android", "ios"],
        default=None,
        help="Stamp manifest.json with a platform tag. Omit to build one platform-neutral "
        "manifest (both platforms are identical through slice 4 per section 11.2).",
    )
    a = ap.parse_args()

    if a.check:
        raise SystemExit(check(a.assets))

    fragments = {
        cap: getattr(a, cap)
        for cap in ("view", "health", "weight", "segmentation")
        if getattr(a, cap) is not None
    }
    if not fragments:
        raise SystemExit("nothing to build: pass at least one of --view/--health/--weight/--segmentation")
    print(f"wrote {build(fragments=fragments, assets=a.assets, platform=a.platform)}")


if __name__ == "__main__":
    main()
