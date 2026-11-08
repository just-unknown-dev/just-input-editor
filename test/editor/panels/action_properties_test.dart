import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';
import '../../support/sample_asset.dart';

void main() {
  testWidgets('its type, and what players may rebind', (tester) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const ActionSelection('a10'));
    await tester.tap(find.text('Axis'));
    await tester.pump();
    expect(
      state.session!.asset.actionById('a10')!.action.type,
      ActionValueType.axis,
    );

    await tester.tap(find.text('Players may rebind it'));
    await tester.pump();
    expect(state.session!.asset.actionById('a10')!.action.rebindable, isFalse);
    expect(find.text('fixed'), findsOneWidget, reason: 'tagged in the tree');
  });

  testWidgets('a type change says what went with it', (tester) async {
    final state = await openEditor(
      tester,
      store: MemoryInputAssetStore({
        samplePath: AssetEdits.setProcessors(sampleAsset(), 'a2', const [
          ProcessorDef('normalizeVector2'),
        ]).encode(),
      }),
    );
    await selectIn(tester, state, const ActionSelection('a2'));
    await tester.tap(find.text('Button'));
    await tester.pump();
    final move = state.session!.asset.actionById('a2')!.action;
    expect(move.processors, isEmpty);
    expect(state.session!.message.value, contains('of the wrong kind'));
    expect(find.text('normalizeVector2 (unknown)'), findsNothing);
  });

  testWidgets('an interaction added, and one of its settings set', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const ActionSelection('a10'));
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
    await commit(tester, duration, '0.8');
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

  testWidgets('Enter is one undo step, whatever the edit', (tester) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const ActionSelection('a10'));
    await commit(tester, fieldOf('Shown as'), 'Hop');
    expect(state.session!.asset.actionById('a10')!.action.displayName, 'Hop');
    state.session!.undo();
    expect(state.session!.asset.actionById('a10')!.action.displayName, '');
    expect(state.session!.canUndo, isFalse);
  });

  testWidgets('an edit that changes nothing is no undo step', (tester) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const ActionSelection('a10'));
    // Spaces, trimmed: the same empty name it had.
    await commit(tester, fieldOf('Shown as'), '  ');
    expect(state.session!.canUndo, isFalse);
    expect(state.session!.isDirty, isFalse);
  });
}
