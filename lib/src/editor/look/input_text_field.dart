import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show CommitTextField, editorFieldDecoration;
import 'package:meta/meta.dart';

import 'input_editor_theme.dart';

/// The kit's [CommitTextField] — it keeps what was typed on Enter or when
/// it is left, once, and Esc puts back what was there — for a value the
/// owner may refuse: an empty name, a taken one, a rename the author called
/// off. Once the owner has answered (after [onCommit]'s future, when it
/// returns one), the field shows the owner's [value] again, so a refused
/// edit never stays on screen as if it were kept.
@internal
class InputTextField extends StatefulWidget {
  /// A field showing [value]; [onCommit] gets what was typed.
  const InputTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.hint = '',
    this.mono = false,
  });

  /// What the owner holds.
  final String value;

  /// Called with the text typed, once per change. May return a future: a
  /// rename that first asks.
  final FutureOr<void> Function(String text) onCommit;

  /// Shown, muted, while the field is empty: what an empty value means.
  final String hint;

  /// Whether the text is a path or a group name, in a fixed-width face.
  final bool mono;

  @override
  State<InputTextField> createState() => _InputTextFieldState();
}

class _InputTextFieldState extends State<InputTextField> {
  final FocusNode _focus = FocusNode();

  /// Bumped to make the field afresh from [InputTextField.value].
  int _generation = 0;

  Future<void> _commit(String text) async {
    final answer = widget.onCommit(text);
    if (answer is Future<void>) await answer;
    if (!mounted) return;
    // Once the owner has rebuilt with what it kept.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus && widget.value != text) {
          setState(() => _generation++);
        }
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CommitTextField(
    key: ValueKey(_generation),
    value: widget.value,
    focusNode: _focus,
    onCommit: _commit,
    style: widget.mono ? InputEditorTheme.mono : InputEditorTheme.body,
    decoration: editorFieldDecoration(hint: widget.hint),
  );
}
