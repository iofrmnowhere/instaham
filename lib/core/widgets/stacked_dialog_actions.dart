import 'package:flutter/material.dart';

/// fix-8.md F76: a vertical stack of full-width, centred buttons for a dialog's choices.
/// `AlertDialog.actions` lays its children out in an end-aligned `OverflowBar`; each button
/// keeps its own (label-driven) width, and once three or more do not fit one row they wrap
/// into a right-aligned stack instead of a centred, readable one. This widget replaces that
/// row: it goes in the dialog's `content`, not its `actions`, and every button is at least
/// 44 logical pixels tall (AGENTS.md accessibility rule) and spans the full dialog width.
class StackedDialogActions extends StatelessWidget {
  final List<Widget> buttons;

  const StackedDialogActions({super.key, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SizedBox(height: 44, child: buttons[i]),
        ],
      ],
    );
  }
}
