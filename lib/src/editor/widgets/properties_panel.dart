import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/input_editor_session.dart';
import '../core/checked_edits.dart';
import 'control_picker.dart';
import 'editor_harness.dart';
import 'editor_theme.dart';
import 'step_list.dart';

/// Everything about what is selected, down the right.
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.session,
    required this.harness,
  });

  final InputEditorSession session;
  final EditorHarness harness;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final (title, body) = switch (s.selection) {
      NoSelection() => ('Properties', const _Help()),
      ActionSelection(:final id) => (
        'Action',
        _ActionProperties(session: s, id: id),
      ),
      BindingSelection(:final id) => switch (s.asset.findBinding(id)) {
        null => ('Properties', const _Help()),
        BindingRef(part: final CompositePartDef _) => (
          'Composite part',
          _PartProperties(session: s, harness: harness, id: id),
        ),
        BindingRef(binding: CompositeBindingDef()) => (
          'Composite',
          _CompositeProperties(session: s, id: id),
        ),
        _ => (
          'Binding',
          _ControlProperties(session: s, harness: harness, id: id),
        ),
      },
      OnScreenSelection(:final id) => (
        'On-screen controls',
        _OnScreenProperties(session: s, id: id),
      ),
      SchemeSelection(:final name) => (
        'Control schemes',
        _SchemeProperties(session: s, name: name),
      ),
      SettingsSelection() => (
        'Players & settings',
        _SettingsProperties(session: s),
      ),
    };
    return Container(
      width: 340,
      color: InputEditorTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Small pieces -------------------------------------------------------------

class _Field extends StatelessWidget {
  const _Field(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: InputEditorTheme.bodyMuted),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
    this.hint = '',
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: hint,
    child: InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              height: 24,
              child: Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                activeColor: InputEditorTheme.accent,
                checkColor: InputEditorTheme.background,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            Expanded(child: Text(label, style: InputEditorTheme.body)),
          ],
        ),
      ),
    ),
  );
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1, color: InputEditorTheme.border),
  );
}

class _Problems extends StatelessWidget {
  const _Problems(this.issues);

  final List<AssetIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  i.isError ? Icons.error_outline : Icons.warning_amber_rounded,
                  size: 14,
                  color: i.isError
                      ? InputEditorTheme.danger
                      : InputEditorTheme.warning,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(i.message, style: InputEditorTheme.body)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) => Text(
    'Pick an action or a binding to change it.\n\n'
    'Maps are on the left — the tick says which are on when the game '
    'starts. Actions and their bindings are in the middle: + beside an '
    'action adds a binding, right-click for more.\n\n'
    'Below: the keyboard, a gamepad and a phone, to see what is bound '
    'where, and a live test to try it all.',
    style: InputEditorTheme.bodyMuted,
  );
}

List<StepInfo> _processorsFor(ActionValueType type) => [
  for (final p in InputProcessors.all)
    if (p.forVector == (type == ActionValueType.vector2)) p.info,
];

List<StepInfo> get _interactions => [
  for (final i in InputInteractions.all) i.info,
];

// --- Action -----------------------------------------------------------------------

class _ActionProperties extends StatelessWidget {
  const _ActionProperties({required this.session, required this.id});

  final InputEditorSession session;
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.actionById(id);
    if (ref == null) return const _Help();
    final a = ref.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          'Name',
          EditorTextField(
            value: a.name,
            onCommit: (v) => CheckedEdits.renameAction(s, id, v),
          ),
        ),
        _Field(
          'Shown as',
          EditorTextField(
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
        _Field(
          'Type',
          SegmentedButton<ActionValueType>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: ActionValueType.button,
                label: Text('Button', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: ActionValueType.axis,
                label: Text('Axis', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: ActionValueType.vector2,
                label: Text('Vector 2', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {a.type},
            onSelectionChanged: (v) => s.edit(
              'Change type',
              (x) => AssetEdits.changeActionType(x, id, v.single),
            ),
          ),
        ),
        _Toggle(
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
              'Every change goes through, the latest wins — for pointers and aim.',
        ),
        _Toggle(
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
        const _Gap(),
        StepListEditor<InteractionDef>(
          title: 'Interactions',
          steps: a.interactions,
          available: _interactions,
          settings: s.asset.settings,
          empty: 'None: a plain press.',
          make: InteractionDef.new,
          onChanged: (list) => s.edit(
            'Interactions',
            (x) => AssetEdits.setInteractions(x, id, list),
          ),
        ),
        const _Gap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          steps: a.processors,
          available: _processorsFor(a.type),
          settings: s.asset.settings,
          make: ProcessorDef.new,
          onChanged: (list) => s.edit(
            'Processors',
            (x) => AssetEdits.setProcessors(x, id, list),
          ),
        ),
        const _Gap(),
        _Problems(s.issuesFor(id)),
      ],
    );
  }
}

// --- Bindings ---------------------------------------------------------------------

/// The control a binding or part reads: what it is, and three ways to
/// change it — pick from the list, press it (Listen), or clear it.
class ControlPathField extends StatelessWidget {
  const ControlPathField({
    super.key,
    required this.session,
    required this.harness,
    required this.id,
    required this.wanted,
  });

  final InputEditorSession session;
  final EditorHarness harness;
  final String id;
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
              color: InputEditorTheme.field,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: listening
                    ? InputEditorTheme.accent
                    : InputEditorTheme.border,
              ),
            ),
            child: listening
                ? Text(
                    'Press a key, a button or a stick…  (Esc gives up)',
                    style: TextStyle(
                      color: InputEditorTheme.accent,
                      fontSize: 12,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        InputEditorTheme.layoutIcon(parsed?.layout),
                        size: 16,
                        color: InputEditorTheme.textMuted,
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
                  border: Border.all(color: InputEditorTheme.border),
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
          _Toggle(
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

Set<ControlValueType> _wantedFor(ActionValueType type) =>
    type == ActionValueType.vector2
    ? {ControlValueType.vector2}
    : {ControlValueType.button, ControlValueType.axis};

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
            color: InputEditorTheme.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Also pressed by ${names.join(', ')} in this map — one press, both actions.',
              style: InputEditorTheme.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlProperties extends StatelessWidget {
  const _ControlProperties({
    required this.session,
    required this.harness,
    required this.id,
  });

  final InputEditorSession session;
  final EditorHarness harness;
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    if (ref == null) return const _Help();
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
        const _Gap(),
        _Groups(session: s, binding: b),
        const _Gap(),
        StepListEditor<InteractionDef>(
          title: 'Interactions',
          steps: b.interactions,
          available: _interactions,
          settings: s.asset.settings,
          empty: 'None: the action\'s own apply.',
          make: InteractionDef.new,
          onChanged: (list) => s.edit(
            'Interactions',
            (a) => AssetEdits.setInteractions(a, id, list),
          ),
        ),
        const _Gap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          steps: b.processors,
          available: _processorsFor(ref.action.type),
          settings: s.asset.settings,
          make: ProcessorDef.new,
          onChanged: (list) => s.edit(
            'Processors',
            (a) => AssetEdits.setProcessors(a, id, list),
          ),
        ),
        const _Gap(),
        _Problems(s.issuesFor(id)),
      ],
    );
  }
}

class _CompositeProperties extends StatelessWidget {
  const _CompositeProperties({required this.session, required this.id});

  final InputEditorSession session;
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    if (ref == null || ref.binding is! CompositeBindingDef) {
      return const _Help();
    }
    final c = ref.binding as CompositeBindingDef;
    final entry = InputComposites.entry(c.composite);
    final display = BindingDisplay(asset: s.asset);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${ref.action.name} · ${entry?.info.label ?? c.composite}',
          style: InputEditorTheme.label,
        ),
        if ((entry?.info.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              entry!.info.description,
              style: InputEditorTheme.bodyMuted,
            ),
          ),
        const SizedBox(height: 8),
        _Field(
          'Name',
          EditorTextField(
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
        for (final p in entry?.info.params ?? const <ParamInfo>[])
          ParamField(
            info: p,
            value: c.params[p.name],
            settings: s.asset.settings,
            onChanged: (v) => s.edit(
              'Composite setting',
              (a) => AssetEdits.updateBinding(a, id, (b) {
                final params = Map<String, Object>.of(
                  (b as CompositeBindingDef).params,
                );
                if (v == null) {
                  params.remove(p.name);
                } else {
                  params[p.name] = v;
                }
                return b.copyWith(params: params);
              }),
            ),
          ),
        const _Gap(),
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
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: InputEditorTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 4,
          children: [
            for (final part in entry?.parts ?? const <String>[])
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
        const _Gap(),
        _Groups(session: s, binding: c),
        const _Gap(),
        StepListEditor<InteractionDef>(
          title: 'Interactions',
          steps: c.interactions,
          available: _interactions,
          settings: s.asset.settings,
          make: InteractionDef.new,
          onChanged: (list) => s.edit(
            'Interactions',
            (a) => AssetEdits.setInteractions(a, id, list),
          ),
        ),
        const _Gap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          steps: c.processors,
          available: _processorsFor(ref.action.type),
          settings: s.asset.settings,
          make: ProcessorDef.new,
          onChanged: (list) => s.edit(
            'Processors',
            (a) => AssetEdits.setProcessors(a, id, list),
          ),
        ),
        const _Gap(),
        _Problems(s.issuesFor(id)),
      ],
    );
  }
}

class _PartProperties extends StatelessWidget {
  const _PartProperties({
    required this.session,
    required this.harness,
    required this.id,
  });

  final InputEditorSession session;
  final EditorHarness harness;
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final ref = s.asset.findBinding(id);
    final part = ref?.part;
    if (ref == null || part == null) return const _Help();
    final c = ref.binding as CompositeBindingDef;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => s.select(BindingSelection(c.id)),
          child: Row(
            children: [
              Icon(
                Icons.chevron_left,
                size: 14,
                color: InputEditorTheme.textMuted,
              ),
              Text(
                '${ref.action.name} · ${c.name.isNotEmpty ? c.name : CompositeKinds.label(c.composite)}',
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
        const _Gap(),
        StepListEditor<ProcessorDef>(
          title: 'Processors',
          steps: part.processors,
          available: _processorsFor(ActionValueType.axis),
          settings: s.asset.settings,
          make: ProcessorDef.new,
          onChanged: (list) => s.edit(
            'Processors',
            (a) => AssetEdits.setProcessors(a, id, list),
          ),
        ),
        const _Gap(),
        _Problems(s.issuesFor(id)),
      ],
    );
  }
}

// --- On-screen controls -----------------------------------------------------

class _OnScreenProperties extends StatelessWidget {
  const _OnScreenProperties({required this.session, required this.id});

  final InputEditorSession session;
  final String id;

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => _Field(
    label,
    Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: InputEditorTheme.accent,
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
                selectedColor: InputEditorTheme.selected,
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
        const _Gap(),
        if (c == null)
          Text(
            'Add a button or a stick. Bindings name them as <OnScreen>/id.',
            style: InputEditorTheme.bodyMuted,
          )
        else ...[
          _Field(
            'Id',
            EditorTextField(
              value: c.id,
              onCommit: (v) {
                final next = v.trim();
                if (next.isEmpty || s.asset.onScreenControl(next) != null) {
                  return;
                }
                s.edit(
                  'Rename on-screen control',
                  (a) => AssetEdits.updateOnScreen(
                    a,
                    id,
                    (x) => x.copyWith(id: next),
                  ),
                );
                s.select(OnScreenSelection(next));
              },
            ),
          ),
          Text('Bound as <OnScreen>/${c.id}', style: InputEditorTheme.label),
          const SizedBox(height: 8),
          if (c.kind == OnScreenKind.button)
            _Field(
              'Label',
              EditorTextField(
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
            _Field(
              'Where',
              SegmentedButton<StickMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: StickMode.fixed,
                    label: Text('Fixed', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: StickMode.floating,
                    label: Text(
                      'Under the thumb',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                selected: {c.stickMode},
                onSelectionChanged: (v) => update(
                  'Stick mode',
                  (x) => x.copyWith(stickMode: v.single),
                ),
              ),
            ),
            _Field(
              'Moves',
              SegmentedButton<StickAxis>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: StickAxis.both,
                    label: Text('Both', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: StickAxis.horizontal,
                    label: Text('Across', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: StickAxis.vertical,
                    label: Text('Up/down', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {c.stickAxis},
                onSelectionChanged: (v) => update(
                  'Stick axis',
                  (x) => x.copyWith(stickAxis: v.single),
                ),
              ),
            ),
            if (c.stickMode == StickMode.floating)
              Text(
                'Drag the shaded area in the Touch tab to set where it may appear.',
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
                color: InputEditorTheme.danger,
              ),
              label: Text(
                'Delete',
                style: TextStyle(color: InputEditorTheme.danger),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// --- Schemes ----------------------------------------------------------------------

class _SchemeProperties extends StatelessWidget {
  const _SchemeProperties({required this.session, required this.name});

  final InputEditorSession session;
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
                selectedColor: InputEditorTheme.selected,
                onSelected: (_) => s.select(SchemeSelection(other.name)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Scheme', style: TextStyle(fontSize: 11)),
              onPressed: () {
                final n = AssetEdits.uniqueName(
                  'Scheme',
                  s.asset.schemes.map((x) => x.name),
                );
                s.edit(
                  'Add scheme',
                  (a) => AssetEdits.addScheme(
                    a,
                    ControlSchemeDef(name: n, group: n),
                  ),
                );
                s.select(SchemeSelection(n));
              },
            ),
          ],
        ),
        const _Gap(),
        if (scheme == null)
          Text(
            'A scheme is a way of playing — keyboard and mouse, a gamepad, touch — and the bindings that go with it.',
            style: InputEditorTheme.bodyMuted,
          )
        else ...[
          _Field(
            'Name',
            EditorTextField(
              value: scheme.name,
              onCommit: (v) {
                final n = v.trim();
                if (n.isEmpty || s.asset.schemeNamed(n) != null) return;
                update('Rename scheme', (x) => x.copyWith(name: n));
                s.select(SchemeSelection(n));
              },
            ),
          ),
          _Field(
            'Group',
            EditorTextField(
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
          const _Gap(),
          Text('DEVICES', style: InputEditorTheme.heading),
          const SizedBox(height: 4),
          for (var i = 0; i < scheme.devices.length; i++)
            Row(
              children: [
                Icon(
                  InputEditorTheme.layoutIcon(scheme.devices[i].layout),
                  size: 15,
                  color: InputEditorTheme.textMuted,
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
                  activeColor: InputEditorTheme.accent,
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
                color: InputEditorTheme.danger,
              ),
              label: Text(
                'Delete scheme',
                style: TextStyle(color: InputEditorTheme.danger),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// --- Players and settings ------------------------------------------------------

class _SettingsProperties extends StatelessWidget {
  const _SettingsProperties({required this.session});

  final InputEditorSession session;

  /// The most players the editor offers: what the templates' games have
  /// room for, and what the README promises.
  static const int maxPlayers = 4;

  /// Each setting, its label, and the most it may be: a share of full
  /// travel goes no further than 1; a time has no top.
  static const _settingFields = [
    ('pressPoint', 'Press point', 1.0),
    ('releaseRatio', 'Release at', 1.0),
    ('holdTime', 'Hold time', double.infinity),
    ('tapTime', 'Tap time', double.infinity),
    ('slowTapTime', 'Slow tap', double.infinity),
    ('multiTapDelay', 'Multi-tap gap', double.infinity),
    ('stickDeadzoneMin', 'Stick dead min', 1.0),
    ('stickDeadzoneMax', 'Stick dead max', 1.0),
    ('axisDeadzoneMin', 'Axis dead min', 1.0),
    ('axisDeadzoneMax', 'Axis dead max', 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    final s = session;
    final players = s.asset.players;
    void setPlayers(String label, PlayerSettingsDef next) =>
        s.edit(label, (a) => a.copyWith(players: next));
    final actionPaths = [for (final ref in s.asset.actions) ref.path];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PLAYERS', style: InputEditorTheme.heading),
        const SizedBox(height: 6),
        _Field(
          'At most',
          Row(
            children: [
              EditorIconButton(
                icon: Icons.remove,
                tooltip: 'Fewer',
                onTap: players.maxPlayers <= 1
                    ? null
                    : () => setPlayers(
                        'Players',
                        players.copyWith(maxPlayers: players.maxPlayers - 1),
                      ),
              ),
              SizedBox(
                width: 30,
                child: Center(
                  child: Text(
                    '${players.maxPlayers}',
                    style: InputEditorTheme.body,
                  ),
                ),
              ),
              EditorIconButton(
                icon: Icons.add,
                tooltip: 'More',
                onTap: players.maxPlayers >= maxPlayers
                    ? null
                    : () => setPlayers(
                        'Players',
                        players.copyWith(maxPlayers: players.maxPlayers + 1),
                      ),
              ),
            ],
          ),
        ),
        _Toggle(
          'Players join by an action',
          players.joining == JoinBehavior.onJoinAction,
          (v) => setPlayers(
            'Joining',
            players.copyWith(
              joining: v ? JoinBehavior.onJoinAction : JoinBehavior.disabled,
            ),
          ),
          hint:
              'A device nobody uses joins as the next player when a join action is performed on it.',
        ),
        _Toggle(
          'Player 1 is whoever plays first',
          players.autoJoinFirst,
          (v) => setPlayers('Join first', players.copyWith(autoJoinFirst: v)),
        ),
        _Toggle(
          'Alone, switch devices on use',
          players.autoSwitch,
          (v) => setPlayers('Auto-switch', players.copyWith(autoSwitch: v)),
          hint:
              'With one player, a device nobody uses takes over the moment it is used — scheme and all.',
        ),
        if (players.joining == JoinBehavior.onJoinAction) ...[
          const SizedBox(height: 6),
          Text('JOIN ACTIONS', style: InputEditorTheme.heading),
          Text(
            'Give one a Hold, and a quick press on a free pad switches instead of joining.',
            style: InputEditorTheme.label,
          ),
          const SizedBox(height: 4),
          for (final path in actionPaths)
            _Toggle(path, players.joinActions.contains(path), (on) {
              final list = [
                for (final p in players.joinActions)
                  if (p != path) p,
                if (on) path,
              ];
              setPlayers('Join actions', players.copyWith(joinActions: list));
            }),
        ],
        const _Gap(),
        Text('SETTINGS', style: InputEditorTheme.heading),
        Text(
          'What interactions and dead zones fall back on.',
          style: InputEditorTheme.label,
        ),
        const SizedBox(height: 6),
        for (final (key, label, most) in _settingFields)
          _Field(
            label,
            EditorTextField(
              value: '${s.asset.settings.toJson()[key]}',
              onCommit: (text) {
                // NaN and Infinity parse, and no file can hold them.
                final n = double.tryParse(text.trim());
                if (n == null || !n.isFinite || n < 0 || n > most) {
                  s.say(
                    most.isFinite
                        ? '$label is a number from 0 to ${most.round()}.'
                        : '$label is a number of seconds, 0 or more.',
                  );
                  return;
                }
                final json = s.asset.settings.toJson()..[key] = n;
                s.edit(
                  label,
                  (a) => a.copyWith(settings: InputSettingsDef.fromJson(json)),
                );
              },
            ),
          ),
        const _Gap(),
        _Problems([
          for (final i in s.issues)
            if (i.mapId == null && i.actionId == null) i,
        ]),
      ],
    );
  }
}
