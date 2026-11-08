import 'dart:convert';
import 'dart:io';

import 'package:just_inputs/just_inputs.dart';

/// The names an edit takes away from the game: what code and scenes that
/// ask for an action by its name, or by `map/action`, would stop finding.
final class InputReferenceQuery {
  /// A query for whole values [names] and beginnings [prefixes].
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

  /// Whether it takes nothing away: no name and no prefix.
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
  /// [value], found in [file] at [where].
  const InputReference(this.file, this.where, this.value);

  /// Project-relative, with forward slashes.
  final String file;

  /// Where in it: `Player · ThirdPersonControllerComponent.jumpAction`, `line 12`.
  final String where;

  /// The name or path found there.
  final String value;

  @override
  String toString() => '$file — $where ("$value")';
}

/// The fields of a component saved under [type] that hold input actions'
/// names — one, or a list of them — as the component's definition says:
/// the fields of the engine's input action kinds
/// (`InputDefinitions.isActionKind`). None for a type no definition reads.
///
/// The module's `InputEditorModule.actionFieldsOf` makes one from the
/// editor's definitions.
typedef InputActionFields = Set<String> Function(String type);

/// Looks through a project for what names an action or a map.
abstract interface class InputReferenceFinder {
  /// The places that name what [query] takes away, at most [limit] of them.
  Future<List<InputReference>> find(InputReferenceQuery query, {int limit});
}

/// Looks through a project's files under [root]:
///
/// - JSON assets under [assetFolder] (scenes, prefabs — every `.json` but
///   input assets): the component fields [actionFields] names, holding the
///   name or a list with it — the way `SimpleMovementComponent`'s `action`
///   and a kit's `jumpAction` are saved — and a prefab instance's changes
///   to such a field. A field is one because its definition says so, not
///   because of its name: a timeline trigger's `enterAction` holds what
///   the timeline does (`pause`), and is left alone;
/// - Dart code under [codeFolder]: the name or path as a string literal,
///   the way a game keeps its action names (`static const jump = 'jump'`).
///
/// It cannot see code that builds a name, or code outside [codeFolder] —
/// a kit's own defaults — which is why the editor still says code may name
/// it. A component no definition reads (its module not registered) is not
/// looked in: the game cannot load it either, and the editor's Problems
/// say so.
final class FileInputReferenceFinder implements InputReferenceFinder {
  /// A finder for the project at [root], looking in the fields
  /// [actionFields] names.
  FileInputReferenceFinder(
    this.root, {
    required this.actionFields,
    this.assetFolder = 'assets',
    this.codeFolder = 'lib',
  });

  /// The project folder.
  final String root;

  /// Which fields of each component hold input actions' names.
  final InputActionFields actionFields;

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
    // Asked once per component type for the whole search.
    final fieldsByType = <String, Set<String>>{};
    Set<String> fieldsOf(String type) =>
        fieldsByType[type] ??= actionFields(type);
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
      _inJson(json, query, fieldsOf, (where, value) {
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

  /// Calls [found] for every input action field naming the query, with
  /// where it is: the entity, when the component is one of an entity's, and
  /// the component and field.
  ///
  /// A component is a map with a `type` and `fields` (an entity's, or one
  /// a prefab instance adds); a prefab instance's change to one field is a
  /// map with a `component`, a `field` and its `value`.
  static void _inJson(
    Object? json,
    InputReferenceQuery query,
    InputActionFields actionFields,
    void Function(String where, String value) found, {
    String? entity,
  }) {
    if (json is List) {
      for (final v in json) {
        _inJson(v, query, actionFields, found, entity: entity);
      }
      return;
    }
    if (json is! Map) return;
    final name = json['name'];
    final e = name is String && json.containsKey('components') ? name : entity;
    void check(String component, String field, Object? value) {
      if (!actionFields(component).contains(field)) return;
      final where = e == null ? '$component.$field' : '$e · $component.$field';
      for (final v in value is List ? value : [value]) {
        if (v is String && query.matches(v)) found(where, v);
      }
    }

    final type = json['type'];
    final fields = json['fields'];
    if (type is String && fields is Map) {
      for (final MapEntry(key: k, value: v) in fields.entries) {
        if (k is String) check(type, k, v);
      }
    }
    final component = json['component'];
    final field = json['field'];
    if (component is String && field is String) {
      check(component, field, json['value']);
    }
    for (final v in json.values) {
      _inJson(v, query, actionFields, found, entity: e);
    }
  }

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
