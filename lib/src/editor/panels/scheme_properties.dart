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

/// The control schemes: one chip each to pick it, Add, and the picked
/// one's name, group and devices.
@internal
class SchemeProperties extends StatelessWidget {
  /// The properties of the scheme called [name].
  const SchemeProperties({
    super.key,
    required this.session,
    required this.name,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// The scheme's name.
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final scheme = s.asset.schemeNamed(name);
    void update(
      String label,
      ControlSchemeDef Function(ControlSchemeDef c) f,
    ) => s.edit(label, (a) => AssetEdits.updateScheme(a, name, f));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final other in s.asset.schemes)
              ChoiceChip(
                label: Text(other.name, style: const TextStyle(fontSize: 11)),
                selected: other.name == name,
                selectedColor: EditorTheme.selectionBg,
                onSelected: (_) => s.select(SchemeSelection(other.name)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Scheme', style: TextStyle(fontSize: 11)),
              onPressed: () => s.select(
                SchemeSelection(
                  s.create('Add scheme', (a) => AssetEdits.addScheme(a)),
                ),
              ),
            ),
          ],
        ),
        const PropertyGap(),
        if (scheme == null)
          Text(
            'A scheme is a way of playing — keyboard and mouse, a gamepad, '
            'touch — and the bindings that go with it.',
            style: InputEditorTheme.bodyMuted,
          )
        else ...[
          PropertyField(
            'Name',
            InputTextField(
              value: scheme.name,
              onCommit: (v) => CheckedEdits.renameScheme(s, name, v),
            ),
          ),
          PropertyField(
            'Group',
            InputTextField(
              value: scheme.group,
              mono: true,
              onCommit: (v) {
                final g = v.trim();
                if (g.isEmpty || g == scheme.group) return;
                final other = s.asset.schemeWithGroup(g);
                if (other != null) {
                  s.say('"${other.name}" already uses the group "$g".');
                  return;
                }
                update('Scheme group', (x) => x.copyWith(group: g));
              },
            ),
          ),
          Text(
            'Bindings say which schemes they are in by group.',
            style: InputEditorTheme.label,
          ),
          const PropertyGap(),
          Text('DEVICES', style: InputEditorTheme.heading),
          const SizedBox(height: 4),
          for (var i = 0; i < scheme.devices.length; i++)
            Row(
              children: [
                Icon(
                  InputEditorTheme.layoutIcon(scheme.devices[i].layout),
                  size: 15,
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scheme.devices[i].layout,
                    style: InputEditorTheme.body,
                  ),
                ),
                Text('optional', style: InputEditorTheme.label),
                Checkbox(
                  value: scheme.devices[i].optional,
                  visualDensity: VisualDensity.compact,
                  activeColor: EditorTheme.primaryBright,
                  onChanged: (v) => update(
                    'Device optional',
                    (x) => x.copyWith(
                      devices: [
                        for (var j = 0; j < x.devices.length; j++)
                          j == i
                              ? DeviceRequirement(
                                  x.devices[j].layout,
                                  optional: v ?? false,
                                )
                              : x.devices[j],
                      ],
                    ),
                  ),
                ),
                EditorIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove',
                  size: 20,
                  onTap: () => update(
                    'Remove device',
                    (x) => x.copyWith(devices: [...x.devices]..removeAt(i)),
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 4,
            children: [
              for (final layout in InputLayouts.all)
                if (!scheme.layouts.contains(layout))
                  TextButton(
                    onPressed: () => update(
                      'Add device',
                      (x) => x.copyWith(
                        devices: [...x.devices, DeviceRequirement(layout)],
                      ),
                    ),
                    child: Text(
                      '+ $layout',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => s.edit(
                'Delete scheme',
                (a) => AssetEdits.deleteScheme(a, name),
              ),
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: EditorTheme.error,
              ),
              label: Text(
                'Delete scheme',
                style: TextStyle(color: EditorTheme.error),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
