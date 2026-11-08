// The editor's text field — the kit's CommitTextField — keeps what was
// typed when it is left (Enter, Tab, a click elsewhere) once per change; Esc
// puts back what was there, and with nothing typed leaves Esc to whoever
// wants it. What the owner refuses does not stay on screen.

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/src/editor/look/input_text_field.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late List<String> kept;
  var dismissed = 0;

  Future<Finder> pump(
    WidgetTester tester, {
    FutureOr<void> Function(String)? onCommit,
  }) async {
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
              child: InputTextField(
                value: 'jump',
                onCommit: onCommit ?? kept.add,
              ),
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

  testWidgets('Enter keeps it once, though it also leaves the field', (
    tester,
  ) async {
    final field = await pump(tester);
    await tester.enterText(field, 'leap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(kept, ['leap']);
  }, variant: _desktop);

  testWidgets('a value its owner kept as it was shows again', (tester) async {
    final field = await pump(tester);
    await tester.enterText(field, 'leap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'jump',
      reason: 'the owner here never takes the new value',
    );
    // Shown again, it takes the same edit again.
    await tester.enterText(find.byType(TextField), 'leap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(kept, ['leap', 'leap']);
    expect(field, findsOneWidget);
  }, variant: _desktop);

  testWidgets('an owner that asks first is waited for', (tester) async {
    final answer = Completer<void>();
    final field = await pump(tester, onCommit: (_) => answer.future);
    await tester.enterText(field, 'leap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'leap',
      reason: 'still being asked about',
    );
    answer.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'jump',
      reason: 'called off: the owner kept its value',
    );
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
