import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import 'editor_theme.dart';

/// Every control a binding can name, by device, with a search — the way to
/// bind what cannot be pressed to Listen: Escape, a mouse wheel, the second
/// pad's stick before it is plugged in.
///
/// Completes with the path picked, or null.
Future<String?> pickControl(
  BuildContext context, {
  required List<OnScreenControlDef> onScreen,
  Set<ControlValueType>? wanted,
  String current = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: InputEditorTheme.panel,
    child: SizedBox(
      width: 520,
      height: 560,
      child: _ControlPicker(
        onScreen: onScreen,
        wanted: wanted,
        current: current,
      ),
    ),
  ),
);

class _ControlPicker extends StatefulWidget {
  const _ControlPicker({
    required this.onScreen,
    required this.wanted,
    required this.current,
  });

  final List<OnScreenControlDef> onScreen;
  final Set<ControlValueType>? wanted;
  final String current;

  @override
  State<_ControlPicker> createState() => _ControlPickerState();
}

class _ControlPickerState extends State<_ControlPicker> {
  String _query = '';
  late String _layout =
      ControlPath.tryParse(widget.current)?.layout ?? InputLayouts.keyboard;
  bool _all = false;

  bool _fits(ControlInfo c) {
    final wanted = widget.wanted;
    return _all || wanted == null || wanted.contains(c.type);
  }

  bool _found(ControlInfo c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.label.toLowerCase().contains(q) ||
        c.path.control.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final display = const BindingDisplay();
    final controls = [
      for (final top in ControlCatalog.forLayout(
        _layout,
        onScreen: widget.onScreen,
      ))
        for (final c in top.flattened)
          if (_fits(c) && _found(c)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Text(
                'Pick a control',
                style: TextStyle(color: InputEditorTheme.text, fontSize: 14),
              ),
              const Spacer(),
              if (widget.wanted != null)
                Row(
                  children: [
                    Text('Show all', style: InputEditorTheme.label),
                    Switch(
                      value: _all,
                      activeThumbColor: InputEditorTheme.accent,
                      onChanged: (v) => setState(() => _all = v),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: EditorTextField(
            value: _query,
            hint: 'Search: space, stick, trigger…',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            onCommit: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final layout in InputLayouts.all)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    avatar: Icon(InputEditorTheme.layoutIcon(layout), size: 14),
                    label: Text(layout, style: const TextStyle(fontSize: 11)),
                    selected: layout == _layout,
                    selectedColor: InputEditorTheme.selected,
                    onSelected: (_) => setState(() => _layout = layout),
                  ),
                ),
            ],
          ),
        ),
        Divider(color: InputEditorTheme.border),
        Expanded(
          child: controls.isEmpty
              ? Center(
                  child: Text(
                    _layout == InputLayouts.onScreen && widget.onScreen.isEmpty
                        ? 'This asset has no on-screen controls yet.'
                        : 'Nothing here fits.',
                    style: InputEditorTheme.bodyMuted,
                  ),
                )
              : ListView.builder(
                  itemCount: controls.length,
                  itemBuilder: (context, i) {
                    final c = controls[i];
                    final path = c.path.toString();
                    final current = path == widget.current;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(path),
                      child: Container(
                        height: 30,
                        padding: EdgeInsets.only(
                          left: 14.0 + (c.path.child == null ? 0 : 18),
                          right: 14,
                        ),
                        color: current ? InputEditorTheme.selected : null,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                display.control(path),
                                style: InputEditorTheme.body,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                c.label,
                                style: InputEditorTheme.bodyMuted,
                              ),
                            ),
                            Text(path, style: InputEditorTheme.label),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
