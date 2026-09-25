"""Assemble assets/ml/manifest.json from the per-capability fragments and stage the ONNX files.

    # full build
    python -m ML.export.build_manifest \
        --view build/ml_export/view \
        --health build/ml_export/health \
        --weight build/ml_export/weight \
        --segmentation build/ml_export/segmentation \
        --assets assets/ml

    # CI staleness gate (re-hash model/regressor/class_map files against the manifest)
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


def _key_paths(node: object, prefix: str = "") -> set[str]:
    """Dotted paths to every key reachable by walking nested dicts.

    Lists are treated as leaves (not recursed into) since their positional
    keys carry no stable identity to diff against.
    """
    if not isinstance(node, dict):
        return set()
    paths: set[str] = set()
    for key, value in node.items():
        path = f"{prefix}.{key}" if prefix else key
        paths.add(path)
        paths |= _key_paths(value, path)
    return paths


def _check_no_key_loss(assets: Path, new_manifest: dict, *, allow_key_removal: bool) -> None:
    """Fail if the new manifest silently drops a key the previous one had.

    A stale `build/ml_export/<cap>/manifest_fragment.json` left over from before its
    exporter grew a new block (e.g. F51/F50: `segmentation.input_scale`) changes no file
    hash, so `check()` cannot catch it — this catches it before the manifest is written.
    Changed values pass untouched; only disappearance trips the guard.
    """
    existing_path = assets / "manifest.json"
    if not existing_path.exists():
        return
    old_paths = _key_paths(read_json(existing_path))
    new_paths = _key_paths(new_manifest)
    missing = sorted(old_paths - new_paths)
    if not missing:
        return
    if allow_key_removal:
        print(f"allowing removal of {len(missing)} key(s): {', '.join(missing)}")
        return
    raise SystemExit(
        f"build_manifest: {len(missing)} key(s) present in the existing manifest.json "
        f"would be dropped by this rebuild: {', '.join(missing)}. This is the F50-class "
        "regression: a stale fragment reverting a capability that wasn't touched. Pass "
        "--allow-key-removal if the drop is deliberate."
    )


def build(
    *,
    fragments: dict[str, Path],
    assets: Path,
    platform: str | None = None,
    allow_key_removal: bool = False,
) -> Path:
    assets.mkdir(parents=True, exist_ok=True)
    capabilities: dict[str, dict] = {}
    for cap, frag_dir in fragments.items():
        frag = read_json(frag_dir / "manifest_fragment.json")
        # health.input is decided by ML.export.probe_health_input, not written by hand
        # (section 1.1(c)) — merge it in when the probe has run against this export dir.
        input_protocol_path = frag_dir / "input_protocol.json"
        if cap == "health" and input_protocol_path.exists():
            frag["health"]["input"] = read_json(input_protocol_path)["health"]["input"]
        # capabilities.health.cascade (docs/plan-4.md) is a hand-edited manifest decision,
        # not written by any exporter fragment -- preserve it from the previously-shipped
        # manifest so a routine rebuild does not silently drop it. Without this,
        # _check_no_key_loss() below would still catch the drop and refuse to build, but
        # that is a last resort, not the intended path.
        if cap == "health" and "cascade" not in frag.get("health", {}):
            existing_path = assets / "manifest.json"
            if existing_path.exists():
                existing_cascade = read_json(existing_path).get("capabilities", {}).get(
                    "health", {}
                ).get("cascade")
                if existing_cascade is not None:
                    frag["health"]["cascade"] = existing_cascade
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
    _check_no_key_loss(assets, manifest, allow_key_removal=allow_key_removal)
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
        "--allow-key-removal",
        action="store_true",
        help="Permit the rebuild to drop a key present in the existing manifest.json "
        "(F51 guard). Omit unless the removal is deliberate.",
    )
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
    print(
        f"wrote {build(fragments=fragments, assets=a.assets, platform=a.platform, allow_key_removal=a.allow_key_removal)}"
    )


if __name__ == "__main__":
    main()
