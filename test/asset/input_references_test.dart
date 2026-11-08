// What names an action outside the asset: scene fields whose definitions
// make them input actions, and string literals in the game's code — and
// what it passes over.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_input_editor/just_input_editor.dart';

import '../support/sample_asset.dart';
import '../support/temp_folder.dart';

/// A kit's controller: its action fields of the input action kinds, and a
/// text field named like one that is not.
class _Controller extends Component {
  String jumpAction = 'jump';
  String moveAction = 'move';
  String fire = 'fire';
  List<String> comboActions = [];
  String labelAction = '';
}

FieldDefinition _field(
  String name,
  FieldType kind,
  Object? Function(_Controller c) read,
) => FieldDefinition(
  name: name,
  kind: kind,
  read: (c) => read(c as _Controller),
);

/// The engine's definitions, and the controller's.
ComponentDefinitionRegistry _definitions() => BuiltInComponents.registry()
  ..register(
    ComponentDefinition<_Controller>(
      type: 'ThirdPersonControllerComponent',
      create: _Controller.new,
      fields: [
        _field('jumpAction', InputDefinitions.actionType, (c) => c.jumpAction),
        _field('moveAction', InputDefinitions.actionType, (c) => c.moveAction),
        _field('fire', InputDefinitions.actionType, (c) => c.fire),
        _field(
          'comboActions',
          InputDefinitions.actionListType,
          (c) => c.comboActions,
        ),
        _field('labelAction', FieldTypes.text, (c) => c.labelAction),
      ],
    ),
  );

void main() {
  late Directory root;
  final actionFields = InputEditorModule.actionFieldsOf(_definitions());

  Future<void> write(String path, String text) async {
    final file = File('${root.path}/$path');
    await file.create(recursive: true);
    await file.writeAsString(text);
  }

  Map<String, Object> entity(
    String name,
    List<Map<String, Object>> c, {
    Map<String, Object>? prefab,
  }) => {'name': name, 'components': c, 'prefab': ?prefab};

  setUp(() async {
    root = tempFolder('input_refs');
    final scene = {
      'entities': [
        entity('Player', [
          {
            'type': 'ThirdPersonControllerComponent',
            'fields': {'jumpAction': 'jump', 'moveAction': 'move'},
          },
          {
            'type': 'Sprite',
            'fields': {'animation': 'jump'},
          },
        ]),
        // A timeline trigger's actions say what the timeline does — `pause`
        // is one, and an input action is called that too.
        entity('Door', [
          {
            'type': 'TimelineTriggerComponent',
            'fields': {'enterAction': 'play', 'exitAction': 'pause'},
          },
        ]),
        entity('Menu', [
          {
            'type': 'SimpleMovementComponent',
            'fields': {'action': 'pause'},
          },
        ]),
      ],
    };
    await write('assets/scenes/level.scene.json', jsonEncode(scene));
    await write('assets/input/game.input.json', sampleAsset().encode());
    await write('assets/broken.json', '{"action": "jump"');
    await write(
      'lib/game/actions.dart',
      "const jump = 'jump';\nconst hop = 'player/jump';\n"
          "const word = 'jumping';\nconst all = \"player/move\";\n",
    );
  });

  test('scene fields that hold actions, and string literals in code', () async {
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
    );
    expect(found.map((r) => '${r.file} ${r.where} ${r.value}'), [
      'assets/scenes/level.scene.json '
          'Player · ThirdPersonControllerComponent.jumpAction jump',
      'lib/game/actions.dart line 1 jump',
      'lib/game/actions.dart line 2 player/jump',
    ]);
  });

  test('a timeline trigger\'s actions are not input actions', () async {
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a15'),
    );
    expect(
      found.map((r) => r.where),
      ['Menu · SimpleMovementComponent.action'],
      reason:
          'the Door\'s exitAction "pause" is a timeline action: its '
          'definition says so (an enum), not a list of exceptions',
    );
    // The kind decides: were exitAction an input action field, it would be
    // found.
    final ifItWere = FileInputReferenceFinder(
      root.path,
      actionFields: (type) =>
          type == 'TimelineTriggerComponent' ? {'exitAction'} : const {},
    );
    expect(
      (await ifItWere.find(
        InputReferenceQuery.action(sampleAsset(), 'a15'),
      )).map((r) => r.where),
      ['Door · TimelineTriggerComponent.exitAction'],
    );
  });

  test('a field is found by its kind, not by its name', () async {
    await write(
      'assets/scenes/kinds.scene.json',
      jsonEncode({
        'entities': [
          entity('Hero', [
            {
              'type': 'ThirdPersonControllerComponent',
              // `fire` is not named like an action, and is one; the
              // label is named like one, and is text.
              'fields': {'fire': 'jump', 'labelAction': 'jump'},
            },
          ]),
        ],
      }),
    );
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
    );
    final wheres = [
      for (final r in found)
        if (r.file == 'assets/scenes/kinds.scene.json') r.where,
    ];
    expect(wheres, ['Hero · ThirdPersonControllerComponent.fire']);
  });

  test('a list of actions: each name in it', () async {
    await write(
      'assets/scenes/combo.scene.json',
      jsonEncode({
        'entities': [
          entity('Hero', [
            {
              'type': 'ThirdPersonControllerComponent',
              'fields': {
                'comboActions': ['move', 'player/jump', 'kick'],
              },
            },
          ]),
        ],
      }),
    );
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
    );
    expect(
      [
        for (final r in found)
          if (r.file == 'assets/scenes/combo.scene.json')
            '${r.where} ${r.value}',
      ],
      ['Hero · ThirdPersonControllerComponent.comboActions player/jump'],
    );
  });

  test(
    "a prefab instance's changes: an overridden field, an added component",
    () async {
      await write(
        'assets/scenes/instances.scene.json',
        jsonEncode({
          'entities': [
            entity(
              'Hero 2',
              const [],
              prefab: {
                'path': 'assets/prefabs/hero.prefab.json',
                'overrides': [
                  {
                    'component': 'ThirdPersonControllerComponent',
                    'field': 'jumpAction',
                    'value': 'jump',
                  },
                  {
                    'component': 'TimelineTriggerComponent',
                    'field': 'exitAction',
                    'value': 'jump',
                  },
                ],
                'addedComponents': [
                  {
                    'component': {
                      'type': 'SimpleMovementComponent',
                      'fields': {'action': 'jump'},
                    },
                  },
                ],
              },
            ),
          ],
        }),
      );
      final finder = FileInputReferenceFinder(
        root.path,
        actionFields: actionFields,
      );
      final found = await finder.find(
        InputReferenceQuery.action(sampleAsset(), 'a10'),
      );
      expect(
        [
          for (final r in found)
            if (r.file == 'assets/scenes/instances.scene.json') r.where,
        ],
        [
          'Hero 2 · ThirdPersonControllerComponent.jumpAction',
          'Hero 2 · SimpleMovementComponent.action',
        ],
      );
    },
  );

  test('a component no definition reads is not looked in', () async {
    await write(
      'assets/scenes/unknown.scene.json',
      jsonEncode({
        'entities': [
          entity('Ghost', [
            {
              'type': 'GoneComponent',
              'fields': {'jumpAction': 'jump', 'action': 'jump'},
            },
          ]),
        ],
      }),
    );
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
    );
    expect(found.where((r) => r.file.endsWith('unknown.scene.json')), isEmpty);
  });

  test('each component type is asked about once per search', () async {
    final asked = <String>[];
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: (type) {
        asked.add(type);
        return actionFields(type);
      },
    );
    await finder.find(InputReferenceQuery.action(sampleAsset(), 'a10'));
    expect(asked, hasLength(asked.toSet().length));
    expect(
      asked.toSet(),
      containsAll([
        'ThirdPersonControllerComponent',
        'SimpleMovementComponent',
      ]),
    );
  });

  test('a map\'s paths, not its actions\' bare names', () async {
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.mapRename(sampleAsset(), 'm1'),
    );
    expect(found.map((r) => r.value), ['player/jump', 'player/move']);
  });

  test('input assets and files that do not read are passed over', () async {
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
    );
    expect(
      found.where(
        (r) => r.file.endsWith('.input.json') || r.file.endsWith('broken.json'),
      ),
      isEmpty,
    );
  });

  test('at most [limit] are found', () async {
    final finder = FileInputReferenceFinder(
      root.path,
      actionFields: actionFields,
    );
    final found = await finder.find(
      InputReferenceQuery.action(sampleAsset(), 'a10'),
      limit: 2,
    );
    expect(found, hasLength(2));
  });

  test('an empty query finds nothing, and looks at nothing', () async {
    final finder = FileInputReferenceFinder(
      '${root.path}/nowhere',
      actionFields: actionFields,
    );
    expect(await finder.find(const InputReferenceQuery()), isEmpty);
    expect(const InputReferenceQuery().isEmpty, isTrue);
  });
}
