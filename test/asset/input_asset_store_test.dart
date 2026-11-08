// Where assets are read and written: a save reads back and leaves nothing
// beside the file, even when it fails; a file that is not an asset is a
// FormatException.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_input_editor/just_input_editor.dart';

import '../support/sample_asset.dart';

void main() {
  const path = 'assets/input/game.input.json';

  group('files', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('input_store');
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    test('a save reads back, and leaves nothing beside it', () async {
      final store = FileInputAssetStore(dir.path);
      expect(await store.exists(path), isFalse);
      await store.save(path, sampleAsset());
      expect(await store.exists(path), isTrue);
      expect((await store.load(path)).encode(), sampleAsset().encode());
      expect(File('${dir.path}/$path.saving').existsSync(), isFalse);
    });

    test('a save that fails leaves no half-made file beside it', () async {
      // The file's place is a folder: the swap cannot happen, as when
      // another program holds the file on Windows.
      await Directory('${dir.path}/$path').create(recursive: true);
      final store = FileInputAssetStore(dir.path);
      await expectLater(
        store.save(path, sampleAsset()),
        throwsA(isA<FileSystemException>()),
      );
      final left = Directory(
        '${dir.path}/assets/input',
      ).listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty));
      expect(left.map((s) => s.last), ['game.input.json']);
    });

    test('a file that is not an input asset says why', () async {
      final file = File('${dir.path}/$path');
      await file.create(recursive: true);
      final json = sampleAsset().toJson();
      ((json['maps'] as List).first as Map)['name'] = 3;
      await file.writeAsString(jsonEncode(json));
      await expectLater(
        FileInputAssetStore(dir.path).load(path),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('memory', () {
    test('the same, for tests', () async {
      final store = MemoryInputAssetStore();
      await store.save('a.input.json', sampleAsset());
      expect((await store.load('a.input.json')).name, 'sample');
      expect(store.load('b.input.json'), throwsA(isA<FileSystemException>()));
    });

    test('a value of the wrong kind is a FormatException', () async {
      final json = sampleAsset().toJson();
      ((json['maps'] as List).first as Map)['actions'][0]['type'] = 'vector';
      final store = MemoryInputAssetStore({'x.input.json': jsonEncode(json)});
      await expectLater(
        store.load('x.input.json'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
