import 'package:flutter/material.dart';

/// docs/plan-6.md (round 6, pig folders): the name dialog shared by "New folder" and
/// "Rename folder". Returns the trimmed name, or null if the user cancelled, dismissed
/// the dialog, or entered a blank name.
Future<String?> showFolderNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _FolderNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
    ),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Owns its `TextEditingController` for its own `State`'s lifetime, so it is disposed
/// when the dialog's route is actually removed from the tree -- after its exit
/// transition finishes -- rather than synchronously when `showDialog`'s future resolves.
/// Disposing it there raced the dialog's still-animating close: the transition's last
/// frame or two rebuilt the `TextField` against an already-disposed controller and threw
/// "A TextEditingController was used after being disposed."
class _FolderNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initialName;

  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
  });

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
