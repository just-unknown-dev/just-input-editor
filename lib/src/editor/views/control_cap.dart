import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import 'control_uses.dart';

/// A control drawn like a key: tinted by the action it drives, edged red
/// where two actions share it, outlined where the selection is bound — the
/// look every device picture shares.
@internal
class ControlCap extends StatelessWidget {
  /// A cap reading [label], used by [uses] in the map shown.
  const ControlCap({
    super.key,
    required this.session,
    required this.label,
    required this.uses,
    required this.onTap,
    this.picked = false,
    this.elsewhere = const [],
    this.round = false,
    this.width,
    this.height,
    this.fontSize,
  });

  /// The session whose actions colour it.
  final InputEditorSession session;

  /// The control's face.
  final String label;

  /// Uses in the map shown — these tint it.
  final List<ControlUse> uses;

  /// Uses in other maps — told, not tinted.
  final List<ControlUse> elsewhere;

  /// A click: binds it.
  final VoidCallback onTap;

  /// Whether the selection is bound to it.
  final bool picked;

  /// A round button rather than a key.
  final bool round;

  /// Its size; what it is given when null.
  final double? width, height;

  /// Its face's size; 12 when null.
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final actions = {for (final u in uses) u.actionId};
    final color = actions.isEmpty
        ? null
        : InputEditorTheme.actionColor(session, actions.first);
    final shared = actions.length > 1;
    final radius = BorderRadius.circular(round ? 999 : 5);
    return Tooltip(
      message: [
        label,
        for (final u in uses) '${u.actionName} (${u.mapName})',
        for (final u in elsewhere) '${u.actionName} (${u.mapName})',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color:
                  color?.withValues(alpha: 0.35) ??
                  (elsewhere.isNotEmpty
                      ? EditorTheme.panelRaised
                      : EditorTheme.menuBg),
              borderRadius: radius,
              border: Border.all(
                color: picked
                    ? EditorTheme.textPrimary
                    : shared
                    ? EditorTheme.error
                    : color ?? EditorTheme.borderStrong,
                width: picked || shared ? 2 : 1,
              ),
            ),
            // Long names wrap and shrink rather than being cut off.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: color != null
                      ? EditorTheme.textPrimary
                      : EditorTheme.textMuted,
                  fontSize: fontSize ?? 12,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shown map's actions in their colours, and what a click does — the
/// strip under every device picture.
@internal
class ActionLegend extends StatelessWidget {
  /// The legend of [session]'s shown map, with [hint] at the right.
  const ActionLegend({super.key, required this.session, required this.hint});

  /// The session whose map it shows.
  final InputEditorSession session;

  /// What a click on the picture does.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final map = session.asset.mapById(session.selectedMapId ?? '');
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text('${map?.name ?? ''}:', style: InputEditorTheme.label),
          for (final a in map?.actions ?? const <InputActionDef>[])
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    color: InputEditorTheme.actionColor(session, a.id),
                  ),
                  const SizedBox(width: 4),
                  Text(a.name, style: InputEditorTheme.label),
                ],
              ),
            ),
          const Spacer(),
          Text(hint, style: InputEditorTheme.label),
        ],
      ),
    );
  }
}
