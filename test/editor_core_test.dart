import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import 'sample_asset.dart';

void main() {
  group('asset edits', () {
    test('maps: add with a free name, rename follows the join actions', () {
      var a = sampleAsset();
      final (withMap, id) = AssetEdits.addMap(a, name: 'player');
      expect(withMap.mapById(id)!.name, 'player2');
      expect(id, 'm40');

      a = AssetEdits.renameMap(a, 'm14', 'menu');
      expect(a.players.joinActions, ['menu/join']);
      expect(validateAsset(a), isEmpty);
    });

    test('deleting a map takes its join action with it', () {
      final a = AssetEdits.deleteMap(sampleAsset(), 'm14');
      expect(a.mapNamed('ui'), isNull);
      expect(a.players.joinActions, isEmpty);
    });

    test('duplicating gives every copy fresh ids', () {
      final (a, id) = AssetEdits.duplicateMap(sampleAsset(), 'm1');
      expect(a.maps.map((m) => m.name), ['player', 'player2', 'ui']);
      expect(validateAsset(a).where((i) => i.code == 'duplicateId'), isEmpty);
      final copy = a.mapById(id)!;
      expect(copy.actions.first.bindings.first, isA<CompositeBindingDef>());
      expect(a.nextId, greaterThan(sampleAsset().nextId + 10));
    });

    test('actions: add, rename (join path too), duplicate, delete', () {
      var a = sampleAsset();
      final (added, id) = AssetEdits.addAction(a, 'm1', name: 'jump');
      expect(added.actionById(id)!.action.name, 'jump2');

      a = AssetEdits.renameAction(a, 'a18', 'hop');
      expect(a.players.joinActions, ['ui/hop']);

      final (dup, copyId) = AssetEdits.duplicateAction(a, 'a10');
      final player = dup.mapNamed('player')!;
      expect(player.actions.map((x) => x.name), ['move', 'jump', 'jump2']);
      expect(
        dup.actionById(copyId)!.action.bindings.map((b) => b.id),
        isNot(contains('b11')),
      );

      a = AssetEdits.deleteAction(a, 'a18');
      expect(a.players.joinActions, isEmpty);
    });

    test('an action moved to another map keeps its bindings', () {
      final a = AssetEdits.moveAction(
        sampleAsset(),
        'a15',
        toMapId: 'm1',
        index: 0,
      );
      expect(a.mapNamed('player')!.actions.first.name, 'pause');
      expect(a.mapNamed('ui')!.actions.map((x) => x.name), ['join']);
      expect(a.findAction('player/pause')!.action.bindings, hasLength(2));
    });

    test('moving the join action keeps it the join action', () {
      final a = AssetEdits.moveAction(
        sampleAsset(),
        'a18',
        toMapId: 'm1',
        index: 5,
      );
      expect(a.players.joinActions, ['player/join']);
      expect(validateAsset(a), isEmpty);
    });

    test('reordering within a map', () {
      final a = AssetEdits.moveAction(sampleAsset(), 'a10', index: 0);
      expect(a.mapNamed('player')!.actions.map((x) => x.name), [
        'jump',
        'move',
      ]);
    });

    test('changing the type drops composites that no longer fit', () {
      final a = AssetEdits.changeActionType(
        sampleAsset(),
        'a2',
        ActionValueType.button,
      );
      final move = a.actionById('a2')!.action;
      expect(move.type, ActionValueType.button);
      expect(move.bindings.whereType<CompositeBindingDef>(), isEmpty);
      expect(move.bindings, hasLength(2), reason: 'the two sticks stay');
    });

    test('bindings: add, composite, a second part, set, delete', () {
      var a = sampleAsset();
      final (withB, b) = AssetEdits.addBinding(
        a,
        'a10',
        path: '<Keyboard>/j',
        groups: ['KeyboardMouse'],
      );
      expect(withB.findBinding(b)!.path, '<Keyboard>/j');

      final (withC, c) = AssetEdits.addComposite(
        a,
        'a2',
        CompositeKinds.vector2,
        name: 'Arrows',
      );
      final comp = withC.findBinding(c)!.binding as CompositeBindingDef;
      expect(comp.parts.map((p) => p.part), ['up', 'down', 'left', 'right']);
      expect(comp.parts.every((p) => p.path.isEmpty), isTrue);

      final (withPart, partId) = AssetEdits.addPart(
        withC,
        c,
        'up',
        path: '<Keyboard>/upArrow',
      );
      final parts =
          (withPart.findBinding(c)!.binding as CompositeBindingDef).parts;
      expect(parts.map((p) => p.part), ['up', 'up', 'down', 'left', 'right']);
      expect(parts[1].id, partId);

      a = AssetEdits.setPath(withPart, parts.first.id, '<Keyboard>/i');
      expect(a.findBinding(parts.first.id)!.path, '<Keyboard>/i');
      a = AssetEdits.deleteBinding(a, partId);
      expect(
        (a.findBinding(c)!.binding as CompositeBindingDef).parts,
        hasLength(4),
      );
      a = AssetEdits.deleteBinding(a, c);
      expect(a.findBinding(c), isNull);
    });

    test('processors and interactions go where they are put', () {
      var a = AssetEdits.setInteractions(sampleAsset(), 'a10', const [
        InteractionDef('tap'),
      ]);
      expect(a.actionById('a10')!.action.interactions.single.type, 'tap');
      a = AssetEdits.setProcessors(a, 'b4', const [
        ProcessorDef('scale', {'factor': 2}),
      ]);
      expect(a.findBinding('b4')!.part!.processors.single.type, 'scale');
      a = AssetEdits.setInteractions(a, 'b11', const [InteractionDef('hold')]);
      expect(a.findBinding('b11')!.binding.interactions.single.type, 'hold');
    });

    test('renaming an on-screen control rebinds what named it', () {
      final a = AssetEdits.updateOnScreen(
        sampleAsset(),
        'jump',
        (c) => c.copyWith(id: 'hop'),
      );
      expect(a.findBinding('b13')!.path, '<OnScreen>/hop');
      expect(validateAsset(a), isEmpty);
    });

    test('a group renamed or removed follows into the bindings', () {
      var a = AssetEdits.updateScheme(
        sampleAsset(),
        'Gamepad',
        (s) => s.copyWith(group: 'Pad'),
      );
      expect(a.findBinding('b12')!.binding.groups, ['Pad']);
      a = AssetEdits.deleteScheme(a, 'Gamepad');
      expect(a.findBinding('b12')!.binding.groups, isEmpty);
    });

    test('the starter asset plays, and is clean', () {
      final a = starterInputAsset();
      expect(validateAsset(a).where((i) => i.isError), isEmpty);
      expect(findBindingConflicts(a), isEmpty);
      expect(a.findAction('player/move')!.action.type, ActionValueType.vector2);
    });
  });

  group('the session', () {
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

    test('history is capped', () {
      final session = InputEditorSession(sampleAsset());
      for (var i = 0; i < InputEditorSession.maxUndo + 20; i++) {
        session.edit(
          'n',
          (a) => AssetEdits.updateOnScreen(
            a,
            'jump',
            (c) => c.copyWith(size: i / 1000),
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

    test('problems are found, and the conflicted bindings named', () {
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

    test('saved: not dirty until changed again', () {
      final session = InputEditorSession(sampleAsset(), path: 'x.input.json');
      session.edit('a', (a) => AssetEdits.renameAction(a, 'a10', 'hop'));
      session.markSaved();
      expect(session.isDirty, isFalse);
      session.undo();
      expect(session.isDirty, isTrue, reason: 'the file says hop');
    });
  });

  group('asset stores', () {
    test('files: a save reads back, and leaves nothing beside it', () async {
      final dir = await Directory.systemTemp.createTemp('input_store');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileInputAssetStore(dir.path);
      const path = 'assets/input/game.input.json';
      expect(await store.exists(path), isFalse);
      await store.save(path, sampleAsset());
      expect(await store.exists(path), isTrue);
      expect((await store.load(path)).encode(), sampleAsset().encode());
      expect(File('${dir.path}/$path.saving').existsSync(), isFalse);
    });

    test('memory: the same, for tests', () async {
      final store = MemoryInputAssetStore();
      await store.save('a.input.json', sampleAsset());
      expect((await store.load('a.input.json')).name, 'sample');
      expect(store.load('b.input.json'), throwsA(isA<FileSystemException>()));
    });
  });
}
