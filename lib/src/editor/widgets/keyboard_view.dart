import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/input_editor_session.dart';
import 'editor_harness.dart';
import 'editor_theme.dart';
import 'view_support.dart';

/// A key on the drawn board: its control name and how wide it is, in keys.
/// An empty name is a gap.
typedef _Key = (String name, double width);

/// The board, row by row: a full-size layout without the number pad.
const List<List<_Key>> _mainRows = [
  [
    ('escape', 1),
    ('', 1),
    ('f1', 1),
    ('f2', 1),
    ('f3', 1),
    ('f4', 1),
    ('', 0.5),
    ('f5', 1),
    ('f6', 1),
    ('f7', 1),
    ('f8', 1),
    ('', 0.5),
    ('f9', 1),
    ('f10', 1),
    ('f11', 1),
    ('f12', 1),
  ],
  [
    ('backquote', 1),
    ('1', 1),
    ('2', 1),
    ('3', 1),
    ('4', 1),
    ('5', 1),
    ('6', 1),
    ('7', 1),
    ('8', 1),
    ('9', 1),
    ('0', 1),
    ('minus', 1),
    ('equals', 1),
    ('backspace', 2),
  ],
  [
    ('tab', 1.5),
    ('q', 1),
    ('w', 1),
    ('e', 1),
    ('r', 1),
    ('t', 1),
    ('y', 1),
    ('u', 1),
    ('i', 1),
    ('o', 1),
    ('p', 1),
    ('leftBracket', 1),
    ('rightBracket', 1),
    ('backslash', 1.5),
  ],
  [
    ('capsLock', 1.75),
    ('a', 1),
    ('s', 1),
    ('d', 1),
    ('f', 1),
    ('g', 1),
    ('h', 1),
    ('j', 1),
    ('k', 1),
    ('l', 1),
    ('semicolon', 1),
    ('quote', 1),
    ('enter', 2.25),
  ],
  [
    ('leftShift', 2.25),
    ('z', 1),
    ('x', 1),
    ('c', 1),
    ('v', 1),
    ('b', 1),
    ('n', 1),
    ('m', 1),
    ('comma', 1),
    ('period', 1),
    ('slash', 1),
    ('rightShift', 2.75),
  ],
  [
    ('leftCtrl', 1.25),
    ('leftMeta', 1.25),
    ('leftAlt', 1.25),
    ('space', 6.25),
    ('rightAlt', 1.25),
    ('rightMeta', 1.25),
    ('contextMenu', 1.25),
    ('rightCtrl', 1.25),
  ],
];

const List<List<_Key>> _navRows = [
  [('printScreen', 1), ('scrollLock', 1), ('pause', 1)],
  [('insert', 1), ('home', 1), ('pageUp', 1)],
  [('delete', 1), ('end', 1), ('pageDown', 1)],
  [('', 1), ('', 1), ('', 1)],
  [('', 1), ('upArrow', 1), ('', 1)],
  [('leftArrow', 1), ('downArrow', 1), ('rightArrow', 1)],
];

/// Short faces for keys whose names do not fit a key.
const Map<String, String> _short = {
  'printScreen': 'Print\nScreen',
  'scrollLock': 'Scroll\nLock',
  'pageUp': 'Page\nUp',
  'pageDown': 'Page\nDown',
  'leftMeta': 'Left\nMeta',
  'rightMeta': 'Right\nMeta',
  'leftCtrl': 'Left\nCtrl',
  'rightCtrl': 'Right\nCtrl',
  'leftAlt': 'Left\nAlt',
  'rightAlt': 'Right\nAlt',
  'capsLock': 'Caps\nLock',
};

/// The keyboard and the mouse, each key and button tinted by the action it
/// drives in the shown map — red-edged where two actions share it — and a
/// click binds it.
class KeyboardView extends StatelessWidget {
  const KeyboardView({super.key, required this.session, required this.harness});

  final InputEditorSession session;
  final EditorHarness harness;

  static const double _unit = 40;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final here = controlUses(
      s.asset,
      InputLayouts.keyboard,
      mapId: s.selectedMapId,
      group: s.schemeFilter,
    );
    final everywhere = controlUses(
      s.asset,
      InputLayouts.keyboard,
      group: s.schemeFilter,
    );
    // The either-side names light both sides.
    for (final either in ['shift', 'ctrl', 'alt', 'meta']) {
      for (final use in here[either] ?? const <ControlUse>[]) {
        for (final side in ['left', 'right']) {
          final key = '$side${either[0].toUpperCase()}${either.substring(1)}';
          (here[key] ??= []).add(use);
        }
      }
    }
    final picked = selectedControls(s, InputLayouts.keyboard);

    Widget key(_Key k) {
      final (name, width) = k;
      final w = width * _unit;
      if (name.isEmpty) return SizedBox(width: w, height: _unit);
      final info = KeyboardKeys.byName(name);
      final uses = here[name] ?? const <ControlUse>[];
      final label =
          _short[name] ??
          (info == null ? name : harness.service.keyboard.labelOf(info));
      return Padding(
        padding: const EdgeInsets.all(2),
        child: ControlCap(
          key: ValueKey('key:$name'),
          label: label,
          uses: uses,
          elsewhere: [
            for (final u in everywhere[name] ?? const <ControlUse>[])
              if (!uses.any((x) => x.bindingId == u.bindingId)) u,
          ],
          picked: picked.contains(name),
          width: w - 4,
          height: _unit - 4,
          fontSize: label.length > 3 ? 10 : 13,
          onTap: () =>
              bindFromPicture(s, '<Keyboard>/$name', InputLayouts.keyboard),
        ),
      );
    }

    Widget rows(List<List<_Key>> rows) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final k in row) key(k)],
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: FittedBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  rows(_mainRows),
                  const SizedBox(width: 16),
                  rows(_navRows),
                  const SizedBox(width: 28),
                  _MouseDrawing(session: s),
                ],
              ),
            ),
          ),
        ),
        ActionLegend(
          session: s,
          hint:
              'Select an action or binding, then click a key or mouse button to bind it.',
        ),
      ],
    );
  }
}

/// A zone of the drawn mouse: the control it binds, its box on a 150×240
/// mouse, its face, and how it is bound for a vector or a direction.
typedef _Zone = (String control, Rect box, String label);

const List<_Zone> _zones = [
  (MouseControls.leftButton, Rect.fromLTWH(4, 4, 54, 92), 'Left'),
  (MouseControls.rightButton, Rect.fromLTWH(92, 4, 54, 92), 'Right'),
  ('scroll/up', Rect.fromLTWH(62, 10, 26, 26), '▲'),
  (MouseControls.middleButton, Rect.fromLTWH(62, 38, 26, 22), 'Mid'),
  ('scroll/down', Rect.fromLTWH(62, 62, 26, 26), '▼'),
  (MouseControls.forwardButton, Rect.fromLTWH(4, 108, 26, 34), 'Fwd'),
  (MouseControls.backButton, Rect.fromLTWH(4, 146, 26, 34), 'Back'),
  (MouseControls.delta, Rect.fromLTWH(40, 112, 100, 110), 'Move'),
];

/// The mouse, in the keyboard's look: its buttons, its wheel, its movement.
class _MouseDrawing extends StatelessWidget {
  const _MouseDrawing({required this.session});

  final InputEditorSession session;

  /// What a click on [control] binds, given the selection: movement or the
  /// wheel whole for a vector, a direction of it for a part.
  String _pathFor(String control) {
    final wants = selectionWants(session);
    final base = control.startsWith('scroll/') ? MouseControls.scroll : control;
    if (base == MouseControls.delta || base == MouseControls.scroll) {
      if (wants.vector) return '<Mouse>/$base';
      if (wants.direction != null) return '<Mouse>/$base/${wants.direction}';
    }
    return '<Mouse>/$control';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final here = controlUses(
      s.asset,
      InputLayouts.mouse,
      mapId: s.selectedMapId,
      group: s.schemeFilter,
    );
    final everywhere = controlUses(
      s.asset,
      InputLayouts.mouse,
      group: s.schemeFilter,
    );
    final picked = selectedControls(s, InputLayouts.mouse);

    List<ControlUse> usesOf(
      Map<String, List<ControlUse>> uses,
      String control,
    ) => switch (control) {
      // The wheel's halves also light for the whole wheel.
      'scroll/up' ||
      'scroll/down' => [...?uses[control], ...?uses[MouseControls.scroll]],
      MouseControls.delta => usesUnder(uses, MouseControls.delta),
      _ => [...?uses[control]],
    };

    return SizedBox(
      width: 150,
      height: 240,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MouseBody())),
          for (final (control, box, label) in _zones)
            Positioned.fromRect(
              rect: box,
              child: Builder(
                builder: (context) {
                  final uses = usesOf(here, control);
                  return ControlCap(
                    key: ValueKey('mouse:$control'),
                    label: label,
                    uses: uses,
                    elsewhere: [
                      for (final u in usesOf(everywhere, control))
                        if (!uses.any((x) => x.bindingId == u.bindingId)) u,
                    ],
                    picked:
                        picked.contains(control) ||
                        (control == MouseControls.delta &&
                            picked.any((p) => p.startsWith('delta'))),
                    onTap: () => bindFromPicture(
                      s,
                      _pathFor(control),
                      InputLayouts.mouse,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The mouse's outline.
class _MouseBody extends CustomPainter {
  const _MouseBody();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(70),
      topRight: const Radius.circular(70),
      bottomLeft: const Radius.circular(60),
      bottomRight: const Radius.circular(60),
    );
    canvas
      ..drawRRect(body, Paint()..color = const Color(0xFF221D1D))
      ..drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = InputEditorTheme.border,
      );
  }

  @override
  bool shouldRepaint(_MouseBody old) => false;
}
