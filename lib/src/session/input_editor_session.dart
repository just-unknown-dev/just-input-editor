import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:just_inputs/just_inputs.dart';

import '../asset/asset.dart';
import 'input_editor_selection.dart';

final class _Step {
  const _Step(this.label, this.asset);
  final String label;
  final InputActionAsset asset;
}

/// One part of a session that widgets listen to.
final class _Part extends ChangeNotifier {
  void tell() => notifyListeners();
}

/// The Input Actions editor's state: the asset being edited, its history,
/// what is selected and what is wrong with it.
///
/// History keeps whole assets — they are immutable, so a step costs a
/// reference, and undo is a swap.
///
/// Its listeners hear of every change. What shows one part of it listens
/// to that part alone — [assetChanges], [selectionChanges],
/// [schemeFilterChanges], [searchChanges], [savedChanges],
/// [problemChanges] — so a click that selects something never rebuilds
/// the status line, and a search typed rebuilds the list of actions alone.
class InputEditorSession extends ChangeNotifier {
  /// A session on [asset], saved at [path]. One [isNew] has no file yet:
  /// it starts unsaved, so closing it asks, and its Save is lit.
  InputEditorSession(InputActionAsset asset, {this.path, bool isNew = false})
    : _asset = asset,
      _savedText = isNew ? '' : asset.encode() {
    _selectedMapId = asset.maps.firstOrNull?.id;
  }

  /// Where it is saved, project-relative; null for one never saved.
  String? path;

  final _Part _assetChanges = _Part();
  final _Part _selectionChanges = _Part();
  final _Part _schemeFilterChanges = _Part();
  final _Part _searchChanges = _Part();
  final _Part _savedChanges = _Part();
  final _Part _problemChanges = _Part();

  /// Told when [asset] changes — an edit, an undo or a redo, a file read —
  /// and with it the history ([canUndo], [undoLabel]) and [isDirty]; and
  /// once more when a drag ends, for what was put off while it went on.
  Listenable get assetChanges => _assetChanges;

  /// Told when [selection] or [selectedMapId] changes — an undo that takes
  /// away what was selected included.
  Listenable get selectionChanges => _selectionChanges;

  /// Told when [schemeFilter] changes — picked, or following its scheme
  /// through an edit.
  Listenable get schemeFilterChanges => _schemeFilterChanges;

  /// Told when [search] changes.
  Listenable get searchChanges => _searchChanges;

  /// Told when [path] or what was last saved changes, so [isDirty] may
  /// have although the asset has not: a save, a file read.
  Listenable get savedChanges => _savedChanges;

  /// Told when [issues] and [conflicts] may have changed: an edit outside
  /// a drag, the end of a drag, another [schemeFilter]. Through a drag they
  /// stay as they were.
  Listenable get problemChanges => _problemChanges;

  /// Tells the listeners of each part that changed, then the session's own.
  void _tell({
    bool asset = false,
    bool selection = false,
    bool schemeFilter = false,
    bool search = false,
    bool saved = false,
    bool problems = false,
  }) {
    if (asset) _assetChanges.tell();
    if (selection) _selectionChanges.tell();
    if (schemeFilter) _schemeFilterChanges.tell();
    if (search) _searchChanges.tell();
    if (saved) _savedChanges.tell();
    if (problems) _problemChanges.tell();
    notifyListeners();
  }

  /// Steps kept for undo.
  static const int maxUndo = 200;

  InputActionAsset _asset;

  /// The asset as it is now.
  InputActionAsset get asset => _asset;

  /// [asset] encoded, worked out once per change.
  String get _text => _encoded ??= _asset.encode();
  String? _encoded;

  String _savedText;

  /// Something changed since it was loaded or last saved — or it has never
  /// been saved at all.
  ///
  /// Through a drag that has changed something it is so without comparing:
  /// the file is not written out again on every move.
  bool get isDirty {
    if (_gesture > 0 && _gestureRecorded) return true;
    return _text != _savedText;
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
  bool get isInGesture => _gesture > 0;

  /// Everything until [endGesture] is one undo step — a drag.
  void beginGesture() {
    if (_gesture++ == 0) _gestureRecorded = false;
  }

  /// The drag is over; listeners hear of it once, for what they put off
  /// while it went on — the problems, worked out again now.
  void endGesture() {
    if (_gesture == 0 || _disposed) return;
    if (--_gesture > 0) return;
    _issues = null;
    _conflicts = null;
    _tell(asset: true, problems: true);
  }

  /// Makes [next] the asset, as one undoable step called [label]. One that
  /// changes nothing — the same name typed again, a path set to itself —
  /// is no step: Undo would undo nothing.
  void apply(String label, InputActionAsset next) {
    if (identical(next, _asset)) return;
    final text = next.encode();
    if (text == _text) return;
    if (_gesture == 0 || !_gestureRecorded) {
      _undo.add(_Step(label, _asset));
      if (_undo.length > maxUndo) _undo.removeAt(0);
      _gestureRecorded = _gesture > 0;
    }
    _redo.clear();
    _set(next, text: text);
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
    final text = asset.encode();
    _savedText = text;
    _selection = const NoSelection();
    _selectedMapId = asset.maps.firstOrNull?.id;
    _set(asset, text: text, loaded: true);
  }

  /// What is on disk is [asset] — the one written, which by the time the
  /// write is done may no longer be the one here (a drag went on); this one
  /// when not given.
  void markSaved({String? path, InputActionAsset? asset}) {
    this.path = path ?? this.path;
    _savedText = asset == null ? _text : asset.encode();
    _tell(saved: true);
  }

  /// Makes [next] the asset ([text] its encoding, when known) and tells
  /// the listeners of what changed with it. One [loaded] has also reset
  /// what was saved and selected.
  void _set(InputActionAsset next, {String? text, bool loaded = false}) {
    final filter = _schemeFilter;
    final selection = _selection;
    final mapId = _selectedMapId;
    _schemeFilter = _followFilter(_asset, next);
    _asset = next;
    _encoded = text;
    _colorOrder = null;
    // Through a drag the problems stay as they were, worked out again when
    // it ends: validating on every pointer move is wasted work.
    if (_gesture == 0) {
      _issues = null;
      _conflicts = null;
    }
    _repairSelection();
    _tell(
      asset: true,
      selection: loaded || selection != _selection || mapId != _selectedMapId,
      schemeFilter: filter != _schemeFilter,
      saved: loaded,
      problems: _gesture == 0,
    );
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

  int _checks = 0;
  Completer<void>? _idle;

  /// Whether an edit is waiting on [mayBreak]: typed, but not made yet. A
  /// save, or a close, waits for it ([idle]) — or the edit would be lost,
  /// or land after the file was written.
  bool get isChecking => _checks > 0;

  /// Completes once no edit waits on [mayBreak] — at once when none does.
  Future<void> get idle =>
      _checks == 0 ? Future<void>.value() : (_idle ??= Completer()).future;

  /// Asks [mayBreak] about [change], then — when it may go ahead — makes it
  /// with [then]. Until then it counts as [isChecking].
  Future<void> checked(
    String change,
    InputReferenceQuery query,
    void Function() then,
  ) async {
    _checks++;
    try {
      if (await mayBreak(change, query) && !_disposed) then();
    } finally {
      if (--_checks == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  // --- Selection ----------------------------------------------------------

  InputEditorSelection _selection = const NoSelection();

  /// What the Properties panel shows and the pictures outline.
  InputEditorSelection get selection => _selection;

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
    _tell(selection: true);
  }

  /// Selects [selection], showing its map when it is in one.
  void select(InputEditorSelection selection) {
    if (selection == _selection) return;
    _selection = selection;
    // Selecting something in another map shows that map.
    final mapId = switch (selection) {
      ActionSelection(:final id) => _asset.actionById(id)?.map.id,
      BindingSelection(:final id) => _asset.findBinding(id)?.map.id,
      _ => null,
    };
    if (mapId != null) _selectedMapId = mapId;
    _tell(selection: true);
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

  // --- Colours --------------------------------------------------------------

  Map<String, int>? _colorOrder;

  /// The action [actionId]'s place in its map, so that the actions of a map
  /// take the colours in turn — neighbours never share one, as a hash might
  /// make them. Each map starts over: what one picture shows is one map.
  /// An action not in the asset gets a number from its id.
  int colorIndexOf(String actionId) {
    final order = _colorOrder ??= {
      for (final m in _asset.maps)
        for (var i = 0; i < m.actions.length; i++) m.actions[i].id: i,
    };
    return order[actionId] ?? actionId.hashCode.abs();
  }

  // --- Filters --------------------------------------------------------------

  String? _schemeFilter;

  /// Only bindings in this scheme's group are shown; null shows all.
  String? get schemeFilter => _schemeFilter;

  set schemeFilter(String? group) {
    if (group == _schemeFilter) return;
    _schemeFilter = group;
    _conflicts = null;
    _tell(schemeFilter: true, problems: true);
  }

  String _search = '';

  /// Actions whose name, or a binding's path, contains this.
  String get search => _search;

  set search(String value) {
    if (value == _search) return;
    _search = value;
    _tell(search: true);
  }

  // --- Problems -------------------------------------------------------------

  List<AssetIssue>? _issues;
  List<BindingConflict>? _conflicts;

  /// What `validateAsset` finds wrong with the asset, worked out once per
  /// change (once per drag).
  List<AssetIssue> get issues => _issues ??= validateAsset(_asset);

  /// Controls two actions of a map share, in the [schemeFilter]'s scheme.
  List<BindingConflict> get conflicts =>
      _conflicts ??= findBindingConflicts(_asset, group: _schemeFilter);

  /// Bindings (and parts) some other action also has.
  Set<String> get conflictedBindings => {
    for (final c in conflicts) ...c.bindingIds,
  };

  /// What is wrong with the thing with [id] — an action, binding or part —
  /// its steps and settings included.
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
    for (final part in [
      _assetChanges,
      _selectionChanges,
      _schemeFilterChanges,
      _searchChanges,
      _savedChanges,
      _problemChanges,
    ]) {
      part.dispose();
    }
    super.dispose();
  }

  /// Set by [dispose]: a drag torn down with the editor ends without a word.
  bool _disposed = false;
}
