import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('a map switched off at start', (tester) async {
    final state = await openEditor(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(state.session!.asset.mapById('m1')!.enabled, isFalse);
  });

  testWidgets('maps reordered: the index is counted once it has left', (
    tester,
  ) async {
    final state = await openEditor(tester);
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // The list hands over the index after removal: the end is 1, of two.
    list.onReorderItem!(0, 1);
    await tester.pump();
    expect(state.session!.asset.maps.map((m) => m.name), ['ui', 'player']);
    expect(state.session!.undoLabel, 'Move map');
  });

  testWidgets('an action dropped on a map moves to its end', (tester) async {
    final state = await openEditor(tester);
    final from = tester.getCenter(inTree('jump'));
    final to = tester.getCenter(find.text('ui'));
    final gesture = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.session!.asset.mapById('m14')!.actions.last.name, 'jump');
    expect(state.session!.asset.findAction('player/jump'), isNull);
  });
}
