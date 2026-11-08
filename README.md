# Just Input Editor

The Input Actions editor: the visual side of [`just_inputs`](https://pub.dev/packages/just_inputs), the input core `just_game_engine` runs on.

It edits a game's `.input.json` asset:
- maps, actions and bindings, with undo;
- binding a control by Pick, or by Listen (press the key or button);
- interactions and processors;
- control schemes and player settings (joining, up to four players);
- on-screen controls.

A keyboard, a gamepad and a phone show every binding and let you click to bind. A live test shows the actions as you press.

Names are checked when they are kept (Enter, or leaving the field): an action, a map or an on-screen control needs a name code can ask for (letters, digits and `_`, the rule `just_inputs` checks), unique where it lives. Numbers are kept within what the input system can run: a press point above 0, a dead zone's min below its max, a clamp's too. What `validateAsset` finds wrong is shown where it is edited — on the step, on the setting. Before an action or a map is renamed, moved or deleted, the project's scenes and the Dart code under `lib/` are searched for its name, and what would no longer find it is shown first. In a scene, the fields searched are those whose component definitions make them input actions (`InputDefinitions.actionType`, or `actionListType` for several), whatever they are called: a timeline trigger's `exitAction` holds what the timeline does, not an input action, and is left alone. A kit's or a game's own component marks its action fields the same way, and the editor's inspector then offers the project's actions for them.

## In the engine editor

`InputEditorModule` puts the editor in `just_game_engine_editor` as a workspace, drawn in the editor's own theme, accent and accessibility settings. It adds:
- **A toolbar button**: the pad button on the play toolbar, right after the Sprite Studio brush, which opens the game's controls.
- **Asset actions**: "Edit input actions" on any `.input.json` in the Assets dock, and "New input actions" on folders under `assets/`. A new file is unsaved until you save it.
- **Live apply**: saving the game's asset loads it into the running engine (`engine.input.loadAsset`), during Play or not. During a play-test, a save that takes away an action the running game has (renamed, moved or deleted) is kept until you stop, because the game's code may still ask for it; the status line says so. An asset the engine's input cannot run is not left half loaded: the running game keeps the controls it had, and the status line says why.
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

`InputEditor` is an ordinary widget, so any host can put it in a window. Given another `path` (or `store`), it reopens on that file; ask its close guard first (`setCloseGuard`) if what is open may be unsaved.

```dart
InputEditor(
  store: FileInputAssetStore(projectRoot),
  path: 'assets/input/game.input.json',
  // Optional: what names an action, asked before one is renamed or deleted;
  // in scenes, the fields the component definitions make input actions.
  references: FileInputReferenceFinder(
    projectRoot,
    actionFields: InputEditorModule.actionFieldsOf(engine.context.definitions),
  ),
  // Optional: paths of files something else changed on disk.
  fileChanges: changedPaths,
  onSaved: (asset, path) {
    engine.input.loadAsset(asset);
    return null; // or a note, said after "Saved"
  },
);
```

Listen and the live test run on the editor's own input service (`InputEditorHarness`), so trying a binding there does not move the player. Its pads are the ones you give it: the engine editor's module gives it the real ones, which the running game reads too, so a pad pressed in the live test during a play-test is pressed in the game as well.

## Never in a game

The whole package is design-time only. A game imports `just_inputs` (through `just_game_engine`), never this. Only the game's editor side imports it — in the platformer template, the Asset Store's generated `lib/editor/store_modules.g.dart`, which `lib/main_editor.dart` uses — so none of it reaches a release build.

The game's in-game input widgets stay in `just_inputs`, because they ship: `OnScreenControls`, and the rebinding UI (`RebindList`, `RebindButton`, `BindingLabel`).
