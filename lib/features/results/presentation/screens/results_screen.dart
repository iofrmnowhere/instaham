import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/local_scan_bundle.dart';
import '../../../../core/models/measurement_mode.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';

class ResultsScreen extends StatefulWidget {
  final ScanFlowArgs args;

  const ResultsScreen({super.key, this.args = const ScanFlowArgs()});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  AppDatabase? _database;
  Future<LocalScanBundle?>? _bundle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_database != null) return;
    _database = DatabaseScope.of(context);
    _reload();
  }

  void _reload() {
    final id = widget.args.sessionId;
    setState(() {
      _bundle = id == null
          ? Future<LocalScanBundle?>.value(null)
          : _loadAndRunPipelineIfNeeded(id);
    });
  }

  /// Loads the scan bundle and, the first time a captured image has no stored health
  /// result yet, runs the real inference pipeline and persists it before returning the
  /// refreshed bundle (ML_implementation_plan.md section 11.3, slice 4: "the app stops
  /// showing Pending"). A retake or a scan with no image simply shows the stored/blank
  /// state, same as before this pipeline existed.
  Future<LocalScanBundle?> _loadAndRunPipelineIfNeeded(String id) async {
    final db = _database!;
    var bundle = await db.recordsDao.loadScanBundle(id);
    final imagePath = bundle?.scan.imagePath;
    if (bundle != null && bundle.health == null && imagePath != null) {
      await const RunAndPersistPipelineUseCase().execute(db, id, imagePath);
      bundle = await db.recordsDao.loadScanBundle(id);
    }
    return bundle;
  }

  ReferenceSelection? _referenceFor(LocalScanBundle bundle) {
    final stored = bundle.reference;
    if (stored != null) {
      return ReferenceSelection(
        type: stored.objectType,
        name: stored.objectName,
        lengthCm: stored.lengthCm,
      );
    }
    return widget.args.reference;
  }

  Future<void> _assignPig(LocalScanBundle bundle) async {
    final isEditing = bundle.pig != null;
    final currentTag = bundle.pig?.tag ?? '';
    final currentName = bundle.pig?.displayName ?? bundle.pig?.tag ?? '';

    final tagController = TextEditingController(text: currentTag);
    final nameController = TextEditingController(
      text: isEditing ? currentName : '',
    );

    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Change pig display name' : 'Assign this scan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isEditing) ...[
              TextField(
                controller: tagController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Pig tag or ID'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: nameController,
              autofocus: isEditing,
              decoration: InputDecoration(
                labelText: isEditing
                    ? 'Display name'
                    : 'Display name (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final tag = tagController.text.trim();
              if (tag.isEmpty && !isEditing) return;
              Navigator.pop(dialogContext, [
                isEditing ? currentTag : tag,
                nameController.text.trim(),
              ]);
            },
            child: Text(isEditing ? 'Save' : 'Assign'),
          ),
        ],
      ),
    );
    tagController.dispose();
    nameController.dispose();
    if (result == null) return;
    await _database!.assignPig(
      scanId: bundle.scan.id,
      tag: result.first,
      displayName: result.last,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: false,
      header: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.go('/records'),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Scan details',
              style: AppTextStyles.headline.copyWith(fontSize: 20),
            ),
          ],
        ),
      ),
      child: FutureBuilder<LocalScanBundle?>(
        future: _bundle,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bundle = snapshot.data;
          if (bundle == null) return _MissingRecord(args: widget.args);
          return _buildRecord(bundle);
        },
      ),
    );
  }

  Widget _buildRecord(LocalScanBundle bundle) {
    final goal = scanGoalFromStorage(bundle.scan.goal);
    final reference = _referenceFor(bundle);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhotoPreview(path: bundle.scan.imagePath),
        const SizedBox(height: 14),
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.pets_outlined, color: AppColors.signalPink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.pig?.displayName ??
                          bundle.pig?.tag ??
                          'Unassigned scan',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      goal.label,
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _assignPig(bundle),
                child: Text(bundle.pig == null ? 'Assign' : 'Change'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _viewCard(bundle.viewEvent),
        const SizedBox(height: 12),
        if (goal.requiresReference) ...[
          _weightCard(bundle.weight),
          const SizedBox(height: 12),
        ],
        _healthCard(bundle.health, bundle.viewEvent),
        if (reference != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.straighten, color: AppColors.signalPink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reference used',
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      Text(
                        '${reference.name} · ${reference.lengthCm.toStringAsFixed(1)} cm',
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(
                    '/reference-marking',
                    extra: widget.args.copyWith(
                      sessionId: bundle.scan.id,
                      goal: goal,
                      reference: reference,
                      imagePath: bundle.scan.imagePath,
                    ),
                  ),
                  child: const Text('Review'),
                ),
              ],
            ),
          ),
        ],
        if (bundle.scan.measurementMode == MeasurementMode.fixedHeight.name &&
            bundle.scan.cameraHeightCm != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.height, color: AppColors.signalPink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Camera height used',
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      Text(
                        '${bundle.scan.cameraHeightCm!.toStringAsFixed(1)} cm',
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        AppCard(
          backgroundColor: AppColors.pinkTint,
          border: Border.all(
            color: AppColors.signalPink.withValues(alpha: 0.25),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.medical_information_outlined,
                color: AppColors.signalPink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Visual health screening is not a veterinary diagnosis. Seek professional assessment when the pig is ill or the result is uncertain.',
                  style: AppTextStyles.subtext,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go('/records'),
                child: const Text('Done'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => context.push(
                  '/capture',
                  extra: widget.args.copyWith(
                    sessionId: bundle.scan.id,
                    goal: goal,
                    reference: reference,
                    imagePath: bundle.scan.imagePath,
                  ),
                ),
                child: const Text('Retake'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _weightCard(WeightResult? result) {
    if (result == null) {
      return const _BranchCard(
        icon: Icons.monitor_weight_outlined,
        title: 'Weight',
        value: 'Pending',
        status: ResultStatus.uncertain,
        message:
            'No eligible weight output is stored yet. The model pipeline must complete all weight checks.',
      );
    }
    if (!result.eligible || result.valueKg == null) {
      return _BranchCard(
        icon: Icons.monitor_weight_outlined,
        title: 'Weight',
        value: 'Unavailable',
        status: ResultStatus.blocked,
        message:
            result.failureReason ?? 'Weight eligibility checks did not pass.',
      );
    }
    return _BranchCard(
      icon: Icons.monitor_weight_outlined,
      title: 'Estimated weight',
      value: '${result.valueKg!.toStringAsFixed(1)} kg',
      status: ResultStatus.success,
      message: result.modelVersion == null
          ? 'Model version unavailable.'
          : 'Model ${result.modelVersion}',
    );
  }

  /// TASKS.md's P2: the view gate's own outcome, shown as its own card instead of being
  /// silently folded into a health-card "Unavailable" (Cause C — the two used to be
  /// indistinguishable to the user).
  Widget _viewCard(PipelineEvent? viewEvent) {
    if (viewEvent == null) {
      return const _BranchCard(
        icon: Icons.crop_free,
        title: 'Photo framing',
        value: 'Pending',
        status: ResultStatus.uncertain,
        message: 'Awaiting the view-suitability check.',
      );
    }
    final confidence = double.tryParse(viewEvent.message ?? '');
    final confidenceText = confidence == null
        ? ''
        : ' (${(confidence * 100).round()}% confidence)';
    return switch (viewEvent.status) {
      'dorsal_valid' => _BranchCard(
        icon: Icons.crop_free,
        title: 'Photo framing',
        value: 'Dorsal view$confidenceText',
        status: ResultStatus.success,
        message: 'Suitable for both weight and health screening.',
      ),
      'health_only' => _BranchCard(
        icon: Icons.crop_free,
        title: 'Photo framing',
        value: 'Health-only view$confidenceText',
        status: ResultStatus.uncertain,
        message:
            'Not a dorsal (top-down) view, so weight estimation is skipped. '
            'Health screening still runs.',
      ),
      'reject' => _BranchCard(
        icon: Icons.crop_free,
        title: 'Photo framing',
        value: 'Not usable$confidenceText',
        status: ResultStatus.blocked,
        message: 'Retake with the whole pig visible and well lit.',
      ),
      _ => _BranchCard(
        icon: Icons.crop_free,
        title: 'Photo framing',
        value: viewEvent.status,
        status: ResultStatus.uncertain,
        message: 'Unrecognized view-gate outcome.',
      ),
    };
  }

  Widget _healthCard(HealthResult? result, PipelineEvent? viewEvent) {
    if (result == null) {
      return const _BranchCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Visual health',
        value: 'Pending',
        status: ResultStatus.uncertain,
        message:
            'No visual classification is stored yet. Awaiting the health model pipeline.',
      );
    }
    if (!result.eligible || result.className == null) {
      // A view-gate reject means health was deliberately never attempted -- that is not
      // the same failure as an eligibility check or inference error, so it reads
      // differently (TASKS.md Cause C).
      final skippedByViewGate = viewEvent?.status == 'reject';
      return _BranchCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Visual health',
        value: skippedByViewGate ? 'Skipped' : 'Unavailable',
        status: skippedByViewGate ? ResultStatus.skipped : ResultStatus.blocked,
        message:
            result.failureReason ??
            'The image was not eligible for visual screening.',
      );
    }
    final confidence = result.confidence == null
        ? 'Confidence unavailable'
        : '${(result.confidence! * 100).round()}% confidence';
    return _BranchCard(
      icon: Icons.health_and_safety_outlined,
      title: 'Possible visual indicator',
      value: result.className!,
      status: result.uncertain ? ResultStatus.uncertain : ResultStatus.success,
      message: result.uncertain
          ? '$confidence · Review or retake recommended.'
          : confidence,
    );
  }
}

class _BranchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final ResultStatus status;
  final String message;

  const _BranchCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.status,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ResultStatus.success => AppColors.success,
      ResultStatus.uncertain => AppColors.uncertain,
      ResultStatus.blocked => AppColors.blocked,
      ResultStatus.skipped => AppColors.mutedForeground,
    };
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.headline.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final String? path;

  const _PhotoPreview({this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: path != null && File(path!).existsSync()
          ? Image.file(File(path!), fit: BoxFit.cover)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_outlined,
                    size: 42,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scan photo',
                    style: AppTextStyles.label.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MissingRecord extends StatelessWidget {
  final ScanFlowArgs args;

  const _MissingRecord({required this.args});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 52,
              color: AppColors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              'Scan record not found',
              style: AppTextStyles.headline.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              'The scan may not have been saved or may have been deleted.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => context.go('/records'),
              child: const Text('Back to records'),
            ),
          ],
        ),
      ),
    );
  }
}
