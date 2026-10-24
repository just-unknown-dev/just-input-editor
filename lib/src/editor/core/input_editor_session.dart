import 'package:flutter/foundation.dart';

import 'package:just_inputs/just_inputs.dart';

import 'input_references.dart';

/// What is selected in the Input Actions editor.
sealed class EditorSelection {
  const EditorSelection();
}

/// Nothing: the Properties panel shows how to begin.
final class NoSelection extends EditorSelection {
  const NoSelection();
}

/// An action, by id.
final class ActionSelection extends EditorSelection {
  const ActionSelection(this.id);

  /// The action's id.
  final String id;

  @override
  bool operator ==(Object other) => other is ActionSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A binding, or one part of a composite.
final class BindingSelection extends EditorSelection {
  const BindingSelection(this.id);

  /// The binding's or the part's id.
  final String id;

  @override
  bool operator ==(Object other) => other is BindingSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// An on-screen control, by id.
final class OnScreenSelection extends EditorSelection {
  const OnScreenSelection(this.id);

  /// The control's id — what bindings name: `<OnScreen>/id`.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is OnScreenSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A control scheme, by name.
final class SchemeSelection extends EditorSelection {
  const SchemeSelection(this.name);

  /// The scheme's name.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SchemeSelection && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// The players and the asset-wide settings.
final class SettingsSelection extends EditorSelection {
  const SettingsSelection();
}

final class _Step {
  const _Step(this.label, this.asset);
  final String label;
  final InputActionAsset asset;
}

/// The Input Actions editor's state: the asset being edited, its history,
/// what is selected and what is wrong with it.
///
/// History keeps whole assets — they are immutable, so a step costs a
/// reference, and undo is a swap.
class InputEditorSession extends ChangeNotifier {
  InputEditorSession(InputActionAsset asset, {this.path})
    : _asset = asset,
      _savedText = asset.encode() {
    _selectedMapId = asset.maps.firstOrNull?.id;
  }

  /// Where it is saved, project-relative; null for one never saved.
  String? path;

  /// Steps kept for undo.
  static const int maxUndo = 200;

  InputActionAsset _asset;

  /// The asset as it is now.
  InputActionAsset get asset => _asset;

  String _savedText;
  bool? _dirty;

  /// Something changed since it was loaded or last saved.
  ///
  /// Through a drag that has changed something it is so without comparing:
  /// the file is not written out again on every move.
  bool get isDirty {
    if (_gesture > 0 && _gestureRecorded) return true;
    return _dirty ??= _asset.encode() != _savedText;
  }

  /// Whether [asset] is what was loaded or last saved — a file that changed
  /// on disk only because this session wrote it.
  bool matchesSaved(InputActionAsset asset) => asset.encode() == _savedText;

  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  /// Whether there is a step to [undo].
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is a step to [redo].
  bool get canRedo => _redo.isNotEmpty;

  /// What [undo] would take back, for its tooltip.
  String? get undoLabel => _undo.lastOrNull?.label;

  /// What [redo] would do again.
  String? get redoLabel => _redo.lastOrNull?.label;

  int _gesture = 0;
  bool _gestureRecorded = false;

  /// Whether a drag is under way — [beginGesture] without its
  /// [endGesture] yet. Editing keys wait for it: a delete mid-drag would
  /// end up inside the drag's undo step.
  bool get inGesture => _gesture > 0;

  /// Everything until [endGesture] is one undo step — a drag.
  void beginGesture() {
    if (_gesture++ == 0) _gestureRecorded = false;
  }

  /// The drag is over; listeners hear of it once, for what they put off
  /// while it went on.
  void endGesture() {
    if (_gesture == 0 || _disposed) return;
    if (--_gesture > 0) return;
    _dirty = null;
    notifyListeners();
  }

  /// Makes [next] the asset, as one undoable step called [label].
  void apply(String label, InputActionAsset next) {
    if (identical(next, _asset)) return;
    if (_gesture == 0 || !_gestureRecorded) {
      _undo.add(_Step(label, _asset));
      if (_undo.length > maxUndo) _undo.removeAt(0);
      _gestureRecorded = _gesture > 0;
    }
    _redo.clear();
    _set(next);
  }

  /// [apply] of what [change] makes of the asset.
  void edit(
    String label,
    InputActionAsset Function(InputActionAsset asset) change,
  ) => apply(label, change(_asset));

  /// [edit] for a change that also says what it made — a new id.
  T create<T>(
    String label,
    (InputActionAsset, T) Function(InputActionAsset asset) change,
  ) {
    final (next, made) = change(_asset);
    apply(label, next);
    return made;
  }

  /// Takes back the last step; nothing when there is none.
  void undo() {
    if (_undo.isEmpty) return;
    final step = _undo.removeLast();
    _redo.add(_Step(step.label, _asset));
    _set(step.asset);
  }

  /// Does the last undone step again; nothing when there is none.
  void redo() {
    if (_redo.isEmpty) return;
    final step = _redo.removeLast();
    _undo.add(_Step(step.label, _asset));
    _set(step.asset);
  }

  /// Takes a whole asset in with no history — a file opened.
  void load(InputActionAsset asset, {String? path}) {
    this.path = path ?? this.path;
    _undo.clear();
    _redo.clear();
    _savedText = asset.encode();
    _selection = const NoSelection();
    _selectedMapId = asset.maps.firstOrNull?.id;
    _set(asset);
  }

  /// What is on disk is [asset] — the one written, which by the time the
  /// write is done may no longer be the one here (a drag went on); this one
  /// when not given.
  void markSaved({String? path, InputActionAsset? asset}) {
    this.path = path ?? this.path;
    _savedText = (asset ?? _asset).encode();
    _dirty = null;
    notifyListeners();
  }

  void _set(InputActionAsset next) {
    _schemeFilter = _followFilter(_asset, next);
    _asset = next;
    _dirty = null;
    _issues = null;
    _conflicts = null;
    _repairSelection();
    notifyListeners();
  }

  /// The scheme filter once [next] replaces [previous]: the same group, or
  /// the one its scheme was given; none when the scheme has gone.
  String? _followFilter(InputActionAsset previous, InputActionAsset next) {
    final group = _schemeFilter;
    if (group == null || next.schemeWithGroup(group) != null) return group;
    final scheme = previous.schemeWithGroup(group);
    return scheme == null ? null : next.schemeNamed(scheme.name)?.group;
  }

  // --- Breaking changes -----------------------------------------------------

  /// Asked before an edit that takes a name away from the game — a rename,
  /// a move or a delete of an action or a map — with what the edit is
  /// called and what it takes away: true to go on. The editor sets it to
  /// look through the project and ask when something names it.
  Future<bool> Function(String change, InputReferenceQuery query)?
  confirmBreaking;

  /// Whether [change] may go ahead: what [confirmBreaking] says, or yes
  /// when nothing asks.
  Future<bool> mayBreak(String change, InputReferenceQuery query) async {
    final ask = confirmBreaking;
    if (ask == null || query.isEmpty) return true;
    return ask(change, query);
  }

  // --- Selection ----------------------------------------------------------

  EditorSelection _selection = const NoSelection();

  /// What the Properties panel shows and the pictures outline.
  EditorSelection get selection => _selection;

  String? _selectedMapId;

  /// The map whose actions are listed.
  String? get selectedMapId => _selectedMapId;

  /// Shows the map [id]'s actions; a selected action or binding of another
  /// map is let go.
  void selectMap(String? id) {
    if (id == _selectedMapId) return;
    _selectedMapId = id;
    if (_selection case ActionSelection() || BindingSelection()) {
      _selection = const NoSelection();
    }
    notifyListeners();
  }

  /// Selects [selection], showing its map when it is in one.
  void select(EditorSelection selection) {
    if (selection == _selection) return;
    _selection = selection;
    // Selecting something in another map shows that map.
    final mapId = switch (selection) {
      ActionSelection(:final id) => _asset.actionById(id)?.map.id,
      BindingSelection(:final id) => _asset.findBinding(id)?.map.id,
      _ => null,
    };
    if (mapId != null) _selectedMapId = mapId;
    notifyListeners();
  }

  /// After an undo or a delete, what was selected may be gone: fall back to
  /// what holds it, or to nothing.
  void _repairSelection() {
    if (_asset.mapById(_selectedMapId ?? '') == null) {
      _selectedMapId = _asset.maps.firstOrNull?.id;
    }
    _selection = switch (_selection) {
      ActionSelection(:final id) when _asset.actionById(id) == null =>
        const NoSelection(),
      BindingSelection(:final id) when _asset.findBinding(id) == null =>
        const NoSelection(),
      OnScreenSelection(:final id) when _asset.onScreenControl(id) == null =>
        const NoSelection(),
      SchemeSelection(:final name) when _asset.schemeNamed(name) == null =>
        const NoSelection(),
      final s => s,
    };
  }

  // --- Filters --------------------------------------------------------------

  String? _schemeFilter;

  /// Only bindings in this scheme's group are shown; null shows all.
  String? get schemeFilter => _schemeFilter;

  set schemeFilter(String? group) {
    if (group == _schemeFilter) return;
    _schemeFilter = group;
    _conflicts = null;
    notifyListeners();
  }

  String _search = '';

  /// Actions whose name, or a binding's path, contains this.
  String get search => _search;

  set search(String value) {
    if (value == _search) return;
    _search = value;
    notifyListeners();
  }

  // --- Problems -------------------------------------------------------------

  List<AssetIssue>? _issues;
  List<BindingConflict>? _conflicts;

  /// What `validateAsset` finds wrong with the asset, worked out once per
  /// change.
  List<AssetIssue> get issues => _issues ??= validateAsset(_asset);

  /// Controls two actions of a map share, in the [schemeFilter]'s scheme.

  List<BindingConflict> get conflicts =>
      _conflicts ??= findBindingConflicts(_asset, group: _schemeFilter);

  /// Bindings (and parts) some other action also has.
  Set<String> get conflictedBindings => {
    for (final c in conflicts) ...c.bindingIds,
  };

  /// What is wrong with the thing with [id] — an action, binding or part.
  List<AssetIssue> issuesFor(String id) => [
    for (final i in issues)
      if (i.bindingId == id || (i.bindingId == null && i.actionId == id)) i,
  ];

  // --- Messages -------------------------------------------------------------

  /// The last thing [say] said, for the status line.
  final ValueNotifier<String?> message = ValueNotifier(null);

  /// A short note for the status line.
  void say(String text) => message.value = text;

  @override
  void dispose() {
    _disposed = true;
    message.dispose();
    super.dispose();
  }

  /// Set by [dispose]: a drag torn down with the editor ends without a word.
  bool _disposed = false;
}
