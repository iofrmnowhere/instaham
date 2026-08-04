import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../theme/widgets/app_card.dart';
import '../theme/widgets/app_scaffold.dart';

class PrivacyScreen extends StatefulWidget {
  final bool isFirstScan;

  const PrivacyScreen({
    super.key,
    this.isFirstScan = false,
  });

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool consentAnonymized = true;
  bool consentTracking = false;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: !widget.isFirstScan,
      currentPath: '/privacy',
      header: !widget.isFirstScan
          ? Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => context.pop(),
                  ),
                  Text('Privacy & Consent', style: AppTextStyles.headline.copyWith(fontSize: 20)),
                ],
              ),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (widget.isFirstScan) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.signalPink.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: AppColors.signalPink),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('Privacy & Consent', style: AppTextStyles.headline.copyWith(fontSize: 22)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Before we start, we need your consent',
                style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Anonymized Data Consent Card
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: consentAnonymized,
                  activeColor: AppColors.signalPink,
                  onChanged: (val) => setState(() => consentAnonymized = val ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Allow Anonymized Image Use', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Help us improve accuracy by sharing anonymized scan images for model training',
                        style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Usage Tracking Card
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: consentTracking,
                  activeColor: AppColors.signalPink,
                  onChanged: (val) => setState(() => consentTracking = val ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Usage Analytics', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Allow us to collect usage data to improve the app experience',
                        style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Security Info
          AppCard(
            backgroundColor: AppColors.signalPink.withValues(alpha: 0.05),
            border: Border.all(color: AppColors.signalPink.withValues(alpha: 0.2)),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 20, color: AppColors.signalPink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your data is encrypted and stored securely. You can change these settings anytime in Settings.',
                    style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                'Read Our Privacy Policy',
                style: AppTextStyles.label.copyWith(color: AppColors.signalPink),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          if (widget.isFirstScan) ...[
            ElevatedButton(
              onPressed: () => context.go('/measurements'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.signalPink,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: const Text('I Agree & Start Scanning'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.go('/'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: const Text('Decline'),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => context.pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.signalPink,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.destructive,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: const Text('Delete All Records'),
            ),
          ],
        ],
      ),
    );
  }
}
