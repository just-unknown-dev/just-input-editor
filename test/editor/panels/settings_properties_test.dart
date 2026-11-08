// Players and the asset's settings: the ranges just_inputs gives them, a
// dead zone's min below its max, and what validation finds said at the
// setting.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import 'package:just_input_editor/src/editor/panels/settings_properties.dart';

import '../../support/open_editor.dart';
import '../../support/sample_asset.dart';

void main() {
  Future<InputEditorState> open(WidgetTester tester) async {
    final state = await openEditor(tester);
    await tester.tap(find.text('Players & settings'));
    await tester.pump();
    return state;
  }

  test('every setting takes its range, ends included, and nothing past', () {
    const settings = InputSettingsDef();
    for (final p in InputSettingsDef.params) {
      // Within one dead zone, the min and max are checked against each
      // other too: test each end where its sibling leaves room.
      final low = p.min ?? 0;
      final high = p.max ?? 100;
      final lowOk = p.name.endsWith('Max') ? settings.valueOf(p.name)! : low;
      final highOk = p.name.endsWith('Min') ? settings.valueOf(p.name)! : high;
      expect(
        SettingsProperties.problem(settings, p, lowOk),
        isNull,
        reason: '${p.name} at $lowOk',
      );
      expect(
        SettingsProperties.problem(settings, p, highOk),
        isNull,
        reason: '${p.name} at $highOk',
      );
      expect(
        SettingsProperties.problem(settings, p, low - 0.001),
        isNotNull,
        reason: '${p.name} below its min',
      );
      if (p.max != null) {
        expect(
          SettingsProperties.problem(settings, p, high + 0.001),
          isNotNull,
          reason: '${p.name} past its max',
        );
      }
      expect(SettingsProperties.problem(settings, p, double.nan), isNotNull);
    }
  });

  testWidgets('players: how many, and which actions join', (tester) async {
    final state = await open(tester);
    await tester.tap(find.byTooltip('Fewer'));
    await tester.pump();
    expect(state.session!.asset.players.maxPlayers, 3);
    await tester.tap(find.text('ui/pause'));
    await tester.pump();
    expect(state.session!.asset.players.joinActions, ['ui/join', 'ui/pause']);
  });

  testWidgets('no more than four players', (tester) async {
    final state = await open(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(state.session!.asset.players.maxPlayers, 4);
  });

  testWidgets('a setting refuses NaN, Infinity and what is out of range', (
    tester,
  ) async {
    final state = await open(tester);
    for (final bad in ['NaN', 'Infinity', '-1', 'x']) {
      await commit(tester, fieldOf('Hold time'), bad);
      expect(state.session!.asset.settings.holdTime, 0.4, reason: bad);
    }
    expect(state.session!.isDirty, isFalse);
    expect(state.session!.message.value, contains('Hold time'));
    // A press point of 0 would leave every button pressed at rest.
    for (final bad in ['2', '0']) {
      await commit(tester, fieldOf('Press point'), bad);
      expect(state.session!.asset.settings.pressPoint, 0.5, reason: bad);
    }
    expect(
      state.session!.message.value,
      'Press point is a number from 0.01 to 1.',
    );
    await commit(tester, fieldOf('Press point'), '0.3');
    expect(state.session!.asset.settings.pressPoint, 0.3);
  });

  testWidgets('a dead zone\'s min has to stay below its max', (tester) async {
    final state = await open(tester);
    await commit(tester, fieldOf('Stick dead min'), '0.95');
    expect(state.session!.asset.settings.stickDeadzoneMin, 0.125);
    expect(state.session!.message.value, contains('below Stick dead max'));
    await commit(tester, fieldOf('Axis dead max'), '0.1');
    expect(state.session!.asset.settings.axisDeadzoneMax, 0.925);
    expect(state.session!.message.value, contains('above Axis dead min'));
    expect(validateAsset(state.session!.asset), isEmpty);
  });

  testWidgets('a hand-edited setting validation refuses is said there', (
    tester,
  ) async {
    final bad = sampleAsset().copyWith(
      settings: const InputSettingsDef(pressPoint: 0),
    );
    await openEditor(
      tester,
      store: MemoryInputAssetStore({samplePath: bad.encode()}),
    );
    await tester.tap(find.text('Players & settings'));
    await tester.pump();
    expect(find.textContaining('"Press point" must be'), findsOneWidget);
  });
}
