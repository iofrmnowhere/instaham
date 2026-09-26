import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/folder_summary.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../../core/widgets/folder_name_dialog.dart';
import '../../../../core/widgets/folders_scope.dart';
import '../widgets/folder_summary_card.dart';

/// docs/plan-6.md (round 6, pig folders): the folders list, opened from the Records
/// screen's Folders button.
class FoldersListScreen extends StatelessWidget {
  const FoldersListScreen({super.key});

  Future<void> _createFolder(BuildContext context) async {
    final repository = FoldersScope.of(context);
    final name = await showFolderNameDialog(
      context,
      title: 'New folder',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    await repository.createFolder(name);
  }

  @override
  Widget build(BuildContext context) {
    final repository = FoldersScope.of(context);

    return AppScaffold(
      currentPath: AppRoutes.records,
      header: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Back to records',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            Text(
              'Folders',
              style: AppTextStyles.headline.copyWith(fontSize: 22),
            ),
            IconButton(
              tooltip: 'New folder',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => _createFolder(context),
            ),
          ],
        ),
      ),
      child: StreamBuilder<List<FolderSummary>>(
        stream: repository.watchFolders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final folders = snapshot.data!;
          if (folders.isEmpty) {
            return const _EmptyFolders();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: folders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final summary = folders[index];
              return FolderSummaryCard(
                summary: summary,
                onTap: () => context.push(
                  AppRoutes.recordsFolderDetailPath(summary.folder.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_outlined,
              size: 52,
              color: AppColors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              'No folders yet',
              style: AppTextStyles.headline.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a folder to group pigs and see their total and average weight.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtext.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
