import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'package:just_inputs/just_inputs.dart';

/// The editor's own input: a private [InputService] running the asset as
/// it is being edited, for Listen and for the live test. It never touches
/// the game's — trying a binding here does not move the player.
class EditorHarness extends ChangeNotifier {
  EditorHarness({GamepadSource? gamepads, this.keyboardHook}) {
    if (gamepads != null) service.attachGamepads(gamepads);
    service.players.start();
  }

  final InputService service = InputService();

  /// How Listen takes keys before the editor's own shortcuts do. The real
  /// keyboard unless a test says otherwise.
  final KeyboardCaptureHook? keyboardHook;

  InputActionAsset? _asset;

  /// Runs [asset] from now on. What is held carries on.
  void load(InputActionAsset asset) {
    if (identical(asset, _asset)) return;
    _asset = asset;
    service.loadAsset(asset);
  }

  RebindingOperation? _listening;
  String? _listeningFor;

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
    if (identical(_listening, op)) {
      _listening = null;
      _listeningFor = null;
      notifyListeners();
    }
    return result is RebindCompleted ? result.path : null;
  }

  void cancelListen() => _listening?.cancel();

  /// A pointer event while Listen waits — how a mouse button is heard.
  void feedPointer(PointerEvent event) => _listening?.feedPointer(event);

  @override
  void dispose() {
    cancelListen();
    service.dispose();
    super.dispose();
  }
}
