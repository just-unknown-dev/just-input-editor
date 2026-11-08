import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('in each brand\'s glyphs', (tester) async {
    await openEditor(tester);
    await openTab(tester, 'gamepad');
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
    final state = await openEditor(tester);
    await openTab(tester, 'gamepad');
    await selectIn(tester, state, const BindingSelection('b12'));
    await tester.tap(find.byKey(const ValueKey('pad:buttonNorth')));
    await tester.pump();
    expect(
      state.session!.asset.findBinding('b12')!.path,
      '<Gamepad>/buttonNorth',
    );

    await selectIn(tester, state, const BindingSelection('b8'));
    await tester.tap(find.byKey(const ValueKey('pad:rightStick')));
    await tester.pump();
    expect(
      state.session!.asset.findBinding('b8')!.path,
      '<Gamepad>/rightStick',
    );

    // A composite's part takes the stick's direction.
    await selectIn(tester, state, const BindingSelection('b4'));
    await tester.tap(find.byKey(const ValueKey('pad:leftStick')));
    await tester.pump();
    expect(
      state.session!.asset.findBinding('b4')!.path,
      '<Gamepad>/leftStick/up',
    );
  });

  testWidgets('each bound control names its action beside the pad', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await openTab(tester, 'gamepad');
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
}
