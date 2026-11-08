import 'package:just_inputs/just_inputs.dart';

/// Interactions a game might register that the input system cannot run:
/// one whose machine throws when it is woken (every update), and one that
/// cannot be made at all (every load). Registered for a test, unregistered
/// after it.
abstract final class ThrowingSteps {
  /// How often the throwing machine was woken.
  static int ticks = 0;

  /// Registers `throwsOnUpdate` and `throwsOnLoad`.
  static void register() {
    ticks = 0;
    InputInteractions.register(
      InteractionEntry(
        const StepInfo('throwsOnUpdate', 'Throws on update', []),
        (def, settings) => _Throwing(),
      ),
    );
    InputInteractions.register(
      InteractionEntry(
        const StepInfo('throwsOnLoad', 'Throws on load', []),
        (def, settings) => throw StateError('cannot be made'),
      ),
    );
  }

  /// Takes them away again.
  static void unregister() {
    InputInteractions.unregister('throwsOnUpdate');
    InputInteractions.unregister('throwsOnLoad');
  }

  /// [asset] with its jump action (`a10`) given [type].
  static InputActionAsset _withJumpStep(InputActionAsset asset, String type) =>
      asset.copyWith(
        maps: [
          for (final m in asset.maps)
            m.copyWith(
              actions: [
                for (final a in m.actions)
                  a.id == 'a10'
                      ? a.copyWith(interactions: [InteractionDef(type)])
                      : a,
              ],
            ),
        ],
      );

  /// [asset] whose jump throws on every update.
  static InputActionAsset onUpdate(InputActionAsset asset) =>
      _withJumpStep(asset, 'throwsOnUpdate');

  /// [asset] whose jump cannot be loaded.
  static InputActionAsset onLoad(InputActionAsset asset) =>
      _withJumpStep(asset, 'throwsOnLoad');
}

final class _Throwing extends InteractionMachine {
  @override
  void onInput(
    double actuation,
    bool changed,
    double now,
    InteractionHost host,
  ) {}

  @override
  double? get deadline => 0;

  @override
  void onTime(double now, InteractionHost host) {
    ThrowingSteps.ticks++;
    throw StateError('this interaction throws');
  }
}
