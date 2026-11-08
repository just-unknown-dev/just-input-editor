// A list of interactions or processors: numbers held in range, a min/max
// pair refused the wrong way round, what validation finds said on the step,
// and a step of the wrong kind called that.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';
import '../../support/sample_asset.dart';

void main() {
  Future<InputEditorState> openWith(
    WidgetTester tester,
    InputActionAsset asset,
  ) => openEditor(
    tester,
    store: MemoryInputAssetStore({samplePath: asset.encode()}),
  );

  testWidgets('a step\'s number refuses NaN, and is held in its range', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const ActionSelection('a18'));
    double? duration() => state.session!.asset
        .actionById('a18')!
        .action
        .interactions
        .single
        .number('duration');
    await commit(tester, fieldOf('Duration'), 'Infinity');
    expect(duration(), 0.6);
    await commit(tester, fieldOf('Duration'), '-2');
    expect(duration(), 0, reason: 'no less than its min');
    state.session!.asset.encode();
  });

  testWidgets('a clamp\'s min not below its max is refused, and said', (
    tester,
  ) async {
    final axis = AssetEdits.changeActionType(
      AssetEdits.setProcessors(sampleAsset(), 'a10', const [
        ProcessorDef('clamp'),
      ]),
      'a10',
      ActionValueType.axis,
    );
    final state = await openWith(tester, axis);
    await selectIn(tester, state, const ActionSelection('a10'));
    // Max is unset: 1. A min of 1 is not below it.
    await commit(tester, fieldOf('Min'), '1');
    final clamp = state.session!.asset.actionById('a10')!.action.processors;
    expect(clamp.single.params, isEmpty, reason: 'refused');
    expect(state.session!.message.value, contains('has to be below'));
    expect(validateAsset(state.session!.asset), isEmpty);

    await commit(tester, fieldOf('Min'), '0.5');
    expect(
      state.session!.asset.actionById('a10')!.action.processors.single.params,
      {'min': 0.5},
    );
  });

  testWidgets('what validation finds wrong is said on the step', (
    tester,
  ) async {
    // A hand-edited file: a clamp the wrong way round.
    final bad = AssetEdits.setProcessors(sampleAsset(), 'b11', const [
      ProcessorDef('clamp', {'min': 1, 'max': 0}),
    ]);
    final state = await openWith(tester, bad);
    expect(state.session!.issues.where((i) => i.isError), hasLength(1));
    await selectIn(tester, state, const BindingSelection('b11'));
    final card = find.byKey(const ValueKey('step:processor:0'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('must be below')),
      findsOneWidget,
    );
    final border = tester.widget<Container>(card).decoration! as BoxDecoration;
    expect(border.border, isNotNull, reason: 'the card is marked');
  });

  testWidgets('a processor of the other kind says it has no effect', (
    tester,
  ) async {
    // A hand edit: a vector's processor on a button.
    final odd = AssetEdits.setProcessors(sampleAsset(), 'a10', const [
      ProcessorDef('normalizeVector2'),
      ProcessorDef('nothingRegistered'),
    ]);
    final state = await openWith(tester, odd);
    await selectIn(tester, state, const ActionSelection('a10'));
    expect(
      find.text('Normalize Vector 2 (for vectors: no effect here)'),
      findsOneWidget,
    );
    expect(find.text('nothingRegistered (unknown)'), findsOneWidget);
  });
}
