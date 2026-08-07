import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_error_state.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../domain/repositories/i_analytics_repository.dart';
import '../analytics_scope.dart';
import '../notifier/analytics_notifier.dart';
import '../widgets/health_panel.dart';
import '../widgets/weight_panel.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  IAnalyticsRepository? _currentRepository;
  AnalyticsNotifier? _notifier;
  String _selectedTab = 'weight';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = AnalyticsScope.of(context);
    if (_currentRepository != repository) {
      _currentRepository = repository;
      _notifier?.dispose();
      _notifier = AnalyticsNotifier(repository);
    }
  }

  @override
  void dispose() {
    _notifier?.dispose();
    super.dispose();
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
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'weight',
                    label: Text('Weight Analytics'),
                    icon: Icon(Icons.monitor_weight_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'health',
                    label: Text('Health Analytics'),
                    icon: Icon(Icons.health_and_safety_outlined),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (selection) {
                  setState(() => _selectedTab = selection.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 16.0),
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

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                  child: _selectedTab == 'weight'
                      ? WeightPanel(
                          data: state.weight,
                          timeSeries: state.weightTimeSeries,
                        )
                      : HealthPanel(
                          data: state.health,
                          classBars: state.healthClassBars,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
