import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class AnalyticsState {
  final WeightAnalytics weight;
  final HealthAnalytics health;
  final List<WeightDataPoint> weightTimeSeries;
  final List<HealthClassBar> healthClassBars;
  final bool isLoading;
  final String? error;

  const AnalyticsState({
    required this.weight,
    required this.health,
    required this.weightTimeSeries,
    required this.healthClassBars,
    this.isLoading = false,
    this.error,
  });

  factory AnalyticsState.loading() => AnalyticsState(
    weight: WeightAnalytics.empty(),
    health: HealthAnalytics.empty(),
    weightTimeSeries: const [],
    healthClassBars: const [],
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

  AnalyticsState _state = AnalyticsState.loading();
  AnalyticsState get state => _state;

  AnalyticsNotifier(this._repository) {
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _weightSub = _repository.watchWeightAnalytics().listen(
      (weightData) {
        _state = AnalyticsState(
          weight: weightData,
          health: _state.health,
          weightTimeSeries: _state.weightTimeSeries,
          healthClassBars: _state.healthClassBars,
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
          isLoading: false,
          error: 'Failed to load weight analytics: $e',
        );
        notifyListeners();
      },
    );

    _healthSub = _repository.watchHealthAnalytics().listen(
      (healthData) {
        _state = AnalyticsState(
          weight: _state.weight,
          health: healthData,
          weightTimeSeries: _state.weightTimeSeries,
          healthClassBars: _state.healthClassBars,
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
          isLoading: false,
          error: 'Failed to load health analytics: $e',
        );
        notifyListeners();
      },
    );

    _timeSeriesSub = _repository.watchWeightTimeSeries().listen(
      (points) {
        _state = AnalyticsState(
          weight: _state.weight,
          health: _state.health,
          weightTimeSeries: points,
          healthClassBars: _state.healthClassBars,
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
          isLoading: false,
          error: 'Failed to load weight trends: $e',
        );
        notifyListeners();
      },
    );

    _classBarsSub = _repository.watchHealthClassBars().listen(
      (bars) {
        _state = AnalyticsState(
          weight: _state.weight,
          health: _state.health,
          weightTimeSeries: _state.weightTimeSeries,
          healthClassBars: bars,
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
          isLoading: false,
          error: 'Failed to load health breakdown: $e',
        );
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _healthSub?.cancel();
    _timeSeriesSub?.cancel();
    _classBarsSub?.cancel();
    super.dispose();
  }
}
