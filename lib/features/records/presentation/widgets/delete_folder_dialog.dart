import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/stacked_dialog_actions.dart';

/// docs/plan-6.md (round 6, pig folders): the result of the delete-folder dialog.
enum DeleteFolderChoice {
  /// The user cancelled, or dismissed the dialog, or backed out of the second
  /// confirmation for [folderAndRecords].
  cancelled,

  /// The folder goes; its pigs become ungrouped and keep their scans.
  folderOnly,

  /// The folder, its pigs, and all of those pigs' scans and results are deleted.
  folderAndRecords,
}

/// Shows the two-choice delete dialog for `folderName`. Picking "Delete folder and
/// records" asks a second, plainly-worded confirmation before returning that choice,
/// because it cannot be undone (docs/plan-6.md); every other path -- cancel, dismiss, or
/// backing out of the second confirmation -- returns [DeleteFolderChoice.cancelled].
Future<DeleteFolderChoice> showDeleteFolderDialog(
  BuildContext context,
  String folderName,
) async {
  final choice = await showDialog<DeleteFolderChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete "$folderName"?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'You can remove just the folder, or delete the folder along with its pigs '
            "and all of those pigs' scans and results.",
          ),
          const SizedBox(height: 16),
          StackedDialogActions(
            buttons: [
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, DeleteFolderChoice.folderOnly),
                child: const Text('Delete folder only'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.destructive,
                ),
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DeleteFolderChoice.folderAndRecords,
                ),
                child: const Text('Delete folder and records'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, DeleteFolderChoice.cancelled),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (choice != DeleteFolderChoice.folderAndRecords) {
    return choice ?? DeleteFolderChoice.cancelled;
  }
  if (!context.mounted) return DeleteFolderChoice.cancelled;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('This cannot be undone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This permanently deletes "$folderName", its pigs, and all of those pigs\' '
            'scans and results.',
          ),
          const SizedBox(height: 16),
          StackedDialogActions(
            buttons: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.destructive,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete everything'),
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
  );

  return confirmed == true
      ? DeleteFolderChoice.folderAndRecords
      : DeleteFolderChoice.cancelled;
}
