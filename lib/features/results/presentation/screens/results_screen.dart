import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

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
    final future = id == null
        ? Future<LocalScanBundle?>.value(null)
        : _database!.loadScanBundle(id);
    setState(() {
      _bundle = future;
    });
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
    final tagController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assign this scan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tagController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Pig tag or ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
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
              if (tagController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, [
                tagController.text.trim(),
                nameController.text.trim(),
              ]);
            },
            child: const Text('Assign'),
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
        if (goal.requiresReference) ...[
          _weightCard(bundle.weight),
          const SizedBox(height: 12),
        ],
        _healthCard(bundle.health),
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

  Widget _healthCard(HealthResult? result) {
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
      return _BranchCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Visual health',
        value: 'Unavailable',
        status: ResultStatus.blocked,
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
