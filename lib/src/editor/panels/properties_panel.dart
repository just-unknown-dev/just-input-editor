import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';
import '../look/panel_header.dart';
import 'action_properties.dart';
import 'binding_properties.dart';
import 'on_screen_properties.dart';
import 'property_rows.dart';
import 'scheme_properties.dart';
import 'settings_properties.dart';

/// Everything about what is selected, down the right.
@internal
class PropertiesPanel extends StatelessWidget {
  /// The panel for [session]'s selection.
  const PropertiesPanel({
    super.key,
    required this.session,
    required this.harness,
  });

  /// The session it edits.
  final InputEditorSession session;

  /// What Listen hears through.
  final InputEditorHarness harness;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final (title, body) = switch (s.selection) {
      NoSelection() => ('Properties', const PropertiesHelp()),
      ActionSelection(:final id) => (
        'Action',
        ActionProperties(session: s, id: id),
      ),
      BindingSelection(:final id) => switch (s.asset.findBinding(id)) {
        null => ('Properties', const PropertiesHelp()),
        BindingRef(part: final CompositePartDef _) => (
          'Composite part',
          PartProperties(session: s, harness: harness, id: id),
        ),
        BindingRef(binding: CompositeBindingDef()) => (
          'Composite',
          CompositeProperties(session: s, id: id),
        ),
        _ => (
          'Binding',
          ControlProperties(session: s, harness: harness, id: id),
        ),
      },
      OnScreenSelection(:final id) => (
        'On-screen controls',
        OnScreenProperties(session: s, id: id),
      ),
      SchemeSelection(:final name) => (
        'Control schemes',
        SchemeProperties(session: s, name: name),
      ),
      SettingsSelection() => (
        'Players & settings',
        SettingsProperties(session: s),
      ),
    };
    return Container(
      width: 340,
      color: EditorTheme.menuBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
