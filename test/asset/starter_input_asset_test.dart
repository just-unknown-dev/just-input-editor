import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

void main() {
  test('the starter asset plays, and is clean', () {
    final a = starterInputAsset();
    expect(validateAsset(a).where((i) => i.isError), isEmpty);
    expect(findBindingConflicts(a), isEmpty);
    expect(a.findAction('player/move')!.action.type, ActionValueType.vector2);
    expect(AssetEdits.repairIds(a), isNull, reason: 'its ids are in order');
  });

  test('it takes the name it is given', () {
    expect(starterInputAsset(name: 'menu').name, 'menu');
  });
}
