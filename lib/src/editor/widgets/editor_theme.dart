import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:just_inputs/just_inputs.dart';

/// The colours the Input Actions editor is drawn in.
///
/// Its own type, so the editor runs without the host; the host hands it its
/// palette ([InputEditorTheme.palette]) so an input editor opened inside it
/// matches — the same surfaces, the same lines, the accent the user picked.
@immutable
class InputEditorPalette {
  const InputEditorPalette({
    required this.background,
    required this.panel,
    required this.panelRaised,
    required this.field,
    required this.border,
    required this.workArea,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.selected,
    required this.danger,
    required this.warning,
    required this.ok,
  });

  /// What the editor looks like on its own: the host's classic palette.
  static const InputEditorPalette standalone = InputEditorPalette(
    background: Color(0xFF161414),
    panel: Color(0xFF1C1919),
    panelRaised: Color(0xFF262020),
    field: Color(0xFF0A0909),
    border: Color(0xFF3A2C2C),
    workArea: Color(0xFF0F0D0D),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF999999),
    accent: Color(0xFFFF9C98),
    selected: Color(0xFF3D1A1A),
    danger: Color(0xFFE54B4B),
    warning: Color(0xFFFFD660),
    ok: Color(0xFF7DE6B1),
  );

  /// Behind everything: the editor's window.
  final Color background;

  /// The panels: maps, properties, the bars.
  final Color panel;

  /// What sits on a panel: a step's card, a menu.
  final Color panelRaised;

  /// Inside a text field.
  final Color field;

  /// Lines between things.
  final Color border;

  /// Behind the keyboard, pad and phone pictures.
  final Color workArea;

  /// Text.
  final Color text;

  /// Text that says less: hints, labels.
  final Color textMuted;

  /// What is chosen or active, and the host's accent.
  final Color accent;

  /// Behind a selected row.
  final Color selected;

  /// Errors and deleting.
  final Color danger;

  /// Warnings: a shared control, an unknown value.
  final Color warning;

  /// What worked: a performed action.
  final Color ok;
}

/// The Input Actions editor's colours and text styles, read from [palette].
abstract final class InputEditorTheme {
  /// Set by the host to match it.
  static InputEditorPalette palette = InputEditorPalette.standalone;

  static Color get background => palette.background;
  static Color get panel => palette.panel;
  static Color get panelRaised => palette.panelRaised;
  static Color get field => palette.field;
  static Color get border => palette.border;
  static Color get workArea => palette.workArea;

  static Color get text => palette.text;
  static Color get textMuted => palette.textMuted;
  static Color get accent => palette.accent;
  static Color get selected => palette.selected;
  static const Color hover = Color(0x14FFFFFF);
  static Color get danger => palette.danger;
  static Color get warning => palette.warning;
  static Color get ok => palette.ok;

  static TextStyle get label => TextStyle(color: textMuted, fontSize: 10);
  static TextStyle get body => TextStyle(color: text, fontSize: 12);
  static TextStyle get bodyMuted => TextStyle(color: textMuted, fontSize: 12);
  static TextStyle get mono =>
      TextStyle(color: text, fontSize: 11, fontFamily: 'monospace');
  static TextStyle get heading => TextStyle(
    color: textMuted,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// A colour per action, for tinting the keys it uses — the same action,
  /// the same colour, wherever it shows.
  static Color actionColour(String actionId) {
    final i = _order[actionId] ?? actionId.hashCode.abs();
    return _palette[i % _palette.length];
  }

  /// Each action's place in the asset, so colours go round the palette in
  /// order: neighbours in a map never share one, as a hash might make them.
  static Map<String, int> _order = const {};

  /// Takes the order of [asset]'s actions — the editor calls this whenever
  /// the asset changes.
  static void orderFrom(InputActionAsset asset) {
    final order = <String, int>{};
    for (final m in asset.maps) {
      // Each map starts the palette over: what one picture shows is one map.
      var i = 0;
      for (final a in m.actions) {
        order[a.id] = i++;
      }
    }
    _order = order;
  }

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

  static IconData typeIcon(ActionValueType type) => switch (type) {
    ActionValueType.button => Icons.radio_button_checked,
    ActionValueType.axis => Icons.linear_scale,
    ActionValueType.vector2 => Icons.open_with,
  };

  static IconData layoutIcon(String? layout) => switch (layout) {
    InputLayouts.keyboard => Icons.keyboard_outlined,
    InputLayouts.mouse => Icons.mouse_outlined,
    InputLayouts.gamepad => Icons.sports_esports_outlined,
    InputLayouts.touchscreen => Icons.touch_app_outlined,
    InputLayouts.onScreen => Icons.phone_iphone,
    _ => Icons.link_off,
  };
}

/// A small square button: an icon, a tooltip, lit when [active].
class EditorIconButton extends StatelessWidget {
  const EditorIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.size = 26,
    this.colour,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 400),
    child: Material(
      color: active ? InputEditorTheme.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            icon,
            size: size * 0.6,
            color: onTap == null
                ? InputEditorTheme.textMuted.withValues(alpha: 0.4)
                : active
                ? InputEditorTheme.accent
                : colour ?? InputEditorTheme.text,
          ),
        ),
      ),
    ),
  );
}

/// Fills the host with the editor, or puts it back in its dialog. Nothing
/// where the host offers no such choice.
class FullScreenToggle extends StatelessWidget {
  const FullScreenToggle({
    super.key,
    required this.fullScreen,
    required this.onToggle,
  });

  final ValueListenable<bool> fullScreen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: fullScreen,
    builder: (context, filled, _) => EditorIconButton(
      icon: filled ? Icons.fullscreen_exit : Icons.fullscreen,
      tooltip: filled ? 'Leave full screen' : 'Full screen',
      active: filled,
      onTap: onToggle,
    ),
  );
}

/// A panel's title row: the words, and whatever buttons it offers.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.only(left: 10, right: 4),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: InputEditorTheme.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: InputEditorTheme.heading,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...actions,
      ],
    ),
  );
}

/// A little rounded tag: `hold`, `Gamepad`.
class EditorTag extends StatelessWidget {
  const EditorTag(this.text, {super.key, this.colour});

  final String text;

  /// The tag's colour; the muted text colour when null.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final colour = this.colour ?? InputEditorTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: colour, fontSize: 9)),
    );
  }
}

/// A text field in the editor's look. Commits on Enter and when it loses
/// focus — Tab, a click elsewhere — not per key, so one rename is one undo
/// step. Esc puts back what was there.
class EditorTextField extends StatefulWidget {
  const EditorTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.hint = '',
    this.mono = false,
    this.autofocus = false,
    this.onChanged,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final ValueChanged<String>? onChanged;
  final String hint;
  final bool mono;
  final bool autofocus;

  @override
  State<EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<EditorTextField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  @override
  void didUpdateWidget(EditorTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  /// What was last handed to [EditorTextField.onCommit] — so Enter, which
  /// commits and then takes the focus away, commits once and not twice.
  String? _committed;

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final text = _text.text;
    if (text == widget.value || text == _committed) return;
    _committed = text;
    widget.onCommit(text);
    // Once the owner has rebuilt: a commit it refused (an empty name)
    // left its value as it was, and the field shows that again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _committed = null;
      if (mounted && !_focus.hasFocus && _text.text != widget.value) {
        _text.text = widget.value;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Esc, with a change typed: what was there, and out of the field. With
  /// nothing typed Esc is left to whoever wants it — a dialog closing.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final escape =
        event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
    if (!escape || _text.text == widget.value) {
      return KeyEventResult.ignored;
    }
    _text.text = widget.value;
    widget.onChanged?.call(widget.value);
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: _field(),
    ),
  );

  Widget _field() => TextField(
    controller: _text,
    focusNode: _focus,
    autofocus: widget.autofocus,
    onChanged: widget.onChanged,
    onSubmitted: (_) => _commit(),
    style: widget.mono ? InputEditorTheme.mono : InputEditorTheme.body,
    cursorColor: InputEditorTheme.accent,
    decoration: InputDecoration(
      isDense: true,
      hintText: widget.hint,
      hintStyle: InputEditorTheme.bodyMuted,
      filled: true,
      fillColor: InputEditorTheme.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: InputEditorTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: InputEditorTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: InputEditorTheme.accent),
      ),
    ),
  );
}

/// Asks for a line of text: a name. Null when canceled.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String initial = '',
  String action = 'OK',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: InputEditorTheme.panel,
      title: Text(title, style: InputEditorTheme.body.copyWith(fontSize: 13)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: InputEditorTheme.body,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(action),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// A menu at [position] of [items]; completes with the one picked.
Future<T?> showEditorMenu<T>(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<T>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    color: InputEditorTheme.panelRaised,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// A menu item with an icon, in the editor's text style.
PopupMenuItem<T> editorMenuItem<T>(
  T value,
  IconData icon,
  String label, {
  bool enabled = true,
}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  height: 32,
  child: Row(
    children: [
      Icon(
        icon,
        size: 15,
        color: enabled ? InputEditorTheme.text : InputEditorTheme.textMuted,
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: enabled ? InputEditorTheme.body : InputEditorTheme.bodyMuted,
      ),
    ],
  ),
);
