import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/checked_edits.dart';
import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import '../look/input_text_field.dart';
import 'property_rows.dart';

/// The on-screen controls: one chip each to pick it, Add, and the picked
/// one's id, label, place, size and stick settings.
@internal
class OnScreenProperties extends StatelessWidget {
  /// The properties of the on-screen control [id].
  const OnScreenProperties({
    super.key,
    required this.session,
    required this.id,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// The control's id.
  final String id;

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => PropertyField(
    label,
    Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: EditorTheme.primaryBright,
            onChangeStart: (_) => session.beginGesture(),
            onChangeEnd: (_) => session.endGesture(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(value.toStringAsFixed(2), style: InputEditorTheme.label),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = session;
    final c = s.asset.onScreenControl(id);
    void update(
      String label,
      OnScreenControlDef Function(OnScreenControlDef c) f,
    ) => s.edit(label, (a) => AssetEdits.updateOnScreen(a, id, f));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final other in s.asset.onScreen)
              ChoiceChip(
                label: Text(other.id, style: const TextStyle(fontSize: 11)),
                selected: other.id == id,
                selectedColor: EditorTheme.selectionBg,
                onSelected: (_) => s.select(OnScreenSelection(other.id)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Button', style: TextStyle(fontSize: 11)),
              onPressed: () => s.select(
                OnScreenSelection(
                  s.create(
                    'Add on-screen button',
                    (a) => AssetEdits.addOnScreen(a, OnScreenKind.button),
                  ),
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Stick', style: TextStyle(fontSize: 11)),
              onPressed: () => s.select(
                OnScreenSelection(
                  s.create(
                    'Add on-screen stick',
                    (a) => AssetEdits.addOnScreen(a, OnScreenKind.stick),
                  ),
                ),
              ),
            ),
          ],
        ),
        const PropertyGap(),
        if (c == null)
          Text(
            'Add a button or a stick. Bindings name them as <OnScreen>/id.',
            style: InputEditorTheme.bodyMuted,
          )
        else ...[
          PropertyField(
            'Id',
            InputTextField(
              value: c.id,
              onCommit: (v) => CheckedEdits.renameOnScreen(s, id, v),
            ),
          ),
          Text('Bound as <OnScreen>/${c.id}', style: InputEditorTheme.label),
          const SizedBox(height: 8),
          if (c.kind == OnScreenKind.button)
            PropertyField(
              'Label',
              InputTextField(
                value: c.label,
                onCommit: (v) => update('Label', (x) => x.copyWith(label: v)),
              ),
            ),
          _slider(
            'Across',
            c.anchorX,
            -1,
            1,
            (v) => update('Move control', (x) => x.copyWith(anchorX: v)),
          ),
          _slider(
            'Down',
            c.anchorY,
            -1,
            1,
            (v) => update('Move control', (x) => x.copyWith(anchorY: v)),
          ),
          _slider(
            'Size',
            c.size,
            0.05,
            0.6,
            (v) => update('Resize control', (x) => x.copyWith(size: v)),
          ),
          if (c.kind == OnScreenKind.stick) ...[
            PropertyField(
              'Where',
              PropertySegments<StickMode>(
                values: const [StickMode.fixed, StickMode.floating],
                labels: const ['Fixed', 'Under the thumb'],
                selected: c.stickMode,
                onChanged: (v) =>
                    update('Stick mode', (x) => x.copyWith(stickMode: v)),
              ),
            ),
            PropertyField(
              'Moves',
              PropertySegments<StickAxis>(
                values: const [
                  StickAxis.both,
                  StickAxis.horizontal,
                  StickAxis.vertical,
                ],
                labels: const ['Both', 'Across', 'Up/down'],
                selected: c.stickAxis,
                onChanged: (v) =>
                    update('Stick axis', (x) => x.copyWith(stickAxis: v)),
              ),
            ),
            if (c.stickMode == StickMode.floating)
              Text(
                'Drag the shaded area in the Touch tab to set where it may '
                'appear.',
                style: InputEditorTheme.label,
              ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => CheckedEdits.deleteOnScreen(s, id),
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: EditorTheme.error,
              ),
              label: Text('Delete', style: TextStyle(color: EditorTheme.error)),
            ),
          ),
        ],
      ],
    );
  }
}
