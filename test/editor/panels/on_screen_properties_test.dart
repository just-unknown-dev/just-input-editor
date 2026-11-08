import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('a button added and moved: one undo step per slide', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await tester.tap(find.textContaining('On-screen controls'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Button'));
    await tester.pump();
    final id = (state.session!.selection as OnScreenSelection).id;
    expect(id, 'button');
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(state.session!.asset.onScreenControl(id)!.anchorX, greaterThan(0));
    state.session!.undo();
    expect(
      state.session!.asset.onScreenControl(id)!.anchorX,
      0,
      reason: 'the whole slide',
    );
  });

  testWidgets('an id that is not a name is refused, and the bindings stay', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const OnScreenSelection('jump'));
    await commit(tester, fieldOf('Id'), 'jump btn');
    await tester.pump();
    expect(state.session!.asset.onScreenControl('jump'), isNotNull);
    expect(state.session!.asset.findBinding('b13')!.path, '<OnScreen>/jump');
    expect(state.session!.message.value, contains('is not a name'));
    expect(
      tester.widget<TextField>(fieldOf('Id')).controller!.text,
      'jump',
      reason: 'the field shows the id kept',
    );

    await commit(tester, fieldOf('Id'), 'hop');
    expect(state.session!.asset.findBinding('b13')!.path, '<OnScreen>/hop');
    expect(state.session!.selection, const OnScreenSelection('hop'));
    await commit(tester, fieldOf('Id'), 'jump');
    expect(state.session!.asset.findBinding('b13')!.path, '<OnScreen>/jump');
  });
}
