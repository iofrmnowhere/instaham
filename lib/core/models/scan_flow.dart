enum ScanGoal { weightAndHealth, healthOnly }

extension ScanGoalPresentation on ScanGoal {
  String get storageValue => switch (this) {
    ScanGoal.weightAndHealth => 'weight_health',
    ScanGoal.healthOnly => 'health_only',
  };

  String get label => switch (this) {
    ScanGoal.weightAndHealth => 'Weight + Health',
    ScanGoal.healthOnly => 'Health Only',
  };

  bool get requiresReference => this == ScanGoal.weightAndHealth;
}

ScanGoal scanGoalFromStorage(String value) => switch (value) {
  'health_only' => ScanGoal.healthOnly,
  _ => ScanGoal.weightAndHealth,
};

abstract final class ScanStatuses {
  static const draft = 'draft';
  static const captured = 'captured';
  static const referenceReview = 'reference_review';
  static const analyzing = 'analyzing';
  static const completed = 'completed';
  static const blocked = 'blocked';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
}

class ReferenceSelection {
  final String type;
  final String name;
  final double lengthCm;

  const ReferenceSelection({
    required this.type,
    required this.name,
    required this.lengthCm,
  }) : assert(lengthCm > 0);

  static const meterStick = ReferenceSelection(
    type: 'meter_stick',
    name: '1-meter stick',
    lengthCm: 100,
  );

  static const poracStick = ReferenceSelection(
    type: 'porac_stick',
    name: 'Porac stick',
    lengthCm: 131,
  );
}

class ReferenceSuggestion {
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double confidence;

  const ReferenceSuggestion({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.confidence,
  });
}

class ScanFlowArgs {
  final String? sessionId;
  final ScanGoal goal;
  final ReferenceSelection? reference;
  final String? imagePath;
  final int? imageWidthPx;
  final int? imageHeightPx;
  final ReferenceSuggestion? suggestion;

  const ScanFlowArgs({
    this.sessionId,
    this.goal = ScanGoal.weightAndHealth,
    this.reference,
    this.imagePath,
    this.imageWidthPx,
    this.imageHeightPx,
    this.suggestion,
  });

  ScanFlowArgs copyWith({
    String? sessionId,
    ScanGoal? goal,
    ReferenceSelection? reference,
    String? imagePath,
    int? imageWidthPx,
    int? imageHeightPx,
    ReferenceSuggestion? suggestion,
    bool clearReference = false,
    bool clearSuggestion = false,
  }) {
    return ScanFlowArgs(
      sessionId: sessionId ?? this.sessionId,
      goal: goal ?? this.goal,
      reference: clearReference ? null : reference ?? this.reference,
      imagePath: imagePath ?? this.imagePath,
      imageWidthPx: imageWidthPx ?? this.imageWidthPx,
      imageHeightPx: imageHeightPx ?? this.imageHeightPx,
      suggestion: clearSuggestion ? null : suggestion ?? this.suggestion,
    );
  }
}
