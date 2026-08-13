import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class AnalyticsState {
  final WeightAnalytics weight;
  final HealthAnalytics health;
  final List<WeightDataPoint> weightTimeSeries;
  final List<HealthClassBar> healthClassBars;
  final int totalScanRecords;
  final int filteredScanRecords;
  final bool isLoading;
  final String? error;

  const AnalyticsState({
    required this.weight,
    required this.health,
    required this.weightTimeSeries,
    required this.healthClassBars,
    this.totalScanRecords = 0,
    this.filteredScanRecords = 0,
    this.isLoading = false,
    this.error,
  });

  factory AnalyticsState.loading() => AnalyticsState(
    weight: WeightAnalytics.empty(),
    health: HealthAnalytics.empty(),
    weightTimeSeries: const [],
    healthClassBars: const [],
    totalScanRecords: 0,
    filteredScanRecords: 0,
    isLoading: true,
    error: null,
  );
}

class AnalyticsNotifier extends ChangeNotifier {
  final IAnalyticsRepository _repository;

  StreamSubscription<WeightAnalytics>? _weightSub;
  StreamSubscription<HealthAnalytics>? _healthSub;
  StreamSubscription<List<WeightDataPoint>>? _timeSeriesSub;
  StreamSubscription<List<HealthClassBar>>? _classBarsSub;
  StreamSubscription<int>? _totalScansSub;
  StreamSubscription<int>? _filteredScansSub;

  AnalyticsDateFilter _dateFilter = AnalyticsDateFilter.allTime;
  String? _pigDisplayName;

  AnalyticsState _state = AnalyticsState.loading();
  AnalyticsState get state => _state;

  AnalyticsNotifier(this._repository) {
    _initSubscriptions();
  }

  DateTime? _calculateSince(AnalyticsDateFilter dateFilter) {
    final now = DateTime.now();
    switch (dateFilter) {
      case AnalyticsDateFilter.allTime:
        return null;
      case AnalyticsDateFilter.thisMonth:
        return now.subtract(const Duration(days: 30));
      case AnalyticsDateFilter.thisWeek:
        return now.subtract(const Duration(days: 7));
    }
  }

  void setFilters({
    required AnalyticsDateFilter dateFilter,
    String? pigDisplayName,
  }) {
    _dateFilter = dateFilter;
    _pigDisplayName = pigDisplayName;
    _cancelSubscriptions();
    _initSubscriptions();
  }

  void _cancelSubscriptions() {
    _weightSub?.cancel();
    _healthSub?.cancel();
    _timeSeriesSub?.cancel();
    _classBarsSub?.cancel();
    _totalScansSub?.cancel();
    _filteredScansSub?.cancel();
  }

  void _initSubscriptions() {
    final since = _calculateSince(_dateFilter);
    final pigDisplayName = _pigDisplayName;

    _weightSub = _repository
        .watchWeightAnalytics(since: since, pigDisplayName: pigDisplayName)
        .listen(
          (weightData) {
            _state = AnalyticsState(
              weight: weightData,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load weight analytics: $e',
            );
            notifyListeners();
          },
        );

    _healthSub = _repository
        .watchHealthAnalytics(since: since, pigDisplayName: pigDisplayName)
        .listen(
          (healthData) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: healthData,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load health analytics: $e',
            );
            notifyListeners();
          },
        );

    _timeSeriesSub = _repository
        .watchWeightTimeSeries(since: since, pigDisplayName: pigDisplayName)
        .listen(
          (points) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: points,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load weight trends: $e',
            );
            notifyListeners();
          },
        );

    _classBarsSub = _repository
        .watchHealthClassBars(since: since, pigDisplayName: pigDisplayName)
        .listen(
          (bars) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: bars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load health breakdown: $e',
            );
            notifyListeners();
          },
        );

    _totalScansSub = _repository
        .watchTotalScanRecords(since: null, pigDisplayName: pigDisplayName)
        .listen(
          (count) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: count,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load total scan records: $e',
            );
            notifyListeners();
          },
        );

    _filteredScansSub = _repository
        .watchTotalScanRecords(since: since, pigDisplayName: pigDisplayName)
        .listen(
          (count) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: count,
              isLoading: false,
              error: null,
            );
            notifyListeners();
          },
          onError: (e) {
            _state = AnalyticsState(
              weight: _state.weight,
              health: _state.health,
              weightTimeSeries: _state.weightTimeSeries,
              healthClassBars: _state.healthClassBars,
              totalScanRecords: _state.totalScanRecords,
              filteredScanRecords: _state.filteredScanRecords,
              isLoading: false,
              error: 'Failed to load filtered scan records: $e',
            );
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}
