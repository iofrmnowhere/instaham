import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/models/folder_pig.dart';
import '../../../../core/models/folder_summary.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../../core/widgets/folder_name_dialog.dart';
import '../../../../core/widgets/folders_scope.dart';
import '../../../../core/widgets/stacked_dialog_actions.dart';
import '../widgets/delete_folder_dialog.dart';
import '../widgets/folder_summary_card.dart';

/// docs/plan-6.md (round 6, pig folders): one folder's detail screen -- its summary card,
/// its pigs (each with its latest weight or "No weight yet"), and folder-level actions.
class FolderDetailScreen extends StatelessWidget {
  final String folderId;

  const FolderDetailScreen({super.key, required this.folderId});

  Future<void> _rename(BuildContext context, String currentName) async {
    final repository = FoldersScope.of(context);
    final name = await showFolderNameDialog(
      context,
      title: 'Rename folder',
      confirmLabel: 'Save',
      initialName: currentName,
    );
    if (name == null) return;
    await repository.renameFolder(folderId, name);
  }

  Future<void> _delete(BuildContext context, String folderName) async {
    final repository = FoldersScope.of(context);
    final choice = await showDeleteFolderDialog(context, folderName);
    if (choice == DeleteFolderChoice.cancelled) return;
    await repository.deleteFolder(
      folderId,
      includeRecords: choice == DeleteFolderChoice.folderAndRecords,
    );
    if (context.mounted) context.pop();
  }

  Future<void> _addPigs(BuildContext context) async {
    final repository = FoldersScope.of(context);
    final ungrouped = await repository.watchUngroupedPigs().first;
    if (!context.mounted) return;
    if (ungrouped.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ungrouped pigs to add.')),
      );
      return;
    }
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add pigs'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ungrouped.length,
                  itemBuilder: (context, index) {
                    final pig = ungrouped[index];
                    final label = _pigLabel(pig);
                    return CheckboxListTile(
                      value: selected.contains(pig.id),
                      title: Text(label),
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked ?? false) {
                            selected.add(pig.id);
                          } else {
                            selected.remove(pig.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              StackedDialogActions(
                buttons: [
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Add'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;
    for (final pigId in selected) {
      await repository.setPigFolder(pigId, folderId);
    }
  }

  Future<void> _removePig(BuildContext context, String pigId) async {
    await FoldersScope.of(context).setPigFolder(pigId, null);
  }

  /// fix-8.md F76: shows both the auto ID and the display name, since one record per pig
  /// (F74) means several pigs may now share a name (for example several "Bella"s).
  String _pigLabel(Pig pig) {
    final tag = pig.tag?.trim();
    final name = pig.displayName?.trim();
    final id = (tag != null && tag.isNotEmpty) ? tag : 'Pig ${pig.id}';
    if (name != null && name.isNotEmpty) return '$id · $name';
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final repository = FoldersScope.of(context);

    return StreamBuilder<List<FolderSummary>>(
      stream: repository.watchFolders(),
      builder: (context, folderSnapshot) {
        final summary = folderSnapshot.data
            ?.where((f) => f.folder.id == folderId)
            .firstOrNull;

        if (folderSnapshot.hasData && summary == null) {
          // The folder was deleted (for example from another screen) while this one was
          // open. There is nothing left to show.
          return AppScaffold(
            currentPath: AppRoutes.records,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This folder no longer exists.',
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ),
          );
        }

        return AppScaffold(
          currentPath: AppRoutes.records,
          header: Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to folders',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: Text(
                    summary?.folder.name ?? '',
                    style: AppTextStyles.headline.copyWith(fontSize: 20),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Rename folder',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: summary == null
                      ? null
                      : () => _rename(context, summary.folder.name),
                ),
                IconButton(
                  tooltip: 'Delete folder',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: summary == null
                      ? null
                      : () => _delete(context, summary.folder.name),
                ),
              ],
            ),
          ),
          child: summary == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    FolderSummaryCard(summary: summary),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pigs',
                          style: AppTextStyles.label.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _addPigs(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add pigs'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<FolderPig>>(
                      stream: repository.watchFolderPigs(folderId),
                      builder: (context, pigsSnapshot) {
                        final pigs = pigsSnapshot.data ?? const [];
                        if (pigs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No pigs in this folder yet.',
                              style: AppTextStyles.subtext.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: pigs
                              .map(
                                (folderPig) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _FolderPigTile(
                                    folderPig: folderPig,
                                    onRemove: () =>
                                        _removePig(context, folderPig.pig.id),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _FolderPigTile extends StatelessWidget {
  final FolderPig folderPig;
  final VoidCallback onRemove;

  const _FolderPigTile({required this.folderPig, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final pig = folderPig.pig;
    final name = pig.displayName?.trim();
    final tag = pig.tag?.trim();
    final label = (name != null && name.isNotEmpty)
        ? name
        : (tag != null && tag.isNotEmpty ? tag : 'Pig ${pig.id}');
    final weightLabel = folderPig.latestWeightKg == null
        ? 'No weight yet'
        : '${folderPig.latestWeightKg!.toStringAsFixed(1)} kg';

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  weightLabel,
                  style: AppTextStyles.subtext.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove from folder',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
