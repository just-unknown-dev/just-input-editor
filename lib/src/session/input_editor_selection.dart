/// What is selected in the Input Actions editor.
sealed class InputEditorSelection {
  /// Subclasses are the kinds of selection; this is their common type.
  const InputEditorSelection();
}

/// Nothing: the Properties panel shows how to begin.
final class NoSelection extends InputEditorSelection {
  /// Nothing selected.
  const NoSelection();
}

/// An action, by id.
final class ActionSelection extends InputEditorSelection {
  /// The action [id] selected.
  const ActionSelection(this.id);

  /// The action's id.
  final String id;

  @override
  bool operator ==(Object other) => other is ActionSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A binding, or one part of a composite.
final class BindingSelection extends InputEditorSelection {
  /// The binding or part [id] selected.
  const BindingSelection(this.id);

  /// The binding's or the part's id.
  final String id;

  @override
  bool operator ==(Object other) => other is BindingSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// An on-screen control, by id.
final class OnScreenSelection extends InputEditorSelection {
  /// The on-screen control [id] selected.
  const OnScreenSelection(this.id);

  /// The control's id — what bindings name: `<OnScreen>/id`.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is OnScreenSelection && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A control scheme, by name.
final class SchemeSelection extends InputEditorSelection {
  /// The scheme called [name] selected.
  const SchemeSelection(this.name);

  /// The scheme's name.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SchemeSelection && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// The players and the asset-wide settings.
final class SettingsSelection extends InputEditorSelection {
  /// The players and settings selected.
  const SettingsSelection();
}
