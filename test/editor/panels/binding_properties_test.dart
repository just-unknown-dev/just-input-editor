import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../support/open_editor.dart';
import '../../support/sample_asset.dart';

void main() {
  group('a binding\'s control', () {
    testWidgets('picked from the list — Escape, which Listen cannot hear', (
      tester,
    ) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b11'));
      expect(find.text('Space'), findsWidgets);

      await tester.tap(find.text('Pick…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'esc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('<Keyboard>/escape'));
      await tester.pumpAndSettle();

      expect(
        state.session!.asset.findBinding('b11')!.path,
        '<Keyboard>/escape',
      );
    });

    testWidgets('the picker offers what fits: sticks for a vector', (
      tester,
    ) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b8'));
      await tester.tap(find.text('Pick…'));
      await tester.pumpAndSettle();
      // It opens on the device the binding is on.
      expect(find.text('<Gamepad>/rightStick'), findsOneWidget);
      expect(find.text('<Gamepad>/buttonSouth'), findsNothing);
      await tester.tap(find.text('<Gamepad>/rightStick'));
      await tester.pumpAndSettle();
      expect(
        state.session!.asset.findBinding('b8')!.path,
        '<Gamepad>/rightStick',
      );
    });

    testWidgets('cleared', (tester) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b11'));
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.path, '');
      expect(find.text('<not bound>'), findsOneWidget);
    });

    testWidgets('its schemes: ticked, and none means every one', (
      tester,
    ) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b11'));
      await tester.tap(find.byKey(const ValueKey('scheme:Gamepad')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.binding.groups, [
        'KeyboardMouse',
        'Gamepad',
      ]);
      await tester.tap(find.byKey(const ValueKey('scheme:KeyboardMouse')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('scheme:Gamepad')));
      await tester.pump();
      expect(state.session!.asset.findBinding('b11')!.binding.groups, isEmpty);
      expect(
        find.text('None ticked: it counts in every scheme.'),
        findsOneWidget,
      );
    });
  });

  group('a composite', () {
    testWidgets('its parts listed, one opened, another added', (tester) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b3'));
      expect(find.text('PARTS'), findsOneWidget);
      await tester.tap(find.text('+ up'));
      await tester.pump();
      final parts =
          (state.session!.asset.findBinding('b3')!.binding
                  as CompositeBindingDef)
              .parts;
      expect(parts.where((p) => p.part == 'up'), hasLength(2));
      expect(
        state.session!.selection,
        BindingSelection(parts[1].id),
        reason: 'the new part, to bind',
      );
    });

    testWidgets('its mode', (tester) async {
      final state = await openEditor(tester);
      await selectIn(tester, state, const BindingSelection('b3'));
      await tester.tap(find.text('digitalNormalized'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('analog').last);
      await tester.pumpAndSettle();
      expect(
        (state.session!.asset.findBinding('b3')!.binding as CompositeBindingDef)
            .params['mode'],
        'analog',
      );
    });

    testWidgets('a setting of the wrong kind still shows, and is flagged', (
      tester,
    ) async {
      final odd = AssetEdits.updateBinding(
        sampleAsset(),
        'b3',
        (b) => (b as CompositeBindingDef).copyWith(
          params: const {'mode': 'Digital'},
        ),
      );
      final state = await openEditor(
        tester,
        store: MemoryInputAssetStore({samplePath: odd.encode()}),
      );
      await selectIn(tester, state, const BindingSelection('b3'));
      expect(tester.takeException(), isNull);
      expect(find.text('Digital (unknown)'), findsOneWidget);
      expect(
        find.textContaining('setting "mode" must be'),
        findsOneWidget,
        reason: 'what validation says, at the setting',
      );
    });
  });
}
