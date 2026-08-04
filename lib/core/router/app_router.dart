import 'package:go_router/go_router.dart';

import '../screens/main_screen.dart';
import '../screens/privacy_screen.dart';
import '../../features/capture/presentation/screens/capture_guidance_screen.dart';
import '../../features/capture/presentation/screens/capture_screen.dart';
import '../../features/results/presentation/screens/results_screen.dart';
import '../../features/results/presentation/screens/reject_result_screen.dart';
import '../../features/results/presentation/screens/skip_weight_screen.dart';
import '../../features/results/presentation/screens/uncertain_result_screen.dart';
import '../../features/results/presentation/screens/weight_blocked_screen.dart';
import '../../features/health_assessment/presentation/screens/health_history_screen.dart';
import '../../features/weight_estimation/presentation/screens/measurements_screen.dart';
import '../../features/weight_estimation/presentation/screens/reference_marking_screen.dart';
import '../../features/analytics/presentation/screens/analytics_screen.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: AppRoutes.capture,
        builder: (context, state) => const CaptureScreen(),
      ),
      GoRoute(
        path: AppRoutes.captureGuidance,
        builder: (context, state) => const CaptureGuidanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.analysis,
        builder: (context, state) => const ResultsScreen(),
      ),
      GoRoute(
        path: AppRoutes.health,
        builder: (context, state) => const HealthHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.measurements,
        builder: (context, state) => const MeasurementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.referenceMarking,
        builder: (context, state) => const ReferenceMarkingScreen(),
      ),
      GoRoute(
        path: AppRoutes.analytics,
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.rejectResult,
        builder: (context, state) => const RejectResultScreen(),
      ),
      GoRoute(
        path: AppRoutes.skipWeight,
        builder: (context, state) => const SkipWeightScreen(),
      ),
      GoRoute(
        path: AppRoutes.uncertainResult,
        builder: (context, state) => const UncertainResultScreen(),
      ),
      GoRoute(
        path: AppRoutes.weightBlocked,
        builder: (context, state) => const WeightBlockedScreen(),
      ),
    ],
  );
}
