// The editor is the visual side of just_inputs: it reads the core through
// its public library only, so the core can change its insides freely. This
// walks every import the editor's library reaches. (That every file under
// lib/ is reached, or internal, is library_layout_test's.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Every file under lib/ reachable from [entry] by relative paths and
/// `package:just_input_editor/` ones, plus every `package:` URI met on the
/// way.
(Set<String>, Set<String>) reachable(String entry) {
  final seen = <String>{};
  final packages = <String>{};
  void visit(File file) {
    final path = file.absolute.uri.normalizePath().toFilePath();
    if (!seen.add(path)) return;
    for (final m in _directive.allMatches(file.readAsStringSync())) {
      final uri = m.group(1)!;
      File? next;
      if (uri.startsWith('package:just_input_editor/')) {
        next = File(
          'lib/${uri.substring('package:just_input_editor/'.length)}',
        );
      } else if (uri.startsWith('package:')) {
        packages.add(uri);
      } else if (!uri.contains(':')) {
        next = File.fromUri(file.absolute.uri.resolve(uri));
      }
      if (next != null && next.existsSync()) visit(next);
    }
  }

  visit(File(entry));
  return (seen, packages);
}

void main() {
  test('just_inputs is read through its public library only', () {
    final (_, packages) = reachable('lib/just_input_editor.dart');
    final inputs = packages.where((p) => p.startsWith('package:just_inputs/'));
    expect(inputs, isNotEmpty);
    expect(inputs.where((p) => p.contains('/src/')), isEmpty);
    expect(inputs.where((p) => p.endsWith('/testing.dart')), isEmpty);
  });
}
