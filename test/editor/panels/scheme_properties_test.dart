import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';

void main() {
  testWidgets('a scheme\'s group renamed: its bindings follow', (tester) async {
    final state = await openEditor(tester);
    await tester.tap(find.textContaining('Control schemes'));
    await tester.pump();
    expect(state.session!.selection, const SchemeSelection('Keyboard & Mouse'));
    await selectIn(tester, state, const SchemeSelection('Gamepad'));
    await commit(tester, fieldOf('Group'), 'Pad');
    expect(state.session!.asset.findBinding('b12')!.binding.groups, ['Pad']);
  });

  testWidgets('a taken name is refused, and said', (tester) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const SchemeSelection('Gamepad'));
    await commit(tester, fieldOf('Name'), 'Touch');
    await tester.pump();
    expect(state.session!.asset.schemeNamed('Gamepad'), isNotNull);
    expect(state.session!.message.value, contains('already a scheme'));
  });

  testWidgets('+ Scheme twice: two schemes, two groups', (tester) async {
    final state = await openEditor(tester);
    await selectIn(tester, state, const SchemeSelection('Gamepad'));
    await tester.tap(find.widgetWithText(ActionChip, 'Scheme'));
    await tester.pump();
    expect(state.session!.selection, const SchemeSelection('Scheme'));
    await commit(tester, fieldOf('Name'), 'Joystick');
    expect(state.session!.selection, const SchemeSelection('Joystick'));
    await tester.tap(find.widgetWithText(ActionChip, 'Scheme'));
    await tester.pump();
    final groups = [for (final s in state.session!.asset.schemes) s.group];
    expect(groups.toSet(), hasLength(groups.length));
    expect(
      validateAsset(
        state.session!.asset,
      ).where((i) => i.code == 'duplicateGroup'),
      isEmpty,
    );
  });
}
