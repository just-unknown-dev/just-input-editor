import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../asset/asset.dart';
import 'input_editor_selection.dart';
import 'input_editor_session.dart';

/// The renames, moves and deletes every panel makes the same way: a name
/// that cannot be one is said and nothing changes; then, for an edit that
/// takes a name away from the game (an action or a map), if the project
/// names what is going, the author is asked first
/// ([InputEditorSession.mayBreak]). While that is asked, the session
/// [InputEditorSession.isChecking], and a save or a close waits for it.
@internal
abstract final class CheckedEdits {
  /// Renames the action [id] to [typed], trimmed.
  static Future<void> renameAction(
    InputEditorSession s,
    String id,
    String typed,
  ) async {
    final name = typed.trim();
    final current = s.asset.actionById(id)?.action.name;
    if (current == null || name == current) return;
    final problem = AssetEdits.actionNameProblem(s.asset, id, name);
    if (problem != null) {
      s.say(problem);
      return;
    }
    await s.checked(
      'Rename "$current" to "$name"',
      InputReferenceQuery.action(s.asset, id),
      () =>
          s.edit('Rename action', (a) => AssetEdits.renameAction(a, id, name)),
    );
  }

  /// Renames the map [mapId] to [typed], trimmed.
  static Future<void> renameMap(
    InputEditorSession s,
    String mapId,
    String typed,
  ) async {
    final name = typed.trim();
    final current = s.asset.mapById(mapId)?.name;
    if (current == null || name == current) return;
    final problem = AssetEdits.mapNameProblem(s.asset, mapId, name);
    if (problem != null) {
      s.say(problem);
      return;
    }
    await s.checked(
      'Rename the map "$current" to "$name"',
      InputReferenceQuery.mapRename(s.asset, mapId),
      () => s.edit('Rename map', (a) => AssetEdits.renameMap(a, mapId, name)),
    );
  }

  /// Deletes the action [id].
  static Future<void> deleteAction(InputEditorSession s, String id) async {
    final name = s.asset.actionById(id)?.action.name;
    if (name == null) return;
    await s.checked(
      'Delete "$name"',
      InputReferenceQuery.action(s.asset, id),
      () => s.edit('Delete action', (a) => AssetEdits.deleteAction(a, id)),
    );
  }

  /// Deletes the map [mapId], its actions with it.
  static Future<void> deleteMap(InputEditorSession s, String mapId) async {
    final name = s.asset.mapById(mapId)?.name;
    if (name == null) return;
    await s.checked(
      'Delete the map "$name"',
      InputReferenceQuery.mapDelete(s.asset, mapId),
      () => s.edit('Delete map', (a) => AssetEdits.deleteMap(a, mapId)),
    );
  }

  /// Renames the on-screen control [id] to [typed], trimmed, and selects it
  /// under its new id. Every binding that named it follows. An id that is
  /// not a name, or that another control has, is said and refused: the
  /// bindings would name what no path can, or another control.
  static void renameOnScreen(InputEditorSession s, String id, String typed) {
    final next = typed.trim();
    if (next == id || s.asset.onScreenControl(id) == null) return;
    final problem = AssetEdits.onScreenIdProblem(s.asset, id, next);
    if (problem != null) {
      s.say(problem);
      return;
    }
    s.edit(
      'Rename on-screen control',
      (a) => AssetEdits.updateOnScreen(a, id, (x) => x.copyWith(id: next)),
    );
    s.select(OnScreenSelection(next));
  }

  /// Renames the scheme [name] to [typed], trimmed, and selects it under
  /// its new name; a name that is empty or taken is said and refused.
  static void renameScheme(InputEditorSession s, String name, String typed) {
    final next = typed.trim();
    if (next == name || s.asset.schemeNamed(name) == null) return;
    final problem = AssetEdits.schemeNameProblem(s.asset, name, next);
    if (problem != null) {
      s.say(problem);
      return;
    }
    s.edit(
      'Rename scheme',
      (a) => AssetEdits.updateScheme(a, name, (x) => x.copyWith(name: next)),
    );
    s.select(SchemeSelection(next));
  }

  /// Deletes the on-screen control [id]. The bindings that named it are
  /// left unbound, and how many is said.
  static void deleteOnScreen(InputEditorSession s, String id) {
    var named = 0;
    for (final ref in s.asset.actions) {
      for (final b in ref.action.bindings) {
        for (final path in switch (b) {
          ControlBindingDef(:final path) => [path],
          CompositeBindingDef(:final parts) => [for (final p in parts) p.path],
        }) {
          if (AssetEdits.namesOnScreen(path, id)) named++;
        }
      }
    }
    s.edit('Delete on-screen control', (a) => AssetEdits.deleteOnScreen(a, id));
    if (named > 0) {
      s.say(
        '$named binding${named == 1 ? '' : 's'} named "$id" '
        '${named == 1 ? 'is' : 'are'} unbound now.',
      );
    }
  }

  /// Moves the action [id] to the end of the map [toMapId]: its
  /// `map/action` path goes, and its name too when the map has one like it.
  static Future<void> moveActionToMap(
    InputEditorSession s,
    String id,
    String toMapId,
  ) async {
    final ref = s.asset.actionById(id);
    final target = s.asset.mapById(toMapId);
    if (ref == null || target == null || ref.map.id == toMapId) return;
    final renamed = target.actionNamed(ref.action.name) != null;
    await s.checked(
      'Move "${ref.path}" to "${target.name}"',
      InputReferenceQuery.move(s.asset, id, renamed: renamed),
      () => s.edit(
        'Move action to ${target.name}',
        (a) => AssetEdits.moveAction(
          a,
          id,
          toMapId: toMapId,
          index: a.mapById(toMapId)?.actions.length ?? 0,
        ),
      ),
    );
  }

  /// Changes the action [id]'s type, and says what went with the change:
  /// composites and processors of the wrong kind
  /// ([AssetEdits.changeActionType]).
  static void changeActionType(
    InputEditorSession s,
    String id,
    ActionValueType type,
  ) {
    final before = s.asset.actionById(id)?.action;
    if (before == null || before.type == type) return;
    s.edit('Change type', (a) => AssetEdits.changeActionType(a, id, type));
    final after = s.asset.actionById(id)?.action;
    if (after == null) return;
    // Processors of the bindings that stayed: a composite that went took
    // its own with it, and is counted as a composite.
    final kept = {for (final b in after.bindings) b.id};
    int processors(InputActionDef x) =>
        x.processors.length +
        x.bindings
            .where((b) => kept.contains(b.id))
            .fold(0, (n, b) => n + b.processors.length);
    final composites = before.bindings.length - after.bindings.length;
    final steps = processors(before) - processors(after);
    final gone = [
      if (composites > 0) '$composites composite${composites == 1 ? '' : 's'}',
      if (steps > 0) '$steps processor${steps == 1 ? '' : 's'}',
    ];
    if (gone.isNotEmpty) {
      s.say(
        '${gone.join(' and ')} of the wrong kind for a '
        '${type.name} went with the change.',
      );
    }
  }
}
