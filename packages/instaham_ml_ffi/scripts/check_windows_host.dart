// docs/metrics-plan.md phase 1 exit check -- run AFTER build_windows_host.ps1.
//
// Opens the freshly built build/windows-host/Release/instaham_ml.dll by absolute path (so
// the dependent onnxruntime.dll / OpenCV DLLs staged beside it resolve, and a stray
// C:\Windows\System32\onnxruntime.dll never wins) and exercises the C ABI:
//   - instaham_ml_abi_version()  must equal 1
//   - instaham_ml_build_info()   must be non-empty
//   - instaham_ml_create() on the real assets/ml/manifest.json, then
//     instaham_ml_capability_available() for each capability
//
// Run from the FFI package dir so package:ffi resolves:
//   cd packages/instaham_ml_ffi
//   dart run scripts/check_windows_host.dart
// Exits 0 on success, non-zero with a diagnostic otherwise.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _Int0C = Int32 Function();
typedef _Int0 = int Function();
typedef _StrRetC = Pointer<Utf8> Function();
typedef _CreateC = Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _Create = int Function(Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _CapC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _Cap = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _Destroy = void Function(Pointer<Void>);

void main() {
  // Directory.current is the FFI package dir; the repo root is two levels up.
  final repoRoot = Directory.current.parent.parent.path;
  final candidates = [
    '$repoRoot/build/windows-host/Release/instaham_ml.dll',
    '$repoRoot/build/windows-host/instaham_ml.dll',
  ];
  final found = candidates.where((p) => File(p).existsSync()).toList();
  if (found.isEmpty) {
    stderr.writeln('not found in any of:\n  ${candidates.join("\n  ")}');
    stderr.writeln('run scripts/build_windows_host.ps1 first');
    exit(1);
  }
  final dllFile = File(found.first);
  final dir = dllFile.parent.path;

  // Preload the dependent DLLs by ABSOLUTE path, in dependency order, BEFORE instaham_ml.dll.
  // Two reasons:
  //  1. DynamicLibrary.open() of an absolute path does not add that directory to the search
  //     path for the library's own imports.
  //  2. C:\Windows\System32\onnxruntime.dll may exist (installed by some unrelated app) and
  //     Windows searches System32 before the CWD -- an old copy there only supports ORT API
  //     versions 1-10 and crashes inside OrtGetApiBase's version dispatch for our API 17
  //     headers. Loading our onnxruntime.dll first pins the right module in the process.
  //     (ML/host_scale_test/README.md, "a stray system-wide onnxruntime.dll".)
  for (final dep in [
    'z.dll',
    'onnxruntime.dll',
    'opencv_core4.dll',
    'opencv_imgproc4.dll'
  ]) {
    final p = '$dir/$dep';
    if (File(p).existsSync()) {
      DynamicLibrary.open(p);
      stdout.writeln('preloaded $dep');
    }
  }

  stdout.writeln('opening ${dllFile.path}');
  final lib = DynamicLibrary.open(dllFile.path);

  final abiVersion = lib.lookupFunction<_Int0C, _Int0>(
    'instaham_ml_abi_version',
  );
  final buildInfo = lib.lookupFunction<_StrRetC, _StrRetC>(
    'instaham_ml_build_info',
  );
  final create = lib.lookupFunction<_CreateC, _Create>('instaham_ml_create');
  final capAvail = lib.lookupFunction<_CapC, _Cap>(
    'instaham_ml_capability_available',
  );
  final destroy = lib.lookupFunction<_DestroyC, _Destroy>(
    'instaham_ml_destroy',
  );

  final abi = abiVersion();
  final info = buildInfo().toDartString();
  stdout.writeln('abi_version = $abi');
  stdout.writeln('build_info  = $info');
  if (abi != 1) {
    stderr.writeln('FAIL: expected abi_version 1');
    exit(2);
  }
  if (info.isEmpty) {
    stderr.writeln('FAIL: empty build_info');
    exit(2);
  }

  final manifest = '$repoRoot/assets/ml/manifest.json';
  final mPtr = manifest.toNativeUtf8();
  final outCtx = calloc<Pointer<Void>>();
  final st = create(mPtr, outCtx);
  stdout.writeln('create(manifest) -> status $st');
  if (st != 0 || outCtx.value == nullptr) {
    stderr.writeln('FAIL: instaham_ml_create returned $st');
    exit(3);
  }
  for (final cap in ['view', 'health', 'segmentation', 'weight']) {
    final cPtr = cap.toNativeUtf8();
    stdout.writeln(
      '  capability_available("$cap") = ${capAvail(outCtx.value, cPtr)}',
    );
    calloc.free(cPtr);
  }
  destroy(outCtx.value);
  calloc.free(mPtr);
  calloc.free(outCtx);

  stdout.writeln('\nphase 1 OK: instaham_ml.dll loads and its C ABI answers.');
}
