import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';
import '../look/input_editor_theme.dart';

/// Try it: the asset as it is now, running on the editor's own input — the
/// keyboard once the area below has been clicked, the mouse over it, every
/// pad. Each player's actions show their phase and value as they move;
/// holding Start on a second pad joins player 2, here as in the game.
///
/// An asset the input system cannot run stops it: what went wrong is shown
/// instead, and it starts again once the asset is changed.
@internal
class LiveTestView extends StatefulWidget {
  /// The live test of [session]'s asset, run on [harness].
  const LiveTestView({super.key, required this.session, required this.harness});

  /// The session whose asset it runs.
  final InputEditorSession session;

  /// What it runs on.
  final InputEditorHarness harness;

  @override
  State<LiveTestView> createState() => _LiveTestViewState();
}

class _LiveTestViewState extends State<LiveTestView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'LiveTest');
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.harness.isLive = true;
    _ticker = createTicker(_tick);
    _startIfRunning();
  }

  @override
  void didUpdateWidget(LiveTestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The editor builds this again on every change: a changed asset may
    // run again.
    _startIfRunning();
  }

  void _startIfRunning() {
    if (widget.harness.canRun && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final harness = widget.harness;
    if (!harness.canRun) {
      // It threw: not again every frame. Shown until the asset changes.
      _ticker.stop();
      if (mounted) setState(() {});
      return;
    }
    // The ticker's time, never the wall clock: holds and taps run on it.
    // Only how far it moved: a new ticker starts at zero again, and the
    // harness's clock goes on from where it was.
    final step = elapsed - _last;
    _last = elapsed;
    harness.advance(step.inMicroseconds / 1e6);
    if (mounted) setState(() {});
  }

  /// Keys go to the test only while the area has them; whatever was held
  /// when they went elsewhere is let go, as a game's window losing focus.
  void _focusChanged(bool focused) {
    if (!focused) widget.harness.service.releaseHeld();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    // Nothing stays held once the tab is closed.
    widget.harness
      ..isLive = false
      ..service.releaseHeld();
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
                    onFocusChange: _focusChanged,
                    // Every key, Escape and the editor's shortcuts too: a
                    // game binds them. A click anywhere else gives them back.
                    onKeyEvent: (node, event) {
                      service.handleKeyEvent(event);
                      return KeyEventResult.handled;
                    },
                    child: ListenableBuilder(
                      listenable: _focus,
                      builder: (context, _) => TapRegion(
                        onTapOutside: (_) {
                          if (_focus.hasFocus) _focus.unfocus();
                        },
                        child: Listener(
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
                              color: EditorTheme.surfaceDarker,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _focus.hasFocus
                                    ? EditorTheme.primaryBright
                                    : EditorTheme.borderStrong,
                                width: _focus.hasFocus ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              _focus.hasFocus
                                  ? 'Listening: keys, mouse and pads go to the test. Click outside to stop.'
                                  : 'Click here, then use the keyboard and mouse. Pads work any time.',
                              textAlign: TextAlign.center,
                              style: InputEditorTheme.bodyMuted,
                            ),
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
        VerticalDivider(width: 1, color: EditorTheme.borderStrong),
        Expanded(
          child: switch (widget.harness.runError ?? widget.harness.loadError) {
            final error? => _Stopped(error: error),
            null => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              children: [
                for (final (title, actions) in columns)
                  _PlayerColumn(title: title, actions: actions),
              ],
            ),
          },
        ),
      ],
    );
  }
}

/// What the live test says once the asset will not run.
class _Stopped extends StatelessWidget {
  const _Stopped({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('live-stopped'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 22, color: EditorTheme.error),
          const SizedBox(height: 8),
          Text(
            'The input system cannot run this asset, so the live test has '
            'stopped. It starts again once the asset changes.',
            textAlign: TextAlign.center,
            style: InputEditorTheme.body,
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: InputEditorTheme.label,
          ),
        ],
      ),
    ),
  );
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
      color: EditorTheme.menuBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: EditorTheme.borderStrong),
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
        Divider(height: 1, color: EditorTheme.borderStrong),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final map in actions.maps) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Text(
                    '${map.name}${map.isEnabled ? '' : '  (off)'}'
                        .toUpperCase(),
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

  static Color _phaseColor(InputActionPhase p) => switch (p) {
    InputActionPhase.performed => EditorTheme.success,
    InputActionPhase.started => EditorTheme.warning,
    InputActionPhase.canceled => EditorTheme.error,
    InputActionPhase.waiting => EditorTheme.textMuted,
    InputActionPhase.disabled => EditorTheme.borderStrong,
  };

  @override
  Widget build(BuildContext context) {
    final phase = action.phase;
    final device = action.activeDevice;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: action.wasPerformedThisFrame()
          ? EditorTheme.success.withValues(alpha: 0.12)
          : null,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _phaseColor(phase),
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
              color: EditorTheme.textMuted,
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
          color: action.isPressed ? EditorTheme.primaryBright : null,
          border: Border.all(color: EditorTheme.textMuted),
        ),
      ),
    ),
    ActionValueType.axis => Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: (action.readAxis().abs()).clamp(0.0, 1.0),
            backgroundColor: EditorTheme.surfaceDarker,
            color: EditorTheme.primaryBright,
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
            border: Border.all(color: EditorTheme.textMuted),
          ),
          child: Align(
            alignment: Alignment(
              action.readVector2().dx.clamp(-1, 1),
              action.readVector2().dy.clamp(-1, 1),
            ),
            child: Container(
              width: 6,
              height: 6,
              color: EditorTheme.primaryBright,
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
