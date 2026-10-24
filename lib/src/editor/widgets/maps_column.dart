import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorKeys;

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/checked_edits.dart';
import '../core/input_editor_session.dart';
import 'editor_theme.dart';

/// The action maps, down the left: which one's actions show, which are on
/// when the game starts, and their order. Below them, the asset's setup —
/// players and settings, schemes, on-screen controls.
class MapsColumn extends StatelessWidget {
  const MapsColumn({super.key, required this.session});

  final InputEditorSession session;

  Future<void> _rename(BuildContext context, ActionMapDef map) async {
    final name = await promptForText(
      context,
      title: 'Rename map',
      initial: map.name,
      action: 'Rename',
    );
    if (name == null) return;
    await CheckedEdits.renameMap(session, map.id, name);
  }

  void _add() {
    final id = session.create('Add map', (a) => AssetEdits.addMap(a));
    session.selectMap(id);
  }

  Future<void> _menu(BuildContext context, Offset at, ActionMapDef map) async {
    final choice = await showEditorMenu<String>(context, at, [
      editorMenuItem('rename', Icons.edit_outlined, 'Rename  (F2)'),
      editorMenuItem(
        'duplicate',
        Icons.copy_outlined,
        'Duplicate  (${EditorKeys.withPrimary('D')})',
      ),
      editorMenuItem('delete', Icons.delete_outline, 'Delete'),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        await _rename(context, map);
      case 'duplicate':
        final id = session.create(
          'Duplicate map',
          (a) => AssetEdits.duplicateMap(a, map.id),
        );
        session.selectMap(id);
      case 'delete':
        await CheckedEdits.deleteMap(session, map.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = session.asset;
    return Container(
      width: 210,
      color: InputEditorTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Action maps',
            actions: [
              EditorIconButton(
                icon: Icons.add,
                tooltip: 'Add map',
                onTap: _add,
              ),
            ],
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: asset.maps.length,
              onReorderItem: (from, to) {
                final map = asset.maps[from];
                session.edit(
                  'Move map',
                  (a) => AssetEdits.moveMap(a, map.id, to),
                );
              },
              itemBuilder: (context, i) {
                final map = asset.maps[i];
                return _MapRow(
                  key: ValueKey(map.id),
                  index: i,
                  map: map,
                  selected: map.id == session.selectedMapId,
                  problems: session.issues
                      .where((x) => x.mapId == map.id && x.isError)
                      .length,
                  onTap: () => session.selectMap(map.id),
                  onMenu: (at) => _menu(context, at, map),
                  onEnabled: (on) => session.edit(
                    on ? 'Map on at start' : 'Map off at start',
                    (a) => AssetEdits.setMapEnabled(a, map.id, on),
                  ),
                  onDropAction: (actionId) =>
                      CheckedEdits.moveActionToMap(session, actionId, map.id),
                );
              },
            ),
          ),
          Divider(height: 1, color: InputEditorTheme.border),
          _SetupRow(
            icon: Icons.groups_outlined,
            label: 'Players & settings',
            selected: session.selection is SettingsSelection,
            onTap: () => session.select(const SettingsSelection()),
          ),
          _SetupRow(
            icon: Icons.devices_other,
            label: 'Control schemes (${asset.schemes.length})',
            selected: session.selection is SchemeSelection,
            onTap: () {
              final first = asset.schemes.firstOrNull;
              if (first != null) session.select(SchemeSelection(first.name));
            },
          ),
          _SetupRow(
            icon: Icons.phone_iphone,
            label: 'On-screen controls (${asset.onScreen.length})',
            selected: session.selection is OnScreenSelection,
            onTap: () {
              final first = asset.onScreen.firstOrNull;
              if (first != null) session.select(OnScreenSelection(first.id));
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _MapRow extends StatelessWidget {
  const _MapRow({
    super.key,
    required this.index,
    required this.map,
    required this.selected,
    required this.problems,
    required this.onTap,
    required this.onMenu,
    required this.onEnabled,
    required this.onDropAction,
  });

  final int index;
  final ActionMapDef map;
  final bool selected;
  final int problems;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onDropAction;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    // An action dragged from the list lands at the end of this map.
    onWillAcceptWithDetails: (d) => !map.actions.any((a) => a.id == d.data),
    onAcceptWithDetails: (d) => onDropAction(d.data),
    builder: (context, over, _) => ReorderableDelayedDragStartListener(
      index: index,
      child: GestureDetector(
        // No double-click: waiting to rule one out makes every click — and
        // the tick box — feel slow. F2 and the menu rename.
        onTap: onTap,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 2, right: 8),
          decoration: BoxDecoration(
            color: over.isNotEmpty
                ? InputEditorTheme.accent.withValues(alpha: 0.18)
                : selected
                ? InputEditorTheme.selected
                : null,
            border: selected
                ? Border(
                    left: BorderSide(color: InputEditorTheme.accent, width: 2),
                  )
                : null,
          ),
          child: Row(
            children: [
              Tooltip(
                message: map.enabled
                    ? 'On when the game starts'
                    : 'Off until the game turns it on',
                child: Checkbox(
                  value: map.enabled,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: InputEditorTheme.textMuted),
                  activeColor: InputEditorTheme.accent,
                  checkColor: InputEditorTheme.background,
                  onChanged: (v) => onEnabled(v ?? false),
                ),
              ),
              Expanded(
                child: Text(
                  map.name,
                  overflow: TextOverflow.ellipsis,
                  style: selected
                      ? InputEditorTheme.body.copyWith(
                          color: InputEditorTheme.accent,
                        )
                      : InputEditorTheme.body,
                ),
              ),
              if (problems > 0)
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: InputEditorTheme.danger,
                ),
              Text('${map.actions.length}', style: InputEditorTheme.label),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: selected ? InputEditorTheme.selected : null,
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: selected
                ? InputEditorTheme.accent
                : InputEditorTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: InputEditorTheme.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
