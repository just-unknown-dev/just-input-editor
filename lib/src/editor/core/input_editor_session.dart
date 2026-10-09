import 'package:flutter/foundation.dart';

import 'package:just_inputs/just_inputs.dart';

/// What is selected in the Input Actions editor.
sealed class EditorSelection {
  const EditorSelection();
}

final class NoSelection extends EditorSelection {
  const NoSelection();
}

final class ActionSelection extends EditorSelection {
  const ActionSelection(this.id);
  final String id;

  @override
  bool operator ==(Object other) => other is ActionSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A binding, or one part of a composite.
final class BindingSelection extends EditorSelection {
  const BindingSelection(this.id);
  final String id;

  @override
  bool operator ==(Object other) => other is BindingSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

final class OnScreenSelection extends EditorSelection {
  const OnScreenSelection(this.id);
  final String id;

  @override
  bool operator ==(Object other) =>
      other is OnScreenSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

final class SchemeSelection extends EditorSelection {
  const SchemeSelection(this.name);
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
  InputActionAsset get asset => _asset;

  String _savedText;
  bool? _dirty;

  /// Something changed since it was loaded or last saved.
  bool get isDirty => _dirty ??= _asset.encode() != _savedText;

  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.lastOrNull?.label;
  String? get redoLabel => _redo.lastOrNull?.label;

  int _gesture = 0;
  bool _gestureRecorded = false;

  /// Everything until [endGesture] is one undo step — a drag.
  void beginGesture() {
    if (_gesture++ == 0) _gestureRecorded = false;
  }

  void endGesture() {
    if (_gesture > 0) _gesture--;
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

  void undo() {
    final step = _undo.removeLast();
    _redo.add(_Step(step.label, _asset));
    _set(step.asset);
  }

  void redo() {
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

  /// What is on disk is what is here now.
  void markSaved({String? path}) {
    this.path = path ?? this.path;
    _savedText = _asset.encode();
    _dirty = false;
    notifyListeners();
  }

  void _set(InputActionAsset next) {
    _asset = next;
    _dirty = null;
    _issues = null;
    _conflicts = null;
    _repairSelection();
    notifyListeners();
  }

  // --- Selection ----------------------------------------------------------

  EditorSelection _selection = const NoSelection();
  EditorSelection get selection => _selection;

  String? _selectedMapId;

  /// The map whose actions are listed.
  String? get selectedMapId => _selectedMapId;

  void selectMap(String? id) {
    if (id == _selectedMapId) return;
    _selectedMapId = id;
    if (_selection case ActionSelection() || BindingSelection()) {
      _selection = const NoSelection();
    }
    notifyListeners();
  }

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

  List<AssetIssue> get issues => _issues ??= validateAsset(_asset);

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

  final ValueNotifier<String?> message = ValueNotifier(null);

  /// A short note for the status line.
  void say(String text) => message.value = text;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }
}
