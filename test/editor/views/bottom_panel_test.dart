import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('the tabs follow the scheme picked in the top bar', (
    tester,
  ) async {
    final state = await openEditor(tester);
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

  testWidgets('a scheme chip in the top bar filters', (tester) async {
    final state = await openEditor(tester);
    await tester.tap(find.text('Touch').first);
    await tester.pump();
    expect(state.session!.schemeFilter, 'Touch');
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(state.session!.schemeFilter, isNull);
  });
}
