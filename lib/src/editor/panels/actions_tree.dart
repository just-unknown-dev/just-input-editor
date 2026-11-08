import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/checked_edits.dart';
import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import '../look/panel_header.dart';

/// Asks for a new name for the action [actionId], and renames it.
@internal
Future<void> promptRenameAction(
  BuildContext context,
  InputEditorSession session,
  String actionId,
) async {
  final current = session.asset.actionById(actionId)?.action.name;
  if (current == null) return;
  final name = await showEditorPrompt(
    context,
    title: 'Rename action',
    initial: current,
    actionLabel: 'Rename',
    validate: (text) => text == current
        ? null
        : AssetEdits.actionNameProblem(session.asset, actionId, text),
  );
  if (name != null) await CheckedEdits.renameAction(session, actionId, name);
}

/// The selected map's actions, each with its bindings — and a composite's
/// parts under it. The middle of the editor.
@internal
class ActionsTree extends StatefulWidget {
  /// The tree of [session]'s selected map.
  const ActionsTree({super.key, required this.session});

  /// The session it edits.
  final InputEditorSession session;

  @override
  State<ActionsTree> createState() => _ActionsTreeState();
}

class _ActionsTreeState extends State<ActionsTree> {
  final Set<String> _collapsed = {};

  InputEditorSession get s => widget.session;

  BindingDisplay get _display => BindingDisplay(asset: s.asset);

  /// Whether [action] passes the search: its name, or any binding's words.
  bool _matches(InputActionDef action) {
    final q = s.search.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (action.name.toLowerCase().contains(q) ||
        action.label.toLowerCase().contains(q)) {
      return true;
    }
    for (final b in action.bindings) {
      if (_display.binding(b).toLowerCase().contains(q)) return true;
      if (b.paths.any((p) => p.toString().toLowerCase().contains(q))) {
        return true;
      }
    }
    return false;
  }

  List<String> get _newGroups =>
      s.schemeFilter == null ? const [] : [s.schemeFilter!];

  void _addAction(ActionValueType type) {
    final mapId = s.selectedMapId;
    if (mapId == null) return;
    final name = switch (type) {
      ActionValueType.button => 'action',
      ActionValueType.axis => 'axis',
      ActionValueType.vector2 => 'move',
    };
    final id = s.create(
      'Add action',
      (a) => AssetEdits.addAction(a, mapId, name: name, type: type),
    );
    s.select(ActionSelection(id));
  }

  Future<void> _addBindingMenu(
    BuildContext context,
    Offset at,
    InputActionDef action,
  ) async {
    // Every composite registered, a game's own included, that makes what
    // the action reads.
    final composites = [
      for (final c in StepCatalog.composites)
        if (AssetEdits.fits(action.type, c.valueType)) c,
    ];
    final choice = await showEditorMenu<String>(context, at, [
      editorMenuItem('', 'Binding', icon: Icons.link),
      editorMenuDivider(),
      for (final c in composites)
        editorMenuItem(c.type, c.step.label, icon: Icons.account_tree_outlined),
    ]);
    if (choice == null) return;
    if (choice.isEmpty) {
      final id = s.create(
        'Add binding',
        (a) => AssetEdits.addBinding(a, action.id, groups: _newGroups),
      );
      s.select(BindingSelection(id));
    } else {
      final id = s.create(
        'Add ${_compositeLabel(choice)}',
        (a) =>
            AssetEdits.addComposite(a, action.id, choice, groups: _newGroups),
      );
      final first = (s.asset.findBinding(id)!.binding as CompositeBindingDef)
          .parts
          .firstOrNull;
      s.select(BindingSelection(first?.id ?? id));
    }
    _collapsed.remove(action.id);
  }

  Future<void> _actionMenu(
    BuildContext context,
    Offset at,
    InputActionDef action,
  ) async {
    final choice = await showEditorMenu<String>(context, at, [
      editorMenuItem(
        'rename',
        'Rename',
        icon: Icons.edit_outlined,
        shortcut: 'F2',
      ),
      editorMenuItem(
        'duplicate',
        'Duplicate',
        icon: Icons.copy_outlined,
        shortcut: EditorKeys.withPrimary('D'),
      ),
      editorMenuItem(
        'delete',
        'Delete',
        icon: Icons.delete_outline,
        shortcut: 'Del',
      ),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        await promptRenameAction(context, s, action.id);
      case 'duplicate':
        final id = s.create(
          'Duplicate action',
          (a) => AssetEdits.duplicateAction(a, action.id),
        );
        s.select(ActionSelection(id));
      case 'delete':
        await CheckedEdits.deleteAction(s, action.id);
    }
  }

  Future<void> _bindingMenu(
    BuildContext context,
    Offset at,
    BindingRef ref,
  ) async {
    final composite = ref.part == null ? ref.binding : null;
    final parts = composite is CompositeBindingDef
        ? StepCatalog.composite(composite.composite)?.parts ?? const <String>[]
        : const <String>[];
    final choice = await showEditorMenu<String>(context, at, [
      if (ref.part == null)
        editorMenuItem(
          'duplicate',
          'Duplicate',
          icon: Icons.copy_outlined,
          shortcut: EditorKeys.withPrimary('D'),
        ),
      for (final p in parts)
        editorMenuItem('part:$p', 'Another "$p"', icon: Icons.add),
      editorMenuItem(
        'delete',
        ref.part == null ? 'Delete' : 'Delete part',
        icon: Icons.delete_outline,
        shortcut: 'Del',
      ),
    ]);
    switch (choice) {
      case 'duplicate':
        final id = s.create(
          'Duplicate binding',
          (a) => AssetEdits.duplicateBinding(a, ref.binding.id),
        );
        s.select(BindingSelection(id));
      case 'delete':
        s.edit('Delete binding', (a) => AssetEdits.deleteBinding(a, ref.id));
      case final String c when c.startsWith('part:'):
        final id = s.create(
          'Add part',
          (a) => AssetEdits.addPart(a, ref.binding.id, c.substring(5)),
        );
        s.select(BindingSelection(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = s.asset.mapById(s.selectedMapId ?? '');
    final conflicted = s.conflictedBindings;
    final rows = <Widget>[];
    if (map != null) {
      for (final action in map.actions) {
        if (!_matches(action)) continue;
        final collapsed = _collapsed.contains(action.id);
        rows.add(
          _ActionRow(
            key: ValueKey(action.id),
            action: action,
            color: InputEditorTheme.actionColor(s, action.id),
            collapsed: collapsed,
            selected: s.selection == ActionSelection(action.id),
            problems: s.issuesFor(action.id).where((i) => i.isError).length,
            onToggle: () => setState(
              () => collapsed
                  ? _collapsed.remove(action.id)
                  : _collapsed.add(action.id),
            ),
            onTap: () => s.select(ActionSelection(action.id)),
            onMenu: (at) => _actionMenu(context, at, action),
            onAdd: (at) => _addBindingMenu(context, at, action),
            onDropBefore: (id) => s.edit(
              'Move action',
              (a) => AssetEdits.moveActionBefore(a, id, action.id),
            ),
          ),
        );
        if (collapsed) continue;
        for (final b in action.bindings) {
          if (!b.inGroup(s.schemeFilter)) continue;
          final ref = BindingRef(map, action, b);
          rows.add(
            _BindingRow(
              key: ValueKey(b.id),
              depth: 1,
              icon: b is CompositeBindingDef
                  ? Icons.account_tree_outlined
                  : InputEditorTheme.layoutIcon(
                      (b as ControlBindingDef).control?.layout,
                    ),
              text: b is CompositeBindingDef
                  ? (b.name.isNotEmpty ? b.name : _compositeLabel(b.composite))
                  : _display.control((b as ControlBindingDef).path),
              muted: b is CompositeBindingDef,
              tags: [
                if (s.schemeFilter == null) ...b.groups,
                ...b.interactions.map((i) => i.type),
              ],
              selected: s.selection == BindingSelection(b.id),
              conflict: conflicted.contains(b.id),
              problems: s.issuesFor(b.id).length,
              onTap: () => s.select(BindingSelection(b.id)),
              onMenu: (at) => _bindingMenu(context, at, ref),
            ),
          );
          if (b is CompositeBindingDef) {
            for (final p in b.parts) {
              rows.add(
                _BindingRow(
                  key: ValueKey(p.id),
                  depth: 2,
                  icon: InputEditorTheme.layoutIcon(p.control?.layout),
                  label: prettifyName(p.part),
                  text: _display.control(p.path),
                  selected: s.selection == BindingSelection(p.id),
                  conflict: conflicted.contains(p.id),
                  problems: s.issuesFor(p.id).length,
                  onTap: () => s.select(BindingSelection(p.id)),
                  onMenu: (at) =>
                      _bindingMenu(context, at, BindingRef(map, action, b, p)),
                ),
              );
            }
          }
        }
      }
    }
    return Container(
      key: const ValueKey('actions-tree'),
      color: EditorTheme.dialogBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            map == null ? 'Actions' : 'Actions — ${map.name}',
            actions: [
              if (map != null)
                Builder(
                  builder: (context) => EditorIconButton(
                    icon: Icons.add,
                    tooltip: 'Add action',
                    onTap: () async {
                      final type = await showEditorMenuBelow<ActionValueType>(
                        context,
                        [
                          for (final (type, label) in const [
                            (ActionValueType.button, 'Button'),
                            (ActionValueType.axis, 'Axis'),
                            (ActionValueType.vector2, 'Vector 2'),
                          ])
                            editorMenuItem(
                              type,
                              label,
                              icon: InputEditorTheme.typeIcon(type),
                            ),
                        ],
                      );
                      if (type != null) _addAction(type);
                    },
                  ),
                ),
            ],
          ),
          Expanded(
            child: map == null
                ? Center(
                    child: Text(
                      'Add a map to begin.',
                      style: InputEditorTheme.bodyMuted,
                    ),
                  )
                : rows.isEmpty
                ? Center(
                    child: Text(
                      map.actions.isEmpty
                          ? 'No actions yet — add one with +.'
                          : 'Nothing matches the search.',
                      style: InputEditorTheme.bodyMuted,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: rows,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A small tag after a row's name: `hold`, `Gamepad`.
Widget _tag(String text, [Color? color]) => Padding(
  padding: const EdgeInsets.only(left: 4),
  child: EditorBadge(label: text, accent: color ?? EditorTheme.textMuted),
);

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.action,
    required this.color,
    required this.collapsed,
    required this.selected,
    required this.problems,
    required this.onToggle,
    required this.onTap,
    required this.onMenu,
    required this.onAdd,
    required this.onDropBefore,
  });

  final InputActionDef action;
  final Color color;
  final bool collapsed;
  final bool selected;
  final int problems;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final ValueChanged<Offset> onAdd;
  final ValueChanged<String> onDropBefore;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: 30,
      padding: const EdgeInsets.only(left: 2, right: 4),
      decoration: BoxDecoration(
        color: selected ? EditorTheme.selectionBg : null,
        border: selected
            ? Border(
                left: BorderSide(color: EditorTheme.primaryBright, width: 2),
              )
            : null,
      ),
      child: Row(
        children: [
          EditorIconButton(
            icon: collapsed ? Icons.chevron_right : Icons.expand_more,
            tooltip: collapsed ? 'Show bindings' : 'Hide bindings',
            size: 22,
            onTap: onToggle,
          ),
          Icon(InputEditorTheme.typeIcon(action.type), size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            action.name,
            style: InputEditorTheme.body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (action.displayName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '“${action.displayName}”',
                style: InputEditorTheme.label,
              ),
            ),
          for (final i in action.interactions)
            _tag(i.type, EditorTheme.warning),
          if (action.passThrough) _tag('pass-through'),
          if (!action.rebindable) _tag('fixed'),
          const Spacer(),
          if (problems > 0)
            Tooltip(
              message: 'Something is wrong here — see Properties',
              child: Icon(
                Icons.error_outline,
                size: 14,
                color: EditorTheme.error,
              ),
            ),
          Builder(
            builder: (context) => EditorIconButton(
              icon: Icons.add_link,
              tooltip: 'Add binding',
              size: 24,
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                onAdd(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
              },
            ),
          ),
        ],
      ),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != action.id,
      onAcceptWithDetails: (d) => onDropBefore(d.data),
      builder: (context, over, _) => Draggable<String>(
        data: action.id,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: EditorTheme.panelRaised,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(action.name, style: InputEditorTheme.body),
          ),
        ),
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapUp: (d) => onMenu(d.globalPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: over.isNotEmpty
                  ? Border(
                      top: BorderSide(
                        color: EditorTheme.primaryBright,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    super.key,
    required this.depth,
    required this.icon,
    required this.text,
    required this.selected,
    required this.conflict,
    required this.problems,
    required this.onTap,
    required this.onMenu,
    this.label,
    this.muted = false,
    this.tags = const [],
  });

  final int depth;
  final IconData icon;
  final String? label;
  final String text;
  final bool muted;
  final List<String> tags;
  final bool selected;
  final bool conflict;
  final int problems;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    onSecondaryTapUp: (d) => onMenu(d.globalPosition),
    child: Container(
      height: 26,
      padding: EdgeInsets.only(left: 22.0 + depth * 22, right: 8),
      color: selected ? EditorTheme.selectionBg : null,
      child: Row(
        children: [
          Icon(icon, size: 14, color: EditorTheme.textMuted),
          const SizedBox(width: 8),
          if (label != null)
            SizedBox(
              width: 60,
              child: Text(label!, style: InputEditorTheme.bodyMuted),
            ),
          Flexible(
            child: Text(
              text.isEmpty ? '<not bound>' : text,
              overflow: TextOverflow.ellipsis,
              style: text.isEmpty
                  ? InputEditorTheme.bodyMuted.copyWith(
                      fontStyle: FontStyle.italic,
                    )
                  : muted
                  ? InputEditorTheme.bodyMuted
                  : InputEditorTheme.body,
            ),
          ),
          for (final t in tags) _tag(t),
          const Spacer(),
          if (conflict)
            Tooltip(
              message: 'Another action in this map uses this too',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: EditorTheme.warning,
              ),
            ),
          if (problems > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.error_outline,
                size: 14,
                color: EditorTheme.error,
              ),
            ),
        ],
      ),
    ),
  );
}

/// [type]'s label as the step catalogue gives it; the type itself for a
/// composite nothing registered.
String _compositeLabel(String type) =>
    StepCatalog.composite(type)?.step.label ?? type;
