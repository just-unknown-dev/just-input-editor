// The Input Actions editor's text field keeps what was typed when it is left
// — Enter, Tab, a click elsewhere — once per change; Esc puts back what was
// there, and with nothing typed leaves Esc to whoever wants it.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/src/editor/widgets/editor_theme.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late List<String> kept;
  var dismissed = 0;

  Future<Finder> pump(WidgetTester tester) async {
    kept = [];
    dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  dismissed++,
            },
            child: SizedBox(
              width: 240,
              child: EditorTextField(value: 'jump', onCommit: kept.add),
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.tap(field, kind: PointerDeviceKind.mouse);
    await tester.pump();
    return field;
  }

  testWidgets('keeps what was typed when clicked away from', (tester) async {
    final field = await pump(tester);
    await tester.enterText(field, 'leap');

    await tester.tapAt(const Offset(600, 500), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(kept, ['leap']);
  }, variant: _desktop);

  testWidgets('Esc puts back what was there and keeps nothing', (tester) async {
    final field = await pump(tester);
    await tester.enterText(field, 'leap');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(kept, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, 'jump');
    expect(dismissed, 0, reason: 'this Esc was the field\'s');
  }, variant: _desktop);

  testWidgets('Esc with nothing typed is left to whoever wants it', (
    tester,
  ) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, 1);
  }, variant: _desktop);
}
