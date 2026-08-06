import 'package:go_router/go_router.dart';

import '../screens/main_screen.dart';
import '../screens/privacy_screen.dart';
import '../../features/capture/presentation/screens/capture_guidance_screen.dart';
import '../../features/capture/presentation/screens/capture_screen.dart';
import '../../features/results/presentation/screens/results_screen.dart';
import '../../features/weight_estimation/presentation/screens/reference_marking_screen.dart';
import '../../features/records/presentation/screens/records_screen.dart';
import '../models/scan_flow.dart';
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
        builder: (context, state) => CaptureScreen(
          initialArgs: state.extra is ScanFlowArgs
              ? state.extra! as ScanFlowArgs
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.captureGuidance,
        builder: (context, state) => const CaptureGuidanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.analysis,
        builder: (context, state) => ResultsScreen(
          args: state.extra is ScanFlowArgs
              ? state.extra! as ScanFlowArgs
              : const ScanFlowArgs(),
        ),
      ),
      GoRoute(
        path: AppRoutes.health,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.measurements,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.records,
        builder: (context, state) => const RecordsScreen(),
      ),
      GoRoute(
        path: AppRoutes.referenceMarking,
        builder: (context, state) => ReferenceMarkingScreen(
          args: state.extra is ScanFlowArgs
              ? state.extra! as ScanFlowArgs
              : const ScanFlowArgs(),
        ),
      ),
      GoRoute(
        path: AppRoutes.analytics,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.rejectResult,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.skipWeight,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.uncertainResult,
        redirect: (context, state) => AppRoutes.records,
      ),
      GoRoute(
        path: AppRoutes.weightBlocked,
        redirect: (context, state) => AppRoutes.records,
      ),
    ],
  );
}
