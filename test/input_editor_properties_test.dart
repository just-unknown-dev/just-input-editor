import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart' as gp;
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:just_inputs/testing.dart';

import 'sample_asset.dart';

const _path = 'assets/input/game.input.json';

void main() {
  late FakeGamepadSource pads;

  setUp(() => pads = FakeGamepadSource());
  tearDown(() => pads.dispose());

  Future<InputEditorState> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: InputEditor(
          store: MemoryInputAssetStore({_path: sampleAsset().encode()}),
          path: _path,
          gamepads: pads,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<InputEditorState>(find.byType(InputEditor));
  }

  Future<void> select(
    WidgetTester tester,
    InputEditorState state,
    EditorSelection s,
  ) async {
    state.session!.select(s);
    await tester.pump();
  }

  group('a binding\'s control', () {
    testWidgets('picked from the list — Escape, which Listen cannot hear', (
      tester,
    ) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b11'));
      expect(find.text('Space'), findsWidgets);

      await tester.tap(find.text('Pick…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'esc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('<Keyboard>/escape'));
      await tester.pumpAndSettle();

      expect(
        state.session!.asset.findBinding('b11')!.path,
        '<Keyboard>/escape',
      );
    });

    testWidgets('the picker offers what fits: sticks for a vector', (
      tester,
    ) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b8'));
      await tester.tap(find.text('Pick…'));
      await tester.pumpAndSettle();
      // It opens on the device the binding is on.
      expect(find.text('<Gamepad>/rightStick'), findsOneWidget);
      expect(find.text('<Gamepad>/buttonSouth'), findsNothing);
      await tester.tap(find.text('<Gamepad>/rightStick'));
      await tester.pumpAndSettle();
      expect(
        state.session!.asset.findBinding('b8')!.path,
        '<Gamepad>/rightStick',
      );
    });

    testWidgets('Listen: press a key and it is bound', (tester) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b11'));
      await tester.tap(find.text('Listen'));
      await tester.pump();
      expect(find.textContaining('Press a key'), findsOneWidget);

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyJ,
        physicalKey: PhysicalKeyboardKey.keyJ,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyJ,
        physicalKey: PhysicalKeyboardKey.keyJ,
      );
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/j');
      expect(state.session!.undoLabel, 'Bind control');
    });

    testWidgets('Listen: a pad button counts too', (tester) async {
      final state = await open(tester);
      pads.connect('p');
      await select(tester, state, const BindingSelection('b12'));
      await tester.tap(find.text('Listen'));
      await tester.pump();
      pads.press('p', gp.GamepadButton.y);
      await tester.pumpAndSettle();
      expect(
        state.session!.asset.findBinding('b12')!.path,
        '<Gamepad>/buttonNorth',
      );
    });

    testWidgets('Listen: Escape gives up, and the binding stays', (
      tester,
    ) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b11'));
      await tester.tap(find.text('Listen'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/space');
      expect(find.textContaining('Press a key'), findsNothing);
      expect(state.harness.isListening, isFalse);
    });

    testWidgets('cleared', (tester) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b11'));
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.path, '');
      expect(find.text('<not bound>'), findsOneWidget);
    });

    testWidgets('its schemes: ticked, and none means every one', (
      tester,
    ) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b11'));
      await tester.tap(find.byKey(const ValueKey('scheme:Gamepad')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.binding.groups, [
        'KeyboardMouse',
        'Gamepad',
      ]);
      await tester.tap(find.byKey(const ValueKey('scheme:KeyboardMouse')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('scheme:Gamepad')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.binding.groups, isEmpty);
      expect(
        find.text('None ticked: it counts in every scheme.'),
        findsOneWidget,
      );
    });
  });

  group('an action', () {
    testWidgets('its type, and what players may rebind', (tester) async {
      final state = await open(tester);
      await select(tester, state, const ActionSelection('a10'));
      await tester.tap(find.text('Axis'));
      await tester.pump();
      expect(
        state.session!.asset.actionById('a10')!.action.type,
        ActionValueType.axis,
      );

      await tester.tap(find.text('Players may rebind it'));
      await tester.pump();
      expect(
        state.session!.asset.actionById('a10')!.action.rebindable,
        isFalse,
      );
      expect(find.text('fixed'), findsOneWidget, reason: 'tagged in the tree');
    });

    testWidgets('an interaction added, and one of its settings set', (
      tester,
    ) async {
      final state = await open(tester);
      await select(tester, state, const ActionSelection('a10'));
      await tester.tap(find.byTooltip('Add interactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hold').last);
      await tester.pumpAndSettle();
      expect(
        state.session!.asset.actionById('a10')!.action.interactions.single.type,
        'hold',
      );
      expect(
        find.text('0.4 (asset)'),
        findsOneWidget,
        reason: 'unset: the asset\'s hold time',
      );

      final duration = find.ancestor(
        of: find.text('0.4 (asset)'),
        matching: find.byType(TextField),
      );
      await tester.enterText(duration, '0.8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        state.session!.asset
            .actionById('a10')!
            .action
            .interactions
            .single
            .number('duration'),
        0.8,
      );
    });
  });

  group('a composite', () {
    testWidgets('its parts listed, one opened, another added', (tester) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b3'));
      expect(find.text('PARTS'), findsOneWidget);
      await tester.tap(find.text('+ up'));
      await tester.pump();
      final parts =
          (state.session!.asset.findBinding('b3')!.binding
                  as CompositeBindingDef)
              .parts;
      expect(parts.where((p) => p.part == 'up'), hasLength(2));
      expect(
        state.session!.selection,
        BindingSelection(parts[1].id),
        reason: 'the new part, to bind',
      );
    });

    testWidgets('its mode', (tester) async {
      final state = await open(tester);
      await select(tester, state, const BindingSelection('b3'));
      await tester.tap(find.text('digitalNormalized'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('analog').last);
      await tester.pumpAndSettle();
      expect(
        (state.session!.asset.findBinding('b3')!.binding as CompositeBindingDef)
            .params['mode'],
        'analog',
      );
    });
  });

  group('the setup', () {
    testWidgets('players: how many, and which actions join', (tester) async {
      final state = await open(tester);
      await tester.tap(find.text('Players & settings'));
      await tester.pump();
      await tester.tap(find.byTooltip('Fewer'));
      await tester.pump();
      expect(state.session!.asset.players.maxPlayers, 3);
      await tester.tap(find.text('ui/pause'));
      await tester.pump();
      expect(state.session!.asset.players.joinActions, ['ui/join', 'ui/pause']);
    });

    testWidgets('a scheme renamed; its bindings follow its group', (
      tester,
    ) async {
      final state = await open(tester);
      await tester.tap(find.textContaining('Control schemes'));
      await tester.pump();
      expect(
        state.session!.selection,
        const SchemeSelection('Keyboard & Mouse'),
      );
      await tester.tap(find.text('Gamepad').last);
      await tester.pump();
      final group = find.ancestor(
        of: find.text('Gamepad').last,
        matching: find.byType(TextField),
      );
      expect(group, findsNothing, reason: 'the chip, not a field');
      state.session!.edit(
        'Group',
        (a) => AssetEdits.updateScheme(
          a,
          'Gamepad',
          (s) => s.copyWith(group: 'Pad'),
        ),
      );
      await tester.pump();
      expect(state.session!.asset.findBinding('b12')!.binding.groups, ['Pad']);
    });

    testWidgets(
      'an on-screen button added and moved: one undo step per slide',
      (tester) async {
        final state = await open(tester);
        await tester.tap(find.textContaining('On-screen controls'));
        await tester.pump();
        await tester.tap(find.widgetWithText(ActionChip, 'Button'));
        await tester.pump();
        final id = (state.session!.selection as OnScreenSelection).id;
        expect(id, 'button');
        await tester.drag(find.byType(Slider).first, const Offset(60, 0));
        await tester.pumpAndSettle();
        expect(
          state.session!.asset.onScreenControl(id)!.anchorX,
          greaterThan(0),
        );
        state.session!.undo();
        expect(
          state.session!.asset.onScreenControl(id)!.anchorX,
          0,
          reason: 'the whole slide',
        );
      },
    );
  });
}
