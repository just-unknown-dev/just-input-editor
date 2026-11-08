import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/session.dart';

/// One use of a control: which action, through which binding (or part).
@internal
final class ControlUse {
  /// [actionName] of [mapName] uses the control through [bindingId].
  const ControlUse(
    this.actionId,
    this.actionName,
    this.mapName,
    this.bindingId,
  );

  /// The action's id.
  final String actionId;

  /// The action's name.
  final String actionName;

  /// Its map's name.
  final String mapName;

  /// The binding or part that names the control.
  final String bindingId;
}

/// What [controlUses] worked out, per asset: an asset never changes, so
/// what it uses never does either, and the pictures ask for the same
/// answer several times a build — every pointer move of a drag. Weak: it
/// goes with its asset.
final Expando<_UsesByQuery> _uses = Expando('control uses');

/// [controlUses]' answers for one asset, by (layout, map, group).
typedef _UsesByQuery =
    Map<(String, String?, String?), Map<String, List<ControlUse>>>;

/// Every control of [layout] the asset uses, and by what — in the map
/// shown, or in every map. Keys are control names: `space`, `buttonSouth`.
/// The answer is shared: copy it to change it.
@internal
Map<String, List<ControlUse>> controlUses(
  InputActionAsset asset,
  String layout, {
  String? mapId,
  String? group,
}) => (_uses[asset] ??= {})[(layout, mapId, group)] ??= _find(
  asset,
  layout,
  mapId,
  group,
);

Map<String, List<ControlUse>> _find(
  InputActionAsset asset,
  String layout,
  String? mapId,
  String? group,
) {
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
  return Map.unmodifiable({
    for (final MapEntry(:key, :value) in out.entries)
      key: List<ControlUse>.unmodifiable(value),
  });
}

/// The uses of [control] and of everything under it — the whole stick for
/// `leftStick`, with its directions.
@internal
List<ControlUse> usesUnder(
  Map<String, List<ControlUse>> uses,
  String control,
) => [
  for (final e in uses.entries)
    if (e.key == control || e.key.startsWith('$control/')) ...e.value,
];

/// The controls (of [layout]) the selection is bound to: outlined in the
/// pictures.
@internal
Set<String> selectedControls(InputEditorSession s, String layout) {
  final uses = controlUses(s.asset, layout);
  final ids = switch (s.selection) {
    BindingSelection(:final id) => {id},
    ActionSelection(:final id) => {
      for (final u in uses.values.expand((l) => l))
        if (u.actionId == id) u.bindingId,
    },
    _ => const <String>{},
  };
  return {
    for (final e in uses.entries)
      if (e.value.any((u) => ids.contains(u.bindingId))) e.key,
  };
}

/// The group of the first scheme that uses [layout], for a binding made by
/// clicking that device's picture.
@internal
String? groupFor(InputActionAsset asset, String layout) {
  for (final s in asset.schemes) {
    if (s.layouts.contains(layout)) return s.group;
  }
  return null;
}

/// What the selection wants a click on a two-axis control to bind: the
/// whole thing for a vector, one direction for a composite's part named
/// for one, else null (a button: the caller decides).
@internal
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
@internal
bool canBindFromPicture(InputEditorSession s) =>
    s.selection is ActionSelection || s.selection is BindingSelection;

/// Binds [path] from a click on a device's picture: into the selected
/// binding or part, or as a new binding of the selected action.
@internal
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
