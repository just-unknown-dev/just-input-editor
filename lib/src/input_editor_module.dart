import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_inputs/just_inputs.dart'
    show GamepadSource, InputActionAsset, JustGamepadsSource;

import 'editor/core/asset_edits.dart';
import 'editor/core/asset_store.dart';
import 'editor/widgets/editor_theme.dart';
import 'editor/widgets/input_editor.dart';

/// The Input Actions editor, as a workspace of the engine editor.
///
/// It adds:
/// - the pad button on the play toolbar, right after the sprite brush, which
///   opens the game's controls ([assetPath]);
/// - "Edit input actions" on any `.input.json` in the Assets dock, and
///   "New input actions" on folders under `assets/`;
/// - live apply: saving the game's asset puts it straight into the running
///   engine, Play or no Play.
///
/// Design-time only, like the rest of this package: a game's editor entry
/// point adds it to `JustGameEditorPlugin.register(modules: …)`.
class InputEditorModule extends EditorModule {
  InputEditorModule({
    this.root,
    this.assetPath = defaultAssetPath,
    this.gamepads,
  });

  /// Where a game keeps its input actions, unless it says otherwise.
  static const String defaultAssetPath = 'assets/input/game.input.json';

  /// The project folder; the working directory when null.
  final String? root;

  /// The asset the game runs on — the one the toolbar opens and a save
  /// applies live.
  final String assetPath;

  /// Pads for Listen and the live test; the real ones when null.
  final GamepadSource? gamepads;

  static const String workspaceId = 'input_editor';

  @override
  String get id => 'game.input_editor';

  @override
  String get name => 'Input Actions';

  @override
  IconData? get icon => Icons.sports_esports;

  InputAssetStore get _store =>
      FileInputAssetStore(root ?? Directory.current.path);

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Input Actions',
      icon: Icons.sports_esports,
      fileExtensions: const [InputActionAsset.extension],
      build: (context, workspace) => _matchingTheEditor(
        InputEditor(
          store: _store,
          path: workspace.path ?? assetPath,
          onClose: workspace.onClose,
          onSaved: (asset, path) {
            // The game's own controls change at once — mid-Play included.
            if (path == assetPath) {
              workspace.scope.engine?.input.loadAsset(asset);
            }
            workspace.reloadAssets?.call(path);
          },
          fullScreen: workspace.fullScreen,
          onToggleFullScreen: workspace.onToggleFullScreen,
          setCloseGuard: workspace.setCloseGuard,
          gamepads: gamepads ?? JustGamepadsSource(),
        ),
      ),
    ),
  ];

  /// [child], drawn in the editor's palette: the input editor's colours are
  /// set from it every time the editor builds the workspace — which it does
  /// again when the user picks another accent.
  static Widget _matchingTheEditor(Widget child) {
    final t = EditorTheme.current;
    InputEditorTheme.palette = InputEditorPalette(
      background: t.dialogBg,
      panel: t.menuBg,
      panelRaised: t.panelRaised,
      field: t.surfaceDarker,
      border: t.borderStrong,
      workArea: t.panelBg,
      text: t.textPrimary,
      textMuted: t.textMuted,
      accent: t.primaryBright,
      selected: t.selectionBg,
      danger: t.error,
      warning: t.warning,
      ok: t.success,
    );
    return child;
  }

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'input_editor.open',
      icon: Icons.sports_esports,
      tooltip: 'Input Actions: controls for every player',
      // Right after the sprite editor's brush, which keeps the default 100.
      order: 101,
      isActive: (scope) =>
          scope.activeWorkspace.value?.definition.id == workspaceId,
      onPressed: (scope) => scope.openWorkspace(workspaceId, path: assetPath),
    ),
  ];

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: 'input_editor.edit',
      label: 'Edit input actions',
      icon: Icons.sports_esports,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory &&
          path.toLowerCase().endsWith('.${InputActionAsset.extension}'),
      run: (scope, path) => scope.openWorkspace(workspaceId, path: path),
    ),
    AssetAction(
      id: 'input_editor.new',
      label: 'New input actions',
      icon: Icons.add_circle_outline,
      order: 130,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && (path == 'assets' || path.startsWith('assets/')),
      run: (scope, path) =>
          scope.openWorkspace(workspaceId, path: _freePath(path)),
    ),
  ];

  /// `folder/new.input.json`, or `new2`… — a name not taken yet.
  String _freePath(String folder) {
    final dir = Directory('${root ?? Directory.current.path}/$folder');
    final taken = dir.existsSync()
        ? [
            for (final f in dir.listSync())
              f.uri.pathSegments.last.replaceAll(
                '.${InputActionAsset.extension}',
                '',
              ),
          ]
        : const <String>[];
    return '$folder/${AssetEdits.uniqueName('new', taken)}.${InputActionAsset.extension}';
  }
}
