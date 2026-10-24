// The editor at its edges: files that do not read, names refused, numbers
// no file can hold, keys that must not be lost or doubled, Listen and the
// live test giving the keyboard back, drags that stay one undo step.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart' as gp;
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:just_inputs/testing.dart';

import 'sample_asset.dart';

const _path = 'assets/input/game.input.json';

/// [text] in the actions tree — not the live test or a legend.
Finder inTree(String text) => find.descendant(
  of: find.byKey(const ValueKey('actions-tree')),
  matching: find.text(text),
);

/// The text field on the Properties row labelled [label].
Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byType(TextField),
);

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

/// Says one scene names `jump`, whatever is asked about it.
final class _Finder implements InputReferenceFinder {
  @override
  Future<List<InputReference>> find(
    InputReferenceQuery query, {
    int limit = 50,
  }) async => [
    if (query.matches('jump'))
      const InputReference(
        'assets/scenes/level.scene.json',
        'Player · Controller.jumpAction',
        'jump',
      ),
  ];
}

void main() {
  late FakeGamepadSource pads;
  late _Store store;
  late int closed;

  setUp(() {
    pads = FakeGamepadSource();
    store = _Store({_path: sampleAsset().encode()});
    closed = 0;
  });
  tearDown(() => pads.dispose());

  Future<InputEditorState> open(
    WidgetTester tester, {
    InputReferenceFinder? references,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: InputEditor(
          store: store,
          path: _path,
          gamepads: pads,
          references: references,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<InputEditorState>(find.byType(InputEditor));
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('tab:$name')));
    await tester.pump();
  }

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

  group('a file that does not read', () {
    testWidgets('says why, and can be closed — not a spinner', (tester) async {
      store = _Store({
        _path: jsonWith((j) {
          final maps = j['maps'] as List;
          ((maps.first as Map)['actions'] as List).first['type'] = 'vector';
        }),
      });
      await open(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Could not read'), findsOneWidget);
      await tester.tap(find.text('Close'));
      expect(closed, 1);
    });

    testWidgets('a scheme with no name', (tester) async {
      store = _Store({
        _path: jsonWith((j) => (j['schemes'] as List).first.remove('name')),
      });
      await open(tester);
      expect(find.textContaining('Could not read'), findsOneWidget);
    });

    testWidgets('a store that fails another way', (tester) async {
      final failing = _Failing();
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: InputEditor(store: failing, path: _path),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('the disk is gone'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('ids behind the counter are put right on opening', (
      tester,
    ) async {
      store = _Store({_path: sampleAsset().copyWith(nextId: 3).encode()});
      final state = await open(tester);
      final s = state.session!;
      expect(s.asset.nextId, 21);
      expect(s.isDirty, isTrue);
      expect(s.undoLabel, 'Repair ids');
      expect(s.message.value, contains('nextId'));
    });
  });

  group('names', () {
    testWidgets('an emptied name is refused, said, and shown again', (
      tester,
    ) async {
      final state = await open(tester);
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      await tester.enterText(fieldOf('Name'), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
      expect(state.session!.message.value, 'An action needs a name.');
      expect(
        tester.widget<TextField>(fieldOf('Name')).controller!.text,
        'jump',
      );

      await tester.enterText(fieldOf('Name'), 'move');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
      expect(state.session!.message.value, contains('already has'));
    });

    testWidgets('F2 with a binding selected renames nothing', (tester) async {
      final state = await open(tester);
      state.session!.select(const BindingSelection('b11'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Rename map'), findsNothing);
    });

    testWidgets('what names it is shown before a rename or a delete', (
      tester,
    ) async {
      final state = await open(tester, references: _Finder());
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      await tester.enterText(fieldOf('Name'), 'hop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Rename "jump" to "hop"?'), findsOneWidget);
      expect(find.textContaining('jumpAction'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');

      await tester.enterText(fieldOf('Name'), 'hop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete "jump"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.session!.asset.actionById('a10'), isNotNull);
    });
  });

  group('numbers', () {
    testWidgets('a setting refuses NaN and Infinity', (tester) async {
      final state = await open(tester);
      await tester.tap(find.text('Players & settings'));
      await tester.pump();
      for (final bad in ['NaN', 'Infinity', '-1']) {
        await tester.enterText(fieldOf('Hold time'), bad);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(state.session!.asset.settings.holdTime, 0.4, reason: bad);
      }
      expect(state.session!.isDirty, isFalse);
      expect(state.session!.message.value, contains('Hold time'));
      await tester.enterText(fieldOf('Press point'), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(state.session!.asset.settings.pressPoint, 0.5, reason: 'past 1');
    });

    testWidgets('a step\'s number too, and it is held in its range', (
      tester,
    ) async {
      final state = await open(tester);
      state.session!.select(const ActionSelection('a18'));
      await tester.pump();
      double? duration() => state.session!.asset
          .actionById('a18')!
          .action
          .interactions
          .single
          .number('duration');
      await tester.enterText(fieldOf('Duration'), 'Infinity');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(duration(), 0.6);
      await tester.enterText(fieldOf('Duration'), '-2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(duration(), 0, reason: 'no less than its min');
      state.session!.asset.encode();
    });

    testWidgets('hand-edited settings of the wrong kind still show', (
      tester,
    ) async {
      final odd = withJump(
        sampleAsset(),
        (a) => a.copyWith(
          type: ActionValueType.vector2,
          processors: const [
            ProcessorDef('invertVector2', {'invertX': 'yes'}),
          ],
        ),
      );
      store = _Store({
        _path: AssetEdits.updateBinding(
          odd,
          'b3',
          (b) => (b as CompositeBindingDef).copyWith(
            params: const {'mode': 'Digital'},
          ),
        ).encode(),
      });
      final state = await open(tester);
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Invert X'), findsOneWidget);
      state.session!.select(const BindingSelection('b3'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Digital (unknown)'), findsOneWidget);
    });
  });

  group('text fields', () {
    testWidgets('Enter is one undo step, whatever the edit', (tester) async {
      final state = await open(tester);
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      await tester.enterText(fieldOf('Shown as'), 'Hop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.displayName, 'Hop');
      state.session!.undo();
      expect(state.session!.asset.actionById('a10')!.action.displayName, '');
      expect(state.session!.canUndo, isFalse);
    });
  });

  group('keys', () {
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
      expect(store.inner.files[_path], contains('"hop"'));
    });

    testWidgets('Ctrl+D on a part adds a part, not a map', (tester) async {
      final state = await open(tester);
      state.session!.select(const BindingSelection('b4'));
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyD);
      final asset = state.session!.asset;
      expect(asset.maps, hasLength(2));
      final wasd = asset.findBinding('b3')!.binding as CompositeBindingDef;
      expect(wasd.partsNamed('up'), hasLength(2));
    });
  });

  group('Listen', () {
    Future<void> listen(
      WidgetTester tester,
      InputEditorState state,
      String id,
    ) async {
      state.session!.select(BindingSelection(id));
      await tester.pump();
      await tester.tap(find.text('Listen'));
      await tester.pump();
    }

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key,
      PhysicalKeyboardKey physical,
    ) async {
      await tester.sendKeyDownEvent(key, physicalKey: physical);
      await tester.pump();
      await tester.sendKeyUpEvent(key, physicalKey: physical);
      await tester.pump();
    }

    testWidgets('hears the same key twice running', (tester) async {
      final state = await open(tester);
      await listen(tester, state, 'b11');
      await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/j');

      await listen(tester, state, 'b16');
      await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
      expect(state.session!.asset.findBinding('b16')!.path, '<Keyboard>/j');
    });

    testWidgets('Escape gives up every time', (tester) async {
      final state = await open(tester);
      for (var i = 0; i < 2; i++) {
        await listen(tester, state, 'b11');
        expect(state.harness.isListening, isTrue);
        await press(
          tester,
          LogicalKeyboardKey.escape,
          PhysicalKeyboardKey.escape,
        );
        expect(state.harness.isListening, isFalse, reason: 'press ${i + 1}');
      }
      expect(closed, 0, reason: 'Listen\'s Escape is not the editor\'s');
    });

    testWidgets('gives up when something else is picked', (tester) async {
      final state = await open(tester);
      await listen(tester, state, 'b11');
      state.session!.select(const BindingSelection('b12'));
      await tester.pump();
      expect(state.harness.isListening, isFalse);
      await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/space');
    });
  });

  group('the live test', () {
    testWidgets('a click elsewhere gives the keys back to the editor', (
      tester,
    ) async {
      final state = await open(tester);
      await tab(tester, 'live');
      await tester.tap(
        find.byKey(const ValueKey('live-area')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyD,
        physicalKey: PhysicalKeyboardKey.keyD,
      );
      await tester.pump();
      final keyboard = state.harness.service.keyboard;
      expect(keyboard.isDown(PhysicalKeyboardKey.keyD, live: true), isTrue);

      await tester.tap(inTree('jump'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(
        keyboard.isDown(PhysicalKeyboardKey.keyD, live: true),
        isFalse,
        reason: 'what was held is let go',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyD,
        physicalKey: PhysicalKeyboardKey.keyD,
      );
      expect(state.session!.selection, const ActionSelection('a10'));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(state.session!.asset.actionById('a10'), isNull);
      await tab(tester, 'keyboard');
    });

    testWidgets('its clock goes on from where it was', (tester) async {
      final state = await open(tester);
      await tab(tester, 'live');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final before = state.harness.time;
      expect(before, greaterThan(0.1));
      await tab(tester, 'keyboard');
      await tab(tester, 'live');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(state.harness.time, greaterThan(before));
      expect(state.harness.service.time, greaterThan(before));
      await tab(tester, 'keyboard');
    });

    testWidgets('pads are caught up without it', (tester) async {
      final state = await open(tester);
      pads.connect('p');
      await tester.pump();
      pads.press('p', gp.GamepadButton.a);
      await tester.pump();
      final pad = state.harness.service.gamepads.single;
      expect(pad.applied.pad.buttonsDown, contains(gp.GamepadButton.a));
      pads.release('p');
      await tester.pump();
      expect(pad.applied.pad.buttonsDown, isEmpty);
    });
  });

  group('drags', () {
    testWidgets('editing keys wait for the drag to end', (tester) async {
      final state = await open(tester);
      await tab(tester, 'touch');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('onscreen:jump'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(state.session!.selection, const OnScreenSelection('jump'));
      expect(
        state.harness.service.asset.onScreenControl('jump')!.anchorX,
        0.72,
        reason: 'the live copy is not run again on every move',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(state.session!.asset.onScreenControl('jump'), isNotNull);
      await gesture.up();
      await tester.pump();
      expect(
        state.harness.service.asset.onScreenControl('jump')!.anchorX,
        state.session!.asset.onScreenControl('jump')!.anchorX,
      );
      state.session!.undo();
      expect(state.session!.asset.onScreenControl('jump')!.anchorX, 0.72);
    });

    testWidgets('what is dragged going away mid-drag ends the drag', (
      tester,
    ) async {
      final state = await open(tester);
      await tab(tester, 'touch');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('onscreen:jump'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      final s = state.session!;
      s.edit('Gone', (a) => AssetEdits.deleteOnScreen(a, 'jump'));
      await tester.pump();
      expect(s.inGesture, isFalse);
      await gesture.up();
      s.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      s.edit('b', (a) => AssetEdits.renameAction(a, 'a10', 'leap'));
      s.undo();
      expect(s.asset.actionById('a10')!.action.name, 'hop');
    });
  });

  testWidgets('no more than four players', (tester) async {
    final state = await open(tester);
    await tester.tap(find.text('Players & settings'));
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(state.session!.asset.players.maxPlayers, 4);
  });

  group('the file changed on disk', () {
    testWidgets('read again when nothing is unsaved', (tester) async {
      final state = await open(tester);
      store.inner.files[_path] = AssetEdits.renameAction(
        sampleAsset(),
        'a10',
        'hop',
      ).encode();
      InputEditor.fileChanged(_path);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'hop');
      expect(state.session!.isDirty, isFalse);
    });

    testWidgets('kept, and said, when there are changes', (tester) async {
      final state = await open(tester);
      state.session!.edit(
        'x',
        (a) => AssetEdits.renameAction(a, 'a10', 'leap'),
      );
      store.inner.files[_path] = AssetEdits.renameAction(
        sampleAsset(),
        'a10',
        'hop',
      ).encode();
      InputEditor.fileChanged(_path);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'leap');
      expect(state.session!.message.value, contains('changed on disk'));
    });

    testWidgets('its own save is not news', (tester) async {
      final state = await open(tester);
      state.session!.edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      await state.save();
      InputEditor.fileChanged(_path);
      await tester.pump();
      expect(state.session!.canUndo, isTrue, reason: 'not read again');
    });
  });
}
