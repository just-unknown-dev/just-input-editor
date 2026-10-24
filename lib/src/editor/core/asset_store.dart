import 'dart:io';

import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths;
import 'package:just_inputs/just_inputs.dart';

/// Where the editor reads and writes input assets.
abstract interface class InputAssetStore {
  /// Whether there is a file at [path] (project-relative).
  Future<bool> exists(String path);

  /// Throws [FormatException] for a file that is not an input asset.
  Future<InputActionAsset> load(String path);

  /// Writes [asset] to [path], making its folder if need be.
  Future<void> save(String path, InputActionAsset asset);
}

/// [text] read as an input asset, as [InputActionAsset.parse] reads it —
/// except that anything wrong with it is a [FormatException]: a field of
/// the wrong kind (`"name": 3`), a name no type has (`"type": "vector"`) or
/// a list too short, which the parser meets as a cast or a lookup failing.
InputActionAsset parseInputAsset(String text) {
  try {
    return InputActionAsset.parse(text);
  } on FormatException {
    rethrow;
  } on Object catch (e) {
    throw FormatException(
      'Something in it has the wrong kind of value: '
      '${e is ArgumentError ? e.message ?? e : e}',
    );
  }
}

/// Files under a project [root], paths project-relative with forward
/// slashes — `assets/input/game.input.json`.
final class FileInputAssetStore implements InputAssetStore {
  FileInputAssetStore(this.root);

  /// The project folder the paths are under.
  final String root;

  File _file(String path) => PackageAssetPaths.of(root).file(path);

  @override
  Future<bool> exists(String path) => _file(path).exists();

  @override
  Future<InputActionAsset> load(String path) async =>
      parseInputAsset(await _file(path).readAsString());

  /// Writes beside the file, then swaps it in: a save interrupted half way
  /// leaves the old file whole.
  @override
  Future<void> save(String path, InputActionAsset asset) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.saving');
    await temp.writeAsString(asset.encode(), flush: true);
    await temp.rename(file.path);
  }
}

/// Assets in memory — for tests, and for the editor run on its own.
final class MemoryInputAssetStore implements InputAssetStore {
  MemoryInputAssetStore([Map<String, String>? files]) : files = files ?? {};

  /// Path → file text.
  final Map<String, String> files;

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<InputActionAsset> load(String path) async {
    final text = files[path];
    if (text == null) throw FileSystemException('No such file', path);
    return parseInputAsset(text);
  }

  @override
  Future<void> save(String path, InputActionAsset asset) async =>
      files[path] = asset.encode();
}
