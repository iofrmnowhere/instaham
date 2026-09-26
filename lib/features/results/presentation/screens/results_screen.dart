import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/folder_summary.dart';
import '../../../../core/models/local_scan_bundle.dart';
import '../../../../core/models/measurement_mode.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../../core/widgets/folder_name_dialog.dart';
import '../../../../core/widgets/folders_scope.dart';
import '../../../../core/widgets/stacked_dialog_actions.dart';
import '../../../inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';
import '../widgets/analysis_progress_view.dart';

class ResultsScreen extends StatefulWidget {
  final ScanFlowArgs args;

  const ResultsScreen({super.key, this.args = const ScanFlowArgs()});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  AppDatabase? _database;
  Future<LocalScanBundle?>? _bundle;
  // plan-phase-2/2-progress-ui.md: the phase AnalysisProgressView renders while _bundle is
  // pending. Not a per-stage checklist -- just the three boundaries Dart observes below.
  AnalysisPhase _phase = AnalysisPhase.loadingBundle;
  bool _pipelineRanThisLoad = false;
  bool _popWarned = false;

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
      _phase = AnalysisPhase.loadingBundle;
      _pipelineRanThisLoad = false;
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
      if (mounted) {
        setState(() {
          _phase = AnalysisPhase.runningPipeline;
          _pipelineRanThisLoad = true;
        });
      }
      await const RunAndPersistPipelineUseCase().execute(db, id, imagePath);
      if (mounted) setState(() => _phase = AnalysisPhase.reloadingBundle);
      bundle = await db.recordsDao.loadScanBundle(id);
    }
    if (bundle == null) return null;
    // docs/fix-phase-6/2-dialog-and-routing.md (F68, widens F67): identity-matched, same
    // rule as resolveViewGate/F66 -- a mismatch (no override, or one recorded for an
    // earlier photo in this scan) must never show the banner or affect the card labels.
    final currentImagePath = bundle.scan.imagePath;
    final routeOverride = currentImagePath == null
        ? null
        : await RunAndPersistPipelineUseCase.viewRouteOverride(
            db,
            id,
            currentImagePath,
          );
    return LocalScanBundle(
      scan: bundle.scan,
      pig: bundle.pig,
      reference: bundle.reference,
      weight: bundle.weight,
      health: bundle.health,
      viewEvent: bundle.viewEvent,
      viewRouteOverride: routeOverride,
    );
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

  // docs/fix-8.md F74: every scan already has its own auto-ID pig (from createDraftScan
  // onward), so this only renames it -- there is no "unassigned scan" case to assign a tag
  // to anymore. The tag itself is not editable here; it is the auto-generated ID.
  Future<void> _renamePig(LocalScanBundle bundle) async {
    final pig = bundle.pig;
    if (pig == null) return;

    final nameController = TextEditingController(text: pig.displayName ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename pig'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ID ${pig.tag}',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
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
            onPressed: () =>
                Navigator.pop(dialogContext, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (result == null) return;
    await _database!.renamePigForScan(
      scanId: bundle.scan.id,
      displayName: result,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LocalScanBundle?>(
      future: _bundle,
      builder: (context, snapshot) {
        final analyzing =
            snapshot.connectionState != ConnectionState.done &&
            _pipelineRanThisLoad;
        return PopScope(
          // plan-phase-2/2-progress-ui.md: the run continues on the worker isolate and
          // persists regardless of whether this screen is alive, so leaving is safe -- warn
          // once rather than block. Only armed while the pipeline itself is running, not the
          // cheap bundle load/reload either side of it.
          canPop: !analyzing || _popWarned,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop || !analyzing || _popWarned) return;
            _popWarned = true;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Analysis will finish in the background.'),
              ),
            );
          },
          child: AppScaffold(
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
            child: Builder(
              builder: (context) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return AnalysisProgressView(phase: _phase);
                }
                final bundle = snapshot.data;
                if (bundle == null) return _MissingRecord(args: widget.args);
                return _buildRecord(bundle);
              },
            ),
          ),
        );
      },
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
                    // docs/plan-6.md (round 6, pig folders) step 5: shown only when the
                    // scan has a pig, since folders hold pigs, not unassigned scans.
                    if (bundle.pig != null) ...[
                      const SizedBox(height: 6),
                      _FolderLine(pig: bundle.pig!),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: bundle.pig == null ? null : () => _renamePig(bundle),
                child: const Text('Rename'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (goal.requiresReference) ...[
          _weightCard(bundle.weight, bundle.effectiveRoute),
          const SizedBox(height: 12),
        ],
        _healthCard(bundle.health, bundle.effectiveRoute),
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

  /// ML_implementation_plan.md revision 7, section 12.5: three distinct weight states,
  /// never collapsed into one "Unavailable" the way the health card used to be before
  /// TASKS.md's P2 (see _healthCard's own `skippedByViewGate` split, the same idea
  /// applied here). "Skipped" (not a dorsal photo) is a routing outcome, not a failure;
  /// "Unavailable" (segmentation failed, or the cutter is the identity dummy -- section
  /// 3.4) is the branch genuinely not producing a number this build.
  ///
  /// F70 (docs/fix-phase-6/2-dialog-and-routing.md): `effectiveRoute` is the route that
  /// actually ran (`LocalScanBundle.effectiveRoute` -- the override when present,
  /// otherwise the stored verdict), not the raw verdict. Reading the verdict alone showed
  /// "Skipped" for an overridden `reject`/`health_only` scan whose weight checks then
  /// genuinely failed, which is the "Unavailable" case, not a routing skip.
  Widget _weightCard(WeightResult? result, String? effectiveRoute) {
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
      final skippedByViewGate =
          effectiveRoute != null && effectiveRoute != 'dorsal_valid';
      return _BranchCard(
        icon: Icons.monitor_weight_outlined,
        title: 'Weight',
        value: skippedByViewGate ? 'Skipped' : 'Unavailable',
        status: skippedByViewGate ? ResultStatus.skipped : ResultStatus.blocked,
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

  /// F70 (docs/fix-phase-6/2-dialog-and-routing.md): `effectiveRoute` is the route that
  /// actually ran, not the raw verdict -- a `reject` overridden to `health_only` or
  /// `dorsal_valid` did run health, so it must not read as "Skipped" here either.
  Widget _healthCard(HealthResult? result, String? effectiveRoute) {
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
      // A view-gate reject with no override means health was deliberately never
      // attempted -- that is not the same failure as an eligibility check or inference
      // error, so it reads differently (TASKS.md Cause C).
      final skippedByViewGate = effectiveRoute == 'reject';
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
    // docs/plan-4.md / docs/plan-phase-4/3-app-surfacing.md: the two-stage cascade re-checks
    // a non-healthy whole-photo result against the pig alone (background removed). That
    // second pass cannot clear a false alarm and how well it names the right disease is
    // unmeasured (docs/logs/phase3-health-protocol-measurement.md), so this is worded as a
    // possible indicator, never as a confirmation. Read from the stored row, not the live
    // envelope, so reopening a scan later shows the same wording. Older rows and results
    // that never needed the second pass (`preprocessingVersion` null, or
    // "cascade_v1:full_frame") read exactly as before this plan.
    final secondPassRan =
        result.preprocessingVersion == 'cascade_v1:segmentation_masked';
    final message = secondPassRan
        ? '$confidence · Flagged on the whole photo, then re-checked on the pig alone. '
              'This is a possible indicator, not a confirmed diagnosis.'
              '${result.uncertain ? ' Review or retake recommended.' : ''}'
        : (result.uncertain
              ? '$confidence · Review or retake recommended.'
              : confidence);
    return _BranchCard(
      icon: Icons.health_and_safety_outlined,
      title: 'Possible visual indicator',
      value: result.className!,
      status: result.uncertain ? ResultStatus.uncertain : ResultStatus.success,
      message: message,
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

/// docs/plan-6.md (round 6, pig folders) step 5: the pig card's Folder line and picker.
/// Reads `FoldersScope` live so a folder rename or a move made elsewhere (the folder
/// detail screen) is reflected here without a manual reload.
class _FolderLine extends StatelessWidget {
  final Pig pig;

  const _FolderLine({required this.pig});

  Future<void> _openPicker(
    BuildContext context,
    List<FolderSummary> folders,
  ) async {
    final repository = FoldersScope.of(context);
    final choice = await showDialog<_FolderPickerChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Folder'),
        content: SingleChildScrollView(
          child: StackedDialogActions(
            buttons: [
              for (final summary in folders)
                OutlinedButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _FolderPickerChoice.existing(summary.folder.id),
                  ),
                  child: Text(summary.folder.name),
                ),
              OutlinedButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  const _FolderPickerChoice.none(),
                ),
                child: const Text('No folder'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  const _FolderPickerChoice.createNew(),
                ),
                child: const Text('New folder'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (choice.createNew) {
      if (!context.mounted) return;
      final name = await showFolderNameDialog(
        context,
        title: 'New folder',
        confirmLabel: 'Create',
      );
      if (name == null) return;
      final folderId = await repository.createFolder(name);
      await repository.setPigFolder(pig.id, folderId);
      return;
    }
    await repository.setPigFolder(pig.id, choice.folderId);
  }

  @override
  Widget build(BuildContext context) {
    final repository = FoldersScope.of(context);
    // Two live queries, not the scan bundle's once-loaded `pig.folderId`: a move made from
    // this picker (or from the folder detail screen) must show up here without a reload.
    return StreamBuilder<String?>(
      stream: repository.watchPigFolderId(pig.id),
      builder: (context, pigSnapshot) {
        final currentFolderId = pigSnapshot.data;
        return StreamBuilder<List<FolderSummary>>(
          stream: repository.watchFolders(),
          builder: (context, foldersSnapshot) {
            final folders = foldersSnapshot.data ?? const [];
            FolderSummary? current;
            for (final summary in folders) {
              if (summary.folder.id == currentFolderId) {
                current = summary;
                break;
              }
            }
            return Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: AppColors.mutedForeground,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    current?.folder.name ?? 'No folder',
                    style: AppTextStyles.subtext.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _openPicker(context, folders),
                  child: const Text('Folder'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FolderPickerChoice {
  final bool createNew;
  final String? folderId;

  const _FolderPickerChoice.none() : createNew = false, folderId = null;

  const _FolderPickerChoice.existing(String id)
    : createNew = false,
      folderId = id;

  const _FolderPickerChoice.createNew() : createNew = true, folderId = null;
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
