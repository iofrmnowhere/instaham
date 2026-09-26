import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/services/folder_weight_summary.dart';

void main() {
  group('latestEligibleWeightKg', () {
    test(
      'repeat scans of one pig: picks the newest eligible-with-value scan',
      () {
        final scans = [
          ScanWeightSample(
            createdAt: DateTime(2026, 1, 1),
            eligible: true,
            valueKg: 40.0,
          ),
          ScanWeightSample(
            createdAt: DateTime(2026, 2, 1),
            eligible: true,
            valueKg: 55.0,
          ),
          ScanWeightSample(
            createdAt: DateTime(2026, 1, 15),
            eligible: true,
            valueKg: 45.0,
          ),
        ];

        expect(latestEligibleWeightKg(scans), 55.0);
      },
    );

    test('falls back to createdAt when capturedAt is missing', () {
      final scans = [
        ScanWeightSample(
          capturedAt: DateTime(2026, 3, 1),
          createdAt: DateTime(2026, 1, 1),
          eligible: true,
          valueKg: 60.0,
        ),
        // No capturedAt (an old gallery photo, per docs/plan-6.md): falls back to
        // createdAt, which is earlier than the row above's capturedAt.
        ScanWeightSample(
          createdAt: DateTime(2026, 2, 1),
          eligible: true,
          valueKg: 70.0,
        ),
      ];

      expect(latestEligibleWeightKg(scans), 60.0);
    });

    test(
      'ineligible latest scan: an older eligible scan is used instead, not null',
      () {
        final scans = [
          ScanWeightSample(
            createdAt: DateTime(2026, 1, 1),
            eligible: true,
            valueKg: 42.0,
          ),
          // Newest by date, but ineligible -- "latest" means latest among eligible scans.
          ScanWeightSample(
            createdAt: DateTime(2026, 2, 1),
            eligible: false,
            valueKg: null,
          ),
        ];

        expect(latestEligibleWeightKg(scans), 42.0);
      },
    );

    test('eligible scan with no value is treated like an ineligible one', () {
      final scans = [
        ScanWeightSample(
          createdAt: DateTime(2026, 1, 1),
          eligible: true,
          valueKg: 30.0,
        ),
        ScanWeightSample(
          createdAt: DateTime(2026, 2, 1),
          eligible: true,
          valueKg: null,
        ),
      ];

      expect(latestEligibleWeightKg(scans), 30.0);
    });

    test('no weights at all: returns null', () {
      final scans = [
        ScanWeightSample(
          createdAt: DateTime(2026, 1, 1),
          eligible: false,
          valueKg: null,
        ),
      ];

      expect(latestEligibleWeightKg(scans), isNull);
      expect(latestEligibleWeightKg(const <ScanWeightSample>[]), isNull);
    });
  });

  group('summarizeFolderWeights', () {
    test('no weights at all: total and average are null, not zero', () {
      final summary = summarizeFolderWeights([null, null, null]);

      expect(summary.totalKg, isNull);
      expect(summary.averageKg, isNull);
      expect(summary.weighedCount, 0);
      expect(summary.totalCount, 3);
    });

    test('partial weights: total/average cover only the weighed pigs', () {
      final summary = summarizeFolderWeights([40.0, null, 60.0, null]);

      expect(summary.totalKg, 100.0);
      expect(summary.averageKg, 50.0);
      expect(summary.weighedCount, 2);
      expect(summary.totalCount, 4);
    });

    test('every pig weighed', () {
      final summary = summarizeFolderWeights([10.0, 20.0, 30.0]);

      expect(summary.totalKg, 60.0);
      expect(summary.averageKg, 20.0);
      expect(summary.weighedCount, 3);
      expect(summary.totalCount, 3);
    });

    test('empty folder: counts are zero, total/average null', () {
      final summary = summarizeFolderWeights(const <double?>[]);

      expect(summary.totalKg, isNull);
      expect(summary.averageKg, isNull);
      expect(summary.weighedCount, 0);
      expect(summary.totalCount, 0);
    });
  });
}
