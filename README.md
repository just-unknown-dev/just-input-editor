# Just Input Editor

The Input Actions editor: the visual side of [`just_inputs`](https://pub.dev/packages/just_inputs), the input core `just_game_engine` runs on.

It edits a game's `.input.json` asset:
- maps, actions and bindings, with undo;
- binding a control by Pick, or by Listen (press the key or button);
- interactions and processors;
- control schemes and player settings (joining, up to four players);
- on-screen controls.

A keyboard, a gamepad and a phone show every binding and let you click to bind. A live test shows the actions as you press.

Names are checked as they are typed: an action or a map needs a name code can ask for (letters, digits and `_`), unique where it lives. Before an action or a map is renamed, moved or deleted, the project's scenes and the Dart code under `lib/` are searched for its name, and what would no longer find it is shown first.

## In the engine editor

`InputEditorModule` puts the editor in `just_game_engine_editor` as a workspace. It adds:
- **A toolbar button**: the pad button on the play toolbar, right after the Sprite Studio brush, which opens the game's controls.
- **Asset actions**: "Edit input actions" on any `.input.json` in the Assets dock, and "New input actions" on folders under `assets/`.
- **Live apply**: saving the game's asset loads it into the running engine (`engine.input.loadAsset`), during Play or not. During a play-test, a save that takes away an action the running game has (renamed, moved or deleted) is kept until you stop, because the game's code may still ask for it; the status line says so.
- **Files changed outside**: when the game's asset changes on disk through the editor (a tool, a file dropped in), the engine takes it up, and an open Input Actions window reads it again, or says saving will replace it when it has unsaved changes.

```dart
import 'package:just_input_editor/just_input_editor.dart';

await JustGameEditorPlugin.register(
  engine: engine,
  modules: [
    InputEditorModule(assetPath: 'assets/input/game.input.json'),
  ],
);
```

## On its own

`InputEditor` is an ordinary widget, so any host can put it in a window:

```dart
InputEditor(
  store: FileInputAssetStore(projectRoot),
  path: 'assets/input/game.input.json',
  // Optional: what names an action, asked before one is renamed or deleted.
  references: FileInputReferenceFinder(projectRoot),
  onSaved: (asset, path) {
    engine.input.loadAsset(asset);
    return null; // or a note, said after "Saved"
  },
);
```

## Never in a game

The whole package is design-time only. A game imports `just_inputs` (through `just_game_engine`), never this. Only the game's editor side imports it — in the platformer template, the Asset Store's generated `lib/editor/store_modules.g.dart`, which `lib/main_editor.dart` uses — so none of it reaches a release build.

The game's in-game input widgets stay in `just_inputs`, because they ship: `OnScreenControls`, and the rebinding UI (`RebindList`, `RebindButton`, `BindingLabel`).
