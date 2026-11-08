import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('a drag moves a control, and is one undo step', (tester) async {
    final state = await openEditor(tester);
    await openTab(tester, 'touch');
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
    final state = await openEditor(tester);
    await openTab(tester, 'touch');
    await tester.tap(find.widgetWithText(TextButton, 'Button'));
    await tester.pump();
    expect(state.session!.asset.onScreenControl('button'), isNotNull);
    expect(find.byKey(const ValueKey('onscreen:button')), findsOneWidget);
  });

  testWidgets(
    'a click binds when an action is picked, else picks the control',
    (tester) async {
      final state = await openEditor(tester);
      await openTab(tester, 'touch');
      await tester.tap(find.byKey(const ValueKey('onscreen:jump')));
      await tester.pump();
      expect(state.session!.selection, const OnScreenSelection('jump'));

      await selectIn(tester, state, const ActionSelection('a10'));
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
    await openEditor(tester);
    await openTab(tester, 'touch');
    final stick = find.byKey(const ValueKey('onscreen:moveStick'));
    expect(
      find.descendant(of: stick, matching: find.text('move')),
      findsOneWidget,
    );
  });

  group('drags', () {
    testWidgets('editing keys wait for the drag to end', (tester) async {
      final state = await openEditor(tester);
      await openTab(tester, 'touch');
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
        state.harness!.service.asset.onScreenControl('jump')!.anchorX,
        0.72,
        reason: 'the live copy is not run again on every move',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(state.session!.asset.onScreenControl('jump'), isNotNull);
      await gesture.up();
      await tester.pump();
      expect(
        state.harness!.service.asset.onScreenControl('jump')!.anchorX,
        state.session!.asset.onScreenControl('jump')!.anchorX,
      );
      state.session!.undo();
      expect(state.session!.asset.onScreenControl('jump')!.anchorX, 0.72);
    });

    testWidgets('what is dragged going away mid-drag ends the drag', (
      tester,
    ) async {
      final state = await openEditor(tester);
      await openTab(tester, 'touch');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('onscreen:jump'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      final s = state.session!;
      s.edit('Gone', (a) => AssetEdits.deleteOnScreen(a, 'jump'));
      await tester.pump();
      expect(s.isInGesture, isFalse);
      await gesture.up();
      s.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      s.edit('b', (a) => AssetEdits.renameAction(a, 'a10', 'leap'));
      s.undo();
      expect(s.asset.actionById('a10')!.action.name, 'hop');
    });
  });
}
