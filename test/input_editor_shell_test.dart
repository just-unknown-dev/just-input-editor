import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import 'sample_asset.dart';

const _path = 'assets/input/game.input.json';

/// [text] in the actions tree — not the keyboard's legend below it.
Finder inTree(String text) => find.descendant(
  of: find.byKey(const ValueKey('actions-tree')),
  matching: find.text(text),
);

void main() {
  late MemoryInputAssetStore store;
  late List<String> saved;
  late int closed;

  setUp(() {
    store = MemoryInputAssetStore({_path: sampleAsset().encode()});
    saved = [];
    closed = 0;
  });

  Future<InputEditorState> open(
    WidgetTester tester, {
    String? path = _path,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: InputEditor(
          store: store,
          path: path,
          onSaved: (asset, path) {
            saved.add('$path:${asset.name}');
            return null;
          },
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<InputEditorState>(find.byType(InputEditor));
  }

  testWidgets('opens the file: its maps, and the first map\'s actions', (
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

  testWidgets('no file yet: the starter asset, saved where asked', (
    tester,
  ) async {
    final state = await open(tester, path: 'assets/input/new.input.json');
    expect(state.session!.asset.name, 'new');
    expect(inTree('move'), findsOneWidget);
    await state.save();
    expect(store.files.keys, contains('assets/input/new.input.json'));
  });

  testWidgets(
    'a rename is one step: dirty, saved with Ctrl+S, undone with Ctrl+Z',
    (tester) async {
      final state = await open(tester);
      await tester.tap(inTree('jump'));
      await tester.pump();
      expect(find.text('ACTION'), findsOneWidget);

      final nameField = find.byType(TextField).at(1); // after the search box
      await tester.enterText(nameField, 'hop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'hop');
      expect(state.session!.isDirty, isTrue);
      expect(find.byTooltip('Not saved'), findsOneWidget);

      // Enter gave the keys back to the editor.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(saved, ['$_path:sample']);
      expect(
        InputActionAsset.parse(
          store.files[_path]!,
        ).actionById('a10')!.action.name,
        'hop',
      );
      expect(state.session!.isDirty, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(state.session!.asset.actionById('a10')!.action.name, 'jump');
    },
  );

  testWidgets('closing with changes asks first', (tester) async {
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

  testWidgets('closing with nothing changed just closes', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Close  (Esc)'));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('a host opening something else over it asks the same', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<bool> Function()? guard;
    await tester.pumpWidget(
      MaterialApp(
        home: InputEditor(
          store: store,
          path: _path,
          setCloseGuard: (g) => guard = g,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await guard!(), isTrue, reason: 'nothing to lose');

    tester
        .state<InputEditorState>(find.byType(InputEditor))
        .session!
        .edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
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

  testWidgets('a map switched off at start, and an action added', (
    tester,
  ) async {
    final state = await open(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(state.session!.asset.mapById('m1')!.enabled, isFalse);

    await tester.tap(find.byTooltip('Add action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vector 2').last);
    await tester.pumpAndSettle();
    final added = state.session!.asset.mapById('m1')!.actions.last;
    expect(added.name, 'move2');
    expect(added.type, ActionValueType.vector2);
    expect(state.session!.selection, ActionSelection(added.id));
  });

  testWidgets('a binding another action shares is flagged', (tester) async {
    final state = await open(tester);
    state.session!.edit(
      'Clash',
      (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/w'),
    );
    await tester.pump();
    expect(
      find.byTooltip('Another action in this map uses this too'),
      findsNWidgets(2),
    );
  });
}
