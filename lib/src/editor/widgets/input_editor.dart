import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/asset_store.dart';
import '../core/checked_edits.dart';
import '../core/input_editor_session.dart';
import '../core/input_references.dart';
import '../core/starter_asset.dart';
import 'actions_tree.dart';
import 'bottom_panel.dart';
import 'editor_harness.dart';
import 'editor_theme.dart';
import 'maps_column.dart';
import 'properties_panel.dart';

/// The Input Actions editor: a whole input asset — its maps, actions and
/// bindings, its schemes, players and on-screen controls — with undo, and a
/// place to try it.
///
/// Takes everything from its host through the constructor, so it runs
/// inside the engine editor as a workspace and on its own alike.
class InputEditor extends StatefulWidget {
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
  });

  /// Where assets are read from and written to.
  final InputAssetStore store;

  /// The asset to open. Null, or a file that is not there yet, starts from
  /// the starter asset, saved to [newAssetPath].
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

  /// Tells every open input editor that the file at [path] changed on disk:
  /// what a host calls when something other than the editor wrote it. An
  /// editor with nothing unsaved reads it again; one with changes says that
  /// saving will replace it.
  static void fileChanged(String path) {
    for (final state in [...InputEditorState._open]) {
      state._fileChanged(path);
    }
  }

  @override
  State<InputEditor> createState() => InputEditorState();
}

/// The editor's state: the session once the file is read, and the harness
/// that runs it for Listen and the live test.
class InputEditorState extends State<InputEditor> {
  /// The editors open now, for [InputEditor.fileChanged].
  static final Set<InputEditorState> _open = {};

  InputEditorSession? _session;
  late final EditorHarness _harness = EditorHarness(gamepads: widget.gamepads);

  /// A scope, so a text field that lets go of the keys hands them back to
  /// the editor rather than to nobody.
  final FocusScopeNode _focus = FocusScopeNode(debugLabel: 'InputEditor');
  String? _error;

  /// The asset being edited, its history and selection; null until the
  /// file has been read.
  InputEditorSession? get session => _session;

  /// The editor's own input service, for Listen and the live test.
  EditorHarness get harness => _harness;

  @override
  void initState() {
    super.initState();
    _open.add(this);
    widget.setCloseGuard?.call(_mayDiscard);
    _read();
  }

  Future<void> _read() async {
    final path = widget.path ?? widget.newAssetPath;
    try {
      final asset = await widget.store.exists(path)
          ? await widget.store.load(path)
          : starterInputAsset(name: _nameOf(path));
      if (!mounted) return;
      final session = InputEditorSession(asset, path: path)
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
      session.addListener(_changed);
      _run(session);
      InputEditorTheme.orderFrom(session.asset);
      setState(() => _session = session);
    } on Object catch (e) {
      // Anything at all: a spinner left turning has no Close button.
      if (mounted) {
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

  Object? _toldError;

  /// The harness runs [s]'s asset; when the input system cannot, that is
  /// said once.
  void _run(InputEditorSession s) {
    _harness.load(s.asset);
    final error = _harness.loadError;
    if (error != null && !identical(error, _toldError)) {
      s.say('Listen and the live test cannot run this asset: $error');
    }
    _toldError = error;
  }

  void _changed() {
    final s = _session!;
    // A drag runs the live copy once it is over, not on every move.
    if (!s.inGesture) _run(s);
    InputEditorTheme.orderFrom(s.asset);
    // Listen hears for the binding the user is looking at: picking
    // something else gives it up, or the next key would bind out of sight.
    final listening = _harness.listeningFor;
    if (listening != null && s.selection != BindingSelection(listening)) {
      _harness.cancelListen();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _open.remove(this);
    widget.setCloseGuard?.call(null);
    _session
      ?..confirmBreaking = null
      ..removeListener(_changed)
      ..dispose();
    _harness.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void>? _saving;

  /// Writes the asset to its file — after any save still under way, so two
  /// never write at once.
  Future<void> save() {
    final next = (_saving ?? Future<void>.value()).then((_) => _saveOnce());
    _saving = next;
    return next.whenComplete(() {
      if (identical(_saving, next)) _saving = null;
    });
  }

  Future<void> _saveOnce() async {
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
      builder: (context) => AlertDialog(
        backgroundColor: InputEditorTheme.panel,
        title: Text(
          '$change?',
          style: InputEditorTheme.body.copyWith(fontSize: 13),
        ),
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Go ahead',
              style: TextStyle(color: InputEditorTheme.danger),
            ),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  /// The file at [path] changed on disk ([InputEditor.fileChanged]).
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

  /// True when it is fine to lose what is open.
  Future<bool> _mayDiscard() async {
    final s = _session;
    if (s == null || !s.isDirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: InputEditorTheme.panel,
        title: Text(
          'Save changes to ${s.path?.split('/').last ?? 'these input actions'}?',
          style: InputEditorTheme.body.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: Text(
              "Don't save",
              style: TextStyle(color: InputEditorTheme.danger),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await save();
      return !(_session?.isDirty ?? false);
    }
    return choice == 'discard';
  }

  Future<void> close() async {
    if (await _mayDiscard()) widget.onClose?.call();
  }

  // --- Keys -------------------------------------------------------------------

  static bool get _isTyping {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final s = _session;
    if (s == null || event is KeyUpEvent || _isTyping || _harness.isListening) {
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
    if (s.inGesture && !(ctrl && key == LogicalKeyboardKey.keyS)) {
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
    final String title, current;
    final Future<void> Function(String name) apply;
    switch (s.selection) {
      case ActionSelection(:final id):
        title = 'Rename action';
        current = s.asset.actionById(id)?.action.name ?? '';
        apply = (n) => CheckedEdits.renameAction(s, id, n);
      case NoSelection() || SettingsSelection():
        final mapId = s.selectedMapId;
        if (mapId == null) return;
        title = 'Rename map';
        current = s.asset.mapById(mapId)?.name ?? '';
        apply = (n) => CheckedEdits.renameMap(s, mapId, n);
      default:
        return;
    }
    if (current.isEmpty) return;
    final name = await promptForText(
      context,
      title: title,
      initial: current,
      action: 'Rename',
    );
    if (name != null) await apply(name);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return ColoredBox(
        color: InputEditorTheme.background,
        child: Center(
          child: _error == null
              ? CircularProgressIndicator(color: InputEditorTheme.accent)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: InputEditorTheme.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Close'),
                    ),
                  ],
                ),
        ),
      );
    }
    return FocusScope(
      node: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        // A click anywhere that is not a text field brings the keys back.
        onPointerDown: (_) {
          if (!_isTyping) _focus.requestFocus();
        },
        child: Material(
          color: InputEditorTheme.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(state: this, session: s),
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MapsColumn(session: s),
                    VerticalDivider(width: 1, color: InputEditorTheme.border),
                    Expanded(child: ActionsTree(session: s)),
                    VerticalDivider(width: 1, color: InputEditorTheme.border),
                    PropertiesPanel(session: s, harness: _harness),
                  ],
                ),
              ),
              Divider(height: 1, color: InputEditorTheme.border),
              Expanded(
                flex: 2,
                child: BottomPanel(session: s, harness: _harness),
              ),
              _StatusLine(session: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.session});

  final InputEditorState state;
  final InputEditorSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final widget = state.widget;
    final file = s.path?.split('/').last ?? 'untitled';
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: InputEditorTheme.panel,
        border: Border(bottom: BorderSide(color: InputEditorTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_esports, size: 18, color: InputEditorTheme.accent),
          const SizedBox(width: 8),
          Text(
            'Input Actions',
            style: TextStyle(
              color: InputEditorTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(file, style: InputEditorTheme.bodyMuted),
          if (s.isDirty)
            Padding(
              padding: EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Not saved',
                child: Icon(
                  Icons.circle,
                  size: 8,
                  color: InputEditorTheme.accent,
                ),
              ),
            ),
          const SizedBox(width: 16),
          _SchemeFilter(session: s),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: EditorTextField(
              value: s.search,
              hint: 'Search actions and keys',
              onChanged: (v) => s.search = v,
              onCommit: (v) => s.search = v,
            ),
          ),
          const Spacer(),
          EditorIconButton(
            icon: Icons.undo,
            tooltip: s.canUndo
                ? 'Undo ${s.undoLabel}  (${EditorKeys.withPrimary('Z')})'
                : 'Nothing to undo',
            onTap: s.canUndo ? s.undo : null,
          ),
          EditorIconButton(
            icon: Icons.redo,
            tooltip: s.canRedo
                ? 'Redo ${s.redoLabel}  (${EditorKeys.withPrimary('Y')})'
                : 'Nothing to redo',
            onTap: s.canRedo ? s.redo : null,
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: s.isDirty
                  ? InputEditorTheme.accent
                  : InputEditorTheme.panelRaised,
              foregroundColor: s.isDirty
                  ? InputEditorTheme.background
                  : InputEditorTheme.textMuted,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: state.save,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save'),
          ),
          const SizedBox(width: 6),
          if (widget.fullScreen != null && widget.onToggleFullScreen != null)
            FullScreenToggle(
              fullScreen: widget.fullScreen!,
              onToggle: widget.onToggleFullScreen!,
            ),
          EditorIconButton(
            icon: Icons.close,
            tooltip: 'Close  (Esc)',
            onTap: state.close,
          ),
        ],
      ),
    );
  }
}

/// All, or one scheme's bindings.
class _SchemeFilter extends StatelessWidget {
  const _SchemeFilter({required this.session});

  final InputEditorSession session;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? group) {
      final on = session.schemeFilter == group;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => session.schemeFilter = group,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: on ? InputEditorTheme.selected : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? InputEditorTheme.accent : InputEditorTheme.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? InputEditorTheme.accent : InputEditorTheme.text,
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('All', null),
        for (final scheme in session.asset.schemes)
          chip(scheme.name, scheme.group),
      ],
    );
  }
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
      color: InputEditorTheme.panel,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 13,
            color: errors > 0
                ? InputEditorTheme.danger
                : InputEditorTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text('$errors', style: InputEditorTheme.label),
          const SizedBox(width: 10),
          Icon(
            Icons.warning_amber_rounded,
            size: 13,
            color: warnings > 0
                ? InputEditorTheme.warning
                : InputEditorTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text('$warnings', style: InputEditorTheme.label),
          const SizedBox(width: 10),
          Icon(
            Icons.compare_arrows,
            size: 13,
            color: conflicts > 0
                ? InputEditorTheme.warning
                : InputEditorTheme.textMuted,
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
