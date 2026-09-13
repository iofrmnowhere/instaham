// docs/metrics-plan.md phase 4 task 4: loads a `test/fixtures/scenarios/<NN>_<slug>/meta.json`
// fixture so `functional_scenarios_test.dart`'s nine two-tier bodies don't each duplicate
// JSON-path knowledge. Deliberately thin -- no envelope shaping or assertion logic lives
// here, only field access, so a fixture's own meta.json stays the single source of truth
// (task 2's restatement work) and this class cannot silently drift from it.
import 'dart:convert';
import 'dart:io';

class ScenarioFixture {
  final int id;
  final String dirPath;
  final Map<String, dynamic> meta;

  ScenarioFixture._(this.id, this.dirPath, this.meta);

  /// `id` is the scenario's §14 bullet number (1, 2, 3, 5, 6, 7, 8, 9, 11 -- 4 and 10 were
  /// removed, finding 9). Looks up the `<NN>_<slug>` directory by its zero-padded prefix
  /// rather than hardcoding slugs here, so a future rename of a fixture's slug needs no
  /// change in this file.
  static ScenarioFixture load(int id) {
    final root = Directory('test/fixtures/scenarios');
    final prefix = '${id.toString().padLeft(2, '0')}_';
    final dir = root.listSync().whereType<Directory>().firstWhere(
      (d) => _basename(d.path).startsWith(prefix),
      orElse: () =>
          throw StateError('no scenario fixture directory matching $prefix*'),
    );
    final meta =
        jsonDecode(File('${dir.path}/meta.json').readAsStringSync())
            as Map<String, dynamic>;
    return ScenarioFixture._(id, dir.path, meta);
  }

  String get title => meta['title'] as String;

  Map<String, dynamic> get expectedOutcome =>
      meta['expected_outcome'] as Map<String, dynamic>;

  /// The exact envelope task 1 recorded against the real Windows host build
  /// (`observed_phase4.envelope`) -- Tier A replays this, per the plan's own instruction
  /// ("drives RunAndPersistPipelineUseCase with a stubbed IPipelineService replaying a
  /// recorded envelope"), rather than a hand-built synthetic one.
  Map<String, dynamic> get observedEnvelope =>
      (meta['observed_phase4'] as Map<String, dynamic>)['envelope']
          as Map<String, dynamic>;

  /// null when this fixture's endpoints are not hand-marked yet (task 1's "Known gaps" /
  /// scenario 11's open item) -- callers must not invent a value when this is null.
  double? get cmPerPixel {
    final ref = meta['reference'] as Map<String, dynamic>?;
    final endpoints = ref?['pixel_endpoints'] as Map<String, dynamic>?;
    return (endpoints?['cm_per_px'] as num?)?.toDouble();
  }

  double? get referenceLengthCm {
    final ref = meta['reference'] as Map<String, dynamic>?;
    return (ref?['physical_length_cm'] as num?)?.toDouble();
  }

  /// Path to the image this scenario drives through the pipeline. `variant` selects among
  /// scenario 11's `image_files` map ('heic' | 'jpeg' | 'png'); every other scenario has a
  /// single `image_file` and this parameter is unused for them.
  String imagePath([String? variant]) {
    if (variant != null) {
      final files = meta['image_files'] as Map<String, dynamic>;
      return '$dirPath/${files[variant]}';
    }
    return '$dirPath/${meta['image_file']}';
  }
}

String _basename(String path) =>
    path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).last;
