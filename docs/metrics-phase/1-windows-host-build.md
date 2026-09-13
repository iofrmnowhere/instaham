# Metrics plan phase 1 — Windows host build of `instaham_ml.dll`

Status: **done** on this machine. `flutter test` still reports 93 passed / 21 skipped (this
phase adds no tests; it unblocks phases 2, 4, and 5).

## What this phase delivers

A Windows build of the real native pipeline library, `instaham_ml.dll`, produced directly
through CMake (not through the Flutter build — the FFI package has no `windows/` plugin).
Once it exists, a Dart VM process such as `flutter test` can `DynamicLibrary.open` it and
call the same C ABI the app calls on Android, so the scenario and parity tests can run
against the actual segmentation → construction → cutter → Chen16 → XGBoost stages instead of
staying skipped with "needs concrete ML service".

## Changes

| file | change |
|---|---|
| `packages/instaham_ml_ffi/src/CMakeLists.txt` | added an `elseif(WIN32)` branch to the `INSTAHAM_ML_WITH_ORT` block (previously a hard `FATAL_ERROR` off Android); added a `WIN32` POST_BUILD step that stages `onnxruntime.dll` and the vcpkg OpenCV runtime DLLs next to the output |
| `packages/instaham_ml_ffi/scripts/stage_windows_ort.py` | new — stages a Windows `onnxruntime.dll` + generated import `.lib` into `src/third_party/onnxruntime/lib/windows/` |
| `packages/instaham_ml_ffi/scripts/build_windows_host.ps1` | new — configure + build wrapper (Visual Studio generator; no `vcvars64.bat` shell needed) |
| `packages/instaham_ml_ffi/scripts/check_windows_host.dart` | new — the exit check: loads the built DLL and exercises the C ABI |

The Android path is untouched: the `if(ANDROID)` arm of the ORT block is unchanged, and the
new POST_BUILD is guarded on `WIN32 AND INSTAHAM_ML_WITH_ORT`. `INSTAHAM_ML_WITH_OPENCV`
already had a working non-Android arm (vcpkg `find_package(OpenCV CONFIG REQUIRED)`), so only
ORT needed a new branch.

Nothing new is committed under `src/third_party/` — that tree's `.gitignore` excludes
everything but `.gitignore`/`README.md`, same policy as the Android prebuilts. The staged
DLL/`.lib` are reproduced by `stage_windows_ort.py`, which is the source of truth.

## Toolchain (this machine)

Identical to `ML/host_scale_test/README.md`:

- MSVC 2022 BuildTools 19.44, Windows SDK 10.0.26100.
- CMake 3.22.1 at `C:\Android_Studio_Loc\cmake\3.22.1\bin\cmake.exe`.
- vcpkg at `C:\vcpkg`, `opencv4` installed → OpenCV 4.12.0 (`x64-windows`).
- ONNX Runtime: headers already in-repo at
  `packages/instaham_ml_ffi/src/third_party/onnxruntime/include` (`ORT_API_VERSION 17`);
  the Windows DLL is `onnxruntime` **1.29.0** copied from
  `ML/host_scale_test/third_party/onnxruntime.dll` (originally the pip wheel in
  `.venv-export`). API-17 headers against a 1.29 runtime is a supported, backward-compatible
  pairing.

**Deviation from the host-scale-test recipe:** that harness used `-G Ninja` inside a
`vcvars64.bat` shell. On this machine `vcvars64.bat` cannot find `vswhere.exe` and, invoked
non-interactively, hangs after printing its banner. Switching to `-G "Visual Studio 17 2022"
-A x64` sidesteps it entirely — CMake locates the MSVC toolchain itself, no shell priming.
`build_windows_host.ps1` uses the VS generator for that reason.

## Commands

```
# 1. stage the Windows ONNX Runtime (once per checkout)
python packages/instaham_ml_ffi/scripts/stage_windows_ort.py

# 2. configure + build  ->  build/windows-host/Release/instaham_ml.dll
powershell -File packages/instaham_ml_ffi/scripts/build_windows_host.ps1

# 3. exit check
cd packages/instaham_ml_ffi
dart run scripts/check_windows_host.dart
```

Equivalent bare CMake for step 2:

```
cmake -G "Visual Studio 17 2022" -A x64 \
  -S packages/instaham_ml_ffi/src -B build/windows-host \
  -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake \
  -DINSTAHAM_ML_WITH_ORT=ON -DINSTAHAM_ML_WITH_OPENCV=ON
cmake --build build/windows-host --config Release
```

## Verification

Build: all 39 translation units compiled, link clean.

```
instaham_ml.vcxproj -> build\windows-host\Release\instaham_ml.dll   (675 KB)
```

Staged beside it by the POST_BUILD step: `onnxruntime.dll` (18 MB), `opencv_core4.dll`,
`opencv_imgproc4.dll`, `z.dll`.

Exit check (`dart run scripts/check_windows_host.dart`):

```
preloaded z.dll
preloaded onnxruntime.dll
preloaded opencv_core4.dll
preloaded opencv_imgproc4.dll
opening ...\build\windows-host\Release\instaham_ml.dll
abi_version = 1
build_info  = instaham_ml revision7 android ort=1.17.1 opencv-mobile=4.13.0
create(manifest) -> status 0
  capability_available("view") = 1
  capability_available("health") = 1
  capability_available("segmentation") = 1
  capability_available("weight") = 1

phase 1 OK: instaham_ml.dll loads and its C ABI answers.
```

`instaham_ml_create` loads the real `assets/ml/manifest.json` and reports all four
capabilities available (weight included — the shipped manifest carries the
`--enable-for-testing` weight capability). `build_info` is a compile-time string baked for
the Android build; it is not a runtime version probe, so its `ort=1.17.1` does not contradict
the 1.29.0 runtime DLL.

## Findings that carry into phase 2

1. **`DynamicLibrary.open` of an absolute path does not put that directory on the search
   path for the library's own imports.** `instaham_ml.dll`'s dependents
   (`onnxruntime.dll`, `opencv_core4.dll`, `opencv_imgproc4.dll`) must be made resolvable
   another way.

2. **The stray `C:\Windows\System32\onnxruntime.dll` is real and reproduced here.** With the
   correct 1.29.0 `onnxruntime.dll` sitting next to `instaham_ml.dll`, a bare-name load
   still picked up the System32 copy first (Windows searches System32 before the CWD), which
   supports only ORT API versions 1–10 and crashed inside `OrtGetApiBase`'s version dispatch
   with:

   ```
   The given version [17] is not supported, only version 1 to 10 is supported in this build.
   ```

   Fix, and the pattern the phase 2 native harness must follow: **preload the dependent DLLs
   by absolute path, ORT before the rest, before opening `instaham_ml.dll`.** The exit-check
   script does exactly this and then loads cleanly.

3. Phase 2's `test/support/native_harness.dart` should locate
   `build/windows-host/Release/`, preload `onnxruntime.dll` / OpenCV / `z.dll` by absolute
   path, then open `instaham_ml.dll` by absolute path, and gate on `INSTAHAM_NATIVE_TESTS=1`
   plus "does that directory exist" — reporting a precise skip otherwise.

## Not done here (deferred to later phases / out of scope)

- No CI wiring — the build is local-only.
- iOS host build — still unimplemented, still `FATAL_ERROR`.
- The `flutter test` skip count is unchanged; phases 2/4/5 consume this.
