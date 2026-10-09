/// The Input Actions editor: maps, actions and bindings; schemes, players
/// and on-screen controls; a keyboard, a pad and a phone to see them on; and
/// a place to try them — the visual side of `just_inputs`.
///
/// [InputEditorModule] puts it in `just_game_engine_editor` as a workspace.
///
/// Design-time only, all of it. A game never imports this package: its
/// controls are a `.input.json` asset the engine's `just_inputs` runs.
library;

export 'src/editor/core/asset_edits.dart';
export 'src/editor/core/asset_store.dart';
export 'src/editor/core/input_editor_session.dart';
export 'src/editor/core/starter_asset.dart';
export 'src/editor/widgets/editor_harness.dart';
export 'src/editor/widgets/editor_theme.dart'
    show InputEditorPalette, InputEditorTheme;
export 'src/editor/widgets/input_editor.dart';
export 'src/input_editor_module.dart';
