import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../look/input_editor_theme.dart';
import '../look/input_text_field.dart';
import 'property_rows.dart';

/// A list of interactions or processors: add from what is registered, take
/// away, and set each one's settings — an empty setting shows the asset's
/// own value it falls back on. What validation finds wrong with a step is
/// said on its card, and on the setting it is about.
@internal
class StepListEditor<T extends ParamDef> extends StatelessWidget {
  /// The [kind] steps [steps], called [title].
  const StepListEditor({
    super.key,
    required this.title,
    required this.kind,
    required this.steps,
    required this.available,
    required this.make,
    required this.onChanged,
    required this.onRefused,
    required this.settings,
    this.issues = const [],
    this.empty = '',
  });

  /// The list's name: `Interactions`.
  final String title;

  /// Whether these are interactions or processors.
  final StepKind kind;

  /// The steps, in order.
  final List<T> steps;

  /// What can be added.
  final List<StepInfo> available;

  /// A step of [type] with [params].
  final T Function(String type, Map<String, Object> params) make;

  /// Called with the list as changed.
  final ValueChanged<List<T>> onChanged;

  /// Called with why a change was refused.
  final ValueChanged<String> onRefused;

  /// The asset's settings, which unset steps' settings fall back on.
  final InputSettingsDef settings;

  /// What is wrong with the thing these steps belong to; the ones about
  /// this list ([AssetIssue.stepKind] is [kind]) are shown on their steps.
  final List<AssetIssue> issues;

  /// Said when there are none.
  final String empty;

  /// The interactions an action or a binding can have: every one
  /// registered.
  static List<StepInfo> get interactions => [...StepCatalog.interactions];

  /// The processors that work on an action of [type]: a vector's for a
  /// vector, the others for a button or an axis.
  static List<StepInfo> processorsFor(ActionValueType type) => [
    for (final p in InputProcessors.all)
      if (p.forVector == (type == ActionValueType.vector2)) p.info,
  ];

  /// Why [params] cannot be [info]'s settings, or null when they can: a
  /// range ([StepInfo.ranges]) whose min is not below its max, counting an
  /// unset end as its default, or the asset setting it falls back on — the
  /// check `validateAsset` makes.
  static String? rangeProblem(
    StepInfo info,
    Map<String, Object> params,
    InputSettingsDef settings,
  ) {
    double? effective(String name) {
      final value = params[name];
      if (value is num && value.isFinite) return value.toDouble();
      final p = info.param(name);
      final fallback = p?.defaultValue;
      if (fallback is num) return fallback.toDouble();
      final from = p?.fromSettings;
      return from == null ? null : settings.valueOf(from);
    }

    for (final (low, high) in info.ranges) {
      final a = effective(low), b = effective(high);
      if (a != null && b != null && a >= b) {
        final lowLabel = info.param(low)?.label ?? low;
        final highLabel = info.param(high)?.label ?? high;
        return '${info.label}: $lowLabel (${plainNumber(a)}) has to be below '
            '$highLabel (${plainNumber(b)}).';
      }
    }
    return null;
  }

  StepInfo? _registered(String type) => kind == StepKind.interaction
      ? StepCatalog.interaction(type)
      : StepCatalog.processor(type);

  /// What [type] is, and whether it is one this list can use.
  (StepInfo?, bool) _info(String type) {
    for (final i in available) {
      if (i.type == type) return (i, true);
    }
    return (_registered(type), false);
  }

  String _label(String type) {
    final (info, usable) = _info(type);
    if (info == null) return '$type (unknown)';
    if (usable) return info.label;
    // Registered, but for the other kind of action.
    final forVector = InputProcessors.entry(type)?.forVector ?? false;
    return '${info.label} (for ${forVector ? 'vectors' : 'buttons and axes'}: '
        'no effect here)';
  }

  void _set(int index, String param, Object? value) {
    final step = steps[index];
    final params = Map<String, Object>.of(step.params);
    if (value == null) {
      params.remove(param);
    } else {
      params[param] = value;
    }
    final info = _info(step.type).$1;
    final problem = info == null ? null : rangeProblem(info, params, settings);
    if (problem != null) {
      onRefused(problem);
      return;
    }
    onChanged([
      for (var i = 0; i < steps.length; i++)
        i == index ? make(step.type, params) : steps[i],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final mine = [
      for (final i in issues)
        if (i.stepKind == kind) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title.toUpperCase(), style: InputEditorTheme.heading),
            ),
            Builder(
              builder: (context) => EditorIconButton(
                icon: Icons.add,
                tooltip: 'Add ${title.toLowerCase()}',
                size: 22,
                onTap: available.isEmpty
                    ? null
                    : () async {
                        final type = await showEditorMenuBelow<String>(
                          context,
                          [
                            for (final i in available)
                              editorMenuItem(i.type, i.label, icon: Icons.add),
                          ],
                        );
                        if (type != null) {
                          onChanged([...steps, make(type, const {})]);
                        }
                      },
              ),
            ),
          ],
        ),
        if (steps.isEmpty && empty.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(empty, style: InputEditorTheme.label),
          ),
        for (var i = 0; i < steps.length; i++)
          _card(i, [
            for (final issue in mine)
              if (issue.stepIndex == i) issue,
          ]),
      ],
    );
  }

  Widget _card(int i, List<AssetIssue> issues) {
    final step = steps[i];
    final info = _info(step.type).$1;
    final error = issues.any((x) => x.isError);
    return Container(
      key: ValueKey('step:${kind.name}:$i'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 2, 6),
      decoration: BoxDecoration(
        color: EditorTheme.panelRaised,
        borderRadius: BorderRadius.circular(4),
        border: issues.isEmpty
            ? null
            : Border.all(
                color: error ? EditorTheme.error : EditorTheme.warning,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _label(step.type),
                  style: InputEditorTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              EditorIconButton(
                icon: Icons.close,
                tooltip: 'Remove',
                size: 20,
                onTap: () => onChanged([...steps]..removeAt(i)),
              ),
            ],
          ),
          if ((info?.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(info!.description, style: InputEditorTheme.label),
            ),
          // What is wrong with the step, not with one of its settings.
          for (final issue in issues)
            if (issue.param == null || info?.param(issue.param!) == null)
              IssueLine(issue),
          for (final p in info?.params ?? const <ParamInfo>[])
            ParamField(
              info: p,
              value: step.params[p.name],
              settings: settings,
              issues: [
                for (final issue in issues)
                  if (issue.param == p.name) issue,
              ],
              onChanged: (v) => _set(i, p.name, v),
            ),
        ],
      ),
    );
  }
}

/// One setting: a number, a switch, or a choice — and what validation finds
/// wrong with it.
@internal
class ParamField extends StatelessWidget {
  /// The field for [info], holding [value].
  const ParamField({
    super.key,
    required this.info,
    required this.value,
    required this.onChanged,
    required this.settings,
    this.issues = const [],
  });

  /// What the setting is.
  final ParamInfo info;

  /// What the asset holds; null when unset.
  final Object? value;

  /// Null clears it — back to the default.
  final ValueChanged<Object?> onChanged;

  /// The asset's settings, which an unset one may fall back on.
  final InputSettingsDef settings;

  /// What is wrong with this setting.
  final List<AssetIssue> issues;

  String get _fallback {
    final from = info.fromSettings;
    if (from != null) return '${settings.valueOf(from)} (asset)';
    return '${info.defaultValue ?? ''}';
  }

  /// [text] as this setting's number: null for anything that is not a
  /// finite number (NaN and Infinity parse, and no file can hold them),
  /// otherwise held within the setting's range.
  num? _number(String text) {
    final n = num.tryParse(text);
    if (n == null || !n.isFinite) return null;
    final (min, max) = (info.min, info.max);
    if (min != null && n < min) return min;
    if (max != null && n > max) return max;
    return n;
  }

  // A hand-edited file may hold any number, flag or text in any setting:
  // what does not fit the setting's kind shows as unset, or as itself.
  Widget _choice() {
    final choices = info.choices;
    final d = info.defaultValue;
    final fallback = d is String ? d : (choices.isEmpty ? null : choices.first);
    final current = value == null ? fallback : '$value';
    final known = current != null && choices.contains(current);
    return DropdownButton<String>(
      value: current,
      isDense: true,
      isExpanded: true,
      dropdownColor: EditorTheme.menuBg,
      style: InputEditorTheme.body,
      underline: const SizedBox.shrink(),
      items: [
        for (final c in choices) DropdownMenuItem(value: c, child: Text(c)),
        if (current != null && !known)
          DropdownMenuItem(
            value: current,
            child: Text(
              '$current (unknown)',
              style: TextStyle(color: EditorTheme.warning),
            ),
          ),
      ],
      onChanged: (v) => onChanged(v),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                info.label,
                style: issues.isEmpty
                    ? InputEditorTheme.bodyMuted
                    : InputEditorTheme.bodyMuted.copyWith(
                        color: issues.any((i) => i.isError)
                            ? EditorTheme.error
                            : EditorTheme.warning,
                      ),
              ),
            ),
            Expanded(
              child: switch (info.kind) {
                ParamKind.number => InputTextField(
                  value: value == null ? '' : '$value',
                  hint: _fallback,
                  onCommit: (text) {
                    final t = text.trim();
                    if (t.isEmpty) return onChanged(null);
                    final n = _number(t);
                    if (n != null) onChanged(n);
                  },
                ),
                ParamKind.flag => Align(
                  alignment: Alignment.centerLeft,
                  child: Checkbox(
                    value: switch ((value, info.defaultValue)) {
                      (final bool v, _) => v,
                      (_, final bool d) => d,
                      _ => false,
                    },
                    activeColor: EditorTheme.primaryBright,
                    checkColor: EditorTheme.dialogBg,
                    onChanged: (v) => onChanged(v),
                  ),
                ),
                ParamKind.choice => _choice(),
              },
            ),
          ],
        ),
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(left: 96, top: 2),
            child: IssueLine(i),
          ),
      ],
    ),
  );
}
