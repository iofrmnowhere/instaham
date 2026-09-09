# Phase 1 — Host toolchain and ONNX Runtime import library

Status: done

## Goal

Produce a host build environment in which the repository's `packages/instaham_ml_ffi/src`
stage sources compile and link on Windows x64, including ONNX Runtime, and leave a written
record of the exact commands in `ML/host_scale_test/README.md`.

## What is already verified present on this machine

Do not re-derive these; they were checked before this plan was written.

| dependency | location | notes |
|---|---|---|
| OpenCV 4 (vcpkg) | `C:\vcpkg\installed\x64-windows` | `core`, `imgproc`, `imgcodecs` libs and headers all present |
| vcpkg toolchain file | `C:\vcpkg\scripts\buildsystems\vcpkg.cmake` | what `find_package(OpenCV CONFIG REQUIRED)` needs |
| CMake 3.22.1 | `C:\Android_Studio_Loc\cmake\3.22.1\bin\cmake.exe` | meets the `cmake_minimum_required(VERSION 3.18)` in the native CMakeLists |
| Ninja | `C:\Android_Studio_Loc\cmake\3.22.1\bin\ninja.exe` | |
| MSVC 2022 BuildTools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat` | also supplies `dumpbin.exe` and `lib.exe`, needed below |
| ONNX Runtime C++ headers | `packages/instaham_ml_ffi/src/third_party/onnxruntime/include` | `ORT_API_VERSION 17` |
| ONNX Runtime Windows DLL | `.venv-export/Lib/site-packages/onnxruntime/capi/onnxruntime.dll` | 18 MB, version 1.29.0 |
| nlohmann/json | `packages/instaham_ml_ffi/src/third_party/nlohmann_json/single_include` | header-only |
| stb_image | `packages/instaham_ml_ffi/src/third_party/stb` | backs `util/image_io.cpp` |

`VCPKG_ROOT` is **not** set in the environment. Pass the toolchain file explicitly to CMake
rather than relying on it.

## The one missing piece

`packages/instaham_ml_ffi/src/third_party/onnxruntime/lib/` contains only Android shared
objects — `android/arm64-v8a`, `android/armeabi-v7a`, `android/x86_64`. There is no
`onnxruntime.lib` for Windows x64, and MSVC cannot link against a bare DLL without an import
library.

The repository's own `CMakeLists.txt` makes this explicit at the `INSTAHAM_ML_WITH_ORT`
block: the non-Android branch is

```cmake
message(FATAL_ERROR "INSTAHAM_ML_WITH_ORT is only wired for Android in this pass; ...")
```

so any host build that needs ORT must supply its own wiring. This phase supplies it inside
`ML/host_scale_test/`, and does **not** edit
`packages/instaham_ml_ffi/src/CMakeLists.txt` — that file is the app's build and is out of
scope for a throwaway experiment.

## Steps

- [x] Create `ML/host_scale_test/` and `ML/host_scale_test/third_party/`.
- [x] Open a shell with MSVC on PATH by running `vcvars64.bat` (the paths above). Every
      later command in this phase and phase 2 assumes that environment. `dumpbin` and `lib`
      are not on PATH without it.
- [x] Copy `.venv-export/Lib/site-packages/onnxruntime/capi/onnxruntime.dll` into
      `ML/host_scale_test/third_party/`. Copy, do not symlink — the DLL must sit next to the
      built `.exe` at run time, and a copy makes that unambiguous.
- [x] Generate the import library from that DLL's export table:
      - `dumpbin /exports third_party\onnxruntime.dll > third_party\ort_exports.txt`
      - Write `third_party\onnxruntime.def` beginning with the line `EXPORTS`, followed by
        one symbol name per line, taken from the fourth column of the `dumpbin` output's
        ordinal table. A short Python script is the sane way to do this; keep it in the
        folder as `make_ort_lib.py` so the step is reproducible.
      - `lib /def:third_party\onnxruntime.def /machine:x64 /out:third_party\onnxruntime.lib`
      - Confirm `OrtGetApiBase` appears in the `.def`. It is the only symbol
        `onnx_runner.cpp` strictly needs to resolve; if it is missing, the export parse was
        wrong.
- [x] Record in `README.md` that the headers are API version 17 while the runtime is 1.29.0,
      and that this is a supported combination — ONNX Runtime's C API is backward
      compatible, so a `GetApi(17)` request against a 1.29 runtime returns a valid function
      table. Do not "fix" the mismatch by downloading matching headers; the in-repo headers
      are what the app compiles against and using them is the point.
- [x] Write `ML/host_scale_test/CMakeLists.txt` as a standalone project (see the source list
      below). Configure and build it once against a trivial `main()` to prove the toolchain
      links, before phase 2 writes the real CLI:
      ```
      cmake -G Ninja -S ML/host_scale_test -B ML/host_scale_test/build ^
        -DCMAKE_BUILD_TYPE=Release ^
        -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake
      cmake --build ML/host_scale_test/build
      ```
- [x] Copy `onnxruntime.dll` next to the produced `.exe` (or set the CMake output directory
      to `third_party/` so they land together).
- [x] Add the drift guard described below and confirm it passes.
- [x] Write `README.md` with every command above verbatim, including the vcvars invocation.

## Source list for the standalone CMakeLists

The CLI needs these translation units from `packages/instaham_ml_ffi/src` (referenced by
relative path from `ML/host_scale_test/`; the repository root is two levels up):

```
manifest.cpp
onnx_runner.cpp
util/image_io.cpp
util/sha256.cpp
stages/segmentation.cpp
stages/construction.cpp
stages/cutter.cpp
stages/feature_calculation.cpp
stages/weight_prediction.cpp
```

Plus the vendor sets, which the app's CMakeLists names
`INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES` (2 files: `MaskUtils.cpp`,
`preprocess/JiDuan.cpp`), `INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES` (19 files under
`src/features/`), and `INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES` (7 files under `src/cutter/`).
All three sets are required: the cutter needs common + cutter, the feature extractor needs
common + feature.

Do **not** include `pipeline.cpp`, `instaham_ml.cpp`, `classifier.cpp`, or `health_input.cpp`.
`pipeline.cpp` owns the FFI-level flow including the view and health branches, pulls in the
classifier models, and would drag the whole library in. Phase 2's CLI reimplements only the
weight branch's ordering, which is a deliberate and documented narrowing — see phase 2's
"What the CLI must reproduce exactly".

Include directories:

```
packages/instaham_ml_ffi/src
packages/instaham_ml_ffi/src/include
packages/instaham_ml_ffi/src/vendor/instaham_v176/include
packages/instaham_ml_ffi/src/third_party/onnxruntime/include
packages/instaham_ml_ffi/src/third_party/nlohmann_json/single_include
```

Compile definitions: `INSTAHAM_ML_HAS_OPENCV=1` and `INSTAHAM_ML_HAS_JSON=1`, matching what
the app's build sets. Set `CMAKE_CXX_STANDARD 17`.

Link: `opencv_core`, `opencv_imgproc` from vcpkg's config package, plus the generated
`third_party/onnxruntime.lib`.

`onnx_runner.cpp` already carries a `_WIN32` branch for the wide-character model path that
`Ort::Session` requires on Windows, so no source edit is needed there.

## Drift guard

The source lists above are copied from
`packages/instaham_ml_ffi/src/CMakeLists.txt` and will silently rot if that file gains or
loses a vendor source. Add a check that fails the build rather than producing a stale
result — a CMake `file(GLOB ...)` over `vendor/instaham_v176/src/features/*.cpp` and
`vendor/instaham_v176/src/cutter/*.cpp` compared against the expected counts of **19** and
**7**, with `message(FATAL_ERROR ...)` on mismatch, is sufficient and takes four lines.

Glob is normally the wrong tool in CMake because it does not re-run on file addition. Here
that weakness is acceptable: the guard exists to catch a human editing the vendor tree
between sessions, and a stale configure is itself caught by the next clean build.

## Verification

- [x] `cmake --build` completes with no errors.
- [x] The trivial binary runs and exits 0 with `onnxruntime.dll` alongside it.
- [x] Deliberately move `onnxruntime.dll` away and confirm the binary fails to start — this
      proves it is actually linking the runtime rather than silently omitting it.
- [x] The drift guard fires when given a wrong expected count (test it once, then restore).

## Open questions

- If `lib /def:` rejects any exported name (ORT exports are plain C, so this is unlikely),
  fall back to downloading the official `onnxruntime-win-x64-1.29.0` release zip, which ships
  a real `.lib`. Record which route was taken in `README.md` — phase 4 reports the ORT
  version and its provenance.
