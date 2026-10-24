// The Input Actions editor inside the engine editor: its button, its files,
// and a save that changes the running engine's controls at once.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('its workspace opens .input.json files', () {
    final module = InputEditorModule();
    final workspace = module.workspaces.single;
    expect(workspace.id, InputEditorModule.workspaceId);
    expect(workspace.fileExtensions, ['input.json']);
    expect(workspace.presentation, WorkspacePresentation.dialog);
  });

  test('its button opens the game\'s controls, after the default 100', () {
    final module = InputEditorModule(assetPath: 'assets/input/mine.input.json');
    final button = module.toolbarButtons.single;
    expect(button.id, 'input_editor.open');
    expect(button.order, 101);
    expect(module.assetPath, 'assets/input/mine.input.json');
    expect(InputEditorModule().assetPath, InputEditorModule.defaultAssetPath);
  });

  test('the Assets dock offers edit on its files and new on folders', () {
    final actions = InputEditorModule().assetActions;
    final edit = actions.firstWhere((a) => a.id == 'input_editor.edit');
    final make = actions.firstWhere((a) => a.id == 'input_editor.new');
    expect(
      edit.appliesTo(InputEditorModule.defaultAssetPath, isDirectory: false),
      isTrue,
    );
    expect(
      edit.appliesTo('assets/scenes/level_01.scene.json', isDirectory: false),
      isFalse,
    );
    expect(make.appliesTo('assets/input', isDirectory: true), isTrue);
    expect(make.appliesTo('lib', isDirectory: true), isFalse);
  });

  testWidgets('a save of the game\'s asset changes the running controls', (
    tester,
  ) async {
    const path = InputEditorModule.defaultAssetPath;
    final (engine, root) = (await tester.runAsync(() async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.input.loadAsset(starterInputAsset());
      final root = await Directory.systemTemp.createTemp('input_module');
      await FileInputAssetStore(root.path).save(path, starterInputAsset());
      return (engine, root);
    }))!;
    addTearDown(() {
      // Windows may still hold the folder for a moment; it is a temp one.
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException catch (_) {}
    });

    final module = InputEditorModule(
      root: root.path,
      gamepads: FakeGamepadSource(),
    );
    final scope = EditorScope(engine: engine, modules: [module]);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => module.workspaces.single.build(
            context,
            WorkspaceContext(scope: scope, onClose: () {}, path: path),
          ),
        ),
      ),
    );
    // The file is read for real: let real time pass until it is in.
    final state = tester.state<InputEditorState>(find.byType(InputEditor));
    // Up to 5 s: other test files share the disk while the suite runs.
    for (var i = 0; i < 250 && state.session == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(state.session!.asset.name, 'game');
    state.session!.edit('Rename jump', (a) {
      final id = a.findAction('player/jump')!.action.id;
      return AssetEdits.updateAction(
        a,
        id,
        (x) => x.copyWith(displayName: 'Hop'),
      );
    });
    await tester.runAsync(state.save);

    expect(
      engine.input.asset.findAction('player/jump')!.action.displayName,
      'Hop',
    );
    final onDisk = await tester.runAsync(
      () => FileInputAssetStore(root.path).load(path),
    );
    expect(onDisk!.findAction('player/jump')!.action.displayName, 'Hop');
  });

  group('during a play-test', () {
    late Engine engine;
    late Directory root;
    late InputEditorModule module;
    late EditorScope scope;

    Future<void> boot(WidgetTester tester) async {
      (engine, root) = (await tester.runAsync(() async {
        final engine = Engine();
        await engine.initialize();
        engine.input.loadAsset(starterInputAsset());
        final root = await Directory.systemTemp.createTemp('input_play');
        return (engine, root);
      }))!;
      addTearDown(engine.dispose);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException catch (_) {}
      });
      module = InputEditorModule(
        root: root.path,
        gamepads: FakeGamepadSource(),
      );
      scope = EditorScope(engine: engine, modules: [module]);
    }

    InputActionAsset renamed(String name) {
      final a = starterInputAsset();
      final id = a.findAction('player/jump')!.action.id;
      return AssetEdits.renameAction(a, id, name);
    }

    testWidgets('a save that takes an action away waits for Stop', (
      tester,
    ) async {
      await boot(tester);
      scope.isPlayTesting.value = true;
      final note = module.apply(scope, renamed('hop'));
      expect(note, contains('player/jump'));
      expect(
        engine.input.asset.findAction('player/jump'),
        isNotNull,
        reason: 'the running game still asks for it',
      );

      scope.isPlayTesting.value = false;
      module.onPlayStateChanged(false);
      expect(engine.input.asset.findAction('player/hop'), isNotNull);
      expect(engine.input.asset.findAction('player/jump'), isNull);
    });

    testWidgets('one that only adds or changes goes in at once', (
      tester,
    ) async {
      await boot(tester);
      scope.isPlayTesting.value = true;
      final a = starterInputAsset();
      final id = a.findAction('player/jump')!.action.id;
      final note = module.apply(
        scope,
        AssetEdits.updateAction(a, id, (x) => x.copyWith(displayName: 'Hop')),
      );
      expect(note, isNull);
      expect(
        engine.input.asset.findAction('player/jump')!.action.displayName,
        'Hop',
      );
    });

    testWidgets('the game\'s file changed on disk goes into the engine', (
      tester,
    ) async {
      await boot(tester);
      await tester.runAsync(
        () => FileInputAssetStore(
          root.path,
        ).save(InputEditorModule.defaultAssetPath, renamed('leap')),
      );
      module.onAssetChanged(InputEditorModule.defaultAssetPath);
      for (var i = 0; i < 250; i++) {
        if (engine.input.asset.findAction('player/leap') != null) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(engine.input.asset.findAction('player/leap'), isNotNull);
    });
  });
}
