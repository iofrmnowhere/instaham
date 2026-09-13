// docs/metrics-plan.md phase 2 -- native test harness seam.
//
// Tests must not go through MlRuntime: MlRuntime stages assets via `rootBundle` and
// resolves a directory via `path_provider`, neither of which works unmodified in a host
// `flutter test` process, and forcing them to would mean adding test-only branches to
// production loading code. Instead this harness creates the native InstahamMlContext
// directly from the repo's own assets/ml/manifest.json on disk, using the generated
// bindings, and exposes the same (MlStatus, Map<String, dynamic>) envelope shape
// IPipelineService.run returns (lib/services/ml/pipeline_service.dart). Nothing in lib/
// changes.
//
// Native-backed tests are gated on INSTAHAM_NATIVE_TESTS=1 *and* a loadable DLL; when
// either is absent, load() returns a NativeHarnessSkip with a precise reason instead of
// throwing, so a machine without the C++ toolchain stays green while the gate stays
// explicit (docs/metrics-plan.md phase 2 -- "the one place in this plan where a remaining
// skip is acceptable").
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:instaham_ml_ffi/instaham_ml_ffi.dart';

/// Outcome of [NativeHarness.load]: either a ready harness or a precise skip reason.
sealed class NativeHarnessLoad {
  const NativeHarnessLoad();
}

class NativeHarnessReady extends NativeHarnessLoad {
  const NativeHarnessReady(this.harness);
  final NativeHarness harness;
}

class NativeHarnessSkip extends NativeHarnessLoad {
  const NativeHarnessSkip(this.reason);
  final String reason;
}

/// Dependent DLLs that must be preloaded by absolute path, in dependency order, before
/// instaham_ml.dll: `DynamicLibrary.open()` of an absolute path does not add that
/// directory to the search path for the library's own imports, and a stray
/// C:\Windows\System32\onnxruntime.dll (an old ORT API version installed by some
/// unrelated app) crashes inside OrtGetApiBase's version dispatch for our API 17 headers
/// if it wins the search order instead. See ML/host_scale_test/README.md, "a stray
/// system-wide onnxruntime.dll", and packages/instaham_ml_ffi/scripts/
/// check_windows_host.dart, which this preload order mirrors.
const List<String> _windowsDependents = [
  'z.dll',
  'onnxruntime.dll',
  'opencv_core4.dll',
  'opencv_imgproc4.dll',
];

/// Candidate locations for the host-built instaham_ml.dll, relative to the repo root,
/// checked in order. build_windows_host.ps1 (docs/metrics-plan.md phase 1) configures the
/// Release one; a single-config generator would land at the second.
List<String> _dllCandidates(String repoRoot) => [
  '$repoRoot/build/windows-host/Release/instaham_ml.dll',
  '$repoRoot/build/windows-host/instaham_ml.dll',
];

/// Creates the native InstahamMlContext straight from assets/ml/manifest.json on disk and
/// exposes the same envelope shape as IPipelineService.run, so Tier B scenario tests
/// (docs/metrics-plan.md phase 4) can replay a fixture through the real pipeline without
/// going through MlRuntime/rootBundle/path_provider.
class NativeHarness {
  NativeHarness._(
    this._bindings,
    this._ctx,
    this.manifestPath,
    this.featureFamily,
  );

  final InstahamMlBindings _bindings;
  final Pointer<InstahamMlContext> _ctx;

  /// The on-disk manifest path the context was created from -- assets/ml/manifest.json at
  /// the repo root, never a staged copy.
  final String manifestPath;

  /// `capabilities.weight.feature_family` read directly from the manifest JSON on disk
  /// (AGENTS.md rule 2: the feature list and its order must come from the manifest, never
  /// be hardcoded). Read here rather than through a native ABI call, since no capability
  /// call exposes it.
  final String? featureFamily;

  /// Attempts to build a harness. Returns [NativeHarnessSkip] with a precise reason
  /// instead of throwing when INSTAHAM_NATIVE_TESTS=1 is unset, no built DLL can be found,
  /// or the dependent-DLL preload / instaham_ml_create call fails.
  static NativeHarnessLoad load() {
    if (Platform.environment['INSTAHAM_NATIVE_TESTS'] != '1') {
      return const NativeHarnessSkip(
        'INSTAHAM_NATIVE_TESTS not set to 1 -- native harness opt-in gate is off',
      );
    }
    if (!Platform.isWindows) {
      return NativeHarnessSkip(
        'native harness only wired for Windows host builds '
        '(docs/metrics-plan.md phase 1); got ${Platform.operatingSystem}',
      );
    }

    // flutter test runs with the repo root as the working directory.
    final repoRoot = Directory.current.path;
    final candidates = _dllCandidates(repoRoot);
    final dllPath = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '',
    );
    if (dllPath.isEmpty) {
      return NativeHarnessSkip(
        'instaham_ml.dll not found in any of:\n  ${candidates.join('\n  ')}\n'
        'run packages/instaham_ml_ffi/scripts/build_windows_host.ps1 first',
      );
    }
    final dir = File(dllPath).parent.path;

    try {
      for (final dep in _windowsDependents) {
        final p = '$dir/$dep';
        if (File(p).existsSync()) {
          DynamicLibrary.open(p);
        }
      }
      final bindings = InstahamMlBindings(DynamicLibrary.open(dllPath));

      final manifestPath = '$repoRoot/assets/ml/manifest.json';
      if (!File(manifestPath).existsSync()) {
        return NativeHarnessSkip('manifest not found at $manifestPath');
      }
      final ctx = bindings.create(manifestPath);
      final featureFamily = _readFeatureFamily(manifestPath);
      return NativeHarnessReady(
        NativeHarness._(bindings, ctx, manifestPath, featureFamily),
      );
    } catch (e) {
      return NativeHarnessSkip('native harness failed to load: $e');
    }
  }

  static String? _readFeatureFamily(String manifestPath) {
    try {
      final decoded =
          jsonDecode(File(manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      final capabilities = decoded['capabilities'] as Map<String, dynamic>?;
      final weight = capabilities?['weight'] as Map<String, dynamic>?;
      return weight?['feature_family'] as String?;
    } catch (_) {
      return null;
    }
  }

  bool capabilityAvailable(String capability) =>
      _bindings.capabilityAvailable(_ctx, capability);

  /// Same envelope shape as IPipelineService.run: the raw decoded section-9 envelope
  /// alongside the call's native status. Callers must branch on the envelope's own
  /// per-stage status fields, not just this one (AGENTS.md rule 4: weight and health
  /// branches are independent).
  (MlStatus, Map<String, dynamic>) run(String imagePath, {double? cmPerPixel}) {
    final (status, json) = cmPerPixel == null
        ? _bindings.runPipeline(_ctx, imagePath)
        : _bindings.runPipelineRequest(
            _ctx,
            jsonEncode({'image_path': imagePath, 'cm_per_px': cmPerPixel}),
          );
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    return (status, decoded);
  }

  void dispose() => _bindings.destroy(_ctx);
}
