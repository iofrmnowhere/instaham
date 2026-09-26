abstract final class AppRoutes {
  static const String home = '/';
  static const String capture = '/capture';
  static const String captureGuidance = '/capture-guidance';
  static const String analysis = '/analysis';
  static const String health = '/health';
  static const String measurements = '/measurements';
  static const String records = '/records';
  // docs/plan-6.md (round 6, pig folders).
  static const String recordsFolders = '/records/folders';
  static const String recordsFolderDetail = '/records/folders/:id';
  static String recordsFolderDetailPath(String id) => '/records/folders/$id';
  static const String referenceMarking = '/reference-marking';
  static const String analytics = '/analytics';
  static const String privacy = '/privacy';

  // Inline result state routes
  static const String rejectResult = '/reject-result';
  static const String skipWeight = '/skip-weight';
  static const String uncertainResult = '/uncertain-result';
  static const String weightBlocked = '/weight-blocked';
}
