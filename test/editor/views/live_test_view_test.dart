// The live test: the asset as edited, on the editor's own input; the keys
// handed back when it is left; its clock; pads; and an asset that throws,
// which stops it rather than throwing every frame.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart' as gp;
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:just_inputs/testing.dart';

import '../../support/open_editor.dart';
import '../../support/sample_asset.dart';
import '../../support/throwing_steps.dart';

void main() {
  late FakeGamepadSource pads;

  setUp(() => pads = FakeGamepadSource());
  tearDown(() => pads.dispose());

  Future<InputEditorState> open(
    WidgetTester tester, {
    InputAssetStore? store,
  }) => openEditor(tester, store: store, gamepads: pads);

  Future<void> clickArea(WidgetTester tester) async {
    // Clicked with the mouse, as a person does: player 1 is on the keyboard
    // and mouse.
    await tester.tap(
      find.byKey(const ValueKey('live-area')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  testWidgets('keys pressed in it move the actions, and player 1 joins', (
    tester,
  ) async {
    final state = await open(tester);
    await openTab(tester, 'live');
    expect(find.textContaining('press something to play'), findsOneWidget);

    await clickArea(tester);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyD,
      physicalKey: PhysicalKeyboardKey.keyD,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));

    final service = state.harness!.service;
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
    await openTab(tester, 'keyboard'); // stops the ticker
  });

  testWidgets('it runs the asset as edited, not as saved', (tester) async {
    final state = await open(tester);
    state.session!.edit(
      'Rebind',
      (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/k'),
    );
    await openTab(tester, 'live');
    await clickArea(tester);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(state.harness!.service.players[0]!.action('jump').isPressed, isTrue);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
    );
    await openTab(tester, 'keyboard');
  });

  testWidgets('a click elsewhere gives the keys back to the editor', (
    tester,
  ) async {
    final state = await open(tester);
    await openTab(tester, 'live');
    await clickArea(tester);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyD,
      physicalKey: PhysicalKeyboardKey.keyD,
    );
    await tester.pump();
    final keyboard = state.harness!.service.keyboard;
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
    await openTab(tester, 'keyboard');
  });

  testWidgets('its clock goes on from where it was', (tester) async {
    final state = await open(tester);
    await openTab(tester, 'live');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final before = state.harness!.time;
    expect(before, greaterThan(0.1));
    await openTab(tester, 'keyboard');
    await openTab(tester, 'live');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(state.harness!.time, greaterThan(before));
    expect(state.harness!.service.time, greaterThan(before));
    await openTab(tester, 'keyboard');
  });

  testWidgets('pads are caught up without it', (tester) async {
    final state = await open(tester);
    pads.connect('p');
    await tester.pump();
    pads.press('p', gp.GamepadButton.a);
    await tester.pump();
    final pad = state.harness!.service.gamepads.single;
    expect(pad.applied.pad.buttonsDown, contains(gp.GamepadButton.a));
    pads.release('p');
    await tester.pump();
    expect(pad.applied.pad.buttonsDown, isEmpty);
  });

  group('an asset the input system cannot run', () {
    setUp(ThrowingSteps.register);
    tearDown(ThrowingSteps.unregister);

    testWidgets('stops it, says so once, and it starts again once mended', (
      tester,
    ) async {
      final state = await open(
        tester,
        store: MemoryInputAssetStore({
          samplePath: ThrowingSteps.onUpdate(sampleAsset()).encode(),
        }),
      );
      await openTab(tester, 'live');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull);
      expect(state.harness!.runError, isNotNull);
      expect(ThrowingSteps.ticks, 1, reason: 'not again every frame');
      expect(find.byKey(const ValueKey('live-stopped')), findsOneWidget);
      expect(state.session!.message.value, contains('live test stopped'));

      // The interaction taken away: the asset runs again.
      state.session!.edit(
        'Mend',
        (a) => AssetEdits.setInteractions(a, 'a10', const []),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(state.harness!.runError, isNull);
      expect(find.byKey(const ValueKey('live-stopped')), findsNothing);
      await openTab(tester, 'keyboard');
    });

    testWidgets('a pad moved with the tab closed throws nothing', (
      tester,
    ) async {
      final state = await open(
        tester,
        store: MemoryInputAssetStore({
          samplePath: ThrowingSteps.onUpdate(sampleAsset()).encode(),
        }),
      );
      pads.connect('p');
      await tester.pump();
      pads.press('p', gp.GamepadButton.a);
      await tester.pump();
      pads.release('p');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(state.harness!.runError, isNotNull);
    });

    testWidgets('one that cannot load shows why, and never ticks', (
      tester,
    ) async {
      final state = await open(
        tester,
        store: MemoryInputAssetStore({
          samplePath: ThrowingSteps.onLoad(sampleAsset()).encode(),
        }),
      );
      expect(state.harness!.loadError, isNotNull);
      expect(state.session!.message.value, contains('cannot run this asset'));
      await openTab(tester, 'live');
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('live-stopped')), findsOneWidget);
      await openTab(tester, 'keyboard');
    });
  });
}
