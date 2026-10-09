import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('tab:$name')));
    await tester.pump();
  }

  String tooltipOf(WidgetTester tester, String key) => tester
      .widget<Tooltip>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Tooltip),
            )
            .first,
      )
      .message!;

  group('the keyboard', () {
    testWidgets('says what each key does, and where', (tester) async {
      await open(tester);
      expect(tooltipOf(tester, 'key:space'), contains('jump (player)'));
      expect(
        tooltipOf(tester, 'key:escape'),
        contains('pause (ui)'),
        reason: 'another map, still told',
      );
      expect(tooltipOf(tester, 'key:w'), contains('move (player)'));
    });

    testWidgets('a key shared by two actions says so', (tester) async {
      final state = await open(tester);
      state.session!.edit(
        'Clash',
        (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/d'),
      );
      await tester.pump();
      final text = tooltipOf(tester, 'key:d');
      expect(text, contains('move'));
      expect(text, contains('jump'));
    });

    testWidgets('a click binds the key to the selected action', (tester) async {
      final state = await open(tester);
      state.session!.select(const ActionSelection('a10'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('key:j')));
      await tester.pump();
      final added =
          state.session!.asset.actionById('a10')!.action.bindings.last
              as ControlBindingDef;
      expect(added.path, '<Keyboard>/j');
      expect(added.groups, ['KeyboardMouse'], reason: 'the keyboard\'s scheme');
      expect(state.session!.selection, BindingSelection(added.id));
    });

    testWidgets('… or rebinds the selected binding', (tester) async {
      final state = await open(tester);
      state.session!.select(const BindingSelection('b11'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('key:enter')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/enter');
    });
  });

  group('the gamepad', () {
    testWidgets('in each brand\'s glyphs', (tester) async {
      await open(tester);
      await tab(tester, 'gamepad');
      Finder onPad(String k, String t) => find.descendant(
        of: find.byKey(ValueKey('pad:$k')),
        matching: find.text(t),
      );
      expect(onPad('buttonSouth', 'Ⓐ'), findsOneWidget);
      await tester.tap(find.text('PlayStation'));
      await tester.pump();
      expect(onPad('buttonSouth', '✕'), findsOneWidget);
    });

    testWidgets('a click binds: a button, or a whole stick for a vector', (
      tester,
    ) async {
      final state = await open(tester);
      await tab(tester, 'gamepad');
      state.session!.select(const BindingSelection('b12'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad:buttonNorth')));
      await tester.pump();
      expect(
        state.session!.asset.findBinding('b12')!.path,
        '<Gamepad>/buttonNorth',
      );

      state.session!.select(const BindingSelection('b8'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad:rightStick')));
      await tester.pump();
      expect(
        state.session!.asset.findBinding('b8')!.path,
        '<Gamepad>/rightStick',
      );

      // A composite's part takes the stick's direction.
      state.session!.select(const BindingSelection('b4'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad:leftStick')));
      await tester.pump();
      expect(
        state.session!.asset.findBinding('b4')!.path,
        '<Gamepad>/leftStick/up',
      );
    });
  });

  group('the touch layout', () {
    testWidgets('a drag moves a control, and is one undo step', (tester) async {
      final state = await open(tester);
      await tab(tester, 'touch');
      final before = state.session!.asset.onScreenControl('jump')!;
      await tester.drag(
        find.byKey(const ValueKey('onscreen:jump')),
        const Offset(-80, -40),
      );
      await tester.pumpAndSettle();
      final after = state.session!.asset.onScreenControl('jump')!;
      expect(after.anchorX, lessThan(before.anchorX));
      expect(after.anchorY, lessThan(before.anchorY));
      expect(state.session!.selection, const OnScreenSelection('jump'));
      state.session!.undo();
      expect(
        state.session!.asset.onScreenControl('jump')!.anchorX,
        before.anchorX,
      );
    });

    testWidgets('controls are added from the tab', (tester) async {
      final state = await open(tester);
      await tab(tester, 'touch');
      await tester.tap(find.widgetWithText(TextButton, 'Button'));
      await tester.pump();
      expect(state.session!.asset.onScreenControl('button'), isNotNull);
      expect(find.byKey(const ValueKey('onscreen:button')), findsOneWidget);
    });
  });

  group('the live test', () {
    testWidgets('keys pressed in it move the actions, and player 1 joins', (
      tester,
    ) async {
      final state = await open(tester);
      await tab(tester, 'live');
      expect(find.textContaining('press something to play'), findsOneWidget);

      // Clicked with the mouse, as a person does: player 1 is on the
      // keyboard and mouse.
      await tester.tap(
        find.byKey(const ValueKey('live-area')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyD,
        physicalKey: PhysicalKeyboardKey.keyD,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      final service = state.harness.service;
      expect(service.players.players.single.index, 0);
      expect(find.textContaining('P1 · Keyboard & Mouse'), findsOneWidget);
      expect(
        service.players[0]!.action('move').readVector2(),
        const Offset(1, 0),
      );
      expect(find.text('performed'), findsWidgets);

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyD,
        physicalKey: PhysicalKeyboardKey.keyD,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tab(tester, 'keyboard'); // stops the ticker
    });

    testWidgets('it runs the asset as edited, not as saved', (tester) async {
      final state = await open(tester);
      state.session!.edit(
        'Rebind',
        (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/k'),
      );
      await tab(tester, 'live');
      // Clicked with the mouse, as a person does: player 1 is on the
      // keyboard and mouse.
      await tester.tap(
        find.byKey(const ValueKey('live-area')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyK,
        physicalKey: PhysicalKeyboardKey.keyK,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        state.harness.service.players[0]!.action('jump').isPressed(),
        isTrue,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyK,
        physicalKey: PhysicalKeyboardKey.keyK,
      );
      await tab(tester, 'keyboard');
    });
  });

  group('the mouse', () {
    testWidgets(
      'its buttons bind like keys; movement binds whole to a vector',
      (tester) async {
        final state = await open(tester);
        state.session!.select(const BindingSelection('b11'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mouse:leftButton')));
        await tester.pump();
        expect(
          state.session!.asset.findBinding('b11')!.path,
          '<Mouse>/leftButton',
        );

        state.session!.select(const ActionSelection('a2')); // move, a vector
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mouse:delta')));
        await tester.pump();
        final added =
            state.session!.asset.actionById('a2')!.action.bindings.last
                as ControlBindingDef;
        expect(added.path, '<Mouse>/delta');

        // A composite part takes one direction of the wheel.
        state.session!.select(const BindingSelection('b4'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mouse:scroll/up')));
        await tester.pump();
        expect(
          state.session!.asset.findBinding('b4')!.path,
          '<Mouse>/scroll/up',
        );
      },
    );
  });

  group('gamepad callouts', () {
    testWidgets('each bound control names its action beside the pad', (
      tester,
    ) async {
      final state = await open(tester);
      await tab(tester, 'gamepad');
      final south = find.byKey(const ValueKey('callout:buttonSouth'));
      expect(
        find.descendant(of: south, matching: find.textContaining('jump')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('callout:leftStick')),
        findsOneWidget,
        reason: 'move',
      );
      expect(
        find.byKey(const ValueKey('callout:buttonNorth')),
        findsNothing,
        reason: 'unbound',
      );

      state.session!.edit(
        'Clash',
        (a) => AssetEdits.setPath(a, 'b12', '<Gamepad>/leftStickPress'),
      );
      await tester.pump();
      final stick = find.byKey(const ValueKey('callout:leftStick'));
      expect(
        find.descendant(of: stick, matching: find.textContaining('⚠')),
        findsOneWidget,
      );
    });
  });

  group('touch', () {
    testWidgets(
      'a click binds when an action is picked, else picks the control',
      (tester) async {
        final state = await open(tester);
        await tab(tester, 'touch');
        await tester.tap(find.byKey(const ValueKey('onscreen:jump')));
        await tester.pump();
        expect(state.session!.selection, const OnScreenSelection('jump'));

        state.session!.select(const ActionSelection('a10'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('onscreen:moveStick')));
        await tester.pump();
        final added =
            state.session!.asset.actionById('a10')!.action.bindings.last
                as ControlBindingDef;
        expect(added.path, '<OnScreen>/moveStick');
        expect(added.groups, ['Touch'], reason: 'the touch scheme');
      },
    );

    testWidgets('a stick says what it moves', (tester) async {
      await open(tester);
      await tab(tester, 'touch');
      final stick = find.byKey(const ValueKey('onscreen:moveStick'));
      expect(
        find.descendant(of: stick, matching: find.text('move')),
        findsOneWidget,
      );
    });
  });

  testWidgets('the tabs follow the scheme picked in the top bar', (
    tester,
  ) async {
    final state = await open(tester);
    state.session!.schemeFilter = 'Gamepad';
    await tester.pump();
    expect(find.text('Show as'), findsOneWidget);
    state.session!.schemeFilter = 'Touch';
    await tester.pump();
    expect(find.byKey(const ValueKey('touch-frame')), findsOneWidget);
    state.session!.schemeFilter = null; // All: the tab stays
    await tester.pump();
    expect(find.byKey(const ValueKey('touch-frame')), findsOneWidget);
    state.session!.schemeFilter = 'KeyboardMouse';
    await tester.pump();
    expect(find.byKey(const ValueKey('key:space')), findsOneWidget);
  });
}
