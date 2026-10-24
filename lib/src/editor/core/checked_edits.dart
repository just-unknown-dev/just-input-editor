import 'package:just_inputs/just_inputs.dart';

import 'asset_edits.dart';
import 'input_editor_session.dart';
import 'input_references.dart';

/// The edits that take a name away from the game — renaming, moving and
/// deleting actions and maps — the way every panel makes them: a name that
/// cannot be one is said and nothing changes; then, if the project names
/// what is going, the author is asked first ([InputEditorSession.mayBreak]).
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
    final query = InputReferenceQuery.action(s.asset, id);
    if (!await s.mayBreak('Rename "$current" to "$name"', query)) return;
    s.edit('Rename action', (a) => AssetEdits.renameAction(a, id, name));
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
    final query = InputReferenceQuery.mapRename(s.asset, mapId);
    if (!await s.mayBreak('Rename the map "$current" to "$name"', query)) {
      return;
    }
    s.edit('Rename map', (a) => AssetEdits.renameMap(a, mapId, name));
  }

  /// Deletes the action [id].
  static Future<void> deleteAction(InputEditorSession s, String id) async {
    final name = s.asset.actionById(id)?.action.name;
    if (name == null) return;
    final query = InputReferenceQuery.action(s.asset, id);
    if (!await s.mayBreak('Delete "$name"', query)) return;
    s.edit('Delete action', (a) => AssetEdits.deleteAction(a, id));
  }

  /// Deletes the map [mapId], its actions with it.
  static Future<void> deleteMap(InputEditorSession s, String mapId) async {
    final name = s.asset.mapById(mapId)?.name;
    if (name == null) return;
    final query = InputReferenceQuery.mapDelete(s.asset, mapId);
    if (!await s.mayBreak('Delete the map "$name"', query)) return;
    s.edit('Delete map', (a) => AssetEdits.deleteMap(a, mapId));
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
    final query = InputReferenceQuery.move(s.asset, id, renamed: renamed);
    if (!await s.mayBreak('Move "${ref.path}" to "${target.name}"', query)) {
      return;
    }
    s.edit(
      'Move action to ${target.name}',
      (a) => AssetEdits.moveAction(
        a,
        id,
        toMapId: toMapId,
        index: a.mapById(toMapId)?.actions.length ?? 0,
      ),
    );
  }
}
