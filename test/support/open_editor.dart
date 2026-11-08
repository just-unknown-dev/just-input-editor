import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';
import 'package:just_inputs/just_inputs.dart';

import 'sample_asset.dart';

/// Where the tests keep the asset they open.
const samplePath = 'assets/input/game.input.json';

/// A store holding [sampleAsset] at [samplePath].
MemoryInputAssetStore sampleStore() =>
    MemoryInputAssetStore({samplePath: sampleAsset().encode()});

/// Opens an [InputEditor] on [store] at [path], at the size the whole
/// editor is laid out for (1600 × 1000, a pixel ratio of 1), and waits for
/// the file to be read.
Future<InputEditorState> openEditor(
  WidgetTester tester, {
  InputAssetStore? store,
  String? path = samplePath,
  GamepadSource? gamepads,
  InputReferenceFinder? references,
  VoidCallback? onClose,
  String? Function(InputActionAsset asset, String path)? onSaved,
  void Function(Future<bool> Function()? guard)? setCloseGuard,
  Stream<String>? fileChanges,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: InputEditor(
        store: store ?? sampleStore(),
        path: path,
        gamepads: gamepads,
        references: references,
        onClose: onClose,
        onSaved: onSaved,
        setCloseGuard: setCloseGuard,
        fileChanges: fileChanges,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<InputEditorState>(find.byType(InputEditor));
}

/// [text] in the actions tree — not the live test or a legend.
Finder inTree(String text) => find.descendant(
  of: find.byKey(const ValueKey('actions-tree')),
  matching: find.text(text),
);

/// The text field on the Properties row labelled [label].
Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byType(TextField),
);

/// Types [text] into [field] and presses Enter — then a frame more: a
/// value the editor refused is put back in the field the frame after.
Future<void> commit(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
}

/// Opens the bottom tab called [name]: `keyboard`, `gamepad`, `touch`,
/// `live`.
Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('tab:$name')));
  await tester.pump();
}

/// Selects [selection] in [state]'s session, and lets the editor show it.
Future<void> selectIn(
  WidgetTester tester,
  InputEditorState state,
  InputEditorSelection selection,
) async {
  state.session!.select(selection);
  await tester.pump();
}
