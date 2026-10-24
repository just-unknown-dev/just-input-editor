import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import 'editor_theme.dart';

/// A list of interactions or processors: add from what is registered, take
/// away, and set each one's settings — an empty setting shows the asset's
/// own value it falls back on.
class StepListEditor<T extends ParamDef> extends StatelessWidget {
  const StepListEditor({
    super.key,
    required this.title,
    required this.steps,
    required this.available,
    required this.make,
    required this.onChanged,
    required this.settings,
    this.empty = '',
  });

  final String title;
  final List<T> steps;

  /// What can be added.
  final List<StepInfo> available;

  /// A step of [type] with [params].
  final T Function(String type, Map<String, Object> params) make;
  final ValueChanged<List<T>> onChanged;
  final InputSettingsDef settings;

  /// Said when there are none.
  final String empty;

  StepInfo? _info(String type) {
    for (final i in available) {
      if (i.type == type) return i;
    }
    return null;
  }

  void _set(int index, String param, Object? value) {
    final step = steps[index];
    final params = Map<String, Object>.of(step.params);
    if (value == null) {
      params.remove(param);
    } else {
      params[param] = value;
    }
    onChanged([
      for (var i = 0; i < steps.length; i++)
        i == index ? make(step.type, params) : steps[i],
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(
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
                      final box = context.findRenderObject()! as RenderBox;
                      final type = await showEditorMenu<String>(
                        context,
                        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                        [
                          for (final i in available)
                            editorMenuItem(i.type, Icons.add, i.label),
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
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 4, 2, 6),
          decoration: BoxDecoration(
            color: InputEditorTheme.panelRaised,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _info(steps[i].type)?.label ??
                          '${steps[i].type} (unknown)',
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
              if ((_info(steps[i].type)?.description ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _info(steps[i].type)!.description,
                    style: InputEditorTheme.label,
                  ),
                ),
              for (final p
                  in _info(steps[i].type)?.params ?? const <ParamInfo>[])
                ParamField(
                  info: p,
                  value: steps[i].params[p.name],
                  settings: settings,
                  onChanged: (v) => _set(i, p.name, v),
                ),
            ],
          ),
        ),
    ],
  );
}

/// One setting: a number, a switch, or a choice.
class ParamField extends StatelessWidget {
  const ParamField({
    super.key,
    required this.info,
    required this.value,
    required this.onChanged,
    required this.settings,
  });

  final ParamInfo info;
  final Object? value;

  /// Null clears it — back to the default.
  final ValueChanged<Object?> onChanged;
  final InputSettingsDef settings;

  String get _fallback {
    final from = info.fromSettings;
    if (from != null) return '${settings.toJson()[from]} (asset)';
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
      dropdownColor: InputEditorTheme.panelRaised,
      style: InputEditorTheme.body,
      underline: const SizedBox.shrink(),
      items: [
        for (final c in choices) DropdownMenuItem(value: c, child: Text(c)),
        if (current != null && !known)
          DropdownMenuItem(
            value: current,
            child: Text(
              '$current (unknown)',
              style: TextStyle(color: InputEditorTheme.warning),
            ),
          ),
      ],
      onChanged: (v) => onChanged(v),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(info.label, style: InputEditorTheme.bodyMuted),
        ),
        Expanded(
          child: switch (info.kind) {
            ParamKind.number => EditorTextField(
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
                activeColor: InputEditorTheme.accent,
                checkColor: InputEditorTheme.background,
                onChanged: (v) => onChanged(v),
              ),
            ),
            ParamKind.choice => _choice(),
          },
        ),
      ],
    ),
  );
}
