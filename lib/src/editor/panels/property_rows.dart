import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../look/input_editor_theme.dart';

/// A labelled row of the Properties panel: the label at the left, [child]
/// filling the rest.
@internal
class PropertyField extends StatelessWidget {
  /// A row called [label] holding [child].
  const PropertyField(this.label, this.child, {super.key});

  /// What the row is.
  final String label;

  /// Its field.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: InputEditorTheme.bodyMuted),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A tick box with its words, the whole row a target.
@internal
class PropertyToggle extends StatelessWidget {
  /// A box called [label], ticked by [value].
  const PropertyToggle(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
    this.hint = '',
  });

  /// What it switches.
  final String label;

  /// Whether it is ticked.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool> onChanged;

  /// Said on a hover.
  final String hint;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: hint,
    child: InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              height: 24,
              child: Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                activeColor: EditorTheme.primaryBright,
                checkColor: EditorTheme.dialogBg,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            Expanded(child: Text(label, style: InputEditorTheme.body)),
          ],
        ),
      ),
    ),
  );
}

/// The line between groups of rows.
@internal
class PropertyGap extends StatelessWidget {
  /// A line.
  const PropertyGap({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1, color: EditorTheme.borderStrong),
  );
}

/// [issue]'s icon and message, in its severity's colour.
@internal
class IssueLine extends StatelessWidget {
  /// The line for [issue].
  const IssueLine(this.issue, {super.key});

  /// What is wrong.
  final AssetIssue issue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          issue.isError ? Icons.error_outline : Icons.warning_amber_rounded,
          size: 14,
          color: issue.isError ? EditorTheme.error : EditorTheme.warning,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(issue.message, style: InputEditorTheme.body)),
      ],
    ),
  );
}

/// What is wrong with the thing shown, but not with one of its steps or
/// settings: those are said where they are edited.
@internal
class PropertyProblems extends StatelessWidget {
  /// The problems among [issues] that belong to no field.
  const PropertyProblems(this.issues, {super.key});

  /// Everything wrong with the thing shown.
  final List<AssetIssue> issues;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final i in issues)
        if (i.stepKind == null && i.param == null) i,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final i in shown) IssueLine(i)],
    );
  }
}

/// What the Properties panel says with nothing selected.
@internal
class PropertiesHelp extends StatelessWidget {
  /// The help.
  const PropertiesHelp({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Pick an action or a binding to change it.\n\n'
    'Maps are on the left — the tick says which are on when the game '
    'starts. Actions and their bindings are in the middle: + beside an '
    'action adds a binding, right-click for more.\n\n'
    'Below: the keyboard, a gamepad and a phone, to see what is bound '
    'where, and a live test to try it all.',
    style: InputEditorTheme.bodyMuted,
  );
}

/// A choice of [values], each shown as its label, the [selected] one lit.
@internal
class PropertySegments<T> extends StatelessWidget {
  /// Segments for [values] labelled by [labels].
  const PropertySegments({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  /// The choices, in order.
  final List<T> values;

  /// Each choice's words.
  final List<String> labels;

  /// The one chosen.
  final T selected;

  /// Called with the one picked.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: [
      for (var i = 0; i < values.length; i++)
        ButtonSegment(
          value: values[i],
          label: Text(labels[i], style: const TextStyle(fontSize: 11)),
        ),
    ],
    selected: {selected},
    onSelectionChanged: (v) => onChanged(v.single),
  );
}

/// [n] as a person writes it: `1`, `0.01` — no `1.0`.
@internal
String plainNumber(num n) =>
    n == n.roundToDouble() ? '${n.round()}' : n.toString();
