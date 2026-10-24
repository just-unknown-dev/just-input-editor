import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'package:just_inputs/just_inputs.dart';

/// The editor's own input: a private [InputService] running the asset as
/// it is being edited, for Listen and for the live test. It never touches
/// the game's — trying a binding here does not move the player.
class EditorHarness extends ChangeNotifier {
  EditorHarness({GamepadSource? gamepads, this.keyboardHook}) {
    if (gamepads != null) {
      service.attachGamepads(gamepads);
      // After the service's own listeners: what they queued is caught up.
      _padEvents = [
        gamepads.stateChanges.listen((_) => _catchUp()),
        gamepads.connections.listen((_) => _catchUp()),
      ];
    }
    service.players.start();
  }

  /// The editor's own input service: its devices, the asset as edited, and
  /// the players of the live test.
  final InputService service = InputService();

  List<StreamSubscription<Object>> _padEvents = const [];
  bool _disposed = false;

  /// The harness's clock, in seconds: it only goes forward, whichever view
  /// moves it, so holds and taps never see time run backwards.
  double get time => _time;
  double _time = 0;

  /// Whether a view is moving the clock every frame (the live test). While
  /// none is, what devices send is still caught up at once, on the clock as
  /// it stands — or every pad's movements would pile up until one did.
  bool live = false;

  /// Moves the clock on by [seconds] and runs an update: the live test, each
  /// frame.
  void advance(double seconds) {
    if (seconds > 0) _time += seconds;
    service.update(_time);
  }

  bool _catchingUp = false;

  /// Replays what devices queued, soon, unless the live test is about to.
  void _catchUp() {
    if (_catchingUp || live || _disposed) return;
    _catchingUp = true;
    scheduleMicrotask(() {
      _catchingUp = false;
      if (!live && !_disposed) service.update(_time);
    });
  }

  /// How Listen takes keys before the editor's own shortcuts do. The real
  /// keyboard unless a test says otherwise.
  final KeyboardCaptureHook? keyboardHook;

  InputActionAsset? _asset;

  /// Runs [asset] from now on. What is held carries on.
  ///
  /// An asset the input system cannot run — a hand-edited setting of the
  /// wrong kind, which it meets as a failed cast — can still be edited (and
  /// put right): what went wrong is kept in [loadError], null once one
  /// runs. Listen and the live test may not work until then.
  void load(InputActionAsset asset) {
    if (identical(asset, _asset)) return;
    _asset = asset;
    try {
      service.loadAsset(asset);
      loadError = null;
    } on Object catch (e) {
      loadError = e;
    }
  }

  /// Why the last asset [load]ed does not run, or null.
  Object? loadError;

  RebindingOperation? _listening;
  String? _listeningFor;

  /// Whether [listen] is waiting for a control.
  bool get isListening => _listening != null;

  /// The binding Listen is waiting on, or null.
  String? get listeningFor => _listeningFor;

  /// Waits for the next control pressed — any device — to bind to
  /// [bindingId]. Null when given up (Escape, or [cancelListen]).
  Future<String?> listen(String bindingId) async {
    cancelListen();
    final op = RebindingOperation(
      service: service,
      target: service.actions,
      bindingId: bindingId,
      layouts: InputLayouts.all.toSet(),
      keyboardHook: keyboardHook,
    );
    _listening = op;
    _listeningFor = bindingId;
    notifyListeners();
    final result = await op.start();
    // The press that ended it took the hook away with it, so its release
    // never comes here: let go of the keyboard and the mouse now, or the
    // next Listen would take that key for one still held and not hear it.
    if (!_disposed) {
      service
        ..releaseKeyboard()
        ..handlePointerEvent(
          const PointerCancelEvent(kind: PointerDeviceKind.mouse),
        );
      _catchUp();
    }
    if (identical(_listening, op)) {
      _listening = null;
      _listeningFor = null;
      if (!_disposed) notifyListeners();
    }
    return result is RebindCompleted ? result.path : null;
  }

  /// Gives up [listen]: it completes with null.
  void cancelListen() => _listening?.cancel();

  /// A pointer event while Listen waits — how a mouse button is heard.
  void feedPointer(PointerEvent event) => _listening?.feedPointer(event);

  @override
  void dispose() {
    _disposed = true;
    cancelListen();
    for (final s in _padEvents) {
      s.cancel();
    }
    service.dispose();
    super.dispose();
  }
}
