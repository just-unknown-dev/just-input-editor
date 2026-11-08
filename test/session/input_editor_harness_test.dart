// The editor's own input service: an asset it cannot run stops it, once,
// rather than throwing every frame; the next asset gets its chance.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';

import '../support/sample_asset.dart';
import '../support/throwing_steps.dart';

void main() {
  setUp(ThrowingSteps.register);
  tearDown(ThrowingSteps.unregister);

  test('an update that throws stops it until the next asset', () {
    final harness = InputEditorHarness();
    addTearDown(harness.dispose);
    var heard = 0;
    harness.addListener(() => heard++);
    harness.load(ThrowingSteps.onUpdate(sampleAsset()));
    expect(harness.loadError, isNull);
    for (var i = 0; i < 3; i++) {
      harness.advance(0.1);
    }
    expect(harness.runError, isA<StateError>());
    expect(harness.canRun, isFalse);
    expect(ThrowingSteps.ticks, 1, reason: 'not again every frame');
    expect(heard, 1, reason: 'said once');

    harness.load(sampleAsset());
    expect(harness.runError, isNull);
    expect(harness.canRun, isTrue);
    harness.advance(0.1);
    expect(harness.time, greaterThan(0.3));
  });

  test('a load that throws is kept, and nothing updates on it', () {
    final harness = InputEditorHarness();
    addTearDown(harness.dispose);
    harness.load(ThrowingSteps.onLoad(sampleAsset()));
    expect(harness.loadError, isA<StateError>());
    expect(harness.canRun, isFalse);
    harness.advance(0.1);
    harness.load(sampleAsset());
    expect(harness.loadError, isNull);
  });

  test('the live flag is read as isLive', () {
    final harness = InputEditorHarness();
    addTearDown(harness.dispose);
    expect(harness.isLive, isFalse);
  });
}
