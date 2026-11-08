// Every edit as a pure function: what it changes, what follows it (join
// actions, scheme groups, on-screen bindings), what it refuses, and that
// what it makes saves and reads back the same.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import '../support/sample_asset.dart';
import '../support/sample_edits.dart';

void main() {
  group('maps', () {
    test('add with a free name, rename follows the join actions', () {
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

    test('a map\'s name follows the name rule, and is unique', () {
      final a = sampleAsset();
      expect(AssetEdits.mapNameProblem(a, 'm1', 'ui'), contains('already'));
      expect(AssetEdits.mapNameProblem(a, 'm1', ''), isNotNull);
      expect(AssetEdits.mapNameProblem(a, 'm1', 'my map'), isNotNull);
      expect(identical(AssetEdits.renameMap(a, 'm1', 'ui'), a), isTrue);
      expect(AssetEdits.renameMap(a, 'm1', 'hero').mapNamed('hero'), isNotNull);
    });
  });

  group('actions', () {
    test('add, rename (join path too), duplicate, delete', () {
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

    test('the name rule is just_inputs\' own', () {
      for (final name in ['hop', '_x', 'a1', 'big jump', '2x', 'a/b', '']) {
        expect(
          AssetEdits.actionNameProblem(sampleAsset(), 'a10', name) == null,
          InputNames.isValid(name),
          reason: name,
        );
      }
    });

    test('moved to another map, it keeps its bindings', () {
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

    test('the join action moved stays the join action', () {
      final a = AssetEdits.moveAction(
        sampleAsset(),
        'a18',
        toMapId: 'm1',
        index: 5,
      );
      expect(a.players.joinActions, ['player/join']);
      expect(validateAsset(a), isEmpty);
    });

    test('reordered within a map', () {
      final a = AssetEdits.moveAction(sampleAsset(), 'a10', index: 0);
      expect(a.mapNamed('player')!.actions.map((x) => x.name), [
        'jump',
        'move',
      ]);
    });

    test('dropped on a row, it lands before it, either way', () {
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
  });

  group('changing an action\'s type', () {
    test('drops composites that no longer fit', () {
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

    test('drops processors of the wrong kind, on it and its bindings', () {
      final withSteps = AssetEdits.setProcessors(
        AssetEdits.setProcessors(sampleAsset(), 'a2', const [
          ProcessorDef('normalizeVector2'),
          ProcessorDef('mystery'),
        ]),
        'b8',
        const [ProcessorDef('stickDeadzone'), ProcessorDef('scaleVector2')],
      );
      final a = AssetEdits.changeActionType(
        withSteps,
        'a2',
        ActionValueType.button,
      );
      final move = a.actionById('a2')!.action;
      expect(
        move.processors.map((p) => p.type),
        ['mystery'],
        reason:
            'a vector\'s goes; one nothing registered stays for '
            'validation to flag',
      );
      expect(
        a.findBinding('b8')!.binding.processors.map((p) => p.type),
        isEmpty,
      );
      expect(
        validateAsset(a).where((i) => i.code == 'unknownProcessor'),
        hasLength(1),
      );
    });

    test('a composite fits by what it makes: a vector for a vector', () {
      bool fits(ActionValueType t, ControlValueType m) => AssetEdits.fits(t, m);
      expect(fits(ActionValueType.button, ControlValueType.axis), isTrue);
      expect(fits(ActionValueType.button, ControlValueType.button), isTrue);
      expect(fits(ActionValueType.button, ControlValueType.vector2), isFalse);
      expect(fits(ActionValueType.axis, ControlValueType.vector2), isFalse);
      expect(fits(ActionValueType.vector2, ControlValueType.vector2), isTrue);
      expect(fits(ActionValueType.vector2, ControlValueType.axis), isFalse);
    });
  });

  group('bindings', () {
    test('add, composite, a second part, set, delete', () {
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
  });

  group('on-screen controls', () {
    test('renamed, it takes what named it along', () {
      final a = AssetEdits.updateOnScreen(
        sampleAsset(),
        'jump',
        (c) => c.copyWith(id: 'hop'),
      );
      expect(a.findBinding('b13')!.path, '<OnScreen>/hop');
      expect(validateAsset(a), isEmpty);
    });

    test('an id that is not a name, or is taken, is refused', () {
      final a = sampleAsset();
      for (final bad in ['jump btn', 'jump/btn', '', '2go', 'moveStick']) {
        expect(
          AssetEdits.onScreenIdProblem(a, 'jump', bad),
          isNotNull,
          reason: bad,
        );
        expect(
          identical(
            AssetEdits.updateOnScreen(a, 'jump', (c) => c.copyWith(id: bad)),
            a,
          ),
          isTrue,
          reason: '"$bad" leaves the bindings naming "jump"',
        );
      }
      expect(a.findBinding('b13')!.path, '<OnScreen>/jump');
    });

    test('a rename and its reverse put every binding back', () {
      final there = AssetEdits.updateOnScreen(
        sampleAsset(),
        'moveStick',
        (c) => c.copyWith(id: 'stick2'),
      );
      expect(there.findBinding('b9')!.path, '<OnScreen>/stick2');
      final back = AssetEdits.updateOnScreen(
        there,
        'stick2',
        (c) => c.copyWith(id: 'moveStick'),
      );
      expect(back.encode(), sampleAsset().encode());
    });

    test('deleting one unbinds what named it', () {
      final a = AssetEdits.deleteOnScreen(sampleAsset(), 'jump');
      expect(a.onScreenControl('jump'), isNull);
      expect(a.findBinding('b13')!.path, '', reason: 'unbound, not dangling');
      expect(
        validateAsset(a).where((i) => i.code == 'unknownControl'),
        isEmpty,
      );
      expect(a.findBinding('b9')!.path, '<OnScreen>/moveStick');
    });
  });

  group('schemes', () {
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

    test('a name another scheme has is refused, and said', () {
      final a = sampleAsset();
      expect(AssetEdits.schemeNameProblem(a, 'Gamepad', 'Touch'), isNotNull);
      expect(AssetEdits.schemeNameProblem(a, 'Gamepad', ''), isNotNull);
      expect(AssetEdits.schemeNameProblem(a, 'Gamepad', 'Pad'), isNull);
      expect(
        identical(
          AssetEdits.updateScheme(
            a,
            'Gamepad',
            (s) => s.copyWith(name: 'Touch'),
          ),
          a,
        ),
        isTrue,
      );
    });

    test('a new scheme takes a free name and a free group', () {
      var (a, name) = AssetEdits.addScheme(sampleAsset());
      expect(name, 'Scheme');
      // Renamed, it keeps its group: the next one must not take it.
      a = AssetEdits.updateScheme(
        a,
        'Scheme',
        (s) => s.copyWith(name: 'Joystick'),
      );
      final (b, second) = AssetEdits.addScheme(a);
      expect(second, 'Scheme');
      expect(b.schemes.map((s) => '${s.name}/${s.group}').skip(3), [
        'Joystick/Scheme',
        'Scheme/Scheme2',
      ]);
      expect(
        validateAsset(b).where((i) => i.code == 'duplicateGroup'),
        isEmpty,
      );
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

    test('a copy carries every field but the ids', () {
      // Every field of an action, a binding, a composite and a part set to
      // something not its default: a copy made by hand would drop any field
      // just_inputs adds and the copy forgot.
      const full = InputActionDef(
        id: 'a10',
        name: 'jump',
        type: ActionValueType.axis,
        passThrough: true,
        displayName: 'Hop',
        rebindable: false,
        interactions: [
          InteractionDef('hold', {'duration': 0.3}),
        ],
        processors: [
          ProcessorDef('scale', {'factor': 2}),
        ],
        bindings: [
          ControlBindingDef(
            id: 'b11',
            path: '<Keyboard>/space',
            groups: ['KeyboardMouse'],
            interactions: [InteractionDef('tap')],
            processors: [ProcessorDef('invert')],
          ),
          CompositeBindingDef(
            id: 'b12',
            composite: CompositeKinds.axis1D,
            name: 'QE',
            params: {'whichSideWins': 'positive'},
            groups: ['KeyboardMouse'],
            interactions: [InteractionDef('press')],
            processors: [
              ProcessorDef('clamp', {'min': -0.5}),
            ],
            parts: [
              CompositePartDef(
                id: 'b13',
                part: 'negative',
                path: '<Keyboard>/q',
                processors: [
                  ProcessorDef('scale', {'factor': 3}),
                ],
              ),
            ],
          ),
        ],
      );
      final a = AssetEdits.updateAction(sampleAsset(), 'a10', (_) => full);
      final (copied, id) = AssetEdits.duplicateAction(a, 'a10');
      Object? withoutIds(Object? json) => switch (json) {
        final Map<String, dynamic> m => {
          for (final e in m.entries)
            if (e.key != 'id') e.key: withoutIds(e.value),
        },
        final List<dynamic> l => [for (final x in l) withoutIds(x)],
        _ => json,
      };
      final copy = copied.actionById(id)!.action.toJson();
      expect(withoutIds(copy), withoutIds({...full.toJson(), 'name': 'jump2'}));
      final (map, mapId) = AssetEdits.duplicateMap(a, 'm1');
      expect(
        withoutIds(map.mapById(mapId)!.actions[1].toJson()),
        withoutIds(full.toJson()),
      );
    });
  });

  group('round trips', () {
    // Each edit's result saves, reads back and saves to the same text — no
    // edit leaves anything the format cannot hold.
    final a = sampleAsset();
    for (final MapEntry(key: name, value: edit) in sampleEdits.entries) {
      test(name, () {
        final next = edit(a);
        expect(next.encode(), isNot(a.encode()), reason: 'it changes it');
        expect(InputActionAsset.parse(next.encode()).encode(), next.encode());
      });
    }
  });
}
