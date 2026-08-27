// GENERATED-EQUIVALENT — hand-authored placeholder for the ffigen output.
//
// Replace this file by running:  dart run ffigen --config ffigen.yaml
// (kept hand-written for slice 0 so the Dart side compiles without a local libclang).
//
// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names

import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Mirrors `InstahamMlStatus` in instaham_ml.h.
enum MlStatus {
  ok(0),
  errManifest(1),
  errHashMismatch(2),
  errModelLoad(3),
  errIo(4),
  errInference(5),
  errUnavailable(6),
  errContract(7),
  errInvalidArg(8);

  final int value;
  const MlStatus(this.value);

  static MlStatus fromValue(int v) => MlStatus.values.firstWhere(
    (s) => s.value == v,
    orElse: () => MlStatus.errInference,
  );
}

final class InstahamMlContext extends Opaque {}

typedef _CreateNative =
    Int32 Function(Pointer<Utf8>, Pointer<Pointer<InstahamMlContext>>);
typedef _CreateDart =
    int Function(Pointer<Utf8>, Pointer<Pointer<InstahamMlContext>>);
typedef _DestroyNative = Void Function(Pointer<InstahamMlContext>);
typedef _DestroyDart = void Function(Pointer<InstahamMlContext>);
typedef _AbiNative = Int32 Function();
typedef _InfoNative = Pointer<Utf8> Function();
typedef _CapNative = Int32 Function(Pointer<InstahamMlContext>, Pointer<Utf8>);
typedef _CapDart = int Function(Pointer<InstahamMlContext>, Pointer<Utf8>);
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);
typedef _InferNative =
    Int32 Function(
      Pointer<InstahamMlContext>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
    );
typedef _InferDart =
    int Function(
      Pointer<InstahamMlContext>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
    );

/// Thin typed wrapper over the instaham_ml C ABI. One instance per loaded [DynamicLibrary].
class InstahamMlBindings {
  final DynamicLibrary _lib;

  InstahamMlBindings(this._lib)
    : _create = _lib.lookupFunction<_CreateNative, _CreateDart>(
        'instaham_ml_create',
      ),
      _destroy = _lib.lookupFunction<_DestroyNative, _DestroyDart>(
        'instaham_ml_destroy',
      ),
      _abi = _lib.lookupFunction<_AbiNative, int Function()>(
        'instaham_ml_abi_version',
      ),
      _info = _lib.lookupFunction<_InfoNative, Pointer<Utf8> Function()>(
        'instaham_ml_build_info',
      ),
      _lastError = _lib.lookupFunction<_InfoNative, Pointer<Utf8> Function()>(
        'instaham_ml_last_error',
      ),
      _cap = _lib.lookupFunction<_CapNative, _CapDart>(
        'instaham_ml_capability_available',
      ),
      _stringFree = _lib.lookupFunction<_StringFreeNative, _StringFreeDart>(
        'instaham_ml_string_free',
      ),
      _view = _lib.lookupFunction<_InferNative, _InferDart>(
        'instaham_ml_classify_view_json',
      ),
      _health = _lib.lookupFunction<_InferNative, _InferDart>(
        'instaham_ml_classify_health_json',
      ),
      _weight = _lib.lookupFunction<_InferNative, _InferDart>(
        'instaham_ml_predict_weight_json',
      ),
      _featuresProvisional = _lib.lookupFunction<_InferNative, _InferDart>(
        'instaham_ml_extract_features_provisional_json',
      );

  final _CreateDart _create;
  final _DestroyDart _destroy;
  final int Function() _abi;
  final Pointer<Utf8> Function() _info;
  final Pointer<Utf8> Function() _lastError;
  final _CapDart _cap;
  final _StringFreeDart _stringFree;
  final _InferDart _view;
  final _InferDart _health;
  final _InferDart _weight;
  final _InferDart _featuresProvisional;

  int get abiVersion => _abi();
  String get buildInfo => _info().toDartString();
  String get lastError => _lastError().toDartString();

  Pointer<InstahamMlContext> create(String manifestPath) {
    final pathPtr = manifestPath.toNativeUtf8();
    final outPtr = calloc<Pointer<InstahamMlContext>>();
    try {
      final status = MlStatus.fromValue(_create(pathPtr, outPtr));
      if (status != MlStatus.ok) {
        throw StateError('instaham_ml_create -> $status: $lastError');
      }
      return outPtr.value;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outPtr);
    }
  }

  void destroy(Pointer<InstahamMlContext> ctx) => _destroy(ctx);

  bool capabilityAvailable(Pointer<InstahamMlContext> ctx, String capability) {
    final capPtr = capability.toNativeUtf8();
    try {
      return _cap(ctx, capPtr) == 1;
    } finally {
      calloc.free(capPtr);
    }
  }

  /// Invokes one `*_json` entrypoint and returns `(status, jsonString)`.
  (MlStatus, String) _invoke(
    _InferDart fn,
    Pointer<InstahamMlContext> ctx,
    String imagePath,
  ) {
    final imgPtr = imagePath.toNativeUtf8();
    final outJson = calloc<Pointer<Utf8>>();
    try {
      final status = MlStatus.fromValue(fn(ctx, imgPtr, outJson));
      final json = outJson.value == nullptr
          ? '{}'
          : outJson.value.toDartString();
      if (outJson.value != nullptr) _stringFree(outJson.value);
      return (status, json);
    } finally {
      calloc.free(imgPtr);
      calloc.free(outJson);
    }
  }

  (MlStatus, String) classifyView(
    Pointer<InstahamMlContext> ctx,
    String imagePath,
  ) => _invoke(_view, ctx, imagePath);
  (MlStatus, String) classifyHealth(
    Pointer<InstahamMlContext> ctx,
    String imagePath,
  ) => _invoke(_health, ctx, imagePath);
  (MlStatus, String) predictWeight(
    Pointer<InstahamMlContext> ctx,
    String imagePath,
  ) => _invoke(_weight, ctx, imagePath);
  (MlStatus, String) extractFeaturesProvisional(
    Pointer<InstahamMlContext> ctx,
    String imagePath,
  ) => _invoke(_featuresProvisional, ctx, imagePath);
}
