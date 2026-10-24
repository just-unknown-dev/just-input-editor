import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/checked_edits.dart';
import '../core/input_editor_session.dart';
import 'editor_theme.dart';

/// The selected map's actions, each with its bindings — and a composite's
/// parts under it. The middle of the editor.
class ActionsTree extends StatefulWidget {
  const ActionsTree({super.key, required this.session});

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
    final kinds = switch (action.type) {
      ActionValueType.vector2 => [CompositeKinds.vector2],
      ActionValueType.axis => [
        CompositeKinds.axis1D,
        CompositeKinds.oneModifier,
        CompositeKinds.twoModifiers,
      ],
      ActionValueType.button => [
        CompositeKinds.oneModifier,
        CompositeKinds.twoModifiers,
        CompositeKinds.axis1D,
      ],
    };
    final choice = await showEditorMenu<String>(context, at, [
      editorMenuItem('', Icons.link, 'Binding'),
      const PopupMenuDivider(),
      for (final k in kinds)
        editorMenuItem(k, Icons.account_tree_outlined, CompositeKinds.label(k)),
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
        'Add ${CompositeKinds.label(choice)}',
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
      editorMenuItem('rename', Icons.edit_outlined, 'Rename  (F2)'),
      editorMenuItem(
        'duplicate',
        Icons.copy_outlined,
        'Duplicate  (${EditorKeys.withPrimary('D')})',
      ),
      editorMenuItem('delete', Icons.delete_outline, 'Delete  (Del)'),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        final name = await promptForText(
          context,
          title: 'Rename action',
          initial: action.name,
          action: 'Rename',
        );
        if (name != null) await CheckedEdits.renameAction(s, action.id, name);
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
        ? CompositeKinds.parts[composite.composite] ?? const <String>[]
        : const <String>[];
    final choice = await showEditorMenu<String>(context, at, [
      if (ref.part == null)
        editorMenuItem(
          'duplicate',
          Icons.copy_outlined,
          'Duplicate  (${EditorKeys.withPrimary('D')})',
        ),
      for (final p in parts)
        editorMenuItem('part:$p', Icons.add, 'Another "$p"'),
      editorMenuItem(
        'delete',
        Icons.delete_outline,
        ref.part == null ? 'Delete  (Del)' : 'Delete part  (Del)',
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
                  ? (b.name.isNotEmpty
                        ? b.name
                        : CompositeKinds.label(b.composite))
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
      color: InputEditorTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            map == null ? 'Actions' : 'Actions — ${map.name}',
            actions: [
              if (map != null)
                Builder(
                  builder: (context) => EditorIconButton(
                    icon: Icons.add,
                    tooltip: 'Add action',
                    onTap: () async {
                      final box = context.findRenderObject()! as RenderBox;
                      final type = await showEditorMenu<ActionValueType>(
                        context,
                        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                        [
                          editorMenuItem(
                            ActionValueType.button,
                            InputEditorTheme.typeIcon(ActionValueType.button),
                            'Button',
                          ),
                          editorMenuItem(
                            ActionValueType.axis,
                            InputEditorTheme.typeIcon(ActionValueType.axis),
                            'Axis',
                          ),
                          editorMenuItem(
                            ActionValueType.vector2,
                            InputEditorTheme.typeIcon(ActionValueType.vector2),
                            'Vector 2',
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.action,
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
    final colour = InputEditorTheme.actionColour(action.id);
    final row = Container(
      height: 30,
      padding: const EdgeInsets.only(left: 2, right: 4),
      decoration: BoxDecoration(
        color: selected ? InputEditorTheme.selected : null,
        border: selected
            ? Border(left: BorderSide(color: InputEditorTheme.accent, width: 2))
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
          Icon(InputEditorTheme.typeIcon(action.type), size: 15, color: colour),
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
            EditorTag(i.type, colour: InputEditorTheme.warning),
          if (action.passThrough) const EditorTag('pass-through'),
          if (!action.rebindable) const EditorTag('fixed'),
          const Spacer(),
          if (problems > 0)
            Tooltip(
              message: 'Something is wrong here — see Properties',
              child: Icon(
                Icons.error_outline,
                size: 14,
                color: InputEditorTheme.danger,
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
          color: InputEditorTheme.panelRaised,
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
                      top: BorderSide(color: InputEditorTheme.accent, width: 2),
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
      color: selected ? InputEditorTheme.selected : null,
      child: Row(
        children: [
          Icon(icon, size: 14, color: InputEditorTheme.textMuted),
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
          for (final t in tags) EditorTag(t),
          const Spacer(),
          if (conflict)
            Tooltip(
              message: 'Another action in this map uses this too',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: InputEditorTheme.warning,
              ),
            ),
          if (problems > 0)
            Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.error_outline,
                size: 14,
                color: InputEditorTheme.danger,
              ),
            ),
        ],
      ),
    ),
  );
}
