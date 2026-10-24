import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/asset_edits.dart';
import '../core/input_editor_session.dart';
import 'editor_theme.dart';
import 'view_support.dart';

/// A device to lay the on-screen controls out on.
enum TouchDevice {
  phone('Phone', 19.5 / 9),
  wide('Phone 16:9', 16 / 9),
  tablet('Tablet', 4 / 3);

  const TouchDevice(this.label, this.aspect);

  final String label;

  /// Long side over short.
  final double aspect;
}

/// The on-screen controls on a phone, in the keyboard's look: each coloured
/// by the action it drives in the shown map, red where two share it. With an
/// action or binding selected a click binds; otherwise it picks the control.
/// Drag one to move it, its corner to size it; a floating stick's shaded
/// area is where a thumb may put it. Placement is relative, so what fits
/// this phone fits every screen.
class TouchLayoutView extends StatefulWidget {
  const TouchLayoutView({super.key, required this.session});

  final InputEditorSession session;

  @override
  State<TouchLayoutView> createState() => _TouchLayoutViewState();
}

class _TouchLayoutViewState extends State<TouchLayoutView> {
  TouchDevice _device = TouchDevice.phone;
  bool _portrait = false;

  InputEditorSession get s => widget.session;

  void _update(
    String id,
    String label,
    OnScreenControlDef Function(OnScreenControlDef c) change,
  ) => s.edit(label, (a) => AssetEdits.updateOnScreen(a, id, change));

  /// A click on [c]: binds it when an action or binding is selected, else
  /// picks it to change it.
  void _tap(OnScreenControlDef c) {
    if (!canBindFromPicture(s)) {
      s.select(OnScreenSelection(c.id));
      return;
    }
    final wants = selectionWants(s);
    final path =
        c.kind == OnScreenKind.stick && !wants.vector && wants.direction != null
        ? '<OnScreen>/${c.id}/${wants.direction}'
        : '<OnScreen>/${c.id}';
    bindFromPicture(s, path, InputLayouts.onScreen);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _portrait ? 1 / _device.aspect : _device.aspect;
    final selected = switch (s.selection) {
      OnScreenSelection(:final id) => id,
      _ => null,
    };
    final here = controlUses(
      s.asset,
      InputLayouts.onScreen,
      mapId: s.selectedMapId,
      group: s.schemeFilter,
    );
    final everywhere = controlUses(
      s.asset,
      InputLayouts.onScreen,
      group: s.schemeFilter,
    );
    final picked = selectedControls(s, InputLayouts.onScreen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Row(
            children: [
              DropdownButton<TouchDevice>(
                value: _device,
                isDense: true,
                dropdownColor: InputEditorTheme.panelRaised,
                style: InputEditorTheme.body,
                underline: const SizedBox.shrink(),
                items: [
                  for (final d in TouchDevice.values)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (d) => setState(() => _device = d ?? _device),
              ),
              EditorIconButton(
                icon: _portrait
                    ? Icons.stay_current_portrait
                    : Icons.stay_current_landscape,
                tooltip: _portrait
                    ? 'Portrait — turn it'
                    : 'Landscape — turn it',
                onTap: () => setState(() => _portrait = !_portrait),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => s.select(
                  OnScreenSelection(
                    s.create(
                      'Add on-screen button',
                      (a) => AssetEdits.addOnScreen(a, OnScreenKind.button),
                    ),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Button'),
              ),
              TextButton.icon(
                onPressed: () => s.select(
                  OnScreenSelection(
                    s.create(
                      'Add on-screen stick',
                      (a) => AssetEdits.addOnScreen(a, OnScreenKind.stick),
                    ),
                  ),
                ),
                icon: const Icon(Icons.control_camera, size: 16),
                label: const Text('Stick'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: AspectRatio(
                aspectRatio: aspect,
                child: Container(
                  key: const ValueKey('touch-frame'),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A3440),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF55585E),
                      width: 6,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final size = box.biggest;
                        return Stack(
                          children: [
                            const Positioned.fill(
                              child: CustomPaint(painter: _Ground()),
                            ),
                            for (final c in s.asset.onScreen)
                              if (c.kind == OnScreenKind.stick &&
                                  c.stickMode == StickMode.floating)
                                _Region(
                                  control: c,
                                  size: size,
                                  selected: c.id == selected,
                                  session: s,
                                  onMove: (region) => _update(
                                    c.id,
                                    'Move stick area',
                                    (x) => x.copyWith(region: region),
                                  ),
                                ),
                            for (final c in s.asset.onScreen)
                              _Placed(
                                key: ValueKey('onscreen:${c.id}'),
                                control: c,
                                size: size,
                                selected: c.id == selected,
                                picked: picked.any(
                                  (p) => p == c.id || p.startsWith('${c.id}/'),
                                ),
                                uses: usesUnder(here, c.id),
                                elsewhere: [
                                  for (final u in usesUnder(everywhere, c.id))
                                    if (!usesUnder(
                                      here,
                                      c.id,
                                    ).any((x) => x.bindingId == u.bindingId))
                                      u,
                                ],
                                session: s,
                                onSelect: () =>
                                    s.select(OnScreenSelection(c.id)),
                                onTap: () => _tap(c),
                                onMove: (ax, ay) => _update(
                                  c.id,
                                  'Move control',
                                  (x) => x.copyWith(anchorX: ax, anchorY: ay),
                                ),
                                onSize: (v) => _update(
                                  c.id,
                                  'Resize control',
                                  (x) => x.copyWith(size: v),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ActionLegend(
          session: s,
          hint:
              'Select an action or binding, then click a control to bind it. Drag to move, a corner to size.',
        ),
      ],
    );
  }
}

/// A control where the game would draw it, coloured by its action, and
/// draggable.
class _Placed extends StatelessWidget {
  const _Placed({
    super.key,
    required this.control,
    required this.size,
    required this.selected,
    required this.session,
    required this.onSelect,
    required this.onTap,
    required this.onMove,
    required this.onSize,
    this.picked = false,
    this.uses = const [],
    this.elsewhere = const [],
  });

  final OnScreenControlDef control;
  final Size size;
  final bool selected;

  /// The selection is bound to it.
  final bool picked;

  /// Actions it drives in the map shown — they colour it — and elsewhere.
  final List<ControlUse> uses;
  final List<ControlUse> elsewhere;

  final InputEditorSession session;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final void Function(double anchorX, double anchorY) onMove;
  final ValueChanged<double> onSize;

  @override
  Widget build(BuildContext context) {
    final p = onScreenPlacement(control, size);
    final d = p.diameter;
    final shortest = math.min(size.width, size.height);
    // Coloured like a key: the action it drives; red where two share it.
    final actions = {for (final u in uses) u.actionId};
    final shared = actions.length > 1;
    final colour = actions.isEmpty
        ? Colors.white54
        : InputEditorTheme.actionColour(actions.first);
    final name = control.label.isEmpty ? control.id : control.label;
    final face = control.kind == OnScreenKind.button
        ? OnScreenButtonFace(label: name, color: colour)
        : CustomPaint(
            painter: OnScreenStickPainter(
              centre: Offset(d / 2, d / 2),
              radius: d / 2,
              knob: Offset.zero,
              color: colour.withValues(
                alpha: control.stickMode == StickMode.floating ? 0.6 : 1,
              ),
            ),
          );
    final outline = picked
        ? InputEditorTheme.text
        : shared
        ? InputEditorTheme.danger
        : selected
        ? InputEditorTheme.accent
        : null;
    return Positioned(
      left: p.center.dx - d / 2,
      top: p.center.dy - d / 2,
      width: d,
      height: d,
      child: Tooltip(
        message: [
          '<OnScreen>/${control.id}',
          for (final u in uses) '${u.actionName} (${u.mapName})',
          for (final u in elsewhere) '${u.actionName} (${u.mapName})',
        ].join('\n'),
        waitDuration: const Duration(milliseconds: 300),
        child: _Drag(
          session: session,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onStart: onSelect,
          onUpdate: (e) {
            // Read the latest position: each update moves from where the
            // last one left it.
            final now = session.asset.onScreenControl(control.id) ?? control;
            final at = onScreenPlacement(now, size).center + e.delta;
            onMove(
              (at.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
              (at.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: face),
              if (outline != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: outline, width: 2),
                      ),
                    ),
                  ),
                ),
              if (control.kind == OnScreenKind.stick)
                // A stick has no words of its own: say what it moves.
                Positioned(
                  left: -40,
                  right: -40,
                  bottom: -18,
                  child: IgnorePointer(
                    child: Text(
                      actions.isEmpty
                          ? control.id
                          : {for (final u in uses) u.actionName}.join(', '),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colour,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // The corner: drag to size.
              Positioned(
                right: -6,
                bottom: -6,
                width: 14,
                height: 14,
                child: _Drag(
                  session: session,
                  behavior: HitTestBehavior.opaque,
                  onUpdate: (e) {
                    final now =
                        session.asset.onScreenControl(control.id) ?? control;
                    final grown =
                        now.size * shortest + (e.delta.dx + e.delta.dy);
                    onSize((grown / shortest).clamp(0.05, 0.6));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? InputEditorTheme.accent
                          : InputEditorTheme.textMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a floating stick may appear, shaded; drag to move the area.
class _Region extends StatelessWidget {
  const _Region({
    required this.control,
    required this.size,
    required this.selected,
    required this.session,
    required this.onMove,
  });

  final OnScreenControlDef control;
  final Size size;
  final bool selected;
  final InputEditorSession session;
  final ValueChanged<List<double>> onMove;

  /// [region] as the screen can show it: inside it, left before right and
  /// top before bottom — whatever a hand-edited file says.
  static List<double> _within(List<double> region) {
    double at(int i) => (region.length > i ? region[i] : (i < 2 ? 0.0 : 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
    final (l, t, r, b) = (at(0), at(1), at(2), at(3));
    return [math.min(l, r), math.min(t, b), math.max(l, r), math.max(t, b)];
  }

  @override
  Widget build(BuildContext context) {
    final r = _within(control.region);
    return Positioned(
      left: r[0] * size.width,
      top: r[1] * size.height,
      width: (r[2] - r[0]) * size.width,
      height: (r[3] - r[1]) * size.height,
      child: _Drag(
        session: session,
        onUpdate: (e) {
          final now = _within(
            session.asset.onScreenControl(control.id)?.region ?? r,
          );
          final dx = e.delta.dx / size.width, dy = e.delta.dy / size.height;
          final w = now[2] - now[0], h = now[3] - now[1];
          final left = (now[0] + dx).clamp(0.0, 1 - w);
          final top = (now[1] + dy).clamp(0.0, 1 - h);
          onMove([left, top, left + w, top + h]);
        },
        child: Container(
          decoration: BoxDecoration(
            color: InputEditorTheme.accent.withValues(
              alpha: selected ? 0.14 : 0.07,
            ),
            border: Border.all(
              color: InputEditorTheme.accent.withValues(alpha: 0.4),
            ),
          ),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.all(4),
          child: Text(
            '${control.id} appears here',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ),
    );
  }
}

/// A drag that is one undo step: the session's gesture begins with it and
/// ends with it — or, when what is dragged goes away mid-drag (deleted,
/// undone), with this, since no end of the drag is ever reported then.
class _Drag extends StatefulWidget {
  const _Drag({
    required this.session,
    required this.onUpdate,
    required this.child,
    this.onStart,
    this.onTap,
    this.behavior,
  });

  final InputEditorSession session;
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback? onStart;
  final VoidCallback? onTap;
  final HitTestBehavior? behavior;
  final Widget child;

  @override
  State<_Drag> createState() => _DragState();
}

class _DragState extends State<_Drag> {
  bool _dragging = false;

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    widget.session.endGesture();
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      // Not while the tree is being taken down: the editor rebuilds on
      // what the session says.
      scheduleMicrotask(widget.session.endGesture);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: widget.behavior,
    onTap: widget.onTap,
    onPanStart: (_) {
      widget.onStart?.call();
      if (!_dragging) {
        _dragging = true;
        widget.session.beginGesture();
      }
    },
    onPanUpdate: widget.onUpdate,
    onPanEnd: (_) => _end(),
    onPanCancel: _end,
    child: widget.child,
  );
}

/// A hint of a level behind the controls.
class _Ground extends CustomPainter {
  const _Ground();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.78, size.width, size.height * 0.22),
      Paint()..color = const Color(0xFF3B4A2E),
    );
  }

  @override
  bool shouldRepaint(_Ground old) => false;
}
