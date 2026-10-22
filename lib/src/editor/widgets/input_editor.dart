import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/asset_store.dart';
import '../core/input_editor_session.dart';
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
  });

  /// Where assets are read from and written to.
  final InputAssetStore store;

  /// The asset to open. Null, or a file that is not there yet, starts from
  /// the starter asset, saved to [newAssetPath].
  final String? path;
  final String newAssetPath;

  final VoidCallback? onClose;

  /// After each save — where the host puts the new asset into the running
  /// game.
  final void Function(InputActionAsset asset, String path)? onSaved;

  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  /// Where to leave the question a host asks before it opens something
  /// else over this editor: whether the unsaved work may go. Null clears it.
  final void Function(Future<bool> Function()? guard)? setCloseGuard;

  /// Real pads for Listen and the live test. None in a test.
  final GamepadSource? gamepads;

  @override
  State<InputEditor> createState() => InputEditorState();
}

class InputEditorState extends State<InputEditor> {
  InputEditorSession? _session;
  late final EditorHarness _harness = EditorHarness(gamepads: widget.gamepads);

  /// A scope, so a text field that lets go of the keys hands them back to
  /// the editor rather than to nobody.
  final FocusScopeNode _focus = FocusScopeNode(debugLabel: 'InputEditor');
  String? _error;

  InputEditorSession? get session => _session;
  EditorHarness get harness => _harness;

  @override
  void initState() {
    super.initState();
    widget.setCloseGuard?.call(_mayDiscard);
    _open();
  }

  Future<void> _open() async {
    final path = widget.path ?? widget.newAssetPath;
    try {
      final asset = await widget.store.exists(path)
          ? await widget.store.load(path)
          : starterInputAsset(name: _nameOf(path));
      if (!mounted) return;
      final session = InputEditorSession(asset, path: path)
        ..addListener(_changed);
      _harness.load(asset);
      InputEditorTheme.orderFrom(asset);
      setState(() => _session = session);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not read $path:\n${e.message}');
      }
    }
  }

  static String _nameOf(String path) {
    final file = path.split('/').last;
    return file.endsWith('.input.json')
        ? file.substring(0, file.length - '.input.json'.length)
        : file;
  }

  void _changed() {
    _harness.load(_session!.asset);
    InputEditorTheme.orderFrom(_session!.asset);
    setState(() {});
  }

  @override
  void dispose() {
    widget.setCloseGuard?.call(null);
    _session
      ?..removeListener(_changed)
      ..dispose();
    _harness.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final s = _session;
    if (s == null) return;
    final path = s.path ?? widget.newAssetPath;
    try {
      await widget.store.save(path, s.asset);
      s.markSaved(path: path);
      s.say('Saved ${path.split('/').last}');
      widget.onSaved?.call(s.asset, path);
    } catch (e) {
      s.say('Could not save: $e');
    }
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
        s.edit('Delete action', (a) => AssetEdits.deleteAction(a, id));
      case BindingSelection(:final id):
        s.edit('Delete binding', (a) => AssetEdits.deleteBinding(a, id));
      case OnScreenSelection(:final id):
        s.edit(
          'Delete on-screen control',
          (a) => AssetEdits.deleteOnScreen(a, id),
        );
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
      case BindingSelection(:final id)
          when s.asset.findBinding(id)?.part == null:
        s.select(
          BindingSelection(
            s.create(
              'Duplicate binding',
              (a) => AssetEdits.duplicateBinding(a, id),
            ),
          ),
        );
      default:
        final mapId = s.selectedMapId;
        if (mapId != null) {
          s.selectMap(
            s.create('Duplicate map', (a) => AssetEdits.duplicateMap(a, mapId)),
          );
        }
    }
  }

  Future<void> _rename(InputEditorSession s) async {
    final (title, current, apply) = switch (s.selection) {
      ActionSelection(:final id) => (
        'Rename action',
        s.asset.actionById(id)?.action.name ?? '',
        (String n) =>
            s.edit('Rename action', (a) => AssetEdits.renameAction(a, id, n)),
      ),
      _ => (
        'Rename map',
        s.asset.mapById(s.selectedMapId ?? '')?.name ?? '',
        (String n) => s.edit(
          'Rename map',
          (a) => AssetEdits.renameMap(a, s.selectedMapId!, n),
        ),
      ),
    };
    if (current.isEmpty) return;
    final name = await promptForText(
      context,
      title: title,
      initial: current,
      action: 'Rename',
    );
    if (name != null && name.trim().isNotEmpty) apply(name.trim());
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
