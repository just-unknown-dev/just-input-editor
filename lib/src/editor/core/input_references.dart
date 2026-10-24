import 'dart:convert';
import 'dart:io';

import 'package:just_inputs/just_inputs.dart';

/// The names an edit takes away from the game: what code and scenes that
/// ask for an action by its name, or by `map/action`, would stop finding.
final class InputReferenceQuery {
  const InputReferenceQuery({this.names = const {}, this.prefixes = const {}});

  /// What renaming, moving or deleting the action [actionId] takes away: its
  /// path, and its bare name.
  factory InputReferenceQuery.action(InputActionAsset asset, String actionId) {
    final ref = asset.actionById(actionId);
    if (ref == null) return const InputReferenceQuery();
    return InputReferenceQuery(names: {ref.action.name, ref.path});
  }

  /// What moving the action [actionId] to another map takes away: its path —
  /// and its bare name too when [renamed] (the other map had one like it).
  factory InputReferenceQuery.move(
    InputActionAsset asset,
    String actionId, {
    required bool renamed,
  }) {
    final ref = asset.actionById(actionId);
    if (ref == null) return const InputReferenceQuery();
    return InputReferenceQuery(names: {ref.path, if (renamed) ref.action.name});
  }

  /// What renaming the map [mapId] takes away: its name, and every
  /// `map/action` path in it. Bare action names still find their actions.
  factory InputReferenceQuery.mapRename(InputActionAsset asset, String mapId) {
    final map = asset.mapById(mapId);
    if (map == null) return const InputReferenceQuery();
    return InputReferenceQuery(names: {map.name}, prefixes: {'${map.name}/'});
  }

  /// What deleting the map [mapId] takes away: its name, its paths and the
  /// bare names of its actions.
  factory InputReferenceQuery.mapDelete(InputActionAsset asset, String mapId) {
    final map = asset.mapById(mapId);
    if (map == null) return const InputReferenceQuery();
    return InputReferenceQuery(
      names: {map.name, for (final a in map.actions) a.name},
      prefixes: {'${map.name}/'},
    );
  }

  /// Whole values: `jump`, `player/jump`.
  final Set<String> names;

  /// Beginnings of values: `player/`, for every action of a map.
  final Set<String> prefixes;

  bool get isEmpty => names.isEmpty && prefixes.isEmpty;

  /// Whether [value] names something this query takes away.
  bool matches(String value) =>
      names.contains(value) || prefixes.any(value.startsWith);

  /// Every name and prefix, for a quick look through a file's text before
  /// reading it properly.
  Iterable<String> get _needles => [...names, ...prefixes];
}

/// One place outside the input asset that names what an edit takes away.
final class InputReference {
  const InputReference(this.file, this.where, this.value);

  /// Project-relative, with forward slashes.
  final String file;

  /// Where in it: `Player · ThirdPersonController.jumpAction`, `line 12`.
  final String where;

  /// The name or path found there.
  final String value;

  @override
  String toString() => '$file — $where ("$value")';
}

/// Looks through a project for what names an action or a map.
abstract interface class InputReferenceFinder {
  /// The places that name what [query] takes away, at most [limit] of them.
  Future<List<InputReference>> find(InputReferenceQuery query, {int limit});
}

/// Looks through a project's files under [root]:
///
/// - JSON assets under [assetFolder] (scenes, prefabs, screens — every
///   `.json` but input assets): component fields called `action`,
///   `actions` or `…Action` holding the name — the way `SimpleMovement`'s
///   `action` and a kit's `jumpAction` are saved;
/// - Dart code under [codeFolder]: the name or path as a string literal,
///   the way a game keeps its action names (`static const jump = 'jump'`).
///
/// It cannot see code that builds a name, or code outside [codeFolder] —
/// a kit's own defaults — which is why the editor still says code may name
/// it.
final class FileInputReferenceFinder implements InputReferenceFinder {
  FileInputReferenceFinder(
    this.root, {
    this.assetFolder = 'assets',
    this.codeFolder = 'lib',
  });

  /// The project folder.
  final String root;

  /// Where the JSON assets are, under [root].
  final String assetFolder;

  /// Where the game's Dart code is, under [root].
  final String codeFolder;

  @override
  Future<List<InputReference>> find(
    InputReferenceQuery query, {
    int limit = 50,
  }) async {
    final out = <InputReference>[];
    if (query.isEmpty) return out;
    final base = root.replaceAll(r'\', '/');
    String relative(File f) {
      final p = f.path.replaceAll(r'\', '/');
      return p.startsWith('$base/') ? p.substring(base.length + 1) : p;
    }

    for (final file in await _files(assetFolder, '.json')) {
      if (out.length >= limit) break;
      final name = file.path.toLowerCase();
      if (name.endsWith('.${InputActionAsset.extension}')) continue;
      final text = await _read(file);
      if (text == null || !query._needles.any(text.contains)) continue;
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        continue;
      }
      _inJson(json, query, (where, value) {
        if (out.length < limit) {
          out.add(InputReference(relative(file), where, value));
        }
      });
    }

    for (final file in await _files(codeFolder, '.dart')) {
      if (out.length >= limit) break;
      final text = await _read(file);
      if (text == null || !query._needles.any(text.contains)) continue;
      final lines = const LineSplitter().convert(text);
      for (var i = 0; i < lines.length && out.length < limit; i++) {
        final value = _literalIn(lines[i], query);
        if (value != null) {
          out.add(InputReference(relative(file), 'line ${i + 1}', value));
        }
      }
    }
    return out;
  }

  Future<List<File>> _files(String folder, String ending) async {
    final dir = Directory('$root/$folder');
    if (!await dir.exists()) return const [];
    final files = <File>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith(ending)) files.add(e);
      }
    } on FileSystemException {
      // A folder that cannot be listed hides nothing worth stopping for.
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<String?> _read(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// Calls [found] for every field naming the query, with where it is: the
  /// entity and component when the field is in a scene's component.
  static void _inJson(
    Object? json,
    InputReferenceQuery query,
    void Function(String where, String value) found, {
    String? entity,
    String? component,
    String? key,
  }) {
    if (json is Map) {
      final name = json['name'];
      final type = json['type'];
      final e = name is String && json.containsKey('components')
          ? name
          : entity;
      final c = type is String && json['fields'] is Map ? type : component;
      for (final MapEntry(key: k, value: v) in json.entries) {
        _inJson(
          v,
          query,
          found,
          entity: e,
          component: c,
          key: k is String ? k : key,
        );
      }
    } else if (json is List) {
      for (final v in json) {
        _inJson(
          v,
          query,
          found,
          entity: entity,
          component: component,
          key: key,
        );
      }
    } else if (json is String && key != null && _namesAnAction(key)) {
      if (query.matches(json)) {
        final field = component == null ? key : '$component.$key';
        found(entity == null ? field : '$entity · $field', json);
      }
    }
  }

  /// Whether a field called [key] holds an action's name.
  static bool _namesAnAction(String key) =>
      key == 'action' || key == 'actions' || key.endsWith('Action');

  /// The name or path [line] has as a string literal, if any.
  static String? _literalIn(String line, InputReferenceQuery query) {
    for (final quote in const ["'", '"']) {
      for (final name in query.names) {
        if (line.contains('$quote$name$quote')) return name;
      }
      for (final prefix in query.prefixes) {
        final at = line.indexOf('$quote$prefix');
        if (at < 0) continue;
        final end = line.indexOf(quote, at + 1);
        return end < 0 ? prefix : line.substring(at + 1, end);
      }
    }
    return null;
  }
}
