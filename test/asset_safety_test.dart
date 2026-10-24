// The edits and readers that keep an asset whole: names that code can ask
// for, ids that never collide, references that follow or are found, a file
// that does not read saying why.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import 'sample_asset.dart';

void main() {
  group('names', () {
    test('an action needs a name code can ask for, unique in its map', () {
      final a = sampleAsset();
      expect(AssetEdits.actionNameProblem(a, 'a10', ''), isNotNull);
      expect(AssetEdits.actionNameProblem(a, 'a10', 'big jump'), isNotNull);
      expect(AssetEdits.actionNameProblem(a, 'a10', '2jump'), isNotNull);
      expect(
        AssetEdits.actionNameProblem(a, 'a10', 'move'),
        contains('already has'),
      );
      expect(
        AssetEdits.actionNameProblem(a, 'a10', 'pause'),
        isNull,
        reason: 'another map\'s name is free here',
      );
      for (final bad in ['', 'big jump', 'move']) {
        expect(
          identical(AssetEdits.renameAction(a, 'a10', bad), a),
          isTrue,
          reason: '"$bad" changes nothing',
        );
      }
    });

    test('a map too', () {
      final a = sampleAsset();
      expect(AssetEdits.mapNameProblem(a, 'm1', 'ui'), contains('already'));
      expect(AssetEdits.mapNameProblem(a, 'm1', ''), isNotNull);
      expect(identical(AssetEdits.renameMap(a, 'm1', 'ui'), a), isTrue);
      expect(AssetEdits.renameMap(a, 'm1', 'hero').mapNamed('hero'), isNotNull);
    });
  });

  group('ids', () {
    test('a clean asset needs no repair', () {
      expect(AssetEdits.repairIds(sampleAsset()), isNull);
    });

    test('a nextId behind the ids moves past them', () {
      final stale = sampleAsset().copyWith(nextId: 1);
      final (fixed, said) = AssetEdits.repairIds(stale)!;
      expect(fixed.nextId, 21, reason: 'b20 is the highest id');
      expect(said, contains('nextId'));
      final (added, id) = AssetEdits.addBinding(fixed, 'a10');
      expect(id, 'b21');
      expect(validateAsset(added).where((i) => i.code == 'idAhead'), isEmpty);
    });

    test('an id used twice gets a new one where it comes again', () {
      final a = sampleAsset();
      // A merge: both branches added a binding as b11.
      final doubled = AssetEdits.updateAction(
        a,
        'a15',
        (x) => x.copyWith(
          bindings: [
            ...x.bindings,
            const ControlBindingDef(id: 'b11', path: '<Keyboard>/p'),
          ],
        ),
      );
      final (fixed, said) = AssetEdits.repairIds(doubled)!;
      expect(said, contains('used twice'));
      expect(fixed.findBinding('b11')!.action.name, 'jump', reason: 'first');
      final pause = fixed.actionById('a15')!.action.bindings;
      expect(pause.last.id, 'b40', reason: 'the next free id');
      expect((pause.last as ControlBindingDef).path, '<Keyboard>/p');
      expect(
        validateAsset(fixed).where((i) => i.code == 'duplicateId'),
        isEmpty,
      );
    });
  });

  test('an action dropped on a row lands before it, either way', () {
    final a = sampleAsset();
    final withThree = AssetEdits.addAction(a, 'm1', name: 'dash').$1;
    List<String> names(InputActionAsset x) => [
      for (final y in x.mapById('m1')!.actions) y.name,
    ];
    expect(names(withThree), ['move', 'jump', 'dash']);
    final dashId = withThree.mapById('m1')!.actions.last.id;
    // Down: move onto dash ends up just before dash.
    expect(names(AssetEdits.moveActionBefore(withThree, 'a2', dashId)), [
      'jump',
      'move',
      'dash',
    ]);
    // Up: dash onto move ends up first.
    expect(names(AssetEdits.moveActionBefore(withThree, dashId, 'a2')), [
      'dash',
      'move',
      'jump',
    ]);
  });

  group('schemes', () {
    test('a group another scheme has is refused', () {
      final a = sampleAsset();
      final same = AssetEdits.updateScheme(
        a,
        'Gamepad',
        (s) => s.copyWith(group: 'Touch'),
      );
      expect(identical(same, a), isTrue);
      expect(a.findBinding('b12')!.binding.groups, ['Gamepad']);
    });

    test('the filter follows its scheme\'s group, and goes with it', () {
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

  test('deleting an on-screen control unbinds what named it', () {
    final a = AssetEdits.deleteOnScreen(sampleAsset(), 'jump');
    expect(a.onScreenControl('jump'), isNull);
    expect(a.findBinding('b13')!.path, '', reason: 'unbound, not dangling');
    expect(validateAsset(a).where((i) => i.code == 'unknownControl'), isEmpty);
    expect(a.findBinding('b9')!.path, '<OnScreen>/moveStick');
  });

  group('the session', () {
    test('undo and redo with nothing to do do nothing', () {
      final session = InputEditorSession(sampleAsset());
      session
        ..undo()
        ..redo();
      expect(session.asset.encode(), sampleAsset().encode());
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
      expect(session.inGesture, isTrue);
      expect(session.isDirty, isTrue);
      heard = 0;
      session.endGesture();
      expect(session.inGesture, isFalse);
      expect(heard, 1);
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
  });

  group('reading a file', () {
    String withAction(Object? type) {
      final json = sampleAsset().toJson();
      final maps = json['maps'] as List;
      ((maps.first as Map)['actions'] as List).first['type'] = type;
      return jsonEncode(json);
    }

    test('a value of the wrong kind is a FormatException', () {
      expect(
        () => parseInputAsset(withAction('vector')),
        throwsA(isA<FormatException>()),
        reason: 'no such type: an ArgumentError underneath',
      );
      expect(
        () => parseInputAsset(withAction(3)),
        throwsA(isA<FormatException>()),
        reason: 'a number where a name goes: a cast underneath',
      );
      final short = sampleAsset().toJson();
      ((short['onScreen'] as List).first as Map)['anchor'] = [0.5];
      expect(
        () => parseInputAsset(jsonEncode(short)),
        throwsA(isA<FormatException>()),
      );
      expect(
        parseInputAsset(sampleAsset().encode()).encode(),
        sampleAsset().encode(),
      );
    });

    test('the stores read through it', () async {
      final store = MemoryInputAssetStore({'x.input.json': withAction('x')});
      await expectLater(
        store.load('x.input.json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('what names an action outside the asset', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('input_refs');
      final scene = {
        'entities': [
          {
            'name': 'Player',
            'components': [
              {
                'type': 'ThirdPersonController',
                'fields': {'jumpAction': 'jump', 'moveAction': 'move'},
              },
              {
                'type': 'Sprite',
                'fields': {'animation': 'jump'},
              },
            ],
          },
        ],
      };
      await File(
        '${root.path}/assets/scenes/level.scene.json',
      ).create(recursive: true).then((f) => f.writeAsString(jsonEncode(scene)));
      await File('${root.path}/assets/input/game.input.json')
          .create(recursive: true)
          .then((f) => f.writeAsString(sampleAsset().encode()));
      await File('${root.path}/lib/game/actions.dart')
          .create(recursive: true)
          .then(
            (f) => f.writeAsString(
              "const jump = 'jump';\nconst hop = 'player/jump';\n"
              "const word = 'jumping';\n",
            ),
          );
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    test(
      'scene fields that hold actions, and string literals in code',
      () async {
        final finder = FileInputReferenceFinder(root.path);
        final found = await finder.find(
          InputReferenceQuery.action(sampleAsset(), 'a10'),
        );
        expect(found.map((r) => '${r.file} ${r.where} ${r.value}'), [
          'assets/scenes/level.scene.json '
              'Player · ThirdPersonController.jumpAction jump',
          'lib/game/actions.dart line 1 jump',
          'lib/game/actions.dart line 2 player/jump',
        ]);
      },
    );

    test('a map\'s paths, not its actions\' bare names', () async {
      final finder = FileInputReferenceFinder(root.path);
      final found = await finder.find(
        InputReferenceQuery.mapRename(sampleAsset(), 'm1'),
      );
      expect(found.map((r) => r.value), ['player/jump']);
    });
  });
}
