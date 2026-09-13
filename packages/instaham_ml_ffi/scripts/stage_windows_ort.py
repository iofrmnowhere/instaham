"""Stage a Windows ONNX Runtime DLL + import library into src/third_party/onnxruntime/lib/windows/.

docs/metrics-plan.md phase 1. fetch_deps.sh only stages the Android onnxruntime .so files;
the Windows host build of instaham_ml.dll (so `flutter test` can DynamicLibrary.open the real
native pipeline) needs a Windows onnxruntime.dll and a matching import library. ONNX Runtime's
pip wheel ships the DLL but no .lib, so the .lib is generated here from the DLL's export
table -- the exact recipe recorded in ML/host_scale_test/README.md, lifted into a script so a
fresh checkout can reproduce it.

Usage (run inside a "x64 Native Tools Command Prompt for VS 2022", or any shell that has
sourced vcvars64.bat so `dumpbin` and `lib` are on PATH):

    python packages/instaham_ml_ffi/scripts/stage_windows_ort.py

Source DLL resolution order (override with --dll):
  1. --dll PATH
  2. ML/host_scale_test/third_party/onnxruntime.dll   (already generated for that harness)
  3. .venv-export/Lib/site-packages/onnxruntime/capi/onnxruntime.dll   (the pip install)

The DLL and .lib land in an in-repo path that src/third_party/.gitignore already excludes --
nothing here is committed; this script is the source of truth, same policy as fetch_deps.sh.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEST_DIR = REPO_ROOT / "packages/instaham_ml_ffi/src/third_party/onnxruntime/lib/windows"

CANDIDATE_DLLS = [
    REPO_ROOT / "ML/host_scale_test/third_party/onnxruntime.dll",
    REPO_ROOT / ".venv-export/Lib/site-packages/onnxruntime/capi/onnxruntime.dll",
]


def _resolve_dll(override: str | None) -> Path:
    if override:
        p = Path(override).resolve()
        if not p.is_file():
            sys.exit(f"--dll: not a file: {p}")
        return p
    for c in CANDIDATE_DLLS:
        if c.is_file():
            return c
    sys.exit(
        "no onnxruntime.dll found. Pass --dll PATH, or `pip install onnxruntime` into "
        ".venv-export, or build ML/host_scale_test first.\nlooked in:\n  "
        + "\n  ".join(str(c) for c in CANDIDATE_DLLS)
    )


def _have(tool: str) -> bool:
    return shutil.which(tool) is not None


def _reuse_existing_lib(src_dll: Path) -> Path | None:
    """If the DLL is the one host_scale_test already produced a .lib for, reuse that .lib."""
    sibling = src_dll.with_name("onnxruntime.lib")
    if sibling.is_file():
        return sibling
    return None


def _generate_lib(src_dll: Path, work: Path) -> Path:
    if not _have("dumpbin") or not _have("lib"):
        sys.exit(
            "dumpbin/lib not on PATH -- open a 'x64 Native Tools Command Prompt for VS 2022' "
            "(or source vcvars64.bat) and re-run. No .lib could be reused either."
        )
    work.mkdir(parents=True, exist_ok=True)
    exports_txt = work / "ort_exports.txt"
    def_path = work / "onnxruntime.def"
    lib_path = work / "onnxruntime.lib"

    with exports_txt.open("w", encoding="utf-8") as fh:
        subprocess.run(["dumpbin", "/exports", str(src_dll)], check=True, stdout=fh)

    names: list[str] = []
    in_table = False
    import re

    row_re = re.compile(r"^\s*(\d+)\s+([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)\s+(\S+)\s*$")
    for line in exports_txt.read_text(encoding="utf-8", errors="replace").splitlines():
        if "ordinal hint RVA" in line:
            in_table = True
            continue
        if in_table:
            m = row_re.match(line)
            if m:
                names.append(m.group(4))
            elif not line.strip() and names:
                break
    if "OrtGetApiBase" not in names:
        sys.exit(f"OrtGetApiBase not in {src_dll} exports -- onnx_runner.cpp needs it")

    def_path.write_text("EXPORTS\n" + "\n".join(names) + "\n", encoding="utf-8")
    subprocess.run(
        ["lib", f"/def:{def_path}", "/machine:x64", f"/out:{lib_path}"], check=True
    )
    print(f"generated import lib from {len(names)} export(s): {', '.join(names)}")
    return lib_path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dll", help="explicit path to a Windows onnxruntime.dll")
    args = ap.parse_args()

    src_dll = _resolve_dll(args.dll)
    print(f"source DLL: {src_dll}")

    DEST_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_dll, DEST_DIR / "onnxruntime.dll")

    lib = _reuse_existing_lib(src_dll)
    if lib:
        print(f"reusing existing import lib: {lib}")
    else:
        lib = _generate_lib(src_dll, DEST_DIR / "_gen")
    shutil.copy2(lib, DEST_DIR / "onnxruntime.lib")

    print(f"\nstaged into {DEST_DIR}:")
    for f in ("onnxruntime.dll", "onnxruntime.lib"):
        p = DEST_DIR / f
        print(f"  {f:20s} {p.stat().st_size:>12,d} bytes")


if __name__ == "__main__":
    main()
