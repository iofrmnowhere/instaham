import 'dart:ffi';
import 'dart:io';

export 'instaham_ml_bindings_generated.dart';

const String _libName = 'instaham_ml';

/// Opens `libinstaham_ml.so` / `instaham_ml.framework` for the current platform.
///
/// On Android the shared library is packaged by the FFI plugin; on iOS/macOS the symbols
/// are linked into the app process. Throws [UnsupportedError] on desktop where the native
/// library is not built.
DynamicLibrary openInstahamMl() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError(
    'instaham_ml_ffi: no native library for $operatingSystem',
  );
}

String get operatingSystem => Platform.operatingSystem;
