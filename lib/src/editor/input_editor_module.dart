import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart'
    show ComponentDefinitionRegistry, InputDefinitions;
import 'package:just_inputs/just_inputs.dart'
    show GamepadSource, InputActionAsset, InputService, JustGamepadsSource;

import '../asset/asset.dart';
import 'input_editor.dart';

/// The Input Actions editor, as a workspace of the engine editor.
///
/// It adds:
/// - the pad button on the play toolbar, right after the sprite brush, which
///   opens the game's controls ([assetPath]);
/// - "Edit input actions" on any `.input.json` in the Assets dock, and
///   "New input actions" on folders under `assets/`;
/// - live apply: saving the game's asset puts it straight into the running
///   engine, Play or no Play — except that during a play-test a save that
///   takes an action away (renamed, moved, deleted) waits for Stop, since
///   the running game's code may still ask for it. An asset the engine's
///   input cannot take is not left half in: the one it had goes back;
/// - a check before an action or a map is renamed, moved or deleted: the
///   project's scenes and code under `lib/` are searched for its name, and
///   what would break is shown first. In scenes and prefabs, the fields
///   searched are those whose definitions make them input actions
///   ([actionFieldsOf]).
///
/// The editor is drawn in the editor's own palette ([EditorTheme]), so it
/// follows the accent and the accessibility settings the user picked.
///
/// Design-time only, like the rest of this package: a game's editor entry
/// point adds it to `JustGameEditorPlugin.register(modules: …)`.
class InputEditorModule extends EditorModule {
  /// The module for the project at [root], whose game runs [assetPath].
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

  /// The id the workspace opens by ([ScopeModules.openWorkspace]).
  static const String workspaceId = 'input_editor';

  @override
  String get id => 'game.input_editor';

  @override
  String get name => 'Input Actions';

  @override
  IconData? get icon => Icons.sports_esports;

  String get _root => root ?? Directory.current.path;

  InputAssetStore get _store => FileInputAssetStore(_root);

  /// The editor this module joined, for what happens outside a workspace:
  /// a play-test stopping, a file changing.
  EditorScope? _scope;

  /// Input assets that changed on disk, for the editors this module opened
  /// ([InputEditor.fileChanges]).
  final StreamController<String> _fileChanges = StreamController.broadcast();

  /// Saves kept from a running play-test (see [apply]), by the engine's
  /// input service — so one survives a hot reload, which makes a new module.
  static final Expando<InputActionAsset> _held = Expando('held input');

  @override
  void onRegister(EditorModuleContext context) => _scope = context.scope;

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Input Actions',
      icon: Icons.sports_esports,
      fileExtensions: const [InputActionAsset.extension],
      build: (context, workspace) => InputEditor(
        store: _store,
        path: workspace.path ?? assetPath,
        onClose: workspace.onClose,
        onSaved: (asset, path) {
          _scope = workspace.scope;
          // The game's own controls change at once — mid-Play included,
          // unless that would take an action from under it.
          final note = path == assetPath ? apply(workspace.scope, asset) : null;
          workspace.reloadAssets?.call(path);
          return note;
        },
        fullScreen: workspace.fullScreen,
        onToggleFullScreen: workspace.onToggleFullScreen,
        setCloseGuard: workspace.setCloseGuard,
        gamepads: gamepads ?? JustGamepadsSource(),
        references: FileInputReferenceFinder(
          _root,
          actionFields: actionFieldsOf(workspace.scope.definitions),
        ),
        fileChanges: _fileChanges.stream,
      ),
    ),
  ];

  /// The fields of each component that hold input actions' names, read from
  /// [definitions] when asked — so a module registered later, or a hot
  /// reload's new definitions, count: a field of the engine's input action
  /// kinds (`InputDefinitions.isActionKind`), one name or a list. A type no
  /// definition reads has none.
  static InputActionFields actionFieldsOf(
    ComponentDefinitionRegistry definitions,
  ) => (type) {
    final definition = definitions.definitionByType(type);
    if (definition == null) return const {};
    return {
      for (final field in definition.fields)
        if (InputDefinitions.isActionKind(field.kind)) field.name,
    };
  };

  /// Puts [asset] into [scope]'s running engine, and says what it did when
  /// that is not simply done:
  /// - during a play-test, an asset without an action the running one has
  ///   (renamed, moved or deleted) is kept until the play-test stops — the
  ///   game's code may still ask for it, and would find nothing, or throw,
  ///   mid-play;
  /// - an asset the engine's input cannot run is not left half loaded: the
  ///   one it had is loaded back.
  String? apply(EditorScope scope, InputActionAsset asset) {
    final input = scope.engine?.input;
    if (input == null) return null;
    if (input.asset.encode() == asset.encode()) {
      _held[input] = null;
      return null;
    }
    if (scope.isPlayTesting.value) {
      final gone = lostPaths(input.asset, asset);
      if (gone.isNotEmpty) {
        _held[input] = asset;
        final shown = gone.length > 3
            ? '${gone.take(3).join(', ')} and ${gone.length - 3} more'
            : gone.join(', ');
        return 'the running game keeps its controls until you stop: $shown '
            '${gone.length == 1 ? 'is' : 'are'} gone from it, and its code may '
            'still ask.';
      }
    }
    _held[input] = null;
    return _load(input, asset);
  }

  /// Loads [asset] into [input]; when the input system cannot run it,
  /// loads back the asset [input] had and says so — a half-loaded service
  /// would throw on every frame.
  static String? _load(InputService input, InputActionAsset asset) {
    final previous = input.asset;
    try {
      input.loadAsset(asset);
      return null;
    } on Object catch (e) {
      try {
        input.loadAsset(previous);
      } on Object catch (again) {
        debugPrint('[Input Actions] could not put the controls back: $again');
      }
      return 'but the running game cannot run it, and keeps its controls: $e';
    }
  }

  /// The `map/action` paths [running] has and [next] does not.
  static List<String> lostPaths(
    InputActionAsset running,
    InputActionAsset next,
  ) {
    final kept = {for (final r in next.actions) r.path};
    return [
      for (final r in running.actions)
        if (!kept.contains(r.path)) r.path,
    ];
  }

  @override
  void onPlayStateChanged(bool playing) {
    if (playing) return;
    final InputService? input = _scope?.engine?.input;
    if (input == null) return;
    final held = _held[input];
    if (held == null) return;
    _held[input] = null;
    final note = _load(input, held);
    if (note != null) {
      debugPrint('[Input Actions] the save kept for Stop: $note');
    }
  }

  /// An input asset changed on disk — written by a tool, dropped in from
  /// outside: an open editor hears of it, and the game's own goes into the
  /// engine as a save would.
  @override
  void onAssetChanged(String path) {
    if (!path.toLowerCase().endsWith('.${InputActionAsset.extension}')) return;
    if (!_fileChanges.isClosed) _fileChanges.add(path);
    final scope = _scope;
    if (path != assetPath || scope == null) return;
    unawaited(_reload(scope));
  }

  Future<void> _reload(EditorScope scope) async {
    final InputActionAsset asset;
    try {
      asset = await _store.load(assetPath);
    } on FormatException catch (e) {
      debugPrint('[Input Actions] $assetPath changed and does not read: $e');
      return;
    } on FileSystemException catch (e) {
      debugPrint('[Input Actions] $assetPath changed and cannot be read: $e');
      return;
    }
    final note = apply(scope, asset);
    if (note != null) debugPrint('[Input Actions] $assetPath changed: $note');
  }

  @override
  void dispose() {
    _fileChanges.close();
    super.dispose();
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
          scope.openWorkspace(workspaceId, path: freePath(path)),
    ),
  ];

  /// `folder/new.input.json`, or `new2`… — a name not taken yet in the
  /// project's [folder]. "New input actions" opens it: unsaved until saved.
  String freePath(String folder) {
    final dir = Directory('$_root/$folder');
    final taken = dir.existsSync()
        ? [
            for (final f in dir.listSync())
              f.uri.pathSegments.last.replaceAll(
                '.${InputActionAsset.extension}',
                '',
              ),
          ]
        : const <String>[];
    final name = AssetEdits.uniqueName('new', taken);
    return '$folder/$name.${InputActionAsset.extension}';
  }
}
