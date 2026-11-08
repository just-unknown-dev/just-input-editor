// The session: one undo step per change (none for a change that changes
// nothing), whether it is saved, the selection after an undo, the
// problems, and edits still being checked.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../support/sample_asset.dart';
import '../support/sample_edits.dart';

void main() {
  group('undo', () {
    test('every change is one undo step, and undo is exact', () {
      final session = InputEditorSession(sampleAsset());
      expect(session.isDirty, isFalse);
      session.edit(
        'Rename jump',
        (a) => AssetEdits.renameAction(a, 'a10', 'hop'),
      );
      session.edit('Delete pause', (a) => AssetEdits.deleteAction(a, 'a15'));
      expect(session.isDirty, isTrue);
      expect(session.undoLabel, 'Delete pause');

      session.undo();
      expect(session.asset.actionById('a15'), isNotNull);
      session.undo();
      expect(session.asset.encode(), sampleAsset().encode());
      expect(session.isDirty, isFalse, reason: 'back where it was saved');
      expect(session.canUndo, isFalse);

      session.redo();
      expect(session.asset.actionById('a10')!.action.name, 'hop');
      expect(session.redoLabel, 'Delete pause');
    });

    test('a new change forgets what could be redone', () {
      final session = InputEditorSession(sampleAsset());
      session.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      session.undo();
      session.edit('b', (a) => AssetEdits.renameAction(a, 'a10', 'leap'));
      expect(session.canRedo, isFalse);
    });

    test('undo and redo with nothing to do do nothing', () {
      final session = InputEditorSession(sampleAsset());
      session
        ..undo()
        ..redo();
      expect(session.asset.encode(), sampleAsset().encode());
    });

    test('a change that changes nothing is no step', () {
      final session = InputEditorSession(sampleAsset());
      var heard = 0;
      session.addListener(() => heard++);
      // "  " trimmed into "Shown as" — the same empty name — and a path set
      // to itself: new objects, the same asset.
      session.edit(
        'Rename for players',
        (a) => AssetEdits.updateAction(
          a,
          'a10',
          (x) => x.copyWith(displayName: '  '.trim()),
        ),
      );
      session.edit(
        'Bind control',
        (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/space'),
      );
      expect(session.canUndo, isFalse);
      expect(session.isDirty, isFalse);
      expect(heard, 0);
    });

    test('a gesture — a drag — is one step however many changes', () {
      final session = InputEditorSession(sampleAsset());
      session.beginGesture();
      for (final x in [0.1, 0.2, 0.3]) {
        session.edit(
          'Move button',
          (a) => AssetEdits.updateOnScreen(
            a,
            'jump',
            (c) => c.copyWith(anchorX: x),
          ),
        );
      }
      session.endGesture();
      expect(session.asset.onScreenControl('jump')!.anchorX, 0.3);
      session.undo();
      expect(session.asset.onScreenControl('jump')!.anchorX, 0.72);
      expect(session.canUndo, isFalse);
    });

    test('a drag is unsaved without encoding, and says when it ends', () {
      final session = InputEditorSession(sampleAsset());
      var heard = 0;
      session.addListener(() => heard++);
      session.beginGesture();
      session.edit(
        'Move',
        (a) => AssetEdits.updateOnScreen(
          a,
          'jump',
          (c) => c.copyWith(anchorX: 0.1),
        ),
      );
      expect(session.isInGesture, isTrue);
      expect(session.isDirty, isTrue);
      heard = 0;
      session.endGesture();
      expect(session.isInGesture, isFalse);
      expect(heard, 1);
    });

    test('through a drag the problems stay, and are found again after', () {
      final session = InputEditorSession(sampleAsset());
      expect(session.issues, isEmpty);
      session.beginGesture();
      session.edit(
        'Break',
        (a) => AssetEdits.setPath(a, 'b12', '<Gamepad>/no'),
      );
      expect(session.issues, isEmpty, reason: 'not validated per move');
      session.endGesture();
      expect(session.issuesFor('b12').single.code, 'unknownControl');
    });

    test('history is capped', () {
      final session = InputEditorSession(sampleAsset());
      for (var i = 0; i < InputEditorSession.maxUndo + 20; i++) {
        session.edit(
          'n',
          (a) => AssetEdits.updateOnScreen(
            a,
            'jump',
            (c) => c.copyWith(size: (i + 1) / 1000),
          ),
        );
      }
      var steps = 0;
      while (session.canUndo) {
        session.undo();
        steps++;
      }
      expect(steps, InputEditorSession.maxUndo);
    });
  });

  group('every edit undone', () {
    for (final MapEntry(key: name, value: edit) in sampleEdits.entries) {
      test('$name: back to the very text, and saved again', () {
        final session = InputEditorSession(sampleAsset());
        session.edit(name, edit);
        expect(session.canUndo, isTrue);
        session.undo();
        expect(session.asset.encode(), sampleAsset().encode());
        expect(session.isDirty, isFalse);
        session.redo();
        expect(session.asset.encode(), edit(sampleAsset()).encode());
      });
    }
  });

  group('saved', () {
    test('not dirty until changed again', () {
      final session = InputEditorSession(sampleAsset(), path: 'x.input.json');
      session.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      session.markSaved();
      expect(session.isDirty, isFalse);
      session.undo();
      expect(session.isDirty, isTrue, reason: 'the file says hop');
    });

    test('marked saved as written, not as it is now', () {
      final session = InputEditorSession(sampleAsset());
      session.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      final written = session.asset;
      session.edit('b', (a) => AssetEdits.renameAction(a, 'a10', 'leap'));
      session.markSaved(asset: written);
      expect(session.isDirty, isTrue, reason: 'leap is not on disk');
      session.undo();
      expect(session.isDirty, isFalse);
    });

    test('a new asset with no file yet is unsaved from the start', () {
      final session = InputEditorSession(starterInputAsset(), isNew: true);
      expect(session.isDirty, isTrue);
      expect(session.canUndo, isFalse);
      session.markSaved();
      expect(session.isDirty, isFalse);
    });

    test('a file read again is what is saved', () {
      final session = InputEditorSession(starterInputAsset(), isNew: true);
      session.load(sampleAsset(), path: 'x.input.json');
      expect(session.isDirty, isFalse);
      expect(session.matchesSaved(sampleAsset()), isTrue);
    });
  });

  group('selection', () {
    test('selecting shows its map; deleting it clears the selection', () {
      final session = InputEditorSession(sampleAsset());
      expect(session.selectedMapId, 'm1');
      session.select(const BindingSelection('b17'));
      expect(session.selectedMapId, 'm14');
      session.edit('Delete', (a) => AssetEdits.deleteBinding(a, 'b17'));
      expect(session.selection, const NoSelection());
      session.undo();
      expect(session.asset.findBinding('b17'), isNotNull);
    });

    test('the scheme filter follows its scheme\'s group, and goes with it', () {
      final session = InputEditorSession(sampleAsset())
        ..schemeFilter = 'Gamepad';
      session.edit(
        'Group',
        (a) => AssetEdits.updateScheme(
          a,
          'Gamepad',
          (s) => s.copyWith(group: 'Pad'),
        ),
      );
      expect(session.schemeFilter, 'Pad');
      session.undo();
      expect(session.schemeFilter, 'Gamepad');
      session.edit('Delete', (a) => AssetEdits.deleteScheme(a, 'Gamepad'));
      expect(session.schemeFilter, isNull);
    });
  });

  group('problems', () {
    test('found, and the conflicted bindings named', () {
      final session = InputEditorSession(sampleAsset());
      expect(session.issues, isEmpty);
      session.edit(
        'Clash',
        (a) => AssetEdits.setPath(a, 'b11', '<Keyboard>/w'),
      );
      expect(session.conflictedBindings, containsAll(['b4', 'b11']));
      session.schemeFilter = 'Gamepad';
      expect(session.conflictedBindings, isEmpty);
      session.edit(
        'Break',
        (a) => AssetEdits.setPath(a, 'b12', '<Gamepad>/nope'),
      );
      expect(session.issuesFor('b12').single.code, 'unknownControl');
    });

    test('a step\'s problem says which step and which setting', () {
      final session = InputEditorSession(sampleAsset());
      session.edit(
        'Clamp',
        (a) => AssetEdits.setProcessors(a, 'b8', const [
          ProcessorDef('stickDeadzone'),
          ProcessorDef('clamp', {'min': 1, 'max': 0}),
        ]),
      );
      final issue = session.issuesFor('b8').single;
      expect(issue.code, 'badRange');
      expect(issue.stepKind, StepKind.processor);
      expect(issue.stepIndex, 1);
      expect(issue.param, 'min');
    });
  });

  group('colours', () {
    test('a map\'s actions take the colours in turn; each map starts over', () {
      final session = InputEditorSession(sampleAsset());
      expect(['a2', 'a10', 'a15', 'a18'].map(session.colorIndexOf), [
        0,
        1,
        0,
        1,
      ]);
      session.edit('Move', (a) => AssetEdits.moveAction(a, 'a10', index: 0));
      expect(session.colorIndexOf('a10'), 0);
    });
  });

  group('edits checked before they are made', () {
    test('wait, and are idle once answered', () async {
      final session = InputEditorSession(sampleAsset());
      final answer = Completer<bool>();
      session.confirmBreaking = (change, query) => answer.future;
      expect(session.isChecking, isFalse);
      final made = session.checked(
        'Rename',
        InputReferenceQuery.action(session.asset, 'a10'),
        () => session.edit('x', (a) => AssetEdits.renameAction(a, 'a10', 'h')),
      );
      expect(session.isChecking, isTrue);
      var idle = false;
      unawaited(session.idle.then((_) => idle = true));
      await Future<void>.delayed(Duration.zero);
      expect(idle, isFalse);
      answer.complete(true);
      await made;
      await Future<void>.delayed(Duration.zero);
      expect(idle, isTrue);
      expect(session.isChecking, isFalse);
      expect(session.asset.actionById('a10')!.action.name, 'h');
    });

    test('a no is no change', () async {
      final session = InputEditorSession(sampleAsset())
        ..confirmBreaking = (change, query) async => false;
      await session.checked(
        'Delete',
        InputReferenceQuery.action(session.asset, 'a10'),
        () => session.edit('x', (a) => AssetEdits.deleteAction(a, 'a10')),
      );
      expect(session.asset.actionById('a10'), isNotNull);
      expect(session.isChecking, isFalse);
    });
  });

  group('each part tells its own listeners', () {
    late InputEditorSession session;
    final heard = <String, int>{};

    setUp(() {
      session = InputEditorSession(sampleAsset());
      for (final (name, part) in [
        ('asset', session.assetChanges),
        ('selection', session.selectionChanges),
        ('scheme', session.schemeFilterChanges),
        ('search', session.searchChanges),
        ('saved', session.savedChanges),
        ('problems', session.problemChanges),
        ('session', session),
      ]) {
        part.addListener(() => heard[name] = (heard[name] ?? 0) + 1);
      }
    });
    tearDown(() => session.dispose());

    /// Who hears of [change], and how often.
    Map<String, int> after(void Function() change) {
      heard.clear();
      change();
      return Map.of(heard);
    }

    test('an edit: the asset and the problems', () {
      expect(
        after(
          () => session.edit(
            'Rename jump',
            (a) => AssetEdits.renameAction(a, 'a10', 'hop'),
          ),
        ),
        {'asset': 1, 'problems': 1, 'session': 1},
      );
      expect(after(session.undo), {'asset': 1, 'problems': 1, 'session': 1});
      expect(after(session.redo), {'asset': 1, 'problems': 1, 'session': 1});
    });

    test('a selection, or another map shown: the selection alone', () {
      expect(after(() => session.select(const ActionSelection('a15'))), {
        'selection': 1,
        'session': 1,
      });
      expect(after(() => session.selectMap('m1')), {
        'selection': 1,
        'session': 1,
      });
      expect(
        after(() => session.selectMap('m1')),
        isEmpty,
        reason: 'the same again is no change',
      );
    });

    test('a search: the search alone; a scheme: it and the conflicts', () {
      expect(after(() => session.search = 'jump'), {'search': 1, 'session': 1});
      expect(after(() => session.schemeFilter = 'Gamepad'), {
        'scheme': 1,
        'problems': 1,
        'session': 1,
      });
    });

    test('a save: what was saved alone', () {
      session.edit('Rename', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      expect(after(session.markSaved), {'saved': 1, 'session': 1});
      expect(session.isDirty, isFalse);
    });

    test('a drag: the asset at each move, the problems once, at its end', () {
      session.beginGesture();
      for (final x in [0.1, 0.2, 0.3]) {
        expect(
          after(
            () => session.edit(
              'Move button',
              (a) => AssetEdits.updateOnScreen(
                a,
                'jump',
                (c) => c.copyWith(anchorX: x),
              ),
            ),
          ),
          {'asset': 1, 'session': 1},
        );
      }
      expect(after(session.endGesture), {
        'asset': 1,
        'problems': 1,
        'session': 1,
      });
    });

    test('an undo that takes away what was selected: the selection too', () {
      final id = session.create(
        'Add action',
        (a) => AssetEdits.addAction(a, 'm14', name: 'dash'),
      );
      session.select(ActionSelection(id));
      expect(after(session.undo), {
        'asset': 1,
        'selection': 1,
        'problems': 1,
        'session': 1,
      });
      expect(session.selection, const NoSelection());
    });

    test('a scheme deleted under its filter: the filter goes, and says', () {
      session.schemeFilter = 'Gamepad';
      expect(
        after(
          () => session.edit(
            'Delete scheme',
            (a) => AssetEdits.deleteScheme(a, 'Gamepad'),
          ),
        ),
        {'asset': 1, 'scheme': 1, 'problems': 1, 'session': 1},
      );
      expect(session.schemeFilter, isNull);
    });

    test('a file read: every part it resets', () {
      session.select(const ActionSelection('a10'));
      expect(after(() => session.load(sampleAsset())), {
        'asset': 1,
        'selection': 1,
        'saved': 1,
        'problems': 1,
        'session': 1,
      });
    });

    test('they go with the session', () {
      final s = InputEditorSession(sampleAsset())..dispose();
      expect(
        () => s.assetChanges.addListener(() {}),
        throwsFlutterError,
        reason: 'disposed with it',
      );
    });
  });
}
