import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';

import '../asset/asset.dart';
import '../session/checked_edits.dart';
import '../session/session.dart';
import 'look/input_editor_theme.dart';
import 'panels/actions_tree.dart';
import 'panels/maps_column.dart';
import 'panels/properties_panel.dart';
import 'views/bottom_panel.dart';

/// The Input Actions editor: a whole input asset — its maps, actions and
/// bindings, its schemes, players and on-screen controls — with undo, and a
/// place to try it.
///
/// Takes everything from its host through the constructor, so it runs
/// inside the engine editor as a workspace and on its own alike. A host
/// that gives it another [path] or [store] reopens it on that file: what
/// was unsaved is the host's to ask about first ([setCloseGuard]).
class InputEditor extends StatefulWidget {
  /// An editor of the asset at [path] in [store].
  const InputEditor({
    super.key,
    required this.store,
    this.path,
    this.newAssetPath = 'assets/input/game.input.json',
    this.onClose,
    this.onSaved,
    this.fullScreen,
    this.onToggleFullScreen,
    this.setCloseGuard,
    this.gamepads,
    this.references,
    this.fileChanges,
  });

  /// Where assets are read from and written to.
  final InputAssetStore store;

  /// The asset to open. Null, or a file that is not there yet, starts from
  /// the starter asset, saved to [newAssetPath] — unsaved until it is.
  final String? path;

  /// Where a new asset is saved when [path] is null.
  final String newAssetPath;

  /// Closes the editor — called once unsaved work has been asked about.
  final VoidCallback? onClose;

  /// After each save — where the host puts the new asset into the running
  /// game. What it returns, if anything, is said after "Saved": what became
  /// of the save there ("the running game keeps its controls until Stop").
  final String? Function(InputActionAsset asset, String path)? onSaved;

  /// Whether the editor fills the host, for its full-screen button.
  final ValueListenable<bool>? fullScreen;

  /// Switches between the host's dialog and filling it.
  final VoidCallback? onToggleFullScreen;

  /// Where to leave the question a host asks before it opens something
  /// else over this editor: whether the unsaved work may go. Null clears it.
  final void Function(Future<bool> Function()? guard)? setCloseGuard;

  /// Real pads for Listen and the live test. None in a test.
  final GamepadSource? gamepads;

  /// Where to look for what names an action or a map before one is
  /// renamed, moved or deleted — scenes and code ([FileInputReferenceFinder]).
  /// With none, such edits go ahead without asking.
  final InputReferenceFinder? references;

  /// The paths of files that changed on disk, written by something other
  /// than this editor — what a host sends when a tool or the user changed
  /// one. For its own file, an editor with nothing unsaved reads it again;
  /// one with changes says that saving will replace it.
  final Stream<String>? fileChanges;

  @override
  State<InputEditor> createState() => InputEditorState();
}

/// The editor's state: the session once the file is read, and the harness
/// that runs it for Listen and the live test.
class InputEditorState extends State<InputEditor> {
  InputEditorSession? _session;
  InputEditorHarness? _harness;
  StreamSubscription<String>? _changes;

  /// A scope, so a text field that lets go of the keys hands them back to
  /// the editor rather than to nobody.
  final FocusScopeNode _focus = FocusScopeNode(debugLabel: 'InputEditor');
  String? _error;

  /// Bumped each time the file is read: a read the host has since
  /// replaced comes to nothing.
  int _reading = 0;

  /// The asset being edited, its history and selection; null until the
  /// file has been read.
  InputEditorSession? get session => _session;

  /// The editor's own input service, for Listen and the live test; null
  /// until the file has been read. Made with the session, so an editor
  /// whose file never reads never starts one.
  InputEditorHarness? get harness => _harness;

  @override
  void initState() {
    super.initState();
    widget.setCloseGuard?.call(_mayDiscard);
    _changes = widget.fileChanges?.listen(_fileChanged);
    _read();
  }

  @override
  void didUpdateWidget(InputEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.setCloseGuard != widget.setCloseGuard) {
      old.setCloseGuard?.call(null);
      widget.setCloseGuard?.call(_mayDiscard);
    }
    if (old.fileChanges != widget.fileChanges) {
      _changes?.cancel();
      _changes = widget.fileChanges?.listen(_fileChanged);
    }
    if (old.path != widget.path ||
        old.store != widget.store ||
        old.newAssetPath != widget.newAssetPath ||
        old.gamepads != widget.gamepads) {
      // Another file, or other pads: start again on what the host gives.
      _closeSession();
      _error = null;
      _read();
    }
  }

  Future<void> _read() async {
    final reading = ++_reading;
    final path = widget.path ?? widget.newAssetPath;
    try {
      final exists = await widget.store.exists(path);
      final asset = exists
          ? await widget.store.load(path)
          : starterInputAsset(name: _nameOf(path));
      if (!mounted || reading != _reading) return;
      final session = InputEditorSession(asset, path: path, isNew: !exists)
        ..confirmBreaking = _confirmBreaking;
      // Ids a hand edit or a merge left behind the counter would let the
      // next new id land on an old one: put right at once, as a step that
      // can be undone and makes the file unsaved.
      final repaired = AssetEdits.repairIds(asset);
      if (repaired != null) {
        session
          ..apply('Repair ids', repaired.$1)
          ..say(repaired.$2);
      }
      session.assetChanges.addListener(_assetChanged);
      session.selectionChanges.addListener(_selectionChanged);
      final harness = InputEditorHarness(gamepads: widget.gamepads)
        ..addListener(_harnessChanged);
      _session = session;
      _harness = harness;
      _run(session);
      setState(() {});
    } on Object catch (e) {
      // Anything at all: a spinner left turning has no Close button.
      if (mounted && reading == _reading) {
        setState(() => _error = 'Could not read $path:\n${_reason(e)}');
      }
    }
  }

  static String _reason(Object e) => e is FormatException ? e.message : '$e';

  static String _nameOf(String path) {
    final file = path.split('/').last;
    return file.endsWith('.input.json')
        ? file.substring(0, file.length - '.input.json'.length)
        : file;
  }

  Object? _toldLoad;
  Object? _toldRun;

  /// The harness runs [s]'s asset; when the input system cannot, that is
  /// said once.
  void _run(InputEditorSession s) {
    final harness = _harness!..load(s.asset);
    final error = harness.loadError;
    if (error != null && !identical(error, _toldLoad)) {
      s.say('Listen and the live test cannot run this asset: $error');
    }
    _toldLoad = error;
  }

  /// The harness stopped: an update threw. Said once.
  void _harnessChanged() {
    final error = _harness?.runError;
    if (error != null && !identical(error, _toldRun)) {
      _session?.say('The live test stopped — this asset does not run: $error');
    }
    _toldRun = error;
  }

  /// The asset changed. Nothing is rebuilt from here: each part of the
  /// editor listens to what it shows (see [build]).
  void _assetChanged() {
    final s = _session!;
    // A drag runs the live copy once it is over, not on every move.
    if (!s.isInGesture) _run(s);
  }

  /// Listen hears for the binding the user is looking at: picking
  /// something else gives it up, or the next key would bind out of sight.
  void _selectionChanged() {
    final harness = _harness!;
    final listening = harness.listeningFor;
    if (listening != null &&
        _session!.selection != BindingSelection(listening)) {
      harness.cancelListen();
    }
  }

  void _closeSession() {
    final s = _session;
    s?.assetChanges.removeListener(_assetChanged);
    s?.selectionChanges.removeListener(_selectionChanged);
    s
      ?..confirmBreaking = null
      ..dispose();
    _harness
      ?..removeListener(_harnessChanged)
      ..dispose();
    _session = null;
    _harness = null;
  }

  @override
  void dispose() {
    _reading++;
    _changes?.cancel();
    widget.setCloseGuard?.call(null);
    _closeSession();
    _focus.dispose();
    super.dispose();
  }

  Future<void>? _saving;

  /// Writes the asset to its file — after any save still under way, so two
  /// never write at once, and after what is still being typed and an edit
  /// still being checked ([InputEditorSession.idle]), so a rename typed
  /// just before lands in the file rather than after it.
  Future<void> save() {
    // What is still being typed is kept first, as leaving the field would.
    PendingFieldEdits.flush();
    final next = (_saving ?? Future<void>.value()).then((_) => _saveOnce());
    _saving = next;
    return next.whenComplete(() {
      if (identical(_saving, next)) _saving = null;
    });
  }

  Future<void> _saveOnce() async {
    await _session?.idle;
    final s = _session;
    if (s == null || !mounted) return;
    final path = s.path ?? widget.newAssetPath;
    // The asset written, not the one there once the write is done.
    final asset = s.asset;
    try {
      await widget.store.save(path, asset);
    } on Object catch (e) {
      s.say('Could not save: ${_reason(e)}');
      return;
    }
    s.markSaved(path: path, asset: asset);
    final errors = s.issues.where((i) => i.isError).length;
    final saved = [
      'Saved ${path.split('/').last}',
      if (errors > 0) '$errors error${errors == 1 ? '' : 's'} in it',
    ].join(', ');
    String? note;
    try {
      note = widget.onSaved?.call(asset, path);
    } on Object catch (e) {
      note = 'but it could not be applied: $e';
    }
    s.say(note == null ? saved : '$saved — $note');
  }

  /// What names [query]'s action or map in the project, put to the user
  /// before [change] goes ahead: true to go on.
  Future<bool> _confirmBreaking(
    String change,
    InputReferenceQuery query,
  ) async {
    final finder = widget.references;
    if (finder == null) return true;
    final List<InputReference> found;
    try {
      found = await finder.find(query, limit: 30);
    } on Object catch (e) {
      _session?.say('Could not look for what names it: $e');
      return mounted;
    }
    if (!mounted) return false;
    if (found.isEmpty) return true;
    const shown = 8;
    final go = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => EditorAlert(
        title: '$change?',
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These name it, and would no longer find it:',
                style: InputEditorTheme.body,
              ),
              const SizedBox(height: 8),
              for (final r in found.take(shown))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${r.file} — ${r.where}  ("${r.value}")',
                    style: InputEditorTheme.mono,
                  ),
                ),
              if (found.length > shown)
                Text(
                  '…and ${found.length - shown} more.',
                  style: InputEditorTheme.bodyMuted,
                ),
              const SizedBox(height: 8),
              Text(
                'Code that builds the name, or lives outside lib/, may name '
                'it too. Nothing here is changed for you.',
                style: InputEditorTheme.bodyMuted,
              ),
            ],
          ),
        ),
        actions: [
          EditorButton(
            label: 'Cancel',
            kind: EditorButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          EditorButton(
            label: 'Go ahead',
            kind: EditorButtonKind.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  /// The file at [path] changed on disk ([InputEditor.fileChanges]).
  Future<void> _fileChanged(String path) async {
    final s = _session;
    if (s == null || s.path != path) return;
    final InputActionAsset asset;
    try {
      asset = await widget.store.load(path);
    } on Object catch (e) {
      if (mounted) {
        s.say('The file changed on disk, and does not read: ${_reason(e)}');
      }
      return;
    }
    if (!mounted || !identical(_session, s) || s.matchesSaved(asset)) return;
    if (s.isDirty) {
      s.say('The file changed on disk: saving will replace that.');
      return;
    }
    s.load(asset, path: path);
    s.say('Read again: the file changed on disk.');
  }

  /// True when it is fine to lose what is open. What is still being typed
  /// is kept first, and an edit still being checked lands, so both are
  /// asked about too.
  Future<bool> _mayDiscard() async {
    final s = _session;
    if (s == null) return true;
    PendingFieldEdits.flush();
    await s.idle;
    if (!mounted || !identical(_session, s)) return true;
    return mayLeaveUnsaved(
      context,
      dirty: s.isDirty,
      title:
          'Save changes to ${s.path?.split('/').last ?? 'these input actions'}?',
      save: () async {
        await save();
        return !(_session?.isDirty ?? false);
      },
    );
  }

  /// Closes the editor — once unsaved work has been asked about.
  Future<void> close() async {
    if (await _mayDiscard()) widget.onClose?.call();
  }

  // --- Keys -------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final s = _session;
    final harness = _harness;
    if (s == null ||
        harness == null ||
        event is KeyUpEvent ||
        WorkspaceKeyScope.isTyping ||
        harness.isListening) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = EditorKeys.primaryPressed;
    final shift = keys.isShiftPressed;
    // Held down, undo, redo and delete go on; a save, a copy, a rename or
    // a close happen once.
    final once =
        (ctrl &&
            (key == LogicalKeyboardKey.keyS ||
                key == LogicalKeyboardKey.keyD)) ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.escape;
    if (event is KeyRepeatEvent && once) return KeyEventResult.handled;
    // Mid-drag, an edit would land inside the drag's undo step — or take
    // away what is being dragged: the keys wait until it is let go.
    if (s.isInGesture && !(ctrl && key == LogicalKeyboardKey.keyS)) {
      final editing =
          once ||
          (ctrl &&
              (key == LogicalKeyboardKey.keyZ ||
                  key == LogicalKeyboardKey.keyY)) ||
          EditorKeys.isDeleteKey(key);
      return editing ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      save();
    } else if (ctrl &&
        (key == LogicalKeyboardKey.keyY ||
            (shift && key == LogicalKeyboardKey.keyZ))) {
      if (s.canRedo) s.redo();
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      if (s.canUndo) s.undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyD) {
      _duplicate(s);
    } else if (EditorKeys.isDeleteKey(key)) {
      _delete(s);
    } else if (key == LogicalKeyboardKey.f2) {
      _rename(s);
    } else if (key == LogicalKeyboardKey.escape) {
      close();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _delete(InputEditorSession s) {
    switch (s.selection) {
      case ActionSelection(:final id):
        CheckedEdits.deleteAction(s, id);
      case BindingSelection(:final id):
        s.edit('Delete binding', (a) => AssetEdits.deleteBinding(a, id));
      case OnScreenSelection(:final id):
        CheckedEdits.deleteOnScreen(s, id);
      default:
        return;
    }
  }

  void _duplicate(InputEditorSession s) {
    switch (s.selection) {
      case ActionSelection(:final id):
        s.select(
          ActionSelection(
            s.create(
              'Duplicate action',
              (a) => AssetEdits.duplicateAction(a, id),
            ),
          ),
        );
      case BindingSelection(:final id):
        final ref = s.asset.findBinding(id);
        final part = ref?.part;
        if (ref == null) return;
        // A part: another of the same part, as the menu's "Another …".
        s.select(
          BindingSelection(
            part == null
                ? s.create(
                    'Duplicate binding',
                    (a) => AssetEdits.duplicateBinding(a, id),
                  )
                : s.create(
                    'Add part',
                    (a) => AssetEdits.addPart(a, ref.binding.id, part.part),
                  ),
          ),
        );
      case NoSelection():
        final mapId = s.selectedMapId;
        if (mapId != null) {
          s.selectMap(
            s.create('Duplicate map', (a) => AssetEdits.duplicateMap(a, mapId)),
          );
        }
      default:
        // An on-screen control, a scheme, the settings: nothing to copy by
        // key — and the map is not what is selected.
        return;
    }
  }

  /// F2: the selected action, or — with nothing (or the settings) selected
  /// — the map shown. A binding, a scheme or an on-screen control is named
  /// in Properties, not here.
  Future<void> _rename(InputEditorSession s) async {
    switch (s.selection) {
      case ActionSelection(:final id):
        await promptRenameAction(context, s, id);
      case NoSelection() || SettingsSelection():
        final map = s.asset.mapById(s.selectedMapId ?? '');
        if (map != null) await promptRenameMap(context, s, map);
      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final harness = _harness;
    if (s == null || harness == null) {
      return ColoredBox(
        color: EditorTheme.dialogBg,
        child: Center(
          child: _error == null
              ? CircularProgressIndicator(color: EditorTheme.primaryBright)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: InputEditorTheme.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    EditorButton(label: 'Close', onPressed: widget.onClose),
                  ],
                ),
        ),
      );
    }
    // Each part rebuilds on what it shows, never the whole editor: a click
    // that selects leaves the header and the status line alone, a search
    // typed rebuilds the tree alone, and through a drag the problems are
    // not counted again.
    final asset = s.assetChanges;
    final selection = s.selectionChanges;
    final scheme = s.schemeFilterChanges;
    final problems = s.problemChanges;
    final header = Listenable.merge([asset, s.savedChanges]);
    final schemes = Listenable.merge([asset, scheme]);
    final panels = Listenable.merge([asset, selection, problems]);
    final tree = Listenable.merge([
      asset,
      selection,
      scheme,
      s.searchChanges,
      problems,
    ]);
    final views = Listenable.merge([asset, selection, scheme]);
    Widget on(Listenable parts, Widget Function() part) =>
        ListenableBuilder(listenable: parts, builder: (context, _) => part());
    // Made once, here: the header rebuilding (a save, an edit) hands the
    // same ones back, and they are not built again.
    final tools = [
      on(schemes, () => _SchemeFilter(session: s)),
      const SizedBox(width: 12),
      EditorSearchField(
        initial: s.search,
        hint: 'Search actions and keys',
        width: 180,
        onChanged: (v) => s.search = v,
      ),
    ];
    return FocusScope(
      node: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        // A click anywhere that is not a text field brings the keys back.
        onPointerDown: (_) {
          if (!WorkspaceKeyScope.isTyping) _focus.requestFocus();
        },
        child: Material(
          color: EditorTheme.dialogBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              on(
                header,
                () => WorkspaceHeader(
                  icon: Icons.sports_esports,
                  title: 'Input Actions',
                  file: s.path?.split('/').last ?? 'untitled',
                  dirty: s.isDirty,
                  onSave: save,
                  onUndo: s.canUndo ? s.undo : null,
                  onRedo: s.canRedo ? s.redo : null,
                  undoLabel: s.undoLabel,
                  redoLabel: s.redoLabel,
                  tools: tools,
                  fullScreen: widget.fullScreen,
                  onToggleFullScreen: widget.onToggleFullScreen,
                  onClose: close,
                  closeTooltip: 'Close  (Esc)',
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    on(panels, () => MapsColumn(session: s)),
                    VerticalDivider(width: 1, color: EditorTheme.borderStrong),
                    Expanded(child: on(tree, () => ActionsTree(session: s))),
                    VerticalDivider(width: 1, color: EditorTheme.borderStrong),
                    on(
                      panels,
                      () => PropertiesPanel(session: s, harness: harness),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: EditorTheme.borderStrong),
              Expanded(
                flex: 2,
                child: on(
                  views,
                  () => BottomPanel(session: s, harness: harness),
                ),
              ),
              on(problems, () => _StatusLine(session: s)),
            ],
          ),
        ),
      ),
    );
  }
}

/// All, or one scheme's bindings.
class _SchemeFilter extends StatelessWidget {
  const _SchemeFilter({required this.session});

  final InputEditorSession session;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (label, group) in [
        ('All', null),
        for (final scheme in session.asset.schemes) (scheme.name, scheme.group),
      ])
        EditorChip(
          label: label,
          selected: session.schemeFilter == group,
          onTap: () => session.schemeFilter = group,
        ),
    ],
  );
}

/// Problems at a glance, and the last thing said.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.session});

  final InputEditorSession session;

  @override
  Widget build(BuildContext context) {
    final errors = session.issues.where((i) => i.isError).length;
    final warnings = session.issues.length - errors;
    final conflicts = session.conflicts.length;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: EditorTheme.menuBg,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 13,
            color: errors > 0 ? EditorTheme.error : EditorTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text('$errors', style: InputEditorTheme.label),
          const SizedBox(width: 10),
          Icon(
            Icons.warning_amber_rounded,
            size: 13,
            color: warnings > 0 ? EditorTheme.warning : EditorTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text('$warnings', style: InputEditorTheme.label),
          const SizedBox(width: 10),
          Icon(
            Icons.compare_arrows,
            size: 13,
            color: conflicts > 0 ? EditorTheme.warning : EditorTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text('$conflicts shared', style: InputEditorTheme.label),
          const Spacer(),
          ValueListenableBuilder<String?>(
            valueListenable: session.message,
            builder: (context, text, _) =>
                Text(text ?? '', style: InputEditorTheme.label),
          ),
        ],
      ),
    );
  }
}
