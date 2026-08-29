// Loads the instaham_ml native library, stages the bundled ONNX manifest onto disk with
// sha256 verification, and owns the one InstahamMlContext for the process. Section 3/7 of
// ML_implementation_plan.md: this is the "single entry point" the capability services call
// through — nothing else in lib/ touches dart:ffi or the manifest layout directly.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:instaham_ml_ffi/instaham_ml_ffi.dart';
import 'package:path_provider/path_provider.dart';

export 'package:instaham_ml_ffi/instaham_ml_ffi.dart' show MlStatus;

/// Every file the bundled manifest can reference, relative to `assets/ml/`. Kept as an
/// explicit list (rather than parsing the manifest twice) so staging happens in one pass
/// before the native context is ever created.
// preprocessing.json is not listed: it is an export-time intermediate artifact only --
// the manifest's own "preprocessing" block (which native code actually reads, see
// manifest.cpp's load_classifier()) is inlined into manifest.json by build_manifest.py.
const List<String> _bundledMlAssets = [
  'manifest.json',
  'view/model.onnx',
  'view/classes.json',
  'health/model.onnx',
  'health/classes.json',
  'segmentation/yolo.onnx',
];

class MlRuntime {
  MlRuntime._(this._bindings, this._ctx);

  final InstahamMlBindings _bindings;
  final Pointer<InstahamMlContext> _ctx;

  static MlRuntime? _instance;
  static Future<MlRuntime>? _loading;

  /// Lazily stages assets and creates the native context. Safe to call repeatedly —
  /// concurrent callers share the same in-flight future. A failed load clears [_loading]
  /// so a later call retries instead of replaying the cached failure for the whole app run
  /// (staging can fail for transient reasons, e.g. no space while copying ~80 MB).
  static Future<MlRuntime> instance() {
    if (_instance != null) return Future.value(_instance);
    return _loading ??= _load()
        .then((rt) {
          _instance = rt;
          return rt;
        })
        .onError<Object>((error, stack) {
          _loading = null;
          Error.throwWithStackTrace(error, stack);
        });
  }

  static Future<MlRuntime> _load() async {
    final bindings = InstahamMlBindings(openInstahamMl());
    final manifestPath = await _stageAssets();
    final ctx = bindings.create(manifestPath);
    return MlRuntime._(bindings, ctx);
  }

  /// Copies every file in [_bundledMlAssets] from the Flutter asset bundle into the app's
  /// documents directory (native code needs real filesystem paths, not asset-bundle
  /// handles), skipping a file already on disk with a matching sha256 so a warm start does
  /// not re-copy ~80 MB of models every launch. Returns the staged manifest.json path.
  static Future<String> _stageAssets() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final mlDir = Directory('${docsDir.path}/ml');
    await mlDir.create(recursive: true);

    for (final rel in _bundledMlAssets) {
      final bytes = await _tryLoadAsset('assets/ml/$rel');
      if (bytes == null) {
        continue; // capability not bundled this build (e.g. weight)
      }
      final dest = File('${mlDir.path}/$rel');
      await dest.parent.create(recursive: true);
      if (await dest.exists()) {
        final existing = await dest.readAsBytes();
        if (sha256.convert(existing).toString() ==
            sha256.convert(bytes).toString()) {
          continue;
        }
      }
      await dest.writeAsBytes(bytes, flush: true);
    }
    return '${mlDir.path}/manifest.json';
  }

  static Future<List<int>?> _tryLoadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  bool capabilityAvailable(String capability) =>
      _bindings.capabilityAvailable(_ctx, capability);

  /// Runs one `*_json` entrypoint and decodes the result. Returns `(status, decodedJson)` —
  /// callers branch on `status` per instaham_ml.h's InstahamMlStatus, never on JSON shape.
  (MlStatus, Map<String, dynamic>) _invoke(
    (MlStatus, String) Function(Pointer<InstahamMlContext>, String) fn,
    String imagePath,
  ) {
    final (status, json) = fn(_ctx, imagePath);
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    return (status, decoded);
  }

  (MlStatus, Map<String, dynamic>) classifyView(String imagePath) =>
      _invoke(_bindings.classifyView, imagePath);

  (MlStatus, Map<String, dynamic>) classifyHealth(String imagePath) =>
      _invoke(_bindings.classifyHealth, imagePath);

  (MlStatus, Map<String, dynamic>) segment(String imagePath) =>
      _invoke(_bindings.segment, imagePath);
}
