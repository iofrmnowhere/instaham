import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../core/models/scan_with_pig.dart';
import '../../domain/repositories/i_records_repository.dart';

class RecordsState {
  final List<ScanWithPig> records;
  final bool isLoading;
  final String? error;

  const RecordsState({
    required this.records,
    this.isLoading = false,
    this.error,
  });

  factory RecordsState.loading() =>
      const RecordsState(records: [], isLoading: true, error: null);
}

class RecordsNotifier extends ChangeNotifier {
  final IRecordsRepository _repository;
  StreamSubscription<List<ScanWithPig>>? _subscription;

  RecordsState _state = RecordsState.loading();
  RecordsState get state => _state;

  RecordsNotifier(this._repository) {
    _initSubscription();
  }

  void _initSubscription() {
    _subscription = _repository.watchRecentScans().listen(
      (data) {
        _state = RecordsState(records: data, isLoading: false, error: null);
        notifyListeners();
      },
      onError: (e) {
        _state = RecordsState(
          records: _state.records,
          isLoading: false,
          error: 'Failed to load records: $e',
        );
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
