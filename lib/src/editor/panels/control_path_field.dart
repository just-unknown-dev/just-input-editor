import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import 'control_picker.dart';

/// The control a binding or part reads: what it is, and three ways to
/// change it — pick from the list, press it (Listen), or clear it.
@internal
class ControlPathField extends StatelessWidget {
  /// The field for the binding or part [id], which reads a [wanted] kind
  /// of control.
  const ControlPathField({
    super.key,
    required this.session,
    required this.harness,
    required this.id,
    required this.wanted,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// What Listen hears through.
  final InputEditorHarness harness;

  /// The binding's or part's id.
  final String id;

  /// What the picker offers first.
  final Set<ControlValueType> wanted;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: harness,
    builder: (context, _) {
      final ref = session.asset.findBinding(id);
      final path = ref?.path ?? '';
      final parsed = ControlPath.tryParse(path);
      final listening = harness.listeningFor == id;
      final display = BindingDisplay(
        asset: session.asset,
        keyboard: harness.service.keyboard,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: EditorTheme.surfaceDarker,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: listening
                    ? EditorTheme.primaryBright
                    : EditorTheme.borderStrong,
              ),
            ),
            child: listening
                ? Text(
                    'Press a key, a button or a stick…  (Esc gives up)',
                    style: TextStyle(
                      color: EditorTheme.primaryBright,
                      fontSize: 12,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        InputEditorTheme.layoutIcon(parsed?.layout),
                        size: 16,
                        color: EditorTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              path.isEmpty
                                  ? 'Not bound'
                                  : display.control(path),
                              style: InputEditorTheme.body,
                            ),
                            if (path.isNotEmpty)
                              Text(path, style: InputEditorTheme.label),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (listening)
            // A mouse button is heard by clicking here.
            Listener(
              onPointerDown: harness.feedPointer,
              onPointerUp: harness.feedPointer,
              child: Container(
                height: 34,
                margin: const EdgeInsets.only(top: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: EditorTheme.borderStrong),
                ),
                child: Text(
                  '…or click here with the mouse button to bind',
                  style: InputEditorTheme.label,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: listening
                    ? null
                    : () async {
                        final picked = await pickControl(
                          context,
                          onScreen: session.asset.onScreen,
                          wanted: wanted,
                          current: path,
                        );
                        if (picked != null) {
                          session.edit(
                            'Bind control',
                            (a) => AssetEdits.setPath(a, id, picked),
                          );
                        }
                      },
                icon: const Icon(Icons.list, size: 16),
                label: const Text('Pick…'),
              ),
              TextButton.icon(
                onPressed: listening
                    ? harness.cancelListen
                    : () async {
                        final heard = await harness.listen(id);
                        if (heard != null) {
                          session.edit(
                            'Bind control',
                            (a) => AssetEdits.setPath(a, id, heard),
                          );
                        }
                      },
                icon: Icon(
                  listening ? Icons.stop_circle_outlined : Icons.hearing,
                  size: 16,
                ),
                label: Text(listening ? 'Stop' : 'Listen'),
              ),
              const Spacer(),
              if (path.isNotEmpty && !listening)
                EditorIconButton(
                  icon: Icons.backspace_outlined,
                  tooltip: 'Clear',
                  onTap: () => session.edit(
                    'Clear binding',
                    (a) => AssetEdits.setPath(a, id, ''),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
