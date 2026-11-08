// A test's own folder under the system's temp folder, removed when the test
// ends — and the test fails, naming it, when it cannot be.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How long a removal is tried before the test fails.
const Duration _patience = Duration(seconds: 5);

/// A new folder under the system's temp folder, named from [prefix], and
/// removed when the test ends.
///
/// Synchronous, so a widget test can make one on its fake clock. On Windows
/// a file that is still open cannot be deleted, nor its folder: the removal
/// is tried again for a few seconds (a virus scanner holds a new file for a
/// moment), and the test fails when the folder is still there — a read the
/// code under test never finished, which would otherwise leave the folder
/// behind without a word.
Directory tempFolder(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => removeFolder(dir));
  return dir;
}

/// Deletes [dir] and everything in it, trying again while something holds
/// a file in it; throws the last [FileSystemException] after [_patience].
void removeFolder(Directory dir) {
  final clock = Stopwatch()..start();
  while (true) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (clock.elapsed > _patience) rethrow;
      sleep(const Duration(milliseconds: 50));
    }
  }
}
