<#
docs/metrics-plan.md phase 1 -- configure + build the Windows host instaham_ml.dll.

Produces build/windows-host/Release/instaham_ml.dll with onnxruntime.dll and the vcpkg
OpenCV DLLs staged next to it (POST_BUILD step in src/CMakeLists.txt), so `flutter test` and
the phase 2 native harness can DynamicLibrary.open it. This is NOT part of the flutter build
-- the FFI package has no windows/ plugin; the host DLL is a test-only artifact built
directly through CMake.

Uses the "Visual Studio 17 2022" generator so no vcvars64.bat shell is needed -- CMake
locates the MSVC toolchain itself. (An earlier Ninja + vcvars approach hung on this machine
because vcvars64.bat cannot find vswhere.exe here.)

Prereqs: MSVC 2022 BuildTools, CMake >= 3.21, vcpkg with `opencv4` installed, and a staged
Windows ONNX Runtime -- run scripts/stage_windows_ort.py first.
#>
param(
  [string]$Vcpkg  = "C:\vcpkg\scripts\buildsystems\vcpkg.cmake",
  [string]$CMake  = "C:\Android_Studio_Loc\cmake\3.22.1\bin\cmake.exe",
  [string]$Config = "Release"
)
$ErrorActionPreference = "Stop"

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir   = (Resolve-Path (Join-Path $here "..\src")).Path
$repoRoot = (Resolve-Path (Join-Path $here "..\..\..")).Path
$buildDir = Join-Path $repoRoot "build\windows-host"

if (-not (Test-Path $CMake)) { throw "cmake not found: $CMake" }
$staged = Join-Path $srcDir "third_party\onnxruntime\lib\windows\onnxruntime.lib"
if (-not (Test-Path $staged)) {
  throw "ONNX Runtime not staged. Run: python $here\stage_windows_ort.py"
}

& $CMake -G "Visual Studio 17 2022" -A x64 -S $srcDir -B $buildDir `
  -DCMAKE_TOOLCHAIN_FILE=$Vcpkg -DINSTAHAM_ML_WITH_ORT=ON -DINSTAHAM_ML_WITH_OPENCV=ON
if ($LASTEXITCODE -ne 0) { throw "configure failed ($LASTEXITCODE)" }

& $CMake --build $buildDir --config $Config
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

$dll = Join-Path $buildDir "$Config\instaham_ml.dll"
if (-not (Test-Path $dll)) { throw "expected $dll, not produced" }
Write-Host "`nOK -> $dll"
Get-ChildItem (Split-Path $dll) -Filter *.dll | Select-Object Name,Length | Format-Table -AutoSize
