import 'package:just_inputs/just_inputs.dart';

/// What "New input actions" makes: the three usual schemes, a player map
/// that moves and jumps on keyboard, gamepad and touch, and a ui map for
/// menus — something that plays, to change rather than build from nothing.
InputActionAsset starterInputAsset({String name = 'game'}) => InputActionAsset(
  name: name,
  nextId: 30,
  schemes: const [
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
  maps: const [
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
            ),
          ],
        ),
        InputActionDef(
          id: 'a9',
          name: 'jump',
          bindings: [
            ControlBindingDef(
              id: 'b10',
              path: '<Keyboard>/space',
              groups: ['KeyboardMouse'],
            ),
            ControlBindingDef(
              id: 'b11',
              path: '<Gamepad>/buttonSouth',
              groups: ['Gamepad'],
            ),
          ],
        ),
      ],
    ),
    ActionMapDef(
      id: 'm12',
      name: 'ui',
      actions: [
        InputActionDef(
          id: 'a13',
          name: 'pause',
          bindings: [
            ControlBindingDef(
              id: 'b14',
              path: '<Keyboard>/escape',
              groups: ['KeyboardMouse'],
            ),
            ControlBindingDef(
              id: 'b15',
              path: '<Gamepad>/start',
              groups: ['Gamepad'],
            ),
          ],
        ),
      ],
    ),
  ],
);
