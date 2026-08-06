import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/app_database.dart';
import '../database/database_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/widgets/app_card.dart';
import '../theme/widgets/app_scaffold.dart';

class PrivacyScreen extends StatefulWidget {
  final bool isFirstScan;

  const PrivacyScreen({super.key, this.isFirstScan = false});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  AppDatabase? _database;
  bool _researchSharing = false;
  bool _usageAnalytics = false;
  String _inferenceMode = 'undecided';
  bool _loading = true;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_database != null) return;
    _database = DatabaseScope.of(context);
    _load();
  }

  Future<void> _load() async {
    final preferences = await _database!.getPrivacyPreferences();
    if (!mounted) return;
    setState(() {
      _researchSharing = preferences.researchImageSharing;
      _usageAnalytics = preferences.usageAnalytics;
      _inferenceMode = preferences.inferenceMode;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _database!.savePrivacyPreferences(
      researchImageSharing: _researchSharing,
      usageAnalytics: _usageAnalytics,
      inferenceMode: _inferenceMode,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.isFirstScan) {
      context.go('/capture');
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Privacy settings saved.')));
    }
  }

  Future<void> _deleteAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all local records?'),
        content: const Text(
          'This permanently removes saved pigs, scan sessions, reference annotations, results, and pending sync items from this device. Privacy preferences are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete records'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _database!.deleteAllUserRecords();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All local records were deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: !widget.isFirstScan,
      currentPath: '/privacy',
      header: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            if (widget.isFirstScan)
              IconButton(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.close),
              )
            else
              const SizedBox(width: 8),
            Text(
              'Privacy & data',
              style: AppTextStyles.headline.copyWith(fontSize: 20),
            ),
          ],
        ),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.isFirstScan) ...[
                  const Icon(
                    Icons.shield_outlined,
                    size: 44,
                    color: AppColors.signalPink,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose what you share',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline.copyWith(fontSize: 21),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Optional sharing is off by default. You can scan without agreeing to research or analytics.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtext.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                AppCard(
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _researchSharing,
                    activeTrackColor: AppColors.signalPink,
                    onChanged: (value) =>
                        setState(() => _researchSharing = value),
                    title: Text(
                      'Research image sharing',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Allow captured images to be uploaded for future model improvement. This is never required for local scanning.',
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _usageAnalytics,
                    activeTrackColor: AppColors.signalPink,
                    onChanged: (value) =>
                        setState(() => _usageAnalytics = value),
                    title: Text(
                      'Usage analytics',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Share app interaction and performance events. Scan images and model outputs are excluded unless separately authorized.',
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inference location',
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This setting records the deployment decision. Server and hybrid modes must disclose retention before activation.',
                        style: AppTextStyles.subtext.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _inferenceMode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'undecided',
                            child: Text('Not configured'),
                          ),
                          DropdownMenuItem(
                            value: 'on_device',
                            child: Text('Fully on-device'),
                          ),
                          DropdownMenuItem(
                            value: 'server',
                            child: Text('Server processing'),
                          ),
                          DropdownMenuItem(
                            value: 'hybrid',
                            child: Text('Hybrid processing'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _inferenceMode = value ?? 'undecided',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  backgroundColor: AppColors.pinkTint,
                  border: Border.all(
                    color: AppColors.signalPink.withValues(alpha: 0.25),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.storage_outlined,
                        color: AppColors.signalPink,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Scan records are stored in the app local database. A future backend must use the sync outbox and honor these choices; it must not upload images silently.',
                          style: AppTextStyles.subtext,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.isFirstScan
                              ? 'Save and open camera'
                              : 'Save settings',
                        ),
                ),
                if (!widget.isFirstScan) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Local data',
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _deleteAllRecords,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete all local records'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.destructive,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
