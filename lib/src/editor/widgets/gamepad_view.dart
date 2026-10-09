import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_gamepads/just_gamepads.dart' as gp;

import 'package:just_inputs/just_inputs.dart';
import '../core/input_editor_session.dart';
import 'editor_theme.dart';
import 'view_support.dart';

/// A spot on the drawn pad: the control, where its centre is on a 480×280
/// pad, its size, and whether it is round.
typedef _Spot = (String control, Offset at, Size size, bool round);

const List<_Spot> _spots = [
  (GamepadControls.leftTrigger, Offset(95, 22), Size(64, 24), false),
  (GamepadControls.rightTrigger, Offset(385, 22), Size(64, 24), false),
  (GamepadControls.leftShoulder, Offset(95, 52), Size(84, 22), false),
  (GamepadControls.rightShoulder, Offset(385, 52), Size(84, 22), false),
  (GamepadControls.select, Offset(205, 105), Size(38, 24), false),
  (GamepadControls.start, Offset(275, 105), Size(38, 24), false),
  (GamepadControls.leftStick, Offset(125, 115), Size(56, 56), true),
  (GamepadControls.rightStick, Offset(315, 190), Size(56, 56), true),
  ('dpad/up', Offset(165, 160), Size(26, 28), false),
  ('dpad/down', Offset(165, 216), Size(26, 28), false),
  ('dpad/left', Offset(137, 188), Size(28, 26), false),
  ('dpad/right', Offset(193, 188), Size(28, 26), false),
  (GamepadControls.buttonNorth, Offset(370, 86), Size(34, 34), true),
  (GamepadControls.buttonSouth, Offset(370, 150), Size(34, 34), true),
  (GamepadControls.buttonWest, Offset(338, 118), Size(34, 34), true),
  (GamepadControls.buttonEast, Offset(402, 118), Size(34, 34), true),
];

/// The whole picture: the pad in the middle, labels either side.
const Size _canvas = Size(1000, 300);
const Offset _pad = Offset(260, 10);
const double _labelWidth = 210;
const double _labelGap = 24;

/// A gamepad in the keyboard's look — each control tinted by the action it
/// drives in the shown map, in the glyphs of the chosen brand — with every
/// bound control's action named beside the pad on a line to it. A click
/// binds.
class GamepadView extends StatefulWidget {
  const GamepadView({super.key, required this.session});

  final InputEditorSession session;

  @override
  State<GamepadView> createState() => _GamepadViewState();
}

/// One callout: from a control on the pad to its label at the side.
final class _Callout {
  _Callout(
    this.control,
    this.from,
    this.left,
    this.text,
    this.colour,
    this.shared,
  );

  final String control;

  /// The edge of the control the line leaves from, on the canvas.
  final Offset from;
  final bool left;
  final String text;
  final Color colour;
  final bool shared;

  /// Where the label sits, once laid out without overlaps.
  double y = 0;
}

class _GamepadViewState extends State<GamepadView> {
  gp.GamepadType _brand = gp.GamepadType.xbox;

  InputEditorSession get s => widget.session;

  /// What a click on [control] binds: a whole stick or d-pad for a vector,
  /// a direction for a composite's part, else the stick's press.
  String _pathFor(String control) {
    final wants = selectionWants(s);
    if (control == GamepadControls.leftStick ||
        control == GamepadControls.rightStick) {
      if (wants.vector) return '<Gamepad>/$control';
      if (wants.direction != null) {
        return '<Gamepad>/$control/${wants.direction}';
      }
      return '<Gamepad>/${control}Press';
    }
    if (control.startsWith('dpad/') && wants.vector) return '<Gamepad>/dpad';
    return '<Gamepad>/$control';
  }

  /// Uses of [control] as drawn: a stick is also its press, a d-pad
  /// direction is also the whole d-pad.
  List<ControlUse> _usesOf(
    Map<String, List<ControlUse>> uses,
    String control,
  ) => [
    ...usesUnder(uses, control),
    ...?uses['${control}Press'],
    if (control.startsWith('dpad/')) ...?uses[GamepadControls.dpad],
  ];

  String _glyph(String control) => GamepadGlyphs.label(_brand, control)
      .replaceAll('Left Stick', 'L')
      .replaceAll('Right Stick', 'R')
      .replaceAll('D-Pad ', '');

  /// Callouts for every bound control, labels stacked down each side so
  /// none overlaps the next.
  List<_Callout> _callouts(Map<String, List<ControlUse>> here) {
    final out = <_Callout>[];
    for (final (control, at, size, _) in _spots) {
      final uses = _usesOf(here, control);
      if (uses.isEmpty) continue;
      final names = <String>{for (final u in uses) u.actionName};
      final actions = {for (final u in uses) u.actionId};
      final left = at.dx < 240;
      final centre = _pad + at;
      out.add(
        _Callout(
          control,
          Offset(
            centre.dx + (left ? -size.width / 2 : size.width / 2),
            centre.dy,
          ),
          left,
          '${_glyph(control)}  ${names.join(', ')}',
          InputEditorTheme.actionColour(actions.first),
          actions.length > 1,
        ),
      );
    }
    for (final side in [true, false]) {
      final column = out.where((c) => c.left == side).toList()
        ..sort((a, b) => a.from.dy.compareTo(b.from.dy));
      var next = 12.0;
      for (final c in column) {
        c.y = math.max(c.from.dy, next);
        next = c.y + _labelGap;
      }
      // Pushed off the bottom: pull the column back up.
      final overflow = next - _labelGap - (_canvas.height - 16);
      if (overflow > 0) {
        for (final c in column) {
          c.y -= overflow;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final here = controlUses(
      s.asset,
      InputLayouts.gamepad,
      mapId: s.selectedMapId,
      group: s.schemeFilter,
    );
    final everywhere = controlUses(
      s.asset,
      InputLayouts.gamepad,
      group: s.schemeFilter,
    );
    final picked = selectedControls(s, InputLayouts.gamepad);
    final callouts = _callouts(here);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Row(
            children: [
              Text('Show as', style: InputEditorTheme.label),
              const SizedBox(width: 8),
              SegmentedButton<gp.GamepadType>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: gp.GamepadType.xbox,
                    label: Text('Xbox', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: gp.GamepadType.playStation,
                    label: Text('PlayStation', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: gp.GamepadType.nintendoSwitchPro,
                    label: Text('Switch Pro', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_brand},
                onSelectionChanged: (v) => setState(() => _brand = v.single),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              child: SizedBox.fromSize(
                size: _canvas,
                child: Stack(
                  children: [
                    Positioned(
                      left: _pad.dx,
                      top: _pad.dy,
                      width: 480,
                      height: 280,
                      child: const CustomPaint(painter: _PadBody()),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _Leaders(callouts)),
                    ),
                    for (final (control, at, size, round) in _spots)
                      Positioned(
                        left: _pad.dx + at.dx - size.width / 2,
                        top: _pad.dy + at.dy - size.height / 2,
                        width: size.width,
                        height: size.height,
                        child: Builder(
                          builder: (context) {
                            final uses = _usesOf(here, control);
                            return ControlCap(
                              key: ValueKey('pad:$control'),
                              label: _glyph(control),
                              uses: uses,
                              elsewhere: [
                                for (final u in _usesOf(everywhere, control))
                                  if (!uses.any(
                                    (x) => x.bindingId == u.bindingId,
                                  ))
                                    u,
                              ],
                              round: round,
                              picked:
                                  picked.contains(control) ||
                                  picked.contains('${control}Press') ||
                                  picked.any(
                                    (p) => p.startsWith('$control/'),
                                  ) ||
                                  (control.startsWith('dpad/') &&
                                      picked.contains(GamepadControls.dpad)),
                              onTap: () => bindFromPicture(
                                s,
                                _pathFor(control),
                                InputLayouts.gamepad,
                              ),
                            );
                          },
                        ),
                      ),
                    for (final c in callouts)
                      Positioned(
                        key: ValueKey('callout:${c.control}'),
                        left: c.left
                            ? _pad.dx - _labelWidth - 30
                            : _pad.dx + 480 + 30,
                        top: c.y - 10,
                        width: _labelWidth,
                        height: 20,
                        child: Align(
                          alignment: c.left
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Text(
                            c.shared ? '${c.text}  ⚠' : c.text,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.shared
                                  ? InputEditorTheme.danger
                                  : c.colour,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ActionLegend(
          session: s,
          hint: 'Select an action or binding, then click a control to bind it.',
        ),
      ],
    );
  }
}

/// The lines from each control out to its label.
class _Leaders extends CustomPainter {
  _Leaders(this.callouts);

  final List<_Callout> callouts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in callouts) {
      final paint = Paint()
        ..color = (c.shared ? InputEditorTheme.danger : c.colour).withValues(
          alpha: 0.75,
        )
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      // Out from the pad's edge, then along to the label.
      final edgeX = c.left ? _pad.dx - 20 : _pad.dx + 480 + 20;
      final path = Path()
        ..moveTo(c.from.dx, c.from.dy)
        ..lineTo(
          c.left
              ? math.min(c.from.dx - 12, edgeX + 30)
              : math.max(c.from.dx + 12, edgeX - 30),
          c.y,
        )
        ..lineTo(edgeX, c.y);
      canvas
        ..drawPath(path, paint)
        ..drawCircle(c.from, 3, Paint()..color = paint.color);
    }
  }

  @override
  bool shouldRepaint(_Leaders old) => true;
}

/// The pad's outline: a body with two grips.
class _PadBody extends CustomPainter {
  const _PadBody();

  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(40, 60, 400, 150),
          const Radius.circular(70),
        ),
      )
      ..addOval(const Rect.fromLTWH(50, 120, 150, 150))
      ..addOval(const Rect.fromLTWH(280, 120, 150, 150));
    canvas
      ..drawPath(body, Paint()..color = const Color(0xFF221D1D))
      ..drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = InputEditorTheme.border,
      );
  }

  @override
  bool shouldRepaint(_PadBody old) => false;
}
