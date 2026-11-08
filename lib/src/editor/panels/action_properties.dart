import 'package:flutter/material.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/checked_edits.dart';
import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import '../look/input_text_field.dart';
import 'property_rows.dart';
import 'step_list_editor.dart';

/// An action: its names, its type, whether it passes everything through
/// and may be rebound, and its interactions and processors.
@internal
class ActionProperties extends StatelessWidget {
  /// The properties of the action [id].
  const ActionProperties({super.key, required this.session, required this.id});

  /// The session it edits.
  final InputEditorSession session;

  /// The action's id.
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.actionById(id);
    if (ref == null) return const PropertiesHelp();
    final a = ref.action;
    final issues = s.issuesFor(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyField(
          'Name',
          InputTextField(
            value: a.name,
            onCommit: (v) => CheckedEdits.renameAction(s, id, v),
          ),
        ),
        PropertyField(
          'Shown as',
          InputTextField(
            value: a.displayName,
            hint: a.label,
            onCommit: (v) => s.edit(
              'Rename for players',
              (x) => AssetEdits.updateAction(
                x,
                id,
                (y) => y.copyWith(displayName: v.trim()),
              ),
            ),
          ),
        ),
        PropertyField(
          'Type',
          PropertySegments<ActionValueType>(
            values: const [
              ActionValueType.button,
              ActionValueType.axis,
              ActionValueType.vector2,
            ],
            labels: const ['Button', 'Axis', 'Vector 2'],
            selected: a.type,
            onChanged: (v) => CheckedEdits.changeActionType(s, id, v),
          ),
        ),
        PropertyToggle(
          'Pass-through',
          a.passThrough,
          (v) => s.edit(
            'Pass-through',
            (x) => AssetEdits.updateAction(
              x,
              id,
              (y) => y.copyWith(passThrough: v),
            ),
          ),
          hint:
              'Every change goes through, the latest wins — for pointers and '
              'aim.',
        ),
        PropertyToggle(
          'Players may rebind it',
          a.rebindable,
          (v) => s.edit(
            'Rebindable',
            (x) => AssetEdits.updateAction(
              x,
              id,
              (y) => y.copyWith(rebindable: v),
            ),
          ),
          hint: 'Shown on the Controls screen.',
        ),
        Text(
          'Map: ${ref.map.name}  ·  ${ref.path}',
          style: InputEditorTheme.label,
        ),
        const PropertyGap(),
        StepListEditor<InteractionDef>(
          title: 'Interactions',
          kind: StepKind.interaction,
          steps: a.interactions,
          available: StepListEditor.interactions,
          settings: s.asset.settings,
          issues: issues,
          empty: 'None: a plain press.',
          make: InteractionDef.new,
          onRefused: s.say,
          onChanged: (list) => s.edit(
            'Interactions',
            (x) => AssetEdits.setInteractions(x, id, list),
          ),
        ),
        const PropertyGap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          kind: StepKind.processor,
          steps: a.processors,
          available: StepListEditor.processorsFor(a.type),
          settings: s.asset.settings,
          issues: issues,
          make: ProcessorDef.new,
          onRefused: s.say,
          onChanged: (list) => s.edit(
            'Processors',
            (x) => AssetEdits.setProcessors(x, id, list),
          ),
        ),
        const PropertyGap(),
        PropertyProblems(issues),
      ],
    );
  }
}
