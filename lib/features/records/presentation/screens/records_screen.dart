import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_scope.dart';
import '../../../../core/models/pig_suggestion.dart';
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

enum _RecordsDateFilter { allTime, thisMonth, thisWeek }

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  IRecordsRepository? _currentRepository;
  RecordsNotifier? _notifier;
  String _filter = 'all';
  _RecordsDateFilter _dateFilter = _RecordsDateFilter.allTime;
  bool _searchOpen = false;
  String _searchQuery = '';
  String? _selectedPigId;
  String? _selectedPigLabel;

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

  void _cycleDateFilter() {
    setState(() {
      switch (_dateFilter) {
        case _RecordsDateFilter.allTime:
          _dateFilter = _RecordsDateFilter.thisMonth;
          break;
        case _RecordsDateFilter.thisMonth:
          _dateFilter = _RecordsDateFilter.thisWeek;
          break;
        case _RecordsDateFilter.thisWeek:
          _dateFilter = _RecordsDateFilter.allTime;
          break;
      }
    });
  }

  String get _dateFilterLabel {
    switch (_dateFilter) {
      case _RecordsDateFilter.allTime:
        return 'All Time';
      case _RecordsDateFilter.thisMonth:
        return 'Last 30 Days';
      case _RecordsDateFilter.thisWeek:
        return 'Last 7 Days';
    }
  }

  String get _statusFilterLabel {
    switch (_filter) {
      case 'complete':
        return 'Completed';
      case 'review':
        return 'Needs Review';
      case 'all':
      default:
        return 'All Statuses';
    }
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isDense: true,
                      value: _filter,
                      icon: const Icon(Icons.arrow_drop_down),
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                        fontSize: 15,
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _filter = value);
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('All Records'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 18),
                              SizedBox(width: 8),
                              Text('Completed'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'review',
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Needs Review'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      tooltip: 'Filter: $_dateFilterLabel',
                      icon: Icon(
                        Icons.filter_list,
                        color: _dateFilter != _RecordsDateFilter.allTime
                            ? AppColors.signalPink
                            : AppColors.foreground,
                      ),
                      onPressed: _cycleDateFilter,
                    ),
                    if (_dateFilter != _RecordsDateFilter.allTime)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.signalPink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: _selectedPigId != null
                      ? 'Pig: $_selectedPigLabel (tap to clear)'
                      : 'Search pig',
                  icon: Icon(
                    _selectedPigId != null
                        ? Icons.person
                        : (_searchOpen ? Icons.close : Icons.search),
                    color: _selectedPigId != null
                        ? AppColors.signalPink
                        : AppColors.foreground,
                  ),
                  onPressed: () {
                    if (_selectedPigId != null) {
                      setState(() {
                        _selectedPigId = null;
                        _selectedPigLabel = null;
                        _searchOpen = false;
                        _searchQuery = '';
                      });
                    } else {
                      setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _searchQuery = '';
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0) +
                const EdgeInsets.only(top: 10.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing $_dateFilterLabel • $_statusFilterLabel${_selectedPigLabel != null ? ' • Pig: $_selectedPigLabel' : ''}',
                style: AppTextStyles.subtext.copyWith(
                  color: AppColors.mutedForeground,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
              child: Card(
                elevation: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search pig by display name...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const Divider(height: 1),
                    StreamBuilder<List<PigSuggestion>>(
                      key: ValueKey(_searchQuery),
                      stream: _currentRepository?.watchPigSuggestions(
                        _searchQuery,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final suggestions = snapshot.data ?? [];
                        if (suggestions.isEmpty) {
                          return ListTile(
                            title: Text(
                              'No matching pigs',
                              style: AppTextStyles.subtext.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedPigId = 'non_existent_id';
                                _selectedPigLabel = _searchQuery;
                                _searchOpen = false;
                              });
                            },
                          );
                        }
                        return Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: suggestions.length,
                            itemBuilder: (context, index) {
                              final pig = suggestions[index];
                              return ListTile(
                                dense: true,
                                title: Text(pig.displayLabel),
                                onTap: () {
                                  setState(() {
                                    _selectedPigId = pig.id;
                                    _selectedPigLabel = pig.displayLabel;
                                    _searchOpen = false;
                                  });
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8.0),
          Expanded(
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

                final now = DateTime.now();
                final records = state.records.where((item) {
                  final record = item.scan;

                  if (_filter == 'review') {
                    if (record.status != ScanStatuses.blocked &&
                        record.status != ScanStatuses.rejected) {
                      return false;
                    }
                  } else if (_filter == 'complete') {
                    if (record.status != ScanStatuses.completed) {
                      return false;
                    }
                  }

                  if (_dateFilter == _RecordsDateFilter.thisMonth) {
                    final cutoff = now.subtract(const Duration(days: 30));
                    if (record.updatedAt.isBefore(cutoff)) {
                      return false;
                    }
                  } else if (_dateFilter == _RecordsDateFilter.thisWeek) {
                    final cutoff = now.subtract(const Duration(days: 7));
                    if (record.updatedAt.isBefore(cutoff)) {
                      return false;
                    }
                  }

                  if (_selectedPigId != null) {
                    final matchesPig =
                        item.pig?.id == _selectedPigId ||
                        record.pigId == _selectedPigId;
                    if (!matchesPig) {
                      return false;
                    }
                  }

                  return true;
                }).toList();

                final hasActiveFilters =
                    _filter != 'all' ||
                    _dateFilter != _RecordsDateFilter.allTime ||
                    _selectedPigId != null;

                return records.isEmpty
                    ? _EmptyRecords(hasActiveFilters: hasActiveFilters)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _RecordCard(item: records[index]),
                      );
              },
            ),
          ),
        ],
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
  final bool hasActiveFilters;

  const _EmptyRecords({required this.hasActiveFilters});

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
              !hasActiveFilters ? 'No scans saved yet' : 'No matching records',
              style: AppTextStyles.headline.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              !hasActiveFilters
                  ? 'New scans will appear here after capture.'
                  : 'Try a different filter to see more records.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            if (!hasActiveFilters) ...[
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
