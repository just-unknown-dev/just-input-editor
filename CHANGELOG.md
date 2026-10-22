## 0.1.0

- **Builds on `just_editor_core`**, the editor's module contract, instead of depending on `just_game_engine_editor`: the module's code needs nothing else of the editor.

First version. The Input Actions editor moved here from `just_inputs`, and its module moved here from the platformer template.

- **Esc puts back what was typed** in a text field (`EditorTextField`), which, as everywhere in the editor, keeps it on Enter or on leaving the field — Tab, a click elsewhere. With nothing typed, Esc is left to whatever else wants it.

- **The editor**, moved from `package:just_inputs/editor.dart` with the same API:
  - `InputEditor`, `InputEditorSession`, `AssetEdits`, `FileInputAssetStore` / `MemoryInputAssetStore`, `starterInputAsset`, `EditorHarness`, `InputEditorTheme`.
  - Undo; Pick and Listen.
  - Keyboard, gamepad and touch layout views; a live test.
- **`InputEditorModule`**, moved from the template's `lib/editor/input_editor_module.dart`:
  - The editor as a workspace of `just_game_engine_editor`.
  - The play-toolbar button (order 101).
  - The Assets dock actions.
  - Live apply to the running engine.
  - `assetPath` defaults to `InputEditorModule.defaultAssetPath` (`assets/input/game.input.json`).

The module could not live in a package before, because the editor was inside `just_inputs`, which the engine depends on. A package that sits below the engine cannot depend on the engine editor. Now the editor sits above both.
