// Listen: press a key, a button or a stick and it is bound; Esc gives up;
// and the keyboard is let go after, so the next Listen hears the same key.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart' as gp;
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/testing.dart';

import '../../support/open_editor.dart';

void main() {
  late FakeGamepadSource pads;

  setUp(() => pads = FakeGamepadSource());
  tearDown(() => pads.dispose());

  Future<InputEditorState> open(WidgetTester tester) =>
      openEditor(tester, gamepads: pads);

  Future<void> listen(
    WidgetTester tester,
    InputEditorState state,
    String id,
  ) async {
    await selectIn(tester, state, BindingSelection(id));
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

  testWidgets('press a key and it is bound', (tester) async {
    final state = await open(tester);
    await listen(tester, state, 'b11');
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

  testWidgets('a pad button counts too', (tester) async {
    final state = await open(tester);
    pads.connect('p');
    await listen(tester, state, 'b12');
    pads.press('p', gp.GamepadButton.y);
    await tester.pumpAndSettle();
    expect(
      state.session!.asset.findBinding('b12')!.path,
      '<Gamepad>/buttonNorth',
    );
  });

  testWidgets('Escape gives up, and the binding stays', (tester) async {
    final state = await open(tester);
    await listen(tester, state, 'b11');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/space');
    expect(find.textContaining('Press a key'), findsNothing);
    expect(state.harness!.isListening, isFalse);
  });

  testWidgets('it hears the same key twice running', (tester) async {
    final state = await open(tester);
    await listen(tester, state, 'b11');
    await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
    expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/j');

    await listen(tester, state, 'b16');
    await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
    expect(state.session!.asset.findBinding('b16')!.path, '<Keyboard>/j');
  });

  testWidgets('Escape gives up every time, and is not the editor\'s', (
    tester,
  ) async {
    var closed = 0;
    final state = await openEditor(
      tester,
      gamepads: pads,
      onClose: () => closed++,
    );
    for (var i = 0; i < 2; i++) {
      await listen(tester, state, 'b11');
      expect(state.harness!.isListening, isTrue);
      await press(
        tester,
        LogicalKeyboardKey.escape,
        PhysicalKeyboardKey.escape,
      );
      expect(state.harness!.isListening, isFalse, reason: 'press ${i + 1}');
    }
    expect(closed, 0, reason: 'Listen\'s Escape is not the editor\'s');
  });

  testWidgets('it gives up when something else is picked', (tester) async {
    final state = await open(tester);
    await listen(tester, state, 'b11');
    await selectIn(tester, state, const BindingSelection('b12'));
    expect(state.harness!.isListening, isFalse);
    await press(tester, LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
    expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/space');
  });
}
