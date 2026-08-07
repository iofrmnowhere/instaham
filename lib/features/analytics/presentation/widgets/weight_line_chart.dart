import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../domain/models/analytics_models.dart';

class WeightLineChart extends StatelessWidget {
  final List<WeightDataPoint> points;

  const WeightLineChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    if (points.length < 2) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weight Trend Over Time',
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Add at least 2 scans to view weight trends over time.',
                style: AppTextStyles.subtext.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sortedPoints = List<WeightDataPoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));

    final minKg = sortedPoints.map((p) => p.kg).reduce((a, b) => a < b ? a : b);
    final maxKg = sortedPoints.map((p) => p.kg).reduce((a, b) => a > b ? a : b);
    final paddingKg = ((maxKg - minKg) * 0.2).clamp(2.0, 10.0);

    final spots = sortedPoints.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.kg);
    }).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weight Trend Over Time',
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recorded weight (kg) across scans',
            style: AppTextStyles.subtext.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: (minKg - paddingKg).clamp(0, double.infinity),
                maxY: maxKg + paddingKg,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.card,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        if (index < 0 || index >= sortedPoints.length) {
                          return null;
                        }
                        final pt = sortedPoints[index];
                        final dateStr =
                            '${pt.date.month}/${pt.date.day}/${pt.date.year}';
                        return LineTooltipItem(
                          '${pt.kg.toStringAsFixed(1)} kg\n$dateStr',
                          AppTextStyles.label.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: AppColors.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(0),
                          style: AppTextStyles.subtext.copyWith(
                            color: AppColors.mutedForeground,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (sortedPoints.length / 4).clamp(1.0, 10.0),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= sortedPoints.length) {
                          return const SizedBox.shrink();
                        }
                        final date = sortedPoints[index].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            '${date.month}/${date.day}',
                            style: AppTextStyles.subtext.copyWith(
                              color: AppColors.mutedForeground,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppColors.signalPink,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius: 4,
                            color: AppColors.signalPink,
                            strokeWidth: 2,
                            strokeColor: AppColors.card,
                          ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.signalPink.withValues(alpha: 0.25),
                          AppColors.signalPink.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
