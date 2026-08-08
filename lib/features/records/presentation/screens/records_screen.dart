import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/models/scan_with_pig.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_error_state.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../domain/repositories/i_records_repository.dart';
import '../notifier/records_notifier.dart';
import '../records_scope.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  IRecordsRepository? _currentRepository;
  RecordsNotifier? _notifier;
  String _filter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = RecordsScope.of(context);
    if (_currentRepository != repository) {
      _currentRepository = repository;
      _notifier?.dispose();
      _notifier = RecordsNotifier(repository);
    }
  }

  @override
  void dispose() {
    _notifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_notifier == null) {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      currentPath: '/records',
      header: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Records',
                  style: AppTextStyles.headline.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  'Saved scans and results on this device',
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Add sample record',
              icon: const Icon(Icons.add_task),
              onPressed: () async {
                final db = DatabaseScope.of(context);
                await db.insertSampleRecord();
              },
            ),
          ],
        ),
      ),
      child: ListenableBuilder(
        listenable: _notifier!,
        builder: (context, _) {
          final state = _notifier!.state;

          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.error != null) {
            return AppErrorState(message: state.error!);
          }

          final records = state.records.where((item) {
            final record = item.scan;
            if (_filter == 'review') {
              return record.status == ScanStatuses.blocked ||
                  record.status == ScanStatuses.rejected;
            }
            if (_filter == 'complete') {
              return record.status == ScanStatuses.completed;
            }
            return true;
          }).toList();

          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'complete', label: Text('Completed')),
                    ButtonSegment(value: 'review', label: Text('Needs review')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: records.isEmpty
                    ? _EmptyRecords(filter: _filter)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _RecordCard(item: records[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final ScanWithPig item;

  const _RecordCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final record = item.scan;
    final goal = scanGoalFromStorage(record.goal);
    return AppCard(
      onTap: () => context.push(
        '/analysis',
        extra: ScanFlowArgs(
          sessionId: record.id,
          goal: goal,
          imagePath: record.imagePath,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.pinkTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              goal.requiresReference
                  ? Icons.monitor_weight_outlined
                  : Icons.health_and_safety_outlined,
              color: AppColors.signalPink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayPigName,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${goal.label} · ${_formatDate(record.updatedAt)}',
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(status: record.status),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.mutedForeground,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ScanStatuses.completed => AppColors.success,
      ScanStatuses.blocked || ScanStatuses.rejected => AppColors.blocked,
      _ => AppColors.mutedForeground,
    };
    final label = status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        label,
        style: AppTextStyles.subtext.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  final String filter;

  const _EmptyRecords({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 52,
              color: AppColors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              filter == 'all' ? 'No scans saved yet' : 'No matching records',
              style: AppTextStyles.headline.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              filter == 'all'
                  ? 'New scans will appear here after capture.'
                  : 'Try a different filter to see more records.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            if (filter == 'all') ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => context.push('/capture'),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Start scan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final db = DatabaseScope.of(context);
                      await db.insertSampleRecord();
                    },
                    icon: const Icon(Icons.add_task),
                    label: const Text('Add sample record'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
