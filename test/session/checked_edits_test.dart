// The renames, moves and deletes every panel makes the same way: what
// cannot be is said and refused, and what takes a name from the game asks.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_input_editor/src/session/checked_edits.dart';
import 'package:just_inputs/just_inputs.dart';

import '../support/sample_asset.dart';

void main() {
  group('an on-screen control renamed', () {
    test('to what is not a name is refused, and said', () {
      for (final bad in ['jump btn', 'jump/btn', '', 'moveStick']) {
        final s = InputEditorSession(sampleAsset())
          ..select(const OnScreenSelection('jump'));
        CheckedEdits.renameOnScreen(s, 'jump', bad);
        expect(s.canUndo, isFalse, reason: bad);
        expect(s.message.value, isNotNull, reason: bad);
        expect(s.asset.findBinding('b13')!.path, '<OnScreen>/jump');
        expect(s.selection, const OnScreenSelection('jump'));
      }
    });

    test('to a name, and back: every binding follows both ways', () {
      final s = InputEditorSession(sampleAsset());
      CheckedEdits.renameOnScreen(s, 'jump', ' hop ');
      expect(s.asset.findBinding('b13')!.path, '<OnScreen>/hop');
      expect(s.selection, const OnScreenSelection('hop'));
      CheckedEdits.renameOnScreen(s, 'hop', 'jump');
      expect(s.asset.encode(), sampleAsset().encode());
    });
  });

  group('a scheme renamed', () {
    test('to a taken or empty name is refused, and said', () {
      final s = InputEditorSession(sampleAsset());
      CheckedEdits.renameScheme(s, 'Gamepad', 'Touch');
      expect(s.message.value, contains('already'));
      CheckedEdits.renameScheme(s, 'Gamepad', '  ');
      expect(s.message.value, contains('needs a name'));
      expect(s.canUndo, isFalse);
    });

    test('to a free name, it is selected under it', () {
      final s = InputEditorSession(sampleAsset());
      CheckedEdits.renameScheme(s, 'Gamepad', 'Pad');
      expect(s.asset.schemeNamed('Pad')!.group, 'Gamepad');
      expect(s.selection, const SchemeSelection('Pad'));
    });
  });

  group('an action', () {
    test('renamed to a bad name is refused before anyone is asked', () async {
      var asked = 0;
      final s = InputEditorSession(sampleAsset())
        ..confirmBreaking = (change, query) async {
          asked++;
          return true;
        };
      await CheckedEdits.renameAction(s, 'a10', 'big jump');
      expect(asked, 0);
      expect(s.message.value, contains('not a name'));
      await CheckedEdits.renameAction(s, 'a10', ' hop ');
      expect(asked, 1);
      expect(s.asset.actionById('a10')!.action.name, 'hop');
    });

    test('moved to another map: asked, then moved to its end', () async {
      String? asked;
      final s = InputEditorSession(sampleAsset())
        ..confirmBreaking = (change, query) async {
          asked = change;
          return query.matches('player/jump');
        };
      await CheckedEdits.moveActionToMap(s, 'a10', 'm14');
      expect(asked, 'Move "player/jump" to "ui"');
      expect(s.asset.mapById('m14')!.actions.last.name, 'jump');
      expect(s.asset.findAction('player/jump'), isNull);
    });

    test('moved where it is already, nothing is asked', () async {
      var asked = 0;
      final s = InputEditorSession(sampleAsset())
        ..confirmBreaking = (change, query) async {
          asked++;
          return true;
        };
      await CheckedEdits.moveActionToMap(s, 'a10', 'm1');
      expect(asked, 0);
      expect(s.canUndo, isFalse);
    });

    test('its type changed: what went with it is said', () {
      final s = InputEditorSession(
        AssetEdits.setProcessors(sampleAsset(), 'a2', const [
          ProcessorDef('normalizeVector2'),
        ]),
      );
      CheckedEdits.changeActionType(s, 'a2', ActionValueType.button);
      final move = s.asset.actionById('a2')!.action;
      expect(move.processors, isEmpty);
      expect(
        s.message.value,
        '1 composite and 2 processors of the wrong kind for a button went '
        'with the change.',
        reason: 'WASD; normalizeVector2, and the stick\'s stickDeadzone',
      );
    });
  });

  test('deleting an on-screen control says how many bindings it unbound', () {
    final s = InputEditorSession(sampleAsset());
    CheckedEdits.deleteOnScreen(s, 'jump');
    expect(s.asset.findBinding('b13')!.path, '');
    expect(s.message.value, '1 binding named "jump" is unbound now.');
  });
}
