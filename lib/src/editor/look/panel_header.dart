import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show EditorSectionHeader, EditorTheme;
import 'package:meta/meta.dart';

/// A panel's title row: the kit's [EditorSectionHeader] with whatever
/// buttons the panel offers at its right, over a line.
@internal
class PanelHeader extends StatelessWidget {
  /// The header [title], with [actions] at the right.
  const PanelHeader(this.title, {super.key, this.actions = const []});

  /// The panel's name, shown in capitals.
  final String title;

  /// Buttons at the right end: Add.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorTheme.borderStrong)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 30),
      child: EditorSectionHeader(
        title,
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
        trailing: actions.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    ),
  );
}
