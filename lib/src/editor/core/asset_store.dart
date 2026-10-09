import 'dart:io';

import 'package:just_game_engine_editor/just_game_engine_editor.dart'
    show PackageAssetPaths;
import 'package:just_inputs/just_inputs.dart';

/// Where the editor reads and writes input assets.
abstract interface class InputAssetStore {
  Future<bool> exists(String path);

  /// Throws [FormatException] for a file that is not an input asset.
  Future<InputActionAsset> load(String path);

  Future<void> save(String path, InputActionAsset asset);
}

/// Files under a project [root], paths project-relative with forward
/// slashes — `assets/input/game.input.json`.
final class FileInputAssetStore implements InputAssetStore {
  FileInputAssetStore(this.root);

  final String root;

  File _file(String path) => PackageAssetPaths.of(root).file(path);

  @override
  Future<bool> exists(String path) => _file(path).exists();

  @override
  Future<InputActionAsset> load(String path) async =>
      InputActionAsset.parse(await _file(path).readAsString());

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
    return InputActionAsset.parse(text);
  }

  @override
  Future<void> save(String path, InputActionAsset asset) async =>
      files[path] = asset.encode();
}
