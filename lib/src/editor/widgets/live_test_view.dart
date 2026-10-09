import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/input_editor_session.dart';
import 'editor_harness.dart';
import 'editor_theme.dart';

/// Try it: the asset as it is now, running on the editor's own input — the
/// keyboard once the area below has been clicked, the mouse over it, every
/// pad. Each player's actions show their phase and value as they move;
/// holding Start on a second pad joins player 2, here as in the game.
class LiveTestView extends StatefulWidget {
  const LiveTestView({super.key, required this.session, required this.harness});

  final InputEditorSession session;
  final EditorHarness harness;

  @override
  State<LiveTestView> createState() => _LiveTestViewState();
}

class _LiveTestViewState extends State<LiveTestView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'LiveTest');

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    // The ticker's time, never the wall clock: holds and taps run on it.
    widget.harness.service.update(elapsed.inMicroseconds / 1e6);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    // Nothing stays held once the tab is closed.
    widget.harness.service.releaseKeyboard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.harness.service;
    final players = service.players.players;
    final columns = <(String, InputActions)>[
      if (players.isEmpty)
        ('Everyone — press something to play', service.actions),
      for (final p in players)
        (
          '${p.label} · ${p.scheme?.name ?? p.device?.displayName ?? ''}${p.isLost ? ' · lost' : ''}',
          p.actions,
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Focus(
                    focusNode: _focus,
                    onKeyEvent: (node, event) {
                      service.handleKeyEvent(event);
                      return KeyEventResult.handled;
                    },
                    child: ListenableBuilder(
                      listenable: _focus,
                      builder: (context, _) => Listener(
                        key: const ValueKey('live-area'),
                        onPointerDown: (e) {
                          _focus.requestFocus();
                          service.handlePointerEvent(e);
                        },
                        onPointerUp: service.handlePointerEvent,
                        onPointerMove: service.handlePointerEvent,
                        onPointerHover: service.handlePointerEvent,
                        onPointerSignal: service.handlePointerEvent,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: InputEditorTheme.field,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _focus.hasFocus
                                  ? InputEditorTheme.accent
                                  : InputEditorTheme.border,
                              width: _focus.hasFocus ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            _focus.hasFocus
                                ? 'Listening: keys, mouse and pads go to the test.'
                                : 'Click here, then use the keyboard and mouse. Pads work any time.',
                            textAlign: TextAlign.center,
                            style: InputEditorTheme.bodyMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    service.players
                      ..stop()
                      ..start();
                  },
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Everyone leaves'),
                ),
                const SizedBox(height: 4),
                Text(
                  '${service.gamepads.length} pad${service.gamepads.length == 1 ? '' : 's'} connected',
                  style: InputEditorTheme.label,
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: InputEditorTheme.border),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            children: [
              for (final (title, actions) in columns)
                _PlayerColumn(title: title, actions: actions),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({required this.title, required this.actions});

  final String title;
  final InputActions actions;

  @override
  Widget build(BuildContext context) => Container(
    width: 280,
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(
      color: InputEditorTheme.panel,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: InputEditorTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            title,
            style: InputEditorTheme.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Divider(height: 1, color: InputEditorTheme.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final map in actions.maps) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Text(
                    '${map.name}${map.enabled ? '' : '  (off)'}'.toUpperCase(),
                    style: InputEditorTheme.heading,
                  ),
                ),
                for (final a in map.actions) _ActionLine(action: a),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionLine extends StatelessWidget {
  const _ActionLine({required this.action});

  final InputAction action;

  static Color _phaseColour(InputActionPhase p) => switch (p) {
    InputActionPhase.performed => InputEditorTheme.ok,
    InputActionPhase.started => InputEditorTheme.warning,
    InputActionPhase.canceled => InputEditorTheme.danger,
    InputActionPhase.waiting => InputEditorTheme.textMuted,
    InputActionPhase.disabled => InputEditorTheme.border,
  };

  @override
  Widget build(BuildContext context) {
    final phase = action.phase;
    final device = action.activeDevice;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: action.wasPerformedThisFrame()
          ? InputEditorTheme.ok.withValues(alpha: 0.12)
          : null,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _phaseColour(phase),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text(
              action.name,
              style: InputEditorTheme.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 66,
            child: Text(phase.name, style: InputEditorTheme.label),
          ),
          Expanded(child: _Value(action: action)),
          if (device != null && phase != InputActionPhase.waiting)
            Icon(
              InputEditorTheme.layoutIcon(device.layout),
              size: 12,
              color: InputEditorTheme.textMuted,
            ),
        ],
      ),
    );
  }
}

/// A button lit, an axis as a bar, a vector as a dot in a square.
class _Value extends StatelessWidget {
  const _Value({required this.action});

  final InputAction action;

  @override
  Widget build(BuildContext context) => switch (action.type) {
    ActionValueType.button => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: action.isPressed() ? InputEditorTheme.accent : null,
          border: Border.all(color: InputEditorTheme.textMuted),
        ),
      ),
    ),
    ActionValueType.axis => Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: (action.readAxis().abs()).clamp(0.0, 1.0),
            backgroundColor: InputEditorTheme.field,
            color: InputEditorTheme.accent,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            action.readAxis().toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: InputEditorTheme.label,
          ),
        ),
      ],
    ),
    ActionValueType.vector2 => Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            border: Border.all(color: InputEditorTheme.textMuted),
          ),
          child: Align(
            alignment: Alignment(
              action.readVector2().dx.clamp(-1, 1),
              action.readVector2().dy.clamp(-1, 1),
            ),
            child: Container(
              width: 6,
              height: 6,
              color: InputEditorTheme.accent,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${action.readVector2().dx.toStringAsFixed(2)}, ${action.readVector2().dy.toStringAsFixed(2)}',
            overflow: TextOverflow.clip,
            maxLines: 1,
            style: InputEditorTheme.label,
          ),
        ),
      ],
    ),
  };
}
