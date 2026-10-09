import 'package:just_inputs/just_inputs.dart';

/// Every change the Input Actions editor makes, as pure functions: an asset
/// in, a new asset out. Nothing here knows about widgets or undo — which is
/// what lets each one be tested alone and every one be undone the same way.
abstract final class AssetEdits {
  /// [base], or `base2`, `base3`… — the first not in [taken].
  static String uniqueName(String base, Iterable<String> taken) {
    final used = taken.toSet();
    if (!used.contains(base)) return base;
    var i = 2;
    while (used.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  // --- Maps ------------------------------------------------------------------

  static (InputActionAsset, String) addMap(
    InputActionAsset a, {
    String name = 'map',
  }) {
    final (id, next) = a.takeId('m');
    final map = ActionMapDef(
      id: id,
      name: uniqueName(name, a.maps.map((m) => m.name)),
    );
    return (next.copyWith(maps: [...next.maps, map]), id);
  }

  static InputActionAsset renameMap(
    InputActionAsset a,
    String mapId,
    String name,
  ) {
    final map = a.mapById(mapId);
    if (map == null || map.name == name) return a;
    return _renameJoinPaths(
      _updateMap(a, mapId, (m) => m.copyWith(name: name)),
      (path) => path.startsWith('${map.name}/')
          ? '$name/${path.substring(map.name.length + 1)}'
          : path,
    );
  }

  static InputActionAsset setMapEnabled(
    InputActionAsset a,
    String mapId,
    bool enabled,
  ) => _updateMap(a, mapId, (m) => m.copyWith(enabled: enabled));

  static InputActionAsset deleteMap(InputActionAsset a, String mapId) {
    final map = a.mapById(mapId);
    if (map == null) return a;
    return _dropJoinPaths(
      a.copyWith(
        maps: [
          for (final m in a.maps)
            if (m.id != mapId) m,
        ],
      ),
      (path) => path.startsWith('${map.name}/'),
    );
  }

  static (InputActionAsset, String) duplicateMap(
    InputActionAsset a,
    String mapId,
  ) {
    final map = a.mapById(mapId);
    if (map == null) return (a, mapId);
    var (id, next) = a.takeId('m');
    final actions = <InputActionDef>[];
    for (final action in map.actions) {
      final (copy, after) = _freshAction(next, action);
      actions.add(copy);
      next = after;
    }
    final copy = ActionMapDef(
      id: id,
      name: uniqueName(map.name, a.maps.map((m) => m.name)),
      enabled: map.enabled,
      actions: actions,
    );
    final index = a.maps.indexWhere((m) => m.id == mapId);
    return (next.copyWith(maps: [...next.maps]..insert(index + 1, copy)), id);
  }

  static InputActionAsset moveMap(InputActionAsset a, String mapId, int index) {
    final maps = [...a.maps];
    final from = maps.indexWhere((m) => m.id == mapId);
    if (from < 0) return a;
    final map = maps.removeAt(from);
    maps.insert(index.clamp(0, maps.length), map);
    return a.copyWith(maps: maps);
  }

  // --- Actions ------------------------------------------------------------

  static (InputActionAsset, String) addAction(
    InputActionAsset a,
    String mapId, {
    String name = 'action',
    ActionValueType type = ActionValueType.button,
  }) {
    final map = a.mapById(mapId);
    if (map == null) return (a, '');
    final (id, next) = a.takeId('a');
    final action = InputActionDef(
      id: id,
      name: uniqueName(name, map.actions.map((x) => x.name)),
      type: type,
    );
    return (
      _updateMap(
        next,
        mapId,
        (m) => m.copyWith(actions: [...m.actions, action]),
      ),
      id,
    );
  }

  static InputActionAsset updateAction(
    InputActionAsset a,
    String actionId,
    InputActionDef Function(InputActionDef action) change,
  ) => a.copyWith(
    maps: [
      for (final m in a.maps)
        m.actions.any((x) => x.id == actionId)
            ? m.copyWith(
                actions: [
                  for (final x in m.actions) x.id == actionId ? change(x) : x,
                ],
              )
            : m,
    ],
  );

  static InputActionAsset renameAction(
    InputActionAsset a,
    String actionId,
    String name,
  ) {
    final ref = a.actionById(actionId);
    if (ref == null || ref.action.name == name) return a;
    final old = ref.path;
    return _renameJoinPaths(
      updateAction(a, actionId, (x) => x.copyWith(name: name)),
      (path) => path == old ? '${ref.map.name}/$name' : path,
    );
  }

  static InputActionAsset deleteAction(InputActionAsset a, String actionId) {
    final ref = a.actionById(actionId);
    if (ref == null) return a;
    final path = ref.path;
    return _dropJoinPaths(
      a.copyWith(
        maps: [
          for (final m in a.maps)
            m.copyWith(
              actions: [
                for (final x in m.actions)
                  if (x.id != actionId) x,
              ],
            ),
        ],
      ),
      (p) => p == path,
    );
  }

  static (InputActionAsset, String) duplicateAction(
    InputActionAsset a,
    String actionId,
  ) {
    final ref = a.actionById(actionId);
    if (ref == null) return (a, actionId);
    final (fresh, next) = _freshAction(a, ref.action);
    final copy = fresh.copyWith(
      name: uniqueName(ref.action.name, ref.map.actions.map((x) => x.name)),
    );
    final index = ref.map.actions.indexWhere((x) => x.id == actionId);
    return (
      _updateMap(
        next,
        ref.map.id,
        (m) => m.copyWith(actions: [...m.actions]..insert(index + 1, copy)),
      ),
      copy.id,
    );
  }

  /// Moves an action within its map, or into another at [index]. A name
  /// the other map already has gets a number.
  static InputActionAsset moveAction(
    InputActionAsset a,
    String actionId, {
    String? toMapId,
    required int index,
  }) {
    final ref = a.actionById(actionId);
    if (ref == null) return a;
    final target = a.mapById(toMapId ?? ref.map.id);
    if (target == null) return a;
    if (target.id == ref.map.id) {
      return _updateMap(a, target.id, (m) {
        final actions = [...m.actions];
        final from = actions.indexWhere((x) => x.id == actionId);
        final action = actions.removeAt(from);
        actions.insert(index.clamp(0, actions.length), action);
        return m.copyWith(actions: actions);
      });
    }
    final moved = ref.action.copyWith(
      name: uniqueName(ref.action.name, target.actions.map((x) => x.name)),
    );
    final oldPath = ref.path;
    final newPath = '${target.name}/${moved.name}';
    final without = deleteAction(a, actionId);
    final inserted = _updateMap(without, target.id, (m) {
      final actions = [...m.actions]
        ..insert(index.clamp(0, m.actions.length), moved);
      return m.copyWith(actions: actions);
    });
    // A join action that moved is still the join action.
    final wasJoin = a.players.joinActions.contains(oldPath);
    return wasJoin
        ? inserted.copyWith(
            players: inserted.players.copyWith(
              joinActions: [...inserted.players.joinActions, newPath],
            ),
          )
        : inserted;
  }

  /// Changes what the action reads out. Composites that make the wrong kind
  /// of value go; single controls stay, for validation to flag.
  static InputActionAsset changeActionType(
    InputActionAsset a,
    String actionId,
    ActionValueType type,
  ) => updateAction(a, actionId, (x) {
    if (x.type == type) return x;
    bool keeps(InputBindingDef b) => switch (b) {
      ControlBindingDef() => true,
      CompositeBindingDef(:final composite) => switch (composite) {
        CompositeKinds.vector2 => type == ActionValueType.vector2,
        CompositeKinds.axis1D => type != ActionValueType.vector2,
        CompositeKinds.oneModifier ||
        CompositeKinds.twoModifiers => type != ActionValueType.vector2,
        _ => true,
      },
    };
    return x.copyWith(
      type: type,
      bindings: [
        for (final b in x.bindings)
          if (keeps(b)) b,
      ],
    );
  });

  // --- Bindings -------------------------------------------------------------

  static (InputActionAsset, String) addBinding(
    InputActionAsset a,
    String actionId, {
    String path = '',
    List<String> groups = const [],
  }) {
    final (id, next) = a.takeId('b');
    final binding = ControlBindingDef(id: id, path: path, groups: groups);
    return (
      updateAction(
        next,
        actionId,
        (x) => x.copyWith(bindings: [...x.bindings, binding]),
      ),
      id,
    );
  }

  /// Adds a composite with one of each part it reads, unbound.
  static (InputActionAsset, String) addComposite(
    InputActionAsset a,
    String actionId,
    String composite, {
    String name = '',
    List<String> groups = const [],
    Map<String, String> paths = const {},
  }) {
    var (id, next) = a.takeId('b');
    final parts = <CompositePartDef>[];
    for (final part in CompositeKinds.parts[composite] ?? const <String>[]) {
      final (partId, after) = next.takeId('b');
      next = after;
      parts.add(
        CompositePartDef(id: partId, part: part, path: paths[part] ?? ''),
      );
    }
    final binding = CompositeBindingDef(
      id: id,
      composite: composite,
      name: name,
      groups: groups,
      parts: parts,
    );
    return (
      updateAction(
        next,
        actionId,
        (x) => x.copyWith(bindings: [...x.bindings, binding]),
      ),
      id,
    );
  }

  /// Another entry for [part] — a second key for "up".
  static (InputActionAsset, String) addPart(
    InputActionAsset a,
    String compositeId,
    String part, {
    String path = '',
  }) {
    final (id, next) = a.takeId('b');
    return (
      updateBinding(next, compositeId, (b) {
        if (b is! CompositeBindingDef) return b;
        final parts = [...b.parts];
        final last = parts.lastIndexWhere((p) => p.part == part);
        parts.insert(
          last < 0 ? parts.length : last + 1,
          CompositePartDef(id: id, part: part, path: path),
        );
        return b.copyWith(parts: parts);
      }),
      id,
    );
  }

  /// A binding, by its id — not a part; see [updatePart].
  static InputActionAsset updateBinding(
    InputActionAsset a,
    String bindingId,
    InputBindingDef Function(InputBindingDef binding) change,
  ) => _mapBindings(a, (b) => b.id == bindingId ? change(b) : b);

  static InputActionAsset updatePart(
    InputActionAsset a,
    String partId,
    CompositePartDef Function(CompositePartDef part) change,
  ) => _mapBindings(
    a,
    (b) => b is CompositeBindingDef && b.parts.any((p) => p.id == partId)
        ? b.copyWith(
            parts: [for (final p in b.parts) p.id == partId ? change(p) : p],
          )
        : b,
  );

  /// Binds [id] — a binding or a composite part — to [path].
  static InputActionAsset setPath(InputActionAsset a, String id, String path) {
    final ref = a.findBinding(id);
    if (ref == null) return a;
    if (ref.part != null) {
      return updatePart(a, id, (p) => p.copyWith(path: path));
    }
    return updateBinding(
      a,
      id,
      (b) => b is ControlBindingDef ? b.copyWith(path: path) : b,
    );
  }

  static InputActionAsset setGroups(
    InputActionAsset a,
    String bindingId,
    List<String> groups,
  ) => updateBinding(
    a,
    bindingId,
    (b) => switch (b) {
      ControlBindingDef() => b.copyWith(groups: groups),
      CompositeBindingDef() => b.copyWith(groups: groups),
    },
  );

  /// Removes a binding, or one part of a composite.
  static InputActionAsset deleteBinding(InputActionAsset a, String id) {
    final ref = a.findBinding(id);
    if (ref == null) return a;
    if (ref.part != null) {
      return updateBinding(
        a,
        ref.binding.id,
        (b) => (b as CompositeBindingDef).copyWith(
          parts: [
            for (final p in b.parts)
              if (p.id != id) p,
          ],
        ),
      );
    }
    return updateAction(
      a,
      ref.action.id,
      (x) => x.copyWith(
        bindings: [
          for (final b in x.bindings)
            if (b.id != id) b,
        ],
      ),
    );
  }

  static (InputActionAsset, String) duplicateBinding(
    InputActionAsset a,
    String bindingId,
  ) {
    final ref = a.findBinding(bindingId);
    if (ref == null || ref.part != null) return (a, bindingId);
    final (copy, next) = _freshBinding(a, ref.binding);
    final index = ref.action.bindings.indexWhere((b) => b.id == bindingId);
    return (
      updateAction(
        next,
        ref.action.id,
        (x) => x.copyWith(bindings: [...x.bindings]..insert(index + 1, copy)),
      ),
      copy.id,
    );
  }

  static InputActionAsset moveBinding(
    InputActionAsset a,
    String bindingId,
    int index,
  ) {
    final ref = a.findBinding(bindingId);
    if (ref == null || ref.part != null) return a;
    return updateAction(a, ref.action.id, (x) {
      final bindings = [...x.bindings];
      final from = bindings.indexWhere((b) => b.id == bindingId);
      final b = bindings.removeAt(from);
      bindings.insert(index.clamp(0, bindings.length), b);
      return x.copyWith(bindings: bindings);
    });
  }

  // --- Interactions and processors ---------------------------------------

  /// The interactions of an action, or of one binding.
  static InputActionAsset setInteractions(
    InputActionAsset a,
    String id,
    List<InteractionDef> list,
  ) {
    if (a.actionById(id) != null) {
      return updateAction(a, id, (x) => x.copyWith(interactions: list));
    }
    return updateBinding(
      a,
      id,
      (b) => switch (b) {
        ControlBindingDef() => b.copyWith(interactions: list),
        CompositeBindingDef() => b.copyWith(interactions: list),
      },
    );
  }

  /// The processors of an action, a binding, or a composite part.
  static InputActionAsset setProcessors(
    InputActionAsset a,
    String id,
    List<ProcessorDef> list,
  ) {
    if (a.actionById(id) != null) {
      return updateAction(a, id, (x) => x.copyWith(processors: list));
    }
    final ref = a.findBinding(id);
    if (ref == null) return a;
    if (ref.part != null) {
      return updatePart(a, id, (p) => p.copyWith(processors: list));
    }
    return updateBinding(
      a,
      id,
      (b) => switch (b) {
        ControlBindingDef() => b.copyWith(processors: list),
        CompositeBindingDef() => b.copyWith(processors: list),
      },
    );
  }

  // --- On-screen controls ---------------------------------------------------

  static (InputActionAsset, String) addOnScreen(
    InputActionAsset a,
    OnScreenKind kind,
  ) {
    final id = uniqueName(
      kind == OnScreenKind.button ? 'button' : 'stick',
      a.onScreen.map((c) => c.id),
    );
    final control = OnScreenControlDef(
      id: id,
      kind: kind,
      size: kind == OnScreenKind.button ? 0.16 : 0.28,
      label: kind == OnScreenKind.button ? id.toUpperCase() : '',
    );
    return (a.copyWith(onScreen: [...a.onScreen, control]), id);
  }

  /// Changes an on-screen control. A new id is followed by every binding
  /// that named the old one.
  static InputActionAsset updateOnScreen(
    InputActionAsset a,
    String id,
    OnScreenControlDef Function(OnScreenControlDef control) change,
  ) {
    final old = a.onScreenControl(id);
    if (old == null) return a;
    final next = change(old);
    var asset = a.copyWith(
      onScreen: [for (final c in a.onScreen) c.id == id ? next : c],
    );
    if (next.id != id) {
      asset = _rewritePaths(asset, (path) {
        final p = ControlPath.tryParse(path);
        if (p == null || p.layout != InputLayouts.onScreen || p.root != id) {
          return path;
        }
        return ControlPath(
          InputLayouts.onScreen,
          p.child == null ? next.id : '${next.id}/${p.child}',
        ).toString();
      });
    }
    return asset;
  }

  static InputActionAsset deleteOnScreen(InputActionAsset a, String id) =>
      a.copyWith(
        onScreen: [
          for (final c in a.onScreen)
            if (c.id != id) c,
        ],
      );

  // --- Schemes and settings -----------------------------------------------

  static InputActionAsset addScheme(
    InputActionAsset a,
    ControlSchemeDef scheme,
  ) => a.copyWith(schemes: [...a.schemes, scheme]);

  /// Changes a scheme. A new group is followed by every binding in the old.
  static InputActionAsset updateScheme(
    InputActionAsset a,
    String name,
    ControlSchemeDef Function(ControlSchemeDef scheme) change,
  ) {
    final old = a.schemeNamed(name);
    if (old == null) return a;
    final next = change(old);
    var asset = a.copyWith(
      schemes: [for (final s in a.schemes) s.name == name ? next : s],
    );
    if (next.group != old.group) {
      asset = _mapBindings(
        asset,
        (b) => b.groups.contains(old.group)
            ? _withGroups(b, [
                for (final g in b.groups) g == old.group ? next.group : g,
              ])
            : b,
      );
    }
    return asset;
  }

  /// Removes a scheme; its group leaves every binding that had it.
  static InputActionAsset deleteScheme(InputActionAsset a, String name) {
    final old = a.schemeNamed(name);
    if (old == null) return a;
    return _mapBindings(
      a.copyWith(
        schemes: [
          for (final s in a.schemes)
            if (s.name != name) s,
        ],
      ),
      (b) => b.groups.contains(old.group)
          ? _withGroups(b, [
              for (final g in b.groups)
                if (g != old.group) g,
            ])
          : b,
    );
  }

  // --- Plumbing -------------------------------------------------------------

  static InputActionAsset _updateMap(
    InputActionAsset a,
    String mapId,
    ActionMapDef Function(ActionMapDef map) change,
  ) =>
      a.copyWith(maps: [for (final m in a.maps) m.id == mapId ? change(m) : m]);

  static InputActionAsset _mapBindings(
    InputActionAsset a,
    InputBindingDef Function(InputBindingDef binding) change,
  ) => a.copyWith(
    maps: [
      for (final m in a.maps)
        m.copyWith(
          actions: [
            for (final x in m.actions)
              x.copyWith(bindings: [for (final b in x.bindings) change(b)]),
          ],
        ),
    ],
  );

  static InputBindingDef _withGroups(InputBindingDef b, List<String> groups) =>
      switch (b) {
        ControlBindingDef() => b.copyWith(groups: groups),
        CompositeBindingDef() => b.copyWith(groups: groups),
      };

  static InputActionAsset _rewritePaths(
    InputActionAsset a,
    String Function(String path) change,
  ) => _mapBindings(
    a,
    (b) => switch (b) {
      ControlBindingDef() => b.copyWith(path: change(b.path)),
      CompositeBindingDef() => b.copyWith(
        parts: [for (final p in b.parts) p.copyWith(path: change(p.path))],
      ),
    },
  );

  static InputActionAsset _renameJoinPaths(
    InputActionAsset a,
    String Function(String path) change,
  ) => a.copyWith(
    players: a.players.copyWith(
      joinActions: [for (final p in a.players.joinActions) change(p)],
    ),
  );

  static InputActionAsset _dropJoinPaths(
    InputActionAsset a,
    bool Function(String path) drop,
  ) => a.copyWith(
    players: a.players.copyWith(
      joinActions: [
        for (final p in a.players.joinActions)
          if (!drop(p)) p,
      ],
    ),
  );

  /// A copy of [action] with fresh ids all the way down.
  static (InputActionDef, InputActionAsset) _freshAction(
    InputActionAsset a,
    InputActionDef action,
  ) {
    var (id, next) = a.takeId('a');
    final bindings = <InputBindingDef>[];
    for (final b in action.bindings) {
      final (copy, after) = _freshBinding(next, b);
      bindings.add(copy);
      next = after;
    }
    return (
      InputActionDef(
        id: id,
        name: action.name,
        type: action.type,
        passThrough: action.passThrough,
        displayName: action.displayName,
        rebindable: action.rebindable,
        interactions: action.interactions,
        processors: action.processors,
        bindings: bindings,
      ),
      next,
    );
  }

  static (InputBindingDef, InputActionAsset) _freshBinding(
    InputActionAsset a,
    InputBindingDef b,
  ) {
    var (id, next) = a.takeId('b');
    switch (b) {
      case ControlBindingDef():
        return (
          ControlBindingDef(
            id: id,
            path: b.path,
            groups: b.groups,
            interactions: b.interactions,
            processors: b.processors,
          ),
          next,
        );
      case CompositeBindingDef():
        final parts = <CompositePartDef>[];
        for (final p in b.parts) {
          final (partId, after) = next.takeId('b');
          next = after;
          parts.add(
            CompositePartDef(
              id: partId,
              part: p.part,
              path: p.path,
              processors: p.processors,
            ),
          );
        }
        return (
          CompositeBindingDef(
            id: id,
            composite: b.composite,
            name: b.name,
            params: b.params,
            parts: parts,
            groups: b.groups,
            interactions: b.interactions,
            processors: b.processors,
          ),
          next,
        );
    }
  }
}
