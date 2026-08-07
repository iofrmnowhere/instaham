import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_repository.dart';

class AnalyticsState {
  final WeightAnalytics weight;
  final HealthAnalytics health;
  final bool isLoading;

  const AnalyticsState({
    required this.weight,
    required this.health,
    this.isLoading = false,
  });

  factory AnalyticsState.loading() => AnalyticsState(
    weight: WeightAnalytics.empty(),
    health: HealthAnalytics.empty(),
    isLoading: true,
  );
}

class AnalyticsNotifier extends ChangeNotifier {
  final IAnalyticsRepository _repository;

  StreamSubscription<WeightAnalytics>? _weightSub;
  StreamSubscription<HealthAnalytics>? _healthSub;

  AnalyticsState _state = AnalyticsState.loading();
  AnalyticsState get state => _state;

  AnalyticsNotifier(this._repository) {
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _weightSub = _repository.watchWeightAnalytics().listen((weightData) {
      _state = AnalyticsState(
        weight: weightData,
        health: _state.health,
        isLoading: false,
      );
      notifyListeners();
    });

    _healthSub = _repository.watchHealthAnalytics().listen((healthData) {
      _state = AnalyticsState(
        weight: _state.weight,
        health: healthData,
        isLoading: false,
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _healthSub?.cancel();
    super.dispose();
  }
}
