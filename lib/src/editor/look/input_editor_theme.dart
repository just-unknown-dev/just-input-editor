import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorTheme;
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';

/// What only the Input Actions editor draws: a colour per action, the icons
/// for an action's type and a control's device, and its text styles. Every
/// other colour is the host's, read from [EditorTheme] — so the editor
/// follows the accent and the accessibility settings the user picked.
@internal
abstract final class InputEditorTheme {
  /// Small print: a label, a count, a hint under a field.
  static TextStyle get label =>
      TextStyle(color: EditorTheme.textMuted, fontSize: 10);

  /// Ordinary text: names and values.
  static TextStyle get body =>
      TextStyle(color: EditorTheme.textPrimary, fontSize: 12);

  /// Text that says less: a field's label, a hint.
  static TextStyle get bodyMuted =>
      TextStyle(color: EditorTheme.textMuted, fontSize: 12);

  /// A path or a group name, as the file holds it.
  static TextStyle get mono => TextStyle(
    color: EditorTheme.textPrimary,
    fontSize: 11,
    fontFamily: 'monospace',
  );

  /// The caption over a group of fields: `SCHEMES`, `PARTS`.
  static TextStyle get heading => TextStyle(
    color: EditorTheme.textMuted,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// The colour of the action [actionId] in [session], for tinting the
  /// keys it uses — the same action, the same colour, wherever it shows.
  /// The actions of a map take the colours in turn
  /// ([InputEditorSession.colorIndexOf]).
  static Color actionColor(InputEditorSession session, String actionId) =>
      _palette[session.colorIndexOf(actionId) % _palette.length];

  static const List<Color> _palette = [
    Color(0xFFFF9C98),
    Color(0xFF7DB8FF),
    Color(0xFF7DE6B1),
    Color(0xFFFFC86B),
    Color(0xFFC39BFF),
    Color(0xFF6FE3E8),
    Color(0xFFFF9BD3),
    Color(0xFFB8E36B),
  ];

  /// The icon for an action of [type].
  static IconData typeIcon(ActionValueType type) => switch (type) {
    ActionValueType.button => Icons.radio_button_checked,
    ActionValueType.axis => Icons.linear_scale,
    ActionValueType.vector2 => Icons.open_with,
  };

  /// The icon for a control on a [layout]; a broken link for none.
  static IconData layoutIcon(String? layout) => switch (layout) {
    InputLayouts.keyboard => Icons.keyboard_outlined,
    InputLayouts.mouse => Icons.mouse_outlined,
    InputLayouts.gamepad => Icons.sports_esports_outlined,
    InputLayouts.touchscreen => Icons.touch_app_outlined,
    InputLayouts.onScreen => Icons.phone_iphone,
    _ => Icons.link_off,
  };
}
