import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Metrics 1-3 (cold start, inference latency, startup memory) moved to
// integration_test/benchmark_test.dart — run on Firebase Test Lab per
// docs/device-testing-plan.md. This file keeps the two device metrics that
// need no physical device: file-size and export-accuracy assertions.
//
// Metric 5 (battery/thermal over 50 consecutive scans) was dropped by
// decision on 2026-09-13 — not moved, not deferred. See
// docs/metrics-phase/6-device-metrics.md, "Metric 5 is dropped", for the
// decision and the §14 deviation it records.

const int _maxBytesPerModel = 50 * 1024 * 1024; // 50 MB

/// Every `.onnx` model path declared in the manifest, found generically by walking the
/// JSON tree for any `path` field ending in `.onnx` — so a model added to the bundle is
/// covered automatically, without this test hardcoding the four current paths.
List<String> _onnxPathsFromManifest(dynamic node) {
  final found = <String>[];
  void walk(dynamic value) {
    if (value is Map) {
      final path = value['path'];
      if (path is String && path.endsWith('.onnx')) {
        found.add(path);
      }
      for (final v in value.values) {
        walk(v);
      }
    } else if (value is List) {
      for (final v in value) {
        walk(v);
      }
    }
  }

  walk(node);
  return found;
}

/// Every `{path, sha256}` pair declared in the manifest — any node carrying a `.onnx` `path`
/// alongside a sibling `sha256`. Covers `capabilities.<name>.model` for the health,
/// segmentation and view models, and `capabilities.weight.regressor`, which names its model
/// field `regressor` rather than `model` — found generically rather than by hardcoding both
/// shapes.
List<({String path, String sha256})> _onnxShaPairsFromManifest(dynamic node) {
  final found = <({String path, String sha256})>[];
  void walk(dynamic value) {
    if (value is Map) {
      final path = value['path'];
      final sha256 = value['sha256'];
      if (path is String && path.endsWith('.onnx') && sha256 is String) {
        found.add((path: path, sha256: sha256));
      }
      for (final v in value.values) {
        walk(v);
      }
    } else if (value is List) {
      for (final v in value) {
        walk(v);
      }
    }
  }

  walk(node);
  return found;
}

/// Every capability's declared `protocol_version`, found anywhere within that capability's
/// subtree rather than only at its top level. There is no single top-level
/// `protocol_version` field in this manifest, and the field's depth is not consistent
/// between capabilities: `health`, `segmentation` and `view` each carry it directly under
/// `capabilities.<name>`, but `weight` carries it one level deeper, under
/// `capabilities.weight.feature_extractor.protocol_version`. A shallow lookup misreads that
/// as a missing field when it is only differently nested — this walks each subtree the same
/// way `_onnxPathsFromManifest` walks the whole manifest, so a real absence and a deeper
/// nesting are not confused.
Map<String, dynamic> _protocolVersionsByCapability(
  Map<String, dynamic> manifest,
) {
  final capabilities = manifest['capabilities'] as Map<String, dynamic>? ?? {};
  dynamic findProtocolVersion(dynamic node) {
    if (node is Map) {
      if (node.containsKey('protocol_version')) {
        return node['protocol_version'];
      }
      for (final v in node.values) {
        final found = findProtocolVersion(v);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = findProtocolVersion(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  return {
    for (final entry in capabilities.entries)
      entry.key: findProtocolVersion(entry.value),
  };
}

void main() {
  group('Model package and export assertions (§14 & §Device testing)', () {
    test('Device metric 4: Mobile model package file sizes (< 50MB target)', () async {
      // Plain `flutter test` — pure file stat, no `AssetBundle`, no `tester.runAsync`.
      //
      // The 50 MB figure is a product decision recorded in
      // docs/metrics-phase/6-device-metrics.md ("Agreed targets"), dated 2026-09-12 —
      // INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md §14 states no size target at all, for
      // any metric. The check is deliberately per-model: the assets/ml bundle totals
      // ~68 MB across four models and that bundle total is not asserted here.
      final repoRoot = Directory.current.path;
      final manifestFile = File('$repoRoot/assets/ml/manifest.json');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'assets/ml/manifest.json must exist to derive the model list',
      );

      final manifest = jsonDecode(manifestFile.readAsStringSync());
      final relativePaths = _onnxPathsFromManifest(manifest);
      expect(
        relativePaths,
        isNotEmpty,
        reason:
            'manifest.json declared no *.onnx model paths — nothing to check',
      );

      final failures = <String>[];
      for (final relativePath in relativePaths) {
        final modelFile = File('$repoRoot/assets/ml/$relativePath');
        if (!modelFile.existsSync()) {
          failures.add('$relativePath — file not found on disk');
          continue;
        }
        final bytes = modelFile.lengthSync();
        final mb = bytes / (1024 * 1024);
        // Print every size so a failure names the offender.
        // ignore: avoid_print
        print(
          'MODEL_SIZE: $relativePath = ${mb.toStringAsFixed(2)} MB ($bytes bytes)',
        );
        if (bytes >= _maxBytesPerModel) {
          failures.add(
            '$relativePath — ${mb.toStringAsFixed(2)} MB exceeds the 50 MB per-model target',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('; '));
    });

    test('Device metric 6: Quantization and model export parity validation', () async {
      // §14 device bullet 6: "accuracy after model export or quantization". The manifest
      // already records each model's export self-check delta — this asserts the
      // *recorded* value is present and within a stated tolerance. It does **not**
      // re-run the export or independently re-verify it: a green result here means no
      // model was swapped into the bundle without its self-check re-run, and no
      // recorded delta has grown past its bound. It must not be read as "export
      // verified today".
      //
      // Four of the five deltas are float32 round-trip noise, all ~1e-6, and share one
      // bound. `box_mask_max_abs_diff` is three orders of magnitude larger (~1.4e-3) and
      // needs its own, wider bound — folding it into the tight bound would either make
      // that check meaningless or make this one flake on ordinary noise.
      const noiseTolerance = 1e-4; // covers the four ~1e-6 round-trip deltas
      const boxMaskTolerance =
          5e-3; // covers box_mask_max_abs_diff, ~1.4e-3 observed

      final repoRoot = Directory.current.path;
      final manifestFile = File('$repoRoot/assets/ml/manifest.json');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'assets/ml/manifest.json must exist to read export self-checks',
      );

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final capabilities = manifest['capabilities'] as Map<String, dynamic>;

      double? readDelta(List<String> path) {
        dynamic node = capabilities;
        for (final key in path) {
          if (node is! Map<String, dynamic> || !node.containsKey(key)) {
            return null;
          }
          node = node[key];
        }
        return (node as num?)?.toDouble();
      }

      final checks = <String, ({double? value, double tolerance})>{
        'view.model.onnx_max_abs_diff': (
          value: readDelta(['view', 'model', 'onnx_max_abs_diff']),
          tolerance: noiseTolerance,
        ),
        'health.model.onnx_max_abs_diff': (
          value: readDelta(['health', 'model', 'onnx_max_abs_diff']),
          tolerance: noiseTolerance,
        ),
        'health.model.fusion_max_abs_diff': (
          value: readDelta(['health', 'model', 'fusion_max_abs_diff']),
          tolerance: noiseTolerance,
        ),
        'segmentation.model.onnx_self_check.proto_max_abs_diff': (
          value: readDelta([
            'segmentation',
            'model',
            'onnx_self_check',
            'proto_max_abs_diff',
          ]),
          tolerance: noiseTolerance,
        ),
        'segmentation.model.onnx_self_check.box_mask_max_abs_diff': (
          value: readDelta([
            'segmentation',
            'model',
            'onnx_self_check',
            'box_mask_max_abs_diff',
          ]),
          tolerance: boxMaskTolerance,
        ),
      };

      final failures = <String>[];
      for (final entry in checks.entries) {
        final field = entry.key;
        final value = entry.value.value;
        final tolerance = entry.value.tolerance;
        if (value == null) {
          failures.add('$field — missing from manifest.json');
          continue;
        }
        // Print every delta so a failure names the offender.
        // ignore: avoid_print
        print(
          'EXPORT_DELTA: $field = $value (tolerance ${tolerance.toStringAsExponential(1)})',
        );
        if (value.abs() >= tolerance) {
          failures.add(
            '$field — $value exceeds tolerance ${tolerance.toStringAsExponential(1)}',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('; '));
    });

    test('Device metric — §16 manifest traceability', () async {
      // §16 traceability: assert the manifest carries the fields that identify which build
      // it came from and which files it declares, and that per-model sha256 values actually
      // match the files on disk.
      //
      // This is a labelling check, not a threshold gate — INSTAHAM_APP_REQUIREMENTS_AFTER_
      // TRAINING.md §16 asks for traceability, not specific field values, so bundle_id,
      // reference_commit and schema_version are asserted present and non-empty rather than
      // pinned to today's exact strings; pinning them would make every routine re-export a
      // test failure unrelated to traceability. Per-model sha256 is the one field checked
      // against reality — it is recomputed from the file on disk, so it catches a model
      // swapped into the bundle without updating the manifest, which a presence-only check
      // would miss entirely.
      final repoRoot = Directory.current.path;
      final manifestFile = File('$repoRoot/assets/ml/manifest.json');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason:
            'assets/ml/manifest.json must exist to read traceability fields',
      );

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final failures = <String>[];

      for (final field in ['bundle_id', 'reference_commit', 'schema_version']) {
        final value = manifest[field];
        // ignore: avoid_print
        print('MANIFEST_FIELD: $field = $value');
        if (value == null || (value is String && value.isEmpty)) {
          failures.add('$field — missing or empty at the manifest top level');
        }
      }

      final protocolVersions = _protocolVersionsByCapability(manifest);
      if (protocolVersions.isEmpty) {
        failures.add('no capabilities found to read protocol_version from');
      }
      for (final entry in protocolVersions.entries) {
        // ignore: avoid_print
        print(
          'MANIFEST_FIELD: capabilities.${entry.key}.protocol_version = ${entry.value}',
        );
        if (entry.value == null ||
            (entry.value is String && (entry.value as String).isEmpty)) {
          failures.add(
            'capabilities.${entry.key}.protocol_version — missing or empty',
          );
        }
      }

      final shaPairs = _onnxShaPairsFromManifest(manifest);
      expect(
        shaPairs,
        isNotEmpty,
        reason:
            'manifest.json declared no {path, sha256} model pairs — nothing to verify',
      );
      for (final pair in shaPairs) {
        final modelFile = File('$repoRoot/assets/ml/${pair.path}');
        if (!modelFile.existsSync()) {
          failures.add(
            '${pair.path} — file not found on disk to verify sha256 against',
          );
          continue;
        }
        final actualSha256 = sha256
            .convert(modelFile.readAsBytesSync())
            .toString();
        // ignore: avoid_print
        print(
          'MANIFEST_FIELD: ${pair.path}.sha256 = ${pair.sha256} (actual: $actualSha256)',
        );
        if (actualSha256 != pair.sha256) {
          failures.add(
            '${pair.path} — manifest sha256 ${pair.sha256} does not match the file on '
            'disk ($actualSha256); the model was changed without updating the manifest',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('; '));
    });
  });
}
