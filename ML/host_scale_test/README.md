# Host scale test — phase 1 (toolchain)

Standalone Windows host build of INSTAHAM's real weight-branch C++ stages (segmentation,
construction, the vendor V176/V144 cutter, Chen16 feature extraction, XGBoost-via-ONNX
prediction), used to settle `cm_per_px_target` 0.35 vs 0.3289 against the five PIGRGB images
in `Instaham/PIGRGB-Weight/sub_1.78/`. See `docs/test-plan.md` and
`docs/test-plan-phase/*.md` for the full plan; this file records only what phase 1 actually
did on this machine, so it can be repeated.

## Toolchain used

- OpenCV 4.12.0 via vcpkg: `C:\vcpkg\installed\x64-windows`, toolchain file
  `C:\vcpkg\scripts\buildsystems\vcpkg.cmake`. `VCPKG_ROOT` is not set in the environment —
  the toolchain file is passed explicitly on every `cmake` invocation.
- CMake 3.22.1 + Ninja: `C:\Android_Studio_Loc\cmake\3.22.1\bin\{cmake.exe,ninja.exe}`.
- MSVC 2022 BuildTools (19.44.35228.0), via
  `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat`.
  Also supplies `dumpbin.exe` and `lib.exe`, used below. Every command in this file assumes
  a shell that has sourced this script. The `'vswhere.exe' is not recognized...` line it
  prints on this machine is harmless — the script still initializes the x64 environment
  correctly afterward.
- ONNX Runtime C++ headers already in-repo:
  `packages/instaham_ml_ffi/src/third_party/onnxruntime/include` (`ORT_API_VERSION 17`).
- ONNX Runtime Windows DLL, from the pip install already present at
  `.venv-export/Lib/site-packages/onnxruntime/capi/onnxruntime.dll` (version **1.29.0**, 18 MB).

**Header/runtime version note:** headers are API version 17, the runtime DLL is 1.29.0.
This is a supported combination — ONNX Runtime's C API is backward compatible, so a
`GetApi(17)` request against a 1.29 runtime returns a valid function table. Confirmed
working by the smoke test below, which loads a real ONNX session through this exact
pairing. Do not replace the in-repo headers to "match" the runtime version; the app compiles
against these headers and using them here is the point.

## The missing piece: generating onnxruntime.lib

`packages/instaham_ml_ffi/src/third_party/onnxruntime/lib/` ships only Android `.so` files.
There is no Windows import library, and the app's own
`packages/instaham_ml_ffi/src/CMakeLists.txt` FATAL_ERRORs on any non-Android
`INSTAHAM_ML_WITH_ORT` build, so one had to be generated here rather than reused.

Route taken: generate the import lib from the pip DLL's export table (the "official SDK zip"
fallback in the plan's open questions was not needed).

```
# inside a vcvars64.bat shell, cwd = ML/host_scale_test/third_party
dumpbin /exports onnxruntime.dll > ort_exports.txt
python make_ort_lib.py            # writes onnxruntime.def
lib /def:onnxruntime.def /machine:x64 /out:onnxruntime.lib
```

The DLL exports exactly two C symbols: `OrtGetApiBase` and
`OrtSessionOptionsAppendExecutionProvider_CPU`. `OrtGetApiBase` — the only symbol
`onnx_runner.cpp` needs — was present, so the `.def` covers everything required.
`make_ort_lib.py` is kept in this directory so the step is reproducible without re-deriving
the `dumpbin` output format.

## Build

```
cmake -G Ninja -S ML/host_scale_test -B ML/host_scale_test/build ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake
cmake --build ML/host_scale_test/build
```

(Run inside the vcvars64.bat shell.) This produces `build/host_scale_smoke.exe` — the phase
1 toolchain proof — and copies `third_party/onnxruntime.dll` next to it via a post-build
step, so the exe runs without a manual copy.

`host_scale_smoke.exe` takes one argument, the repo root, loads `assets/ml/manifest.json`
through the real `load_manifest()`, then loads the real `xgboost.onnx` regressor through the
real `OnnxRunner`. It is not a no-op smoke test — it proves the full compile+link+model-load
chain, including the vendor V176/V144 cutter and Chen16 feature sources (39 translation
units total), works before phase 2 replaces it with the actual weight-branch CLI.

Verified working:

```
> host_scale_smoke.exe "C:\...\instaham"
manifest loaded ok. weight.available=1 cm_per_px_target=0.328900
onnxruntime session loaded ok: C:\...\instaham\assets\ml\weight\xgboost.onnx
```

## Drift guard

`CMakeLists.txt` globs the vendor `features/` and `cutter/` directories and FATAL_ERRORs the
configure step if the counts drift from the expected 19 and 7 (matching
`packages/instaham_ml_ffi/src/CMakeLists.txt`'s `INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES` /
`..._CUTTER_SOURCES` lists). Verified: temporarily changing the expected feature count to
999 produced

```
CMake Error at CMakeLists.txt:21 (message):
  expected 19 vendor feature sources, found 19 --
  packages/instaham_ml_ffi/src/CMakeLists.txt's
  INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES list must be re-copied here
```

and restoring the expected value reconfigured clean.

## Real finding: a stray system-wide `onnxruntime.dll`

Verification step "move `onnxruntime.dll` away, confirm the binary fails to start" did
**not** produce a clean failure on this machine. Instead:

```
The given version [17] is not supported, only version 1 to 10 is supported in this build.
```
...followed by a segfault (exit 139).

Cause: **`C:\Windows\System32\onnxruntime.dll` already exists on this machine** (installed
by some other, unrelated application), and it only supports ORT API versions 1–10. Windows'
DLL search order tries the executable's own directory first, so the correctly-built exe with
its own 1.29.0 copy alongside it is unaffected in normal operation — confirmed by re-running
immediately after restoring the local copy, which worked identically to the first run. But
if the local copy is ever missing, misnamed, or the working directory changes in a way that
breaks the "next to the exe" assumption, the process does **not** fail cleanly with a
missing-DLL error; it silently loads the System32 copy and crashes inside
`OrtGetApiBase`'s version dispatch instead.

**Consequence for later phases:** phase 2's CLI and phase 3's driver must always invoke the
binary from its own build directory (or otherwise guarantee `onnxruntime.dll` sits next to
the `.exe`), and should treat a crash with the "version ... not supported" message as this
specific failure mode rather than a pipeline bug, if it ever recurs. This is not a
hypothetical edge case — it reproduced deterministically on the first attempt.

## Files in this directory

```
CMakeLists.txt       standalone host build, drift guard, phase 1's smoke target
smoke_main.cpp        phase 1 toolchain proof (replaced by the real CLI in phase 2)
third_party/
  onnxruntime.dll      copied from .venv-export's pip install (1.29.0)
  onnxruntime.def       generated EXPORTS list
  onnxruntime.lib        generated import library
  ort_exports.txt        raw dumpbin output, kept for reference
  make_ort_lib.py        regenerates onnxruntime.def from ort_exports.txt
build/                 CMake build directory (not committed; see .gitignore)
out/                   phase 3's results land here (empty for now)
```

## Verification checklist (docs/test-plan-phase/1-host-toolchain.md)

- [x] `cmake --build` completes with no errors.
- [x] The binary runs and exits 0 with `onnxruntime.dll` alongside it — and does real work
      (loads the manifest and a real ONNX session), not just `return 0`.
- [x] Moving `onnxruntime.dll` away breaks the binary — though as a crash from a stray
      System32 copy, not a clean "DLL not found," which is now documented above as a real
      risk for later phases rather than a pass/fail formality.
- [x] The drift guard fires on a wrong expected count and was restored afterward.
