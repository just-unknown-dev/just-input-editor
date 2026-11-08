import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';

/// A composite a game might register: two buttons into one axis.
final class _Twin extends CompositeBehavior {
  @override
  Offset evaluate(
    CompositeParts parts,
    Map<String, Object> params,
    InputSettingsDef settings,
  ) => Offset.zero;
}

void main() {
  testWidgets('an action added from the menu, of the type picked', (
    tester,
  ) async {
    final state = await openEditor(tester);
    await tester.tap(find.byTooltip('Add action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vector 2').last);
    await tester.pumpAndSettle();
    final added = state.session!.asset.mapById('m1')!.actions.last;
    expect(added.name, 'move2');
    expect(added.type, ActionValueType.vector2);
    expect(state.session!.selection, ActionSelection(added.id));
  });

  testWidgets('a binding another action shares is flagged', (tester) async {
    final state = await openEditor(tester);
    state.session!.edit(
      'Clash',
      (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/w'),
    );
    await tester.pump();
    expect(
      find.byTooltip('Another action in this map uses this too'),
      findsNWidgets(2),
    );
  });

  testWidgets('an action dragged onto another lands before it', (tester) async {
    final state = await openEditor(tester);
    final from = tester.getCenter(inTree('jump'));
    final to = tester.getCenter(inTree('move'));
    final gesture = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.session!.asset.mapById('m1')!.actions.map((a) => a.name), [
      'jump',
      'move',
    ]);
  });

  testWidgets('"Add binding" lists every composite that fits, a game\'s too', (
    tester,
  ) async {
    InputComposites.register(
      CompositeEntry(
        const StepInfo('twin', 'Twin buttons', []),
        const ['first', 'second'],
        ControlValueType.axis,
        _Twin.new,
      ),
    );
    addTearDown(() => InputComposites.unregister('twin'));
    final state = await openEditor(tester);
    await tester.tap(find.byTooltip('Add binding').at(1)); // jump's
    await tester.pumpAndSettle();
    expect(find.text('Twin buttons'), findsOneWidget);
    expect(find.text('2D Vector'), findsNothing, reason: 'jump is a button');
    await tester.tap(find.text('Twin buttons'));
    await tester.pumpAndSettle();
    final twin = state.session!.asset
        .actionById('a10')!
        .action
        .bindings
        .whereType<CompositeBindingDef>()
        .single;
    expect(twin.parts.map((p) => p.part), ['first', 'second']);
  });
}
