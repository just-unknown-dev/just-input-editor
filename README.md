# Just Input Editor

The Input Actions editor: the visual side of
[`just_inputs`](../just_inputs), the input core `just_game_engine` runs on.

It edits a game's `.input.json` asset:
- maps, actions and bindings, with undo;
- binding a control by Pick, or by Listen (press the key or button);
- interactions and processors;
- control schemes and player settings (joining, up to four players);
- on-screen controls.

A keyboard, a gamepad and a phone show every binding and let you click to bind. A live test shows the actions as you press.

## In the engine editor

`InputEditorModule` puts the editor in `just_game_engine_editor` as a workspace. It adds three things:
- **A toolbar button**: the pad button on the play toolbar, right after the Sprite Studio brush, which opens the game's controls.
- **Asset actions**: "Edit input actions" on any `.input.json` in the Assets dock, and "New input actions" on folders under `assets/`.
- **Live apply**: saving the game's asset loads it into the running engine (`engine.input.loadAsset`), during Play or not.

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
  onSaved: (asset, path) => engine.input.loadAsset(asset),
);
```

## Never in a game

The whole package is design-time only. A game imports `just_inputs` (through `just_game_engine`), never this. Only the editor entry point (`lib/main_editor.dart` in the platformer template) imports it, so none of it reaches a release build.

The game's in-game input widgets stay in `just_inputs`, because they ship: `OnScreenControls`, and the rebinding UI (`RebindList`, `RebindButton`, `BindingLabel`).
