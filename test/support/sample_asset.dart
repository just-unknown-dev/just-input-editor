import 'package:just_inputs/just_inputs.dart';

/// A small asset shaped like a platformer's: a player map with a WASD
/// composite, a stick and a jump; a ui map with pause and a held join; the
/// three schemes; two on-screen controls.
InputActionAsset sampleAsset() => const InputActionAsset(
  name: 'sample',
  nextId: 40,
  players: PlayerSettingsDef(
    maxPlayers: 4,
    joining: JoinBehavior.onJoinAction,
    joinActions: ['ui/join'],
  ),
  schemes: [
    ControlSchemeDef(
      name: 'Keyboard & Mouse',
      group: 'KeyboardMouse',
      devices: [
        DeviceRequirement(InputLayouts.keyboard),
        DeviceRequirement(InputLayouts.mouse, optional: true),
      ],
    ),
    ControlSchemeDef(
      name: 'Gamepad',
      group: 'Gamepad',
      devices: [DeviceRequirement(InputLayouts.gamepad)],
    ),
    ControlSchemeDef(
      name: 'Touch',
      group: 'Touch',
      devices: [
        DeviceRequirement(InputLayouts.onScreen),
        DeviceRequirement(InputLayouts.touchscreen, optional: true),
      ],
    ),
  ],
  onScreen: [
    OnScreenControlDef(
      id: 'moveStick',
      kind: OnScreenKind.stick,
      anchorX: -0.7,
      anchorY: 0.6,
      size: 0.28,
      stickMode: StickMode.floating,
      stickAxis: StickAxis.horizontal,
      region: [0, 0.3, 0.5, 1],
    ),
    OnScreenControlDef(id: 'jump', anchorX: 0.72, anchorY: 0.62, label: 'JUMP'),
  ],
  maps: [
    ActionMapDef(
      id: 'm1',
      name: 'player',
      actions: [
        InputActionDef(
          id: 'a2',
          name: 'move',
          type: ActionValueType.vector2,
          bindings: [
            CompositeBindingDef(
              id: 'b3',
              composite: CompositeKinds.vector2,
              name: 'WASD',
              params: {'mode': 'digitalNormalized'},
              groups: ['KeyboardMouse'],
              parts: [
                CompositePartDef(id: 'b4', part: 'up', path: '<Keyboard>/w'),
                CompositePartDef(id: 'b5', part: 'down', path: '<Keyboard>/s'),
                CompositePartDef(id: 'b6', part: 'left', path: '<Keyboard>/a'),
                CompositePartDef(id: 'b7', part: 'right', path: '<Keyboard>/d'),
              ],
            ),
            ControlBindingDef(
              id: 'b8',
              path: '<Gamepad>/leftStick',
              groups: ['Gamepad'],
              processors: [
                ProcessorDef('stickDeadzone', {'min': 0.2}),
              ],
            ),
            ControlBindingDef(
              id: 'b9',
              path: '<OnScreen>/moveStick',
              groups: ['Touch'],
            ),
          ],
        ),
        InputActionDef(
          id: 'a10',
          name: 'jump',
          bindings: [
            ControlBindingDef(
              id: 'b11',
              path: '<Keyboard>/space',
              groups: ['KeyboardMouse'],
            ),
            ControlBindingDef(
              id: 'b12',
              path: '<Gamepad>/buttonSouth',
              groups: ['Gamepad'],
            ),
            ControlBindingDef(
              id: 'b13',
              path: '<OnScreen>/jump',
              groups: ['Touch'],
            ),
          ],
        ),
      ],
    ),
    ActionMapDef(
      id: 'm14',
      name: 'ui',
      actions: [
        InputActionDef(
          id: 'a15',
          name: 'pause',
          bindings: [
            ControlBindingDef(
              id: 'b16',
              path: '<Keyboard>/escape',
              groups: ['KeyboardMouse'],
            ),
            ControlBindingDef(
              id: 'b17',
              path: '<Gamepad>/start',
              groups: ['Gamepad'],
            ),
          ],
        ),
        InputActionDef(
          id: 'a18',
          name: 'join',
          rebindable: false,
          interactions: [
            InteractionDef('hold', {'duration': 0.6}),
          ],
          bindings: [
            ControlBindingDef(id: 'b19', path: '<Gamepad>/start'),
            ControlBindingDef(id: 'b20', path: '<Keyboard>/enter'),
          ],
        ),
      ],
    ),
  ],
);

/// [asset] with [change] made to its player map's jump action.
InputActionAsset withJump(
  InputActionAsset asset,
  InputActionDef Function(InputActionDef) change,
) {
  final player = asset.maps.first;
  return asset.copyWith(
    maps: [
      player.copyWith(
        actions: [
          for (final a in player.actions) a.name == 'jump' ? change(a) : a,
        ],
      ),
      ...asset.maps.skip(1),
    ],
  );
}
