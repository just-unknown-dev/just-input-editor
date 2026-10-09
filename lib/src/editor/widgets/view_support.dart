import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/input_editor_session.dart';
import 'editor_theme.dart';

/// One use of a control: which action, through which binding (or part).
final class ControlUse {
  const ControlUse(
    this.actionId,
    this.actionName,
    this.mapName,
    this.bindingId,
  );

  final String actionId;
  final String actionName;
  final String mapName;
  final String bindingId;
}

/// Every control of [layout] the asset uses, and by what — in the map
/// shown, or in every map. Keys are control names: `space`, `buttonSouth`.
Map<String, List<ControlUse>> controlUses(
  InputActionAsset asset,
  String layout, {
  String? mapId,
  String? group,
}) {
  final out = <String, List<ControlUse>>{};
  void add(ControlPath? path, ControlUse use) {
    if (path == null || path.layout != layout) return;
    (out[path.control] ??= []).add(use);
  }

  for (final ref in asset.actions) {
    if (mapId != null && ref.map.id != mapId) continue;
    for (final b in ref.action.bindings) {
      if (!b.inGroup(group)) continue;
      switch (b) {
        case ControlBindingDef():
          add(
            b.control,
            ControlUse(ref.action.id, ref.action.name, ref.map.name, b.id),
          );
        case CompositeBindingDef():
          for (final p in b.parts) {
            add(
              p.control,
              ControlUse(ref.action.id, ref.action.name, ref.map.name, p.id),
            );
          }
      }
    }
  }
  return out;
}

/// The uses of [control] and of everything under it — the whole stick for
/// `leftStick`, with its directions.
List<ControlUse> usesUnder(
  Map<String, List<ControlUse>> uses,
  String control,
) => [
  for (final e in uses.entries)
    if (e.key == control || e.key.startsWith('$control/')) ...e.value,
];

/// The controls (of [layout]) the selection is bound to: outlined in the
/// pictures.
Set<String> selectedControls(InputEditorSession s, String layout) {
  final ids = switch (s.selection) {
    BindingSelection(:final id) => {id},
    ActionSelection(:final id) => {
      for (final u in controlUses(s.asset, layout).values.expand((l) => l))
        if (u.actionId == id) u.bindingId,
    },
    _ => const <String>{},
  };
  return {
    for (final e in controlUses(s.asset, layout).entries)
      if (e.value.any((u) => ids.contains(u.bindingId))) e.key,
  };
}

/// The group of the first scheme that uses [layout], for a binding made by
/// clicking that device's picture.
String? groupFor(InputActionAsset asset, String layout) {
  for (final s in asset.schemes) {
    if (s.layouts.contains(layout)) return s.group;
  }
  return null;
}

/// What the selection wants a click on a two-axis control to bind: the
/// whole thing for a vector, one direction for a composite's part named
/// for one, else null (a button: the caller decides).
({bool vector, String? direction}) selectionWants(InputEditorSession s) {
  const directions = {'up', 'down', 'left', 'right'};
  return switch (s.selection) {
    BindingSelection(:final id) => switch (s.asset.findBinding(id)) {
      final ref? => (
        vector: ref.part == null && ref.action.type == ActionValueType.vector2,
        direction: directions.contains(ref.part?.part) ? ref.part!.part : null,
      ),
      null => (vector: false, direction: null),
    },
    ActionSelection(:final id) => (
      vector: s.asset.actionById(id)?.action.type == ActionValueType.vector2,
      direction: null,
    ),
    _ => (vector: false, direction: null),
  };
}

/// Whether a click would bind — an action or a binding is selected.
bool canBindFromPicture(InputEditorSession s) =>
    s.selection is ActionSelection || s.selection is BindingSelection;

/// Binds [path] from a click on a device's picture: into the selected
/// binding or part, or as a new binding of the selected action.
void bindFromPicture(InputEditorSession s, String path, String layout) {
  switch (s.selection) {
    case BindingSelection(:final id):
      final ref = s.asset.findBinding(id);
      if (ref == null) return;
      if (ref.part == null && ref.binding is CompositeBindingDef) {
        s.say('Pick one of the composite\'s parts first.');
        return;
      }
      s.edit('Bind control', (a) => AssetEdits.setPath(a, id, path));
    case ActionSelection(:final id):
      final group = s.schemeFilter ?? groupFor(s.asset, layout);
      final newId = s.create(
        'Add binding',
        (a) => AssetEdits.addBinding(a, id, path: path, groups: [?group]),
      );
      s.select(BindingSelection(newId));
    default:
      s.say('Select an action or a binding, then click to bind it.');
  }
}

/// A control drawn like a key: tinted by the action it drives, edged red
/// where two actions share it, outlined where the selection is bound — the
/// look every device picture shares.
class ControlCap extends StatelessWidget {
  const ControlCap({
    super.key,
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

  final String label;

  /// Uses in the map shown — these tint it.
  final List<ControlUse> uses;

  /// Uses in other maps — told, not tinted.
  final List<ControlUse> elsewhere;

  final VoidCallback onTap;
  final bool picked;
  final bool round;
  final double? width;
  final double? height;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final actions = {for (final u in uses) u.actionId};
    final colour = actions.isEmpty
        ? null
        : InputEditorTheme.actionColour(actions.first);
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
                  colour?.withValues(alpha: 0.35) ??
                  (elsewhere.isNotEmpty
                      ? InputEditorTheme.panelRaised
                      : InputEditorTheme.panel),
              borderRadius: radius,
              border: Border.all(
                color: picked
                    ? InputEditorTheme.text
                    : shared
                    ? InputEditorTheme.danger
                    : colour ?? InputEditorTheme.border,
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
                  color: colour != null
                      ? InputEditorTheme.text
                      : InputEditorTheme.textMuted,
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
class ActionLegend extends StatelessWidget {
  const ActionLegend({super.key, required this.session, required this.hint});

  final InputEditorSession session;
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
                    color: InputEditorTheme.actionColour(a.id),
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
