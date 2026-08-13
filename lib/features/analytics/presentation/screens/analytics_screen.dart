import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_error_state.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';
import '../analytics_scope.dart';
import '../notifier/analytics_notifier.dart';
import '../widgets/health_panel.dart';
import '../widgets/overview_panel.dart';
import '../widgets/weight_panel.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  IAnalyticsRepository? _currentRepository;
  AnalyticsNotifier? _notifier;
  String _selectedTab = 'overview';
  AnalyticsDateFilter _dateFilter = AnalyticsDateFilter.allTime;
  bool _searchOpen = false;
  String _searchQuery = '';
  String? _selectedPigName;
  final TextEditingController _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = AnalyticsScope.of(context);
    if (_currentRepository != repository) {
      _currentRepository = repository;
      _notifier?.dispose();
      _notifier = AnalyticsNotifier(repository);
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notifier?.dispose();
    super.dispose();
  }

  void _applyFilters() {
    _notifier?.setFilters(
      dateFilter: _dateFilter,
      pigDisplayName: _selectedPigName,
    );
  }

  void _cycleDateFilter() {
    setState(() {
      switch (_dateFilter) {
        case AnalyticsDateFilter.allTime:
          _dateFilter = AnalyticsDateFilter.thisMonth;
          break;
        case AnalyticsDateFilter.thisMonth:
          _dateFilter = AnalyticsDateFilter.thisWeek;
          break;
        case AnalyticsDateFilter.thisWeek:
          _dateFilter = AnalyticsDateFilter.allTime;
          break;
      }
    });
    _applyFilters();
  }

  String get _dateFilterLabel {
    switch (_dateFilter) {
      case AnalyticsDateFilter.allTime:
        return 'All Time';
      case AnalyticsDateFilter.thisMonth:
        return 'Last 30 Days';
      case AnalyticsDateFilter.thisWeek:
        return 'Last 7 Days';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifier == null) {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      currentPath: '/analytics',
      header: Container(
        padding: const EdgeInsets.all(16.0),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analytics',
              style: AppTextStyles.headline.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 2),
            Text(
              'Track trends and patterns for weight and health',
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
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
                      value: _selectedTab,
                      icon: const Icon(Icons.arrow_drop_down),
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                        fontSize: 15,
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedTab = value);
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'overview',
                          child: Row(
                            children: [
                              Icon(Icons.analytics_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Overview'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'weight',
                          child: Row(
                            children: [
                              Icon(Icons.monitor_weight_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Weight Analytics'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'health',
                          child: Row(
                            children: [
                              Icon(Icons.health_and_safety_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Health Analytics'),
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
                        color: _dateFilter != AnalyticsDateFilter.allTime
                            ? AppColors.signalPink
                            : AppColors.foreground,
                      ),
                      onPressed: _cycleDateFilter,
                    ),
                    if (_dateFilter != AnalyticsDateFilter.allTime)
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
                  tooltip: _selectedPigName != null
                      ? 'Pig: $_selectedPigName (tap to clear)'
                      : 'Search pig',
                  icon: Icon(
                    _selectedPigName != null
                        ? Icons.person
                        : (_searchOpen ? Icons.close : Icons.search),
                    color: _selectedPigName != null
                        ? AppColors.signalPink
                        : AppColors.foreground,
                  ),
                  onPressed: () {
                    if (_selectedPigName != null) {
                      setState(() {
                        _selectedPigName = null;
                        _searchOpen = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                      _applyFilters();
                    } else {
                      setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _searchQuery = '';
                          _searchController.clear();
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
                'Showing $_dateFilterLabel${_selectedPigName != null ? ' • Pig: $_selectedPigName' : ''}',
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
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search pig by display name...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
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
                                _selectedPigName = _searchQuery;
                                _searchOpen = false;
                              });
                              _applyFilters();
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
                                    _selectedPigName = pig.displayName;
                                    _searchOpen = false;
                                  });
                                  _applyFilters();
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

                Widget panel;
                if (_selectedTab == 'overview') {
                  panel = OverviewPanel(
                    totalScanRecords: state.totalScanRecords,
                    filteredScanRecords: state.filteredScanRecords,
                    dateFilter: _dateFilter,
                    weightData: state.weight,
                    healthData: state.health,
                    weightTimeSeries: state.weightTimeSeries,
                    healthClassBars: state.healthClassBars,
                  );
                } else if (_selectedTab == 'weight') {
                  panel = WeightPanel(
                    data: state.weight,
                    timeSeries: state.weightTimeSeries,
                  );
                } else {
                  panel = HealthPanel(
                    data: state.health,
                    classBars: state.healthClassBars,
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                  child: panel,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
