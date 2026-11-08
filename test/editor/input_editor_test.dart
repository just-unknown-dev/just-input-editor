// The editor as a whole: opening a file (or none), saving, closing and the
// host's guard, keys, a file changed on disk, a host that hands it another
// file, and what each change rebuilds.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:just_inputs/testing.dart';

import '../support/open_editor.dart';
import '../support/sample_asset.dart';

/// A store that counts saves, and can hold one until let go.
final class _Store implements InputAssetStore {
  _Store(Map<String, String> files) : inner = MemoryInputAssetStore(files);

  final MemoryInputAssetStore inner;
  int saves = 0;
  Completer<void>? hold;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<InputActionAsset> load(String path) => inner.load(path);

  @override
  Future<void> save(String path, InputActionAsset asset) async {
    saves++;
    await hold?.future;
    await inner.save(path, asset);
  }
}

/// A store whose file is there but cannot be read.
final class _Failing implements InputAssetStore {
  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<InputActionAsset> load(String path) async =>
      throw StateError('the disk is gone');

  @override
  Future<void> save(String path, InputActionAsset asset) async {}
}

/// Says one scene names `jump`, whatever is asked about it — once [answer]
/// lets it.
final class _Finder implements InputReferenceFinder {
  Completer<void>? answer;

  @override
  Future<List<InputReference>> find(
    InputReferenceQuery query, {
    int limit = 50,
  }) async {
    await answer?.future;
    return [
      if (query.matches('jump'))
        const InputReference(
          'assets/scenes/level.scene.json',
          'Player · Controller.jumpAction',
          'jump',
        ),
    ];
  }
}

void main() {
  late FakeGamepadSource pads;
  late _Store store;
  late int closed;
  late List<String> saved;

  setUp(() {
    pads = FakeGamepadSource();
    store = _Store({samplePath: sampleAsset().encode()});
    closed = 0;
    saved = [];
  });
  tearDown(() => pads.dispose());

  Future<InputEditorState> open(
    WidgetTester tester, {
    String? path = samplePath,
    InputReferenceFinder? references,
    Stream<String>? fileChanges,
    void Function(Future<bool> Function()? guard)? setCloseGuard,
  }) => openEditor(
    tester,
    store: store,
    path: path,
    gamepads: pads,
    references: references,
    fileChanges: fileChanges,
    setCloseGuard: setCloseGuard,
    onClose: () => closed++,
    onSaved: (asset, path) {
      saved.add('$path:${asset.name}');
      return null;
    },
  );

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  String jsonWith(void Function(Map<String, dynamic> json) change) {
    final json = sampleAsset().toJson();
    change(json);
    return jsonEncode(json);
  }

  group('opening', () {
    testWidgets('the file: its maps, and the first map\'s actions', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('player'), findsWidgets);
      expect(find.text('ui'), findsOneWidget);
      expect(inTree('move'), findsOneWidget);
      expect(inTree('jump'), findsOneWidget);
      expect(
        inTree('W'),
        findsOneWidget,
        reason: 'the WASD parts, by their keys',
      );
      expect(inTree('Left Stick'), findsOneWidget);

      await tester.tap(find.text('ui'));
      await tester.pump();
      expect(inTree('pause'), findsOneWidget);
      expect(inTree('move'), findsNothing);
    });

    testWidgets('no file yet: the starter, unsaved until it is saved', (
      tester,
    ) async {
      final state = await open(tester, path: 'assets/input/new.input.json');
      expect(state.session!.asset.name, 'new');
      expect(inTree('move'), findsOneWidget);
      expect(state.session!.isDirty, isTrue, reason: 'there is no file yet');
      expect(find.byTooltip('Not saved'), findsOneWidget);

      // Closed without saving: asked, as for any unsaved work.
      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes to new.input.json?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, 0);

      await state.save();
      expect(store.inner.files.keys, contains('assets/input/new.input.json'));
      expect(state.session!.isDirty, isFalse);
    });

    testWidgets('a file that does not read says why, and can be closed', (
      tester,
    ) async {
      store = _Store({
        samplePath: jsonWith((j) {
          final maps = j['maps'] as List;
          ((maps.first as Map)['actions'] as List).first['type'] = 'vector';
        }),
      });
      final state = await open(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Could not read'), findsOneWidget);
      expect(state.harness, isNull, reason: 'no input service for nothing');
      await tester.tap(find.text('Close'));
      expect(closed, 1);
    });

    testWidgets('a scheme with no name does not read either', (tester) async {
      store = _Store({
        samplePath: jsonWith(
          (j) => (j['schemes'] as List).first.remove('name'),
        ),
      });
      await open(tester);
      expect(find.textContaining('Could not read'), findsOneWidget);
    });

    testWidgets('a store that fails another way', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: InputEditor(store: _Failing(), path: samplePath),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('the disk is gone'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      // Closed with nothing read: no input service was made to throw away.
      final state = tester.state<InputEditorState>(find.byType(InputEditor));
      expect(state.harness, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ids behind the counter are put right on opening', (
      tester,
    ) async {
      store = _Store({samplePath: sampleAsset().copyWith(nextId: 3).encode()});
      final state = await open(tester);
      final s = state.session!;
      expect(s.asset.nextId, 21);
      expect(s.isDirty, isTrue);
      expect(s.undoLabel, 'Repair ids');
      expect(s.message.value, contains('nextId'));
    });

    testWidgets('another file from the host is opened in its place', (
      tester,
    ) async {
      store.inner.files['assets/input/menu.input.json'] = starterInputAsset(
        name: 'menu',
      ).encode();
      final state = await open(tester);
      final first = state.session!;
      await tester.pumpWidget(
        MaterialApp(
          home: InputEditor(
            store: store,
            path: 'assets/input/menu.input.json',
            gamepads: pads,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(InputEditor)), state),
        isTrue,
        reason: 'the same widget, given another path',
      );
      expect(state.session, isNot(same(first)));
      expect(state.session!.path, 'assets/input/menu.input.json');
      expect(state.session!.asset.name, 'menu');
    });
  });

  group('saving', () {
    testWidgets('a rename is one step: dirty, Ctrl+S saves, Ctrl+Z undoes', (
      tester,
    ) async {
      final state = await open(tester);
      await tester.tap(inTree('jump'));
      await tester.pump();
      expect(find.text('ACTION'), findsOneWidget);

      final nameField = find.byType(TextField).at(1); // after the search box
      await commit(tester, nameField, 'hop');
      expect(state.session!.asset.actionById('a10')!.action.name, 'hop');
      expect(state.session!.isDirty, isTrue);
      expect(find.byTooltip('Not saved'), findsOneWidget);

      // Enter gave the keys back to the editor.
      await chord(tester, LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(saved, ['$samplePath:sample']);
      expect(
        InputActionAsset.parse(
          store.inner.files[samplePath]!,
        ).actionById('a10')!.action.name,
        'hop',
      );
      expect(state.session!.isDirty, isFalse);

      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
    });

    testWidgets('Ctrl+S held down saves once', (tester) async {
      await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyS);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(store.saves, 1);
    });

    testWidgets('a change made while saving stays unsaved', (tester) async {
      final state = await open(tester);
      final s = state.session!;
      s.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      store.hold = Completer();
      final saving = state.save();
      await tester.pump();
      s.edit('b', (a) => AssetEdits.renameAction(a, 'a10', 'leap'));
      store.hold!.complete();
      await saving;
      expect(s.isDirty, isTrue);
      expect(store.inner.files[samplePath], contains('"hop"'));
    });

    testWidgets('a save waits for a rename still being checked', (
      tester,
    ) async {
      final finder = _Finder()..answer = Completer();
      final state = await open(tester, references: finder);
      await selectIn(tester, state, const ActionSelection('a2'));
      await commit(tester, fieldOf('Name'), 'walk');
      final saving = state.save();
      await tester.pump();
      expect(store.saves, 0, reason: 'the rename is not in yet');
      finder.answer!.complete();
      await tester.pumpAndSettle();
      await saving;
      expect(store.inner.files[samplePath], contains('"walk"'));
      expect(state.session!.isDirty, isFalse);
    });
  });

  group('closing', () {
    testWidgets('with changes, it asks first', (tester) async {
      final state = await open(tester);
      state.session!.edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      await tester.pump();

      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes to game.input.json?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, 0);

      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't save"));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(saved, isEmpty);
    });

    testWidgets('with nothing changed, it just closes', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('a rename still being checked is asked about too', (
      tester,
    ) async {
      final finder = _Finder()..answer = Completer();
      final state = await open(tester, references: finder);
      await selectIn(tester, state, const ActionSelection('a2'));
      await tester.enterText(fieldOf('Name'), 'walk');
      // Close, straight from typing: the field is left, the rename waits
      // on the search, and Close must wait for it.
      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pump();
      expect(state.session!.isChecking, isTrue);
      expect(closed, 0);
      finder.answer!.complete();
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a2')!.action.name, 'walk');
      expect(find.text('Save changes to game.input.json?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, 0);
    });

    testWidgets('a host opening something else over it asks the same', (
      tester,
    ) async {
      Future<bool> Function()? guard;
      final state = await open(tester, setCloseGuard: (g) => guard = g);
      expect(await guard!(), isTrue, reason: 'nothing to lose');

      state.session!.edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      await tester.pump();
      final answer = guard!();
      await tester.pumpAndSettle();
      expect(find.text('Save changes to game.input.json?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(guard, isNull, reason: 'gone with it');
    });
  });

  group('names refused or checked', () {
    testWidgets('an emptied name is refused, said, and shown again', (
      tester,
    ) async {
      final state = await open(tester);
      await selectIn(tester, state, const ActionSelection('a10'));
      await commit(tester, fieldOf('Name'), '');
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
      expect(state.session!.message.value, 'An action needs a name.');
      expect(
        tester.widget<TextField>(fieldOf('Name')).controller!.text,
        'jump',
      );

      await commit(tester, fieldOf('Name'), 'move');
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
      expect(state.session!.message.value, contains('already has'));
    });

    testWidgets('F2 with a binding selected renames nothing', (tester) async {
      final state = await open(tester);
      await selectIn(tester, state, const BindingSelection('b11'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Rename map'), findsNothing);
    });

    testWidgets('F2 with nothing selected renames the map, by the rule', (
      tester,
    ) async {
      final state = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Rename map'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'my map');
      await tester.pump();
      expect(find.textContaining('is not a name'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'hero');
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.mapById('m1')!.name, 'hero');
    });

    testWidgets('what names it is shown before a rename or a delete', (
      tester,
    ) async {
      final state = await open(tester, references: _Finder());
      await selectIn(tester, state, const ActionSelection('a10'));
      await commit(tester, fieldOf('Name'), 'hop');
      await tester.pumpAndSettle();
      expect(find.text('Rename "jump" to "hop"?'), findsOneWidget);
      expect(find.textContaining('jumpAction'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
      expect(
        tester.widget<TextField>(fieldOf('Name')).controller!.text,
        'jump',
        reason: 'called off: the field shows the name kept',
      );

      await commit(tester, fieldOf('Name'), 'hop');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go ahead'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a10')!.action.name, 'hop');

      // Its new name is found nowhere: a delete goes ahead without asking.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(state.session!.asset.actionById('a10'), isNull);
    });

    testWidgets('a delete asks too', (tester) async {
      final state = await open(tester, references: _Finder());
      await selectIn(tester, state, const ActionSelection('a10'));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete "jump"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a10'), isNotNull);
    });
  });

  testWidgets('Ctrl+D on a part adds a part, not a map', (tester) async {
    final state = await open(tester);
    await selectIn(tester, state, const BindingSelection('b4'));
    await chord(tester, LogicalKeyboardKey.keyD);
    final asset = state.session!.asset;
    expect(asset.maps, hasLength(2));
    final wasd = asset.findBinding('b3')!.binding as CompositeBindingDef;
    expect(wasd.partsNamed('up'), hasLength(2));
  });

  group('the file changed on disk', () {
    late StreamController<String> changes;

    setUp(() => changes = StreamController<String>.broadcast());
    tearDown(() => changes.close());

    testWidgets('read again when nothing is unsaved', (tester) async {
      final state = await open(tester, fileChanges: changes.stream);
      store.inner.files[samplePath] = AssetEdits.renameAction(
        sampleAsset(),
        'a10',
        'hop',
      ).encode();
      changes.add(samplePath);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'hop');
      expect(state.session!.isDirty, isFalse);
    });

    testWidgets('kept, and said, when there are changes', (tester) async {
      final state = await open(tester, fileChanges: changes.stream);
      state.session!.edit(
        'x',
        (a) => AssetEdits.renameAction(a, 'a10', 'leap'),
      );
      store.inner.files[samplePath] = AssetEdits.renameAction(
        sampleAsset(),
        'a10',
        'hop',
      ).encode();
      changes.add(samplePath);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'leap');
      expect(state.session!.message.value, contains('changed on disk'));
    });

    testWidgets('its own save is not news', (tester) async {
      final state = await open(tester, fileChanges: changes.stream);
      state.session!.edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      await state.save();
      changes.add(samplePath);
      await tester.pump();
      expect(state.session!.canUndo, isTrue, reason: 'not read again');
    });

    testWidgets('another file is not this one', (tester) async {
      final state = await open(tester, fileChanges: changes.stream);
      changes.add('assets/input/other.input.json');
      await tester.pump();
      expect(state.session!.message.value, isNull);
    });
  });

  group('each part rebuilds on what it shows', () {
    // The editor's parts, by their widgets' types.
    const parts = {
      'WorkspaceHeader',
      '_SchemeFilter',
      'MapsColumn',
      'ActionsTree',
      'PropertiesPanel',
      'BottomPanel',
      '_StatusLine',
    };
    final all = {for (final p in parts) p: 1};

    /// How often each part is built for [change], up to the frame after.
    Future<Map<String, int>> builtFor(
      WidgetTester tester,
      FutureOr<void> Function() change,
    ) async {
      final built = <String, int>{};
      debugOnRebuildDirtyWidget = (element, _) {
        final type = '${element.widget.runtimeType}';
        if (parts.contains(type)) built[type] = (built[type] ?? 0) + 1;
      };
      try {
        await change();
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return built;
    }

    testWidgets('a selection: not the header, the chips or the status line', (
      tester,
    ) async {
      final s = (await open(tester)).session!;
      expect(
        await builtFor(tester, () => s.select(const ActionSelection('a15'))),
        {
          'MapsColumn': 1,
          'ActionsTree': 1,
          'PropertiesPanel': 1,
          'BottomPanel': 1,
        },
      );
      expect(find.text('ACTION'), findsOneWidget);
      expect(inTree('join'), findsOneWidget, reason: 'its map shown');
    });

    testWidgets('a search: the tree alone', (tester) async {
      final s = (await open(tester)).session!;
      expect(await builtFor(tester, () => s.search = 'jump'), {
        'ActionsTree': 1,
      });
      expect(inTree('jump'), findsOneWidget);
      expect(inTree('move'), findsNothing);
    });

    testWidgets('a scheme filter: all but the header', (tester) async {
      final s = (await open(tester)).session!;
      expect(
        await builtFor(tester, () => s.schemeFilter = 'Gamepad'),
        {...all}..remove('WorkspaceHeader'),
      );
    });

    testWidgets('a drag: the problems once, when it ends', (tester) async {
      final s = (await open(tester)).session!;
      void move(double x) => s.edit(
        'Move button',
        (a) =>
            AssetEdits.updateOnScreen(a, 'jump', (c) => c.copyWith(anchorX: x)),
      );
      s.beginGesture();
      for (final x in [0.1, 0.2, 0.3]) {
        expect(
          await builtFor(tester, () => move(x)),
          {...all}..remove('_StatusLine'),
          reason: 'the problems stay as they were through a drag',
        );
      }
      expect(await builtFor(tester, s.endGesture), all);
    });

    testWidgets('an edit: every part', (tester) async {
      final s = (await open(tester)).session!;
      expect(
        await builtFor(
          tester,
          () => s.edit(
            'Rename jump',
            (a) => AssetEdits.renameAction(a, 'a10', 'hop'),
          ),
        ),
        all,
      );
      expect(inTree('hop'), findsOneWidget);
    });

    testWidgets('a save: the header alone; a word said: no part', (
      tester,
    ) async {
      final state = await open(tester);
      final s = state.session!;
      s.edit('Rename jump', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      await tester.pump();
      expect(find.byTooltip('Not saved'), findsOneWidget);
      expect(await builtFor(tester, state.save), {'WorkspaceHeader': 1});
      expect(find.byTooltip('Not saved'), findsNothing);
      expect(find.text('Saved game.input.json'), findsOneWidget);
      expect(await builtFor(tester, () => s.say('Hello')), isEmpty);
      expect(find.text('Hello'), findsOneWidget);
    });
  });
}
