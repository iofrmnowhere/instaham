// Loads the instaham_ml native library, stages the bundled ONNX manifest onto disk with
// sha256 verification, and owns the one InstahamMlContext for the process. Section 3/7 of
// ML_implementation_plan.md: this is the "single entry point" the capability services call
// through — nothing else in lib/ touches dart:ffi or the manifest layout directly.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:instaham_ml_ffi/instaham_ml_ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/call_queue.dart';

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
  // Only present when the manifest's weight capability is available (test-only override,
  // ML/export/export_xgboost.py --enable-for-testing) -- _tryLoadAsset skips it otherwise.
  'weight/xgboost.onnx',
  'weight/feature_order.json',
];

/// plan-phase-2/1-isolate-offload.md: runs `bindings.classifyView` on a worker isolate so
/// the UI isolate keeps pumping frames while the native call blocks. `ctx` is a native
/// pointer -- sendable as-is between isolates in the same isolate group, since it only
/// wraps an address into memory the isolates already share (no Dart-heap object crosses
/// the boundary). The worker opens its own [InstahamMlBindings] rather than closing over
/// the caller's: a `DynamicLibrary` handle is not guaranteed sendable, and `dlopen` of an
/// already-loaded library is a cheap refcount bump, not a real re-load.
///
/// `instaham_ml_last_error` is `thread_local` (instaham_ml.cpp) -- it must be read here,
/// on the same thread that made the call, or it reads back empty on the UI isolate.
Future<(int, String, String)> _isolateClassifyView(
  Pointer<InstahamMlContext> ctx,
  String imagePath,
) {
  return Isolate.run(() {
    final bindings = InstahamMlBindings(openInstahamMl());
    final (status, json) = bindings.classifyView(ctx, imagePath);
    final lastError = status == MlStatus.ok ? '' : bindings.lastError;
    return (status.value, json, lastError);
  });
}

/// Same offload as [_isolateClassifyView], for the plain (no-extras) whole-graph call.
Future<(int, String, String)> _isolateRunPipeline(
  Pointer<InstahamMlContext> ctx,
  String imagePath,
) {
  return Isolate.run(() {
    final bindings = InstahamMlBindings(openInstahamMl());
    final (status, json) = bindings.runPipeline(ctx, imagePath);
    final lastError = status == MlStatus.ok ? '' : bindings.lastError;
    return (status.value, json, lastError);
  });
}

/// Same offload as [_isolateClassifyView], for the request-shaped whole-graph call
/// (`cmPerPixel` and/or `viewRouteOverride` set).
Future<(int, String, String)> _isolateRunPipelineRequest(
  Pointer<InstahamMlContext> ctx,
  String requestJson,
) {
  return Isolate.run(() {
    final bindings = InstahamMlBindings(openInstahamMl());
    final (status, json) = bindings.runPipelineRequest(ctx, requestJson);
    final lastError = status == MlStatus.ok ? '' : bindings.lastError;
    return (status.value, json, lastError);
  });
}

class MlRuntime {
  MlRuntime._(this._bindings, this._ctx);

  final InstahamMlBindings _bindings;
  final Pointer<InstahamMlContext> _ctx;
  final CallQueue _queue = CallQueue();

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
    return (status, _decode(json));
  }

  static Map<String, dynamic> _decode(String json) {
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// plan-phase-2/1-isolate-offload.md: offloaded to a worker isolate and serialized
  /// through [_queue] -- this is a user-facing wait (the capture review screen's "Verify
  /// reference" button) that must not block the UI isolate's frame pump.
  Future<(MlStatus, Map<String, dynamic>)> classifyView(String imagePath) {
    return _queue.run(() async {
      final (statusCode, json, lastError) = await _isolateClassifyView(
        _ctx,
        imagePath,
      );
      final status = MlStatus.fromValue(statusCode);
      if (status != MlStatus.ok && lastError.isNotEmpty) {
        debugPrint('classifyView failed: $lastError');
      }
      return (status, _decode(json));
    });
  }

  (MlStatus, Map<String, dynamic>) classifyHealth(String imagePath) =>
      _invoke(_bindings.classifyHealth, imagePath);

  (MlStatus, Map<String, dynamic>) segment(String imagePath) =>
      _invoke(_bindings.segment, imagePath);

  /// Test-only override path (ML/export/export_xgboost.py --enable-for-testing): returns
  /// `errUnavailable` unless the bundled manifest's weight capability is available, per
  /// ML_implementation_plan.md section 3.4. When it is, the native chain still ran a real
  /// (uncut-mask) prediction -- see instaham_ml.cpp's instaham_ml_predict_weight_json for
  /// the caveat this carries.
  (MlStatus, Map<String, dynamic>) predictWeight(String imagePath) =>
      _invoke(_bindings.predictWeight, imagePath);

  /// TASKS.md P0: the whole-graph call. One native pass instead of the up-to-three
  /// per-capability calls each re-segmenting -- see run_and_persist_pipeline_use_case.dart.
  ///
  /// TASKS.md W3: `cmPerPixel` is the user-confirmed reference object's measured cm/pixel
  /// for this capture (AGENTS.md rule 7 -- callers must pass it ONLY when the annotation
  /// was user-confirmed and coplanar-confirmed, never a guess). Omitted or null routes to
  /// the plain `instaham_ml_run_pipeline_json` entrypoint unchanged; passing it uses the
  /// request-shaped `instaham_ml_run_pipeline_request_json` (TASKS.md W4) instead, which
  /// degrades the weight branch to `{"status":"unavailable","reason":"scale_..."}` rather
  /// than predicting on unnormalized pixels when the value can't be applied.
  ///
  /// plan-phase-2/1-isolate-offload.md: this is the 12-71 second wait
  /// (docs/device-metrics-results.md) -- offloaded to a worker isolate and serialized
  /// through [_queue] so the UI isolate keeps pumping frames for the `/analysis` progress
  /// indicator for the whole run.
  Future<(MlStatus, Map<String, dynamic>)> runPipeline(
    String imagePath, {
    double? cmPerPixel,
    String? viewRouteOverride,
  }) {
    // docs/fix-phase-6/2-dialog-and-routing.md (F68, widens fix-phase-5/2's boolean): the
    // request-shaped entrypoint is needed whenever EITHER extra is present, not only
    // cmPerPixel -- an override with no confirmed reference (weight branch degrades to
    // unavailable, health still runs) must still reach the native override field.
    final useRequest = cmPerPixel != null || viewRouteOverride != null;
    final requestJson = useRequest
        ? jsonEncode({
            'image_path': imagePath,
            if (cmPerPixel != null) 'cm_per_px': cmPerPixel,
            if (viewRouteOverride != null)
              'view_route_override': viewRouteOverride,
          })
        : null;
    return _queue.run(() async {
      final (statusCode, json, lastError) = useRequest
          ? await _isolateRunPipelineRequest(_ctx, requestJson!)
          : await _isolateRunPipeline(_ctx, imagePath);
      final status = MlStatus.fromValue(statusCode);
      if (status != MlStatus.ok && lastError.isNotEmpty) {
        debugPrint('runPipeline failed: $lastError');
      }
      return (status, _decode(json));
    });
  }
}
