import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';

void main() {
  String tooltipOf(WidgetTester tester, String key) => tester
      .widget<Tooltip>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Tooltip),
            )
            .first,
      )
      .message!;

  group('the keyboard', () {
    testWidgets('says what each key does, and where', (tester) async {
      await openEditor(tester);
      expect(tooltipOf(tester, 'key:space'), contains('jump (player)'));
      expect(
        tooltipOf(tester, 'key:escape'),
        contains('pause (ui)'),
        reason: 'another map, still told',
      );
      expect(tooltipOf(tester, 'key:w'), contains('move (player)'));
    });

    testWidgets('a key shared by two actions says so', (tester) async {
      final state = await openEditor(tester);
      state.session!.edit(
        'Clash',
        (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/d'),
      );
      await tester.pump();
      final text = tooltipOf(tester, 'key:d');
      expect(text, contains('move'));
      expect(text, contains('jump'));
    });

    testWidgets('a click binds the key to the selected action', (tester) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const ActionSelection('a10'));
      await tester.tap(find.byKey(const ValueKey('key:j')));
      await tester.pump();
      final added =
          state.session!.asset.actionById('a10')!.action.bindings.last
              as ControlBindingDef;
      expect(added.path, '<Keyboard>/j');
      expect(added.groups, ['KeyboardMouse'], reason: 'the keyboard\'s scheme');
      expect(state.session!.selection, BindingSelection(added.id));
    });

    testWidgets('… or rebinds the selected binding', (tester) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b11'));
      await tester.tap(find.byKey(const ValueKey('key:enter')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.path, '<Keyboard>/enter');
    });

    testWidgets('either-side keys light both sides, on a copy', (tester) async {
      final state = await openEditor(tester);
      // Shift for jump, and left Shift itself for move's up: the left key
      // already has a list of uses when Shift's is added to it.
      state.session!.edit(
        'Shift',
        (a) => AssetEdits.setPath(
          AssetEdits.setPath(a, 'b11', '<Keyboard>/shift'),
          'b4',
          '<Keyboard>/leftShift',
        ),
      );
      await tester.pump();
      expect(tooltipOf(tester, 'key:leftShift'), contains('jump'));
      expect(tooltipOf(tester, 'key:leftShift'), contains('move'));
      expect(tooltipOf(tester, 'key:rightShift'), contains('jump'));
      // Built again from the same asset: lit once, not once per build.
      state.session!.select(const ActionSelection('a2'));
      await tester.pump();
      expect(
        'jump'.allMatches(tooltipOf(tester, 'key:leftShift')),
        hasLength(1),
      );
    });
  });

  group('the mouse', () {
    testWidgets(
      'its buttons bind like keys; movement binds whole to a vector',
      (tester) async {
        final state = await openEditor(tester);
        await selectIn(tester, state, const BindingSelection('b11'));
        await tester.tap(find.byKey(const ValueKey('mouse:leftButton')));
        await tester.pump();
        expect(
          state.session!.asset.findBinding('b11')!.path,
          '<Mouse>/leftButton',
        );

        await selectIn(tester, state, const ActionSelection('a2'));
        await tester.tap(find.byKey(const ValueKey('mouse:delta')));
        await tester.pump();
        final added =
            state.session!.asset.actionById('a2')!.action.bindings.last
                as ControlBindingDef;
        expect(added.path, '<Mouse>/delta');

        // A composite part takes one direction of the wheel.
        await selectIn(tester, state, const BindingSelection('b4'));
        await tester.tap(find.byKey(const ValueKey('mouse:scroll/up')));
        await tester.pump();
        expect(
          state.session!.asset.findBinding('b4')!.path,
          '<Mouse>/scroll/up',
        );
      },
    );
  });
}
