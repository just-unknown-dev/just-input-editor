## 0.2.0-beta.1

The editor is laid out by feature (`asset` → `session` → `editor`), drawn with `just_editor_core`'s kit instead of its own copy of it, and built on what `just_inputs` 0.2.0 now provides: the name rule, the step catalogue, the settings' ranges, and validation that says which step and which setting is wrong. Values the input system cannot run are refused as they are typed, and an asset that still does not run stops the live test instead of throwing every frame.

### Breaking

- `EditorSelection` → `InputEditorSelection` (its six subclasses keep their names).
- `EditorHarness` → `InputEditorHarness`; its `live` field → `isLive`.
- `InputEditorSession.inGesture` → `isInGesture`.
- `FileInputReferenceFinder(root)` → `FileInputReferenceFinder(root, actionFields: …)`. In scenes and prefabs it looks in the component fields whose definitions make them input actions (just_game_engine's `InputDefinitions.actionType` and `actionListType`, one name or a list), whatever they are called, and no longer in every field named `action`, `actions` or `…Action`; a prefab instance's change to such a field, and a component it adds, count too. A component no definition reads is not looked in. `InputEditorModule` passes `actionFieldsOf(scope.definitions)`.
- `InputEditorState.harness` is nullable, like `session`: the harness is made only once the file has been read.
- `InputEditor.fileChanged(path)` (a static over every open editor) is gone: a host hands each editor a `Stream<String>` of changed paths, `InputEditor(fileChanges: …)`. `InputEditorModule` does this for the editors it opens.
- `AssetEdits.addScheme(asset, scheme)` → `AssetEdits.addScheme(asset, {name})`, which returns `(asset, name)` and picks a free name and a free group.
- `InputEditorTheme` is no longer exported, and `InputEditorPalette` is gone (see Removed): the editor draws in the host's `EditorTheme`. `InputEditorTheme.actionColour(id)` → `actionColor(session, id)`, internal.
- Requires just_inputs ^0.2.0, just_gamepads ^0.2.0, just_editor_core ^0.1.0 and just_game_engine ^2.0.0 (a dependency now, for its input action field kinds; it was a dev dependency); the Asset Store manifest asks for just_game_engine ^2.0.0 (was ^2.0.0-dev.2, which the package could never resolve against) and just_game_engine_editor ^0.1.0.

### Added

- `AssetEdits.onScreenIdProblem` and `AssetEdits.schemeNameProblem`, twins of `actionNameProblem` and `mapNameProblem`; `AssetEdits.fits` and `AssetEdits.processorFits`, which composites and processors suit an action.
- `InputEditorSession(…, isNew: true)` for an asset with no file yet; `isChecking`, `idle` and `checked` for an edit waiting on the reference check; `colorIndexOf`.
- `InputEditorSession.assetChanges`, `selectionChanges`, `schemeFilterChanges`, `searchChanges`, `savedChanges` and `problemChanges`: each part of the session tells its own listeners (the session's own still hear of every change).
- `InputEditorHarness.runError` and `canRun`.
- `InputActionFields`, which fields of a component hold input actions' names, and `InputEditorModule.actionFieldsOf(definitions)`, which reads them from the component definitions when asked (a definition registered later counts).
- `InputEditorModule.freePath`, the name "New input actions" opens.
- Each interaction or processor card shows what validation finds wrong with it, and each setting its own problem.
- `meta`, for `@internal`; `public_member_api_docs` in the analysis options.

### Changed

- Feature folders: `lib/src/asset/` (edits, stores, starter, references), `lib/src/session/` (session, selection, harness, checked edits) and `lib/src/editor/` (the editor and its module; its `look/`, `panels/` and `views/` are internal), one barrel each. `properties_panel.dart` is split by selection kind. `test/` mirrors `lib/src/`, and `test/library_layout_test.dart` guards the layout and the layer order.
- Built on the kit: the header is `WorkspaceHeader`, fields are `CommitTextField`, search is `EditorSearchField`, titles `EditorSectionHeader`, tags `EditorBadge`, scheme filters `EditorChip`, menus the kit's, dialogs `EditorAlert`, `showEditorPrompt` and `askToSaveChanges`. The editor follows the editor's accent and accessibility settings directly.
- The name rule is `just_inputs`' `InputNames`; composites' parts, labels and value types come from `StepCatalog` everywhere, so a composite a game registers can be added from "Add binding"; the settings' fields come from `InputSettingsDef.params` and `ranges`.
- Changing an action's type drops processors of the wrong kind too, and says what went.
- A duplicate, or an id repair, copies each definition through its own JSON, so no field is lost.
- An edit that changes nothing is no undo step.
- Through a drag, the problems are worked out once at its end, and the pictures share one count of what each control does per asset.
- The editor is no longer rebuilt whole on every change: each part listens to the parts of the session it shows. A selection leaves the header, the scheme chips and the status line alone; a search rebuilds the list of actions alone; a save the header alone; through a drag the status line waits for its end.

### Fixed

- An on-screen control renamed to an id that is not a name (`jump btn`, `jump/btn`) or is taken is refused, and said, instead of breaking every binding that named it.
- A taken or empty scheme name is said, not silently refused; "+ Scheme" never makes a second scheme with a group another one has.
- Values the input system cannot run are refused at entry: a press point or release ratio of 0, a dead zone's min not below its max, a clamp's (or a dead zone's, or normalize's) min not below its max.
- An asset that throws in the live test stops it, says so once and shows why, rather than throwing every frame (or from a pad's catch-up); a save the running game cannot run leaves its controls as they were.
- Close, the host's close guard and Save wait for a rename, move or delete still being checked, and keep what is still being typed, so it is never lost without asking.
- A new asset (no file yet) opens unsaved: its dot shows and Close asks.
- A timeline trigger's `pause`/`play` no longer counts as naming an input action: only a field of the input action kinds does.
- The module's tests no longer leave `input_play…` folders in the temp folder on Windows: a test waits for the module's read of the file it broke to end, and every test folder is removed for sure, or the test fails.
- A save that fails takes its `.saving` file away again.
- An `InputEditor` given another path, store or pads reopens on them.
- An editor whose file never reads makes no input service to throw away.
- The pad and mouse drawings follow the theme's colours.

### Removed

- `parseInputAsset`: `InputActionAsset.parse` throws only `FormatException` now.
- `AssetEdits.namePattern`: use `InputNames.pattern` / `InputNames.isValid`.
- The editor's own copies of the kit: `InputEditorPalette`, `EditorIconButton`, `EditorTextField`, `SectionHeader`, `EditorTag`, `FullScreenToggle`, `showEditorMenu`, `editorMenuItem` and `promptForText`.

## 0.1.0-beta.1

First version: the Input Actions editor, the visual side of `just_inputs`. The editor moved here from `just_inputs`, and its module from the platformer template. It builds on `just_editor_core`, the editor's module contract, and needs nothing else of the editor.

- **The editor**, `InputEditor`, on an `InputEditorSession` (the asset, whole-asset undo, the selection, the problems). Every change is an `AssetEdits` function; files go through `FileInputAssetStore` (or `MemoryInputAssetStore`), and a new file starts from `starterInputAsset`.
  - Maps, actions and bindings; composites and their parts; interactions and processors; control schemes; players (up to four) and settings; on-screen controls.
  - Binding by Pick, by Listen (press the key, button or stick; Esc gives up), or by clicking a key, a pad button or an on-screen control in the views below.
  - Keyboard, gamepad and touch-layout views, tinted by action, and a live test on the editor's own input (`EditorHarness`).
  - Names are checked when they are committed (Enter, or leaving the field): an action or a map needs letters, digits and `_`, unique where it lives. Numbers must be finite and in their range.
  - Before an action or a map is renamed, moved or deleted, `FileInputReferenceFinder` looks through the project's scenes (`action` and `…Action` fields) and the code under `lib/` for its name, and shows what would no longer find it.
  - Ids that a hand edit or a merge left behind `nextId`, or used twice, are put right when the file opens, as a step that can be undone.
  - A file that does not read (bad JSON, a value of the wrong kind, an unknown name) says why, with a Close button: `parseInputAsset` turns every failure into a `FormatException`.
  - Text fields commit once, on Enter or on leaving the field, and Esc puts back what was typed. Shortcuts use Cmd on macOS.
- **`InputEditorModule`**, the editor as a workspace of `just_game_engine_editor`:
  - the play-toolbar button (order 101), and "Edit input actions" / "New input actions" in the Assets dock;
  - live apply: a save of the game's asset (`assetPath`, `InputEditorModule.defaultAssetPath` by default) goes into the running engine at once. During a play-test, a save that takes away an action the game has is kept until Stop;
  - the game's asset changed on disk through the editor goes into the engine, and an open editor reads it again.
- Needs Flutter 3.47.1 or later, as `just_editor_core` does.

The module could not live in a package before, because the editor was inside `just_inputs`, which the engine depends on. A package below the engine cannot depend on the engine editor. Now the editor sits above both.
