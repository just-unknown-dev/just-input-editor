// The Input Actions editor inside the engine editor: its button, its files,
// the fields its check looks in, and a save that changes the running
// engine's controls at once — or, when the engine cannot run it, leaves
// them as they were.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart'
    show InputActionAsset, InteractionDef;
import 'package:just_inputs/testing.dart';

import '../support/temp_folder.dart';
import '../support/throwing_steps.dart';

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

  test('"New input actions" names a file not taken yet', () async {
    final root = tempFolder('input_new');
    final module = InputEditorModule(root: root.path);
    expect(module.freePath('assets/input'), 'assets/input/new.input.json');
    await File(
      '${root.path}/assets/input/new.input.json',
    ).create(recursive: true);
    expect(module.freePath('assets/input'), 'assets/input/new2.input.json');
  });

  group('actionFieldsOf: the fields the definitions make input actions', () {
    test("the engine's: simple movement's action, never a timeline "
        "trigger's", () {
      final fieldsOf = InputEditorModule.actionFieldsOf(
        BuiltInComponents.registry(),
      );
      expect(fieldsOf('SimpleMovementComponent'), {'action'});
      expect(
        fieldsOf('TimelineTriggerComponent'),
        isEmpty,
        reason: 'enterAction and exitAction say what the timeline does',
      );
      expect(fieldsOf('TransformComponent'), isEmpty);
      expect(fieldsOf('NoSuchComponent'), isEmpty);
    });

    test('read when asked: a definition registered later counts', () {
      final definitions = BuiltInComponents.registry();
      final fieldsOf = InputEditorModule.actionFieldsOf(definitions);
      expect(fieldsOf('KitControllerComponent'), isEmpty);
      definitions.register(
        ComponentDefinition<_KitController>(
          type: 'KitControllerComponent',
          create: _KitController.new,
          fields: [
            FieldDefinition(
              name: 'jumpAction',
              kind: InputDefinitions.actionType,
              read: (c) => (c as _KitController).jumpAction,
            ),
            FieldDefinition(
              name: 'combo',
              kind: InputDefinitions.actionListType,
              read: (c) => (c as _KitController).combo,
            ),
            FieldDefinition(
              name: 'sayAction',
              kind: FieldTypes.text,
              read: (c) => (c as _KitController).sayAction,
            ),
          ],
        ),
      );
      expect(fieldsOf('KitControllerComponent'), {'jumpAction', 'combo'});
    });

    testWidgets("the workspace's check reads the scope's definitions", (
      tester,
    ) async {
      final root = tempFolder('input_check');
      await tester.runAsync(() async {
        await FileInputAssetStore(
          root.path,
        ).save(InputEditorModule.defaultAssetPath, starterInputAsset());
        final scene = File('${root.path}/assets/scenes/level.scene.json');
        await scene.create(recursive: true);
        await scene.writeAsString(
          '{"entities": [{"name": "Hero", "components": ['
          '{"type": "SimpleMovementComponent", "fields": {"action": "jump"}},'
          '{"type": "TimelineTriggerComponent",'
          ' "fields": {"exitAction": "jump"}}]}]}',
        );
      });
      final module = InputEditorModule(
        root: root.path,
        gamepads: FakeGamepadSource(),
      );
      final scope = EditorScope(
        world: World(extensions: [BuiltInComponents.extension]),
        modules: [module],
      );
      addTearDown(scope.dispose);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => module.workspaces.single.build(
              context,
              WorkspaceContext(
                scope: scope,
                onClose: () {},
                path: InputEditorModule.defaultAssetPath,
              ),
            ),
          ),
        ),
      );
      // The editor's own read of the file is over first, so the folder can
      // go however the test ends.
      final state = tester.state<InputEditorState>(find.byType(InputEditor));
      for (var i = 0; i < 250 && state.session == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(state.session, isNotNull);
      final editor = tester.widget<InputEditor>(find.byType(InputEditor));
      final jump = starterInputAsset().findAction('player/jump')!.action.id;
      final found = await tester.runAsync(
        () => editor.references!.find(
          InputReferenceQuery.action(starterInputAsset(), jump),
        ),
      );
      expect(found!.map((r) => r.where), [
        'Hero · SimpleMovementComponent.action',
      ]);
    });
  });

  test('with no engine, a save goes nowhere and says nothing', () {
    final module = InputEditorModule();
    final scope = EditorScope(world: World(), modules: [module]);
    expect(scope.engine, isNull);
    expect(module.apply(scope, starterInputAsset()), isNull);
  });

  testWidgets('a save of the game\'s asset changes the running controls', (
    tester,
  ) async {
    const path = InputEditorModule.defaultAssetPath;
    final root = tempFolder('input_module');
    final engine = (await tester.runAsync(() async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.input.loadAsset(starterInputAsset());
      await FileInputAssetStore(root.path).save(path, starterInputAsset());
      return engine;
    }))!;

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

  group('with a running engine', () {
    late Engine engine;
    late Directory root;
    late InputEditorModule module;
    late EditorScope scope;

    Future<void> boot(WidgetTester tester) async {
      root = tempFolder('input_play');
      engine = (await tester.runAsync(() async {
        final engine = Engine();
        await engine.initialize();
        engine.input.loadAsset(starterInputAsset());
        return engine;
      }))!;
      addTearDown(engine.dispose);
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

    testWidgets('one the engine cannot run leaves it as it was', (
      tester,
    ) async {
      await boot(tester);
      ThrowingSteps.register();
      addTearDown(ThrowingSteps.unregister);
      final before = engine.input.asset;
      final a = starterInputAsset();
      final broken = AssetEdits.setInteractions(
        a,
        a.findAction('player/jump')!.action.id,
        const [InteractionDef('throwsOnLoad')],
      );
      final note = module.apply(scope, broken);
      expect(note, contains('cannot run it'));
      expect(identical(engine.input.asset, before), isTrue);
      // The engine's input still runs: no half-loaded service.
      engine.input.update(1);
      engine.input.update(2);
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

    testWidgets('another input file changed reaches no engine', (tester) async {
      await boot(tester);
      final before = engine.input.asset;
      await tester.runAsync(
        () => FileInputAssetStore(
          root.path,
        ).save('assets/input/menu.input.json', renamed('leap')),
      );
      module.onAssetChanged('assets/input/menu.input.json');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(identical(engine.input.asset, before), isTrue);
    });

    testWidgets('the game\'s file broken on disk leaves the engine be', (
      tester,
    ) async {
      await boot(tester);
      final before = engine.input.asset;
      await tester.runAsync(() async {
        final file = File('${root.path}/${InputEditorModule.defaultAssetPath}');
        await file.create(recursive: true);
        await file.writeAsString('{"name": 3');
      });
      // What the module says once its read is over: waited for, so the
      // file is closed again before the folder is removed (on Windows an
      // open file keeps its folder).
      final said = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => said.add(message ?? '');
      try {
        module.onAssetChanged(InputEditorModule.defaultAssetPath);
        for (var i = 0; i < 250 && said.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      } finally {
        debugPrint = print;
      }
      expect(said, [contains('changed and does not read')]);
      expect(identical(engine.input.asset, before), isTrue);
    });
  });
}

/// A kit's controller, for a definition registered after the fact.
class _KitController extends Component {
  String jumpAction = 'jump';
  List<String> combo = const [];
  String sayAction = '';
}
