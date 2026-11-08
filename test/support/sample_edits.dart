import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

/// One call of every [AssetEdits] operation, by name, each a change to
/// [sampleAsset]-shaped assets — for the tests that every edit round-trips
/// through the file and is undone exactly.
final Map<String, InputActionAsset Function(InputActionAsset a)> sampleEdits = {
  'addMap': (a) => AssetEdits.addMap(a).$1,
  'renameMap': (a) => AssetEdits.renameMap(a, 'm14', 'menu'),
  'setMapEnabled': (a) => AssetEdits.setMapEnabled(a, 'm1', false),
  'deleteMap': (a) => AssetEdits.deleteMap(a, 'm14'),
  'duplicateMap': (a) => AssetEdits.duplicateMap(a, 'm1').$1,
  'moveMap': (a) => AssetEdits.moveMap(a, 'm14', 0),
  'addAction': (a) => AssetEdits.addAction(a, 'm1').$1,
  'renameAction': (a) => AssetEdits.renameAction(a, 'a10', 'hop'),
  'deleteAction': (a) => AssetEdits.deleteAction(a, 'a10'),
  'duplicateAction': (a) => AssetEdits.duplicateAction(a, 'a2').$1,
  'moveAction': (a) => AssetEdits.moveAction(a, 'a15', toMapId: 'm1', index: 1),
  'changeActionType': (a) =>
      AssetEdits.changeActionType(a, 'a2', ActionValueType.axis),
  'addBinding': (a) => AssetEdits.addBinding(a, 'a10').$1,
  'addComposite': (a) =>
      AssetEdits.addComposite(a, 'a10', CompositeKinds.oneModifier).$1,
  'addPart': (a) => AssetEdits.addPart(a, 'b3', 'left').$1,
  'setPath': (a) => AssetEdits.setPath(a, 'b4', '<Keyboard>/i'),
  'setGroups': (a) => AssetEdits.setGroups(a, 'b11', const []),
  'deleteBinding': (a) => AssetEdits.deleteBinding(a, 'b5'),
  'duplicateBinding': (a) => AssetEdits.duplicateBinding(a, 'b3').$1,
  'moveBinding': (a) => AssetEdits.moveBinding(a, 'b13', 0),
  'setInteractions': (a) =>
      AssetEdits.setInteractions(a, 'a10', const [InteractionDef('tap')]),
  'setProcessors': (a) =>
      AssetEdits.setProcessors(a, 'b6', const [ProcessorDef('invert')]),
  'addOnScreen': (a) => AssetEdits.addOnScreen(a, OnScreenKind.stick).$1,
  'updateOnScreen': (a) =>
      AssetEdits.updateOnScreen(a, 'jump', (c) => c.copyWith(size: 0.2)),
  'deleteOnScreen': (a) => AssetEdits.deleteOnScreen(a, 'moveStick'),
  'addScheme': (a) => AssetEdits.addScheme(a).$1,
  'updateScheme': (a) =>
      AssetEdits.updateScheme(a, 'Touch', (s) => s.copyWith(group: 'T')),
  'deleteScheme': (a) => AssetEdits.deleteScheme(a, 'Touch'),
  'repairIds': (a) => AssetEdits.repairIds(a.copyWith(nextId: 2))!.$1,
};
