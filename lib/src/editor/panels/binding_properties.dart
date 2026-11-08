import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../asset/asset.dart';
import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import '../look/input_text_field.dart';
import 'control_path_field.dart';
import 'property_rows.dart';
import 'step_list_editor.dart';

/// What controls an action of [type] can read.
Set<ControlValueType> _wantedFor(ActionValueType type) =>
    type == ActionValueType.vector2
    ? {ControlValueType.vector2}
    : {ControlValueType.button, ControlValueType.axis};

/// Which schemes a binding belongs to. None ticked is every scheme.
class _Groups extends StatelessWidget {
  const _Groups({required this.session, required this.binding});

  final InputEditorSession session;
  final InputBindingDef binding;

  @override
  Widget build(BuildContext context) {
    final schemes = session.asset.schemes;
    if (schemes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SCHEMES', style: InputEditorTheme.heading),
        const SizedBox(height: 4),
        for (final scheme in schemes)
          PropertyToggle(
            key: ValueKey('scheme:${scheme.group}'),
            scheme.name,
            binding.groups.contains(scheme.group),
            (on) {
              final groups = [
                for (final g in binding.groups)
                  if (g != scheme.group) g,
                if (on) scheme.group,
              ];
              session.edit(
                'Schemes',
                (a) => AssetEdits.setGroups(a, binding.id, groups),
              );
            },
          ),
        if (binding.groups.isEmpty)
          Text(
            'None ticked: it counts in every scheme.',
            style: InputEditorTheme.label,
          ),
      ],
    );
  }
}

/// Other actions that use this control too.
class _SharedWith extends StatelessWidget {
  const _SharedWith({required this.session, required this.id});

  final InputEditorSession session;
  final String id;

  @override
  Widget build(BuildContext context) {
    final names = <String>{
      for (final c in session.conflicts)
        if (c.bindingIds.contains(id))
          for (final actionId in c.actionIds)
            if (session.asset.findBinding(id)?.action.id != actionId)
              session.asset.actionById(actionId)?.action.name ?? actionId,
    };
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: EditorTheme.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Also pressed by ${names.join(', ')} in this map — one press, '
              'both actions.',
              style: InputEditorTheme.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// The interactions and processors of the binding [id], each list with
/// what validation finds wrong in it.
List<Widget> _steps(
  InputEditorSession s,
  String id,
  InputBindingDef b,
  ActionValueType type, {
  String empty = '',
}) {
  final issues = s.issuesFor(id);
  return [
    StepListEditor<InteractionDef>(
      title: 'Interactions',
      kind: StepKind.interaction,
      steps: b.interactions,
      available: StepListEditor.interactions,
      settings: s.asset.settings,
      issues: issues,
      empty: empty,
      make: InteractionDef.new,
      onRefused: s.say,
      onChanged: (list) => s.edit(
        'Interactions',
        (a) => AssetEdits.setInteractions(a, id, list),
      ),
    ),
    const PropertyGap(),
    StepListEditor<ProcessorDef>(
      title: 'Processors',
      kind: StepKind.processor,
      steps: b.processors,
      available: StepListEditor.processorsFor(type),
      settings: s.asset.settings,
      issues: issues,
      make: ProcessorDef.new,
      onRefused: s.say,
      onChanged: (list) =>
          s.edit('Processors', (a) => AssetEdits.setProcessors(a, id, list)),
    ),
  ];
}

/// A binding to one control: the control, its schemes, its steps.
@internal
class ControlProperties extends StatelessWidget {
  /// The properties of the binding [id].
  const ControlProperties({
    super.key,
    required this.session,
    required this.harness,
    required this.id,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// What Listen hears through.
  final InputEditorHarness harness;

  /// The binding's id.
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    if (ref == null) return const PropertiesHelp();
    final b = ref.binding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${ref.action.name} · ${ref.map.name}',
          style: InputEditorTheme.label,
        ),
        const SizedBox(height: 8),
        ControlPathField(
          session: s,
          harness: harness,
          id: id,
          wanted: _wantedFor(ref.action.type),
        ),
        _SharedWith(session: s, id: id),
        const PropertyGap(),
        _Groups(session: s, binding: b),
        const PropertyGap(),
        ..._steps(
          s,
          id,
          b,
          ref.action.type,
          empty: "None: the action's own apply.",
        ),
        const PropertyGap(),
        PropertyProblems(s.issuesFor(id)),
      ],
    );
  }
}

/// A composite: its name, its settings, its parts, its schemes and steps.
@internal
class CompositeProperties extends StatelessWidget {
  /// The properties of the composite [id].
  const CompositeProperties({
    super.key,
    required this.session,
    required this.id,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// The composite's id.
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    if (ref == null || ref.binding is! CompositeBindingDef) {
      return const PropertiesHelp();
    }
    final c = ref.binding as CompositeBindingDef;
    final info = StepCatalog.composite(c.composite);
    final display = BindingDisplay(asset: s.asset);
    final issues = s.issuesFor(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${ref.action.name} · ${info?.step.label ?? c.composite}',
          style: InputEditorTheme.label,
        ),
        if ((info?.step.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              info!.step.description,
              style: InputEditorTheme.bodyMuted,
            ),
          ),
        const SizedBox(height: 8),
        PropertyField(
          'Name',
          InputTextField(
            value: c.name,
            hint: 'WASD, Arrows…',
            onCommit: (v) => s.edit(
              'Name composite',
              (a) => AssetEdits.updateBinding(
                a,
                id,
                (b) => (b as CompositeBindingDef).copyWith(name: v.trim()),
              ),
            ),
          ),
        ),
        for (final p in info?.step.params ?? const <ParamInfo>[])
          ParamField(
            info: p,
            value: c.params[p.name],
            settings: s.asset.settings,
            issues: [
              for (final i in issues)
                if (i.stepKind == null && i.param == p.name) i,
            ],
            onChanged: (v) {
              final params = Map<String, Object>.of(c.params);
              if (v == null) {
                params.remove(p.name);
              } else {
                params[p.name] = v;
              }
              final problem = StepListEditor.rangeProblem(
                info!.step,
                params,
                s.asset.settings,
              );
              if (problem != null) return s.say(problem);
              s.edit(
                'Composite setting',
                (a) => AssetEdits.updateBinding(
                  a,
                  id,
                  (b) => (b as CompositeBindingDef).copyWith(params: params),
                ),
              );
            },
          ),
        const PropertyGap(),
        Text('PARTS', style: InputEditorTheme.heading),
        const SizedBox(height: 4),
        for (final part in c.parts)
          InkWell(
            onTap: () => s.select(BindingSelection(part.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      prettifyName(part.part),
                      style: InputEditorTheme.bodyMuted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      part.path.isEmpty
                          ? 'Not bound'
                          : display.control(part.path),
                      style: InputEditorTheme.body,
                    ),
                  ),
                  if (s.issuesFor(part.id).isNotEmpty)
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: EditorTheme.error,
                    ),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: EditorTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 4,
          children: [
            for (final part in info?.parts ?? const <String>[])
              TextButton(
                onPressed: () => s.select(
                  BindingSelection(
                    s.create(
                      'Add part',
                      (a) => AssetEdits.addPart(a, id, part),
                    ),
                  ),
                ),
                child: Text('+ $part', style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const PropertyGap(),
        _Groups(session: s, binding: c),
        const PropertyGap(),
        ..._steps(s, id, c, ref.action.type),
        const PropertyGap(),
        PropertyProblems(issues),
      ],
    );
  }
}

/// One part of a composite: its control and its processors.
@internal
class PartProperties extends StatelessWidget {
  /// The properties of the part [id].
  const PartProperties({
    super.key,
    required this.session,
    required this.harness,
    required this.id,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// What Listen hears through.
  final InputEditorHarness harness;

  /// The part's id.
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    final part = ref?.part;
    if (ref == null || part == null) return const PropertiesHelp();
    final c = ref.binding as CompositeBindingDef;
    final composite = c.name.isNotEmpty
        ? c.name
        : StepCatalog.composite(c.composite)?.step.label ?? c.composite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => s.select(BindingSelection(c.id)),
          child: Row(
            children: [
              Icon(Icons.chevron_left, size: 14, color: EditorTheme.textMuted),
              Text(
                '${ref.action.name} · $composite',
                style: InputEditorTheme.label,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          prettifyName(part.part),
          style: InputEditorTheme.body.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 8),
        ControlPathField(
          session: s,
          harness: harness,
          id: id,
          wanted: const {ControlValueType.button, ControlValueType.axis},
        ),
        _SharedWith(session: s, id: id),
        const PropertyGap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          kind: StepKind.processor,
          steps: part.processors,
          available: StepListEditor.processorsFor(ActionValueType.axis),
          settings: s.asset.settings,
          issues: s.issuesFor(id),
          make: ProcessorDef.new,
          onRefused: s.say,
          onChanged: (list) => s.edit(
            'Processors',
            (a) => AssetEdits.setProcessors(a, id, list),
          ),
        ),
        const PropertyGap(),
        PropertyProblems(s.issuesFor(id)),
      ],
    );
  }
}
