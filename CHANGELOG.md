## 0.1.0-beta.1

First version: the Input Actions editor, the visual side of `just_inputs`. The editor moved here from `just_inputs`, and its module from the platformer template. It builds on `just_editor_core`, the editor's module contract, and needs nothing else of the editor.

- **The editor**, `InputEditor`, on an `InputEditorSession` (the asset, whole-asset undo, the selection, the problems). Every change is an `AssetEdits` function; files go through `FileInputAssetStore` (or `MemoryInputAssetStore`), and a new file starts from `starterInputAsset`.
  - Maps, actions and bindings; composites and their parts; interactions and processors; control schemes; players (up to four) and settings; on-screen controls.
  - Binding by Pick, by Listen (press the key, button or stick; Esc gives up), or by clicking a key, a pad button or an on-screen control in the views below.
  - Keyboard, gamepad and touch-layout views, tinted by action, and a live test on the editor's own input (`EditorHarness`), which never touches the game's.
  - Names are checked as they are typed: an action or a map needs letters, digits and `_`, unique where it lives. Numbers must be finite and in their range.
  - Before an action or a map is renamed, moved or deleted, `FileInputReferenceFinder` looks through the project's scenes (`action` and `…Action` fields) and the code under `lib/` for its name, and shows what would no longer find it.
  - Ids that a hand edit or a merge left behind `nextId`, or used twice, are put right when the file opens, as a step that can be undone.
  - A file that does not read (bad JSON, a value of the wrong kind, an unknown name) says why, with a Close button: `parseInputAsset` turns every failure into a `FormatException`.
  - Text fields (`EditorTextField`) commit once, on Enter or on leaving the field, and Esc puts back what was typed. Shortcuts use Cmd on macOS.
- **`InputEditorModule`**, the editor as a workspace of `just_game_engine_editor`:
  - the play-toolbar button (order 101), and "Edit input actions" / "New input actions" in the Assets dock;
  - live apply: a save of the game's asset (`assetPath`, `InputEditorModule.defaultAssetPath` by default) goes into the running engine at once. During a play-test, a save that takes away an action the game has is kept until Stop;
  - the game's asset changed on disk through the editor goes into the engine, and an open editor reads it again.
- Needs Flutter 3.47.1 or later, as `just_editor_core` does.

The module could not live in a package before, because the editor was inside `just_inputs`, which the engine depends on. A package below the engine cannot depend on the engine editor. Now the editor sits above both.
