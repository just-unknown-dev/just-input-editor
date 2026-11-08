# Contributing to Just Input Editor

Thank you for your interest in contributing to **Just Input Editor**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Layout](#layout)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-input-editor/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the output of `flutter --version`, and your operating system;
- whether the editor was open inside `just_game_engine_editor` (from the play toolbar or the Assets dock) or as an `InputEditor` in your own app;
- the `.input.json` asset, or the smallest part of it that shows the problem;
- for an undo bug, the edits in order and what Undo put back;
- for Listen or the live test, the device: the keyboard layout (QWERTY, AZERTY, …), or the controller and how it is connected;
- for a layout bug, a screenshot and the window size.

Some bugs belong in a neighbouring package:

- An asset that loads, validates or runs wrongly belongs in [just_inputs](https://github.com/just-unknown-dev/just-inputs/issues). So do the problems and conflicts the editor lists, which come from `validateAsset` and `findBindingConflicts`. Listen and the live test run `just_inputs` itself (`RebindingOperation`, `InputService`), so if they get an action wrong for an asset the editor saved correctly, the bug is probably there.
- A controller that is read wrongly belongs in [just_gamepads](https://github.com/just-unknown-dev/just-gamepads/issues).
- A bug in the engine editor around the workspace, such as its dialog, the play toolbar or the Assets dock, belongs in `just_game_engine_editor`.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is editing `.input.json` assets and putting that editor in `just_game_engine_editor`: maps, actions and bindings, schemes, players, on-screen controls, the keyboard, gamepad and touch views, and the live test. What an asset can hold and how it runs is `just_inputs`' job, so a new field in the format starts there. The in-game widgets (`OnScreenControls`, `RebindList`, `RebindButton`, `BindingLabel`) ship in games, so they stay in `just_inputs` too.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Dart | 3.12.2 |
| Flutter | 3.47.1 |

`just_editor_core` and `just_game_engine` need Flutter 3.47.1 or later (the first stable where Flutter GPU can be switched on in Windows and Linux builds), so this package does too.

There is no app to run here: you work on the package and its tests. To try a change in the engine editor, add the package to a game's `dev_dependencies` with a `path:` to your clone, and register `InputEditorModule()` as the [README](README.md) shows.

```bash
git clone https://github.com/just-unknown-dev/just-input-editor.git just_input_editor
cd just_input_editor
flutter pub get
flutter test
```

If you're working from the Just engine monorepo, run every command from `plugins/just_input_editor`.

---

## Working Against Unpublished Dependencies

The package depends on four `just_*` packages: `just_inputs`, the core it edits; `just_gamepads`, for a pad's type in the gamepad view; `just_editor_core`, the editor's module contract it plugs in through; and `just_game_engine`, whose input action field kinds (`InputDefinitions`) tell the module which component fields name an action. Its tests also use the engine to see a save reach a running one. When a change needs an unreleased version of one, or `flutter pub get` cannot find a version, check it out next to this repository and point this package at it with a `pubspec_overrides.yaml` in the repository root. The paths below use the package names as folder names, as the monorepo does:

```yaml
# pubspec_overrides.yaml: local only, never commit it.
dependency_overrides:
  just_inputs:
    path: ../just_inputs
  just_gamepads:
    path: ../just_gamepads
  just_editor_core:
    path: ../just_editor_core
  just_game_engine:
    path: ../just_game_engine
```

If one of their own dependencies is unpublished too (`just_game_engine` depends on `just_physics_engine`, `just_audio_engine`, `just_game_engine_formats` and others), add an entry for it the same way. Then run `flutter pub get`. Delete the file (or the entry) and run `flutter pub get` again to go back to the published versions.

Do not change `pubspec.yaml` to a path dependency: the Asset Store refuses a package that depends on anything by path or git. If your pull request needs a version that is not published yet, say so in the pull request: this package can only be released after it.

No other `just_*` package depends on this one. Games get it from the Asset Store, which puts it in the project's `plugins/` folder, links it, and registers its module from `just_store.json`; none of it may ship. If you change `InputEditorModule`'s constructor or `InputEditorModule.defaultAssetPath`, say so in the pull request.

---

## How the Package Fits Together

| Path | Contents |
|------|----------|
| `lib/just_input_editor.dart` | The one library. It exports the three features' barrels, whole |
| `lib/src/asset/` | The asset and the project, outside any widget: `AssetEdits` (every edit, as a pure function), `InputAssetStore` with `FileInputAssetStore` and `MemoryInputAssetStore`, `starterInputAsset`, and `InputReferenceFinder` with `FileInputReferenceFinder` (which fields hold actions comes in as `InputActionFields`: the asset layer never reads the engine's definitions itself) |
| `lib/src/session/` | The editor's state, without widgets: `InputEditorSession` (the asset, undo, the selection, the problems), `InputEditorSelection` and its kinds, `InputEditorHarness` (the editor's own input service), and the internal `CheckedEdits` (renames, moves and deletes that check names and ask first) |
| `lib/src/editor/` | `InputEditor` and `InputEditorModule` (the workspace, the play-toolbar button, the Assets dock actions and live apply). Under it, all internal: `look/` (`InputEditorTheme`: action colours, icons, text styles; `InputTextField`; `PanelHeader`), `panels/` (`MapsColumn`, `ActionsTree`, `PropertiesPanel` and one file per kind of selection, `StepListEditor`, the control picker) and `views/` (`BottomPanel`, `KeyboardView`, `GamepadView`, `TouchLayoutView`, `LiveTestView`, `ControlCap` and the control uses they share) |
| `just_store.json` | The Asset Store manifest: an `editor-extension` whose module is `InputEditorModule`, with `editorOnlyLibraries: ["*"]`, so none of it may reach a release build |
| `test/` | The tests, mirroring `lib/src/` (`test/asset/`, `test/session/`, `test/editor/…`); `test/support/` holds what they share: `sampleAsset()`, a small platformer-shaped asset, `openEditor`, `ThrowingSteps` and `tempFolder` |

A few rules hold the package together. Keep them:

- **Every change is one undo step.** Widgets change the asset only through `InputEditorSession.edit` (or `apply`, `create`), and a drag between `beginGesture` and `endGesture` is one step too. History keeps whole assets, up to `InputEditorSession.maxUndo`. Put a new edit in `AssetEdits`, as a pure function (an asset in, a new asset out, no widgets, no undo), so it can be tested alone.
- **Each part rebuilds on what it shows.** The session tells each of its parts' listeners apart: `assetChanges`, `selectionChanges`, `schemeFilterChanges`, `searchChanges`, `savedChanges` and `problemChanges` (the problems wait for the end of a drag). `InputEditorState.build` puts each part of the editor (the header, the maps, the tree, Properties, the views, the status line) under a `ListenableBuilder` of the parts it reads, and never rebuilds the whole editor. A widget that starts reading another part of the session adds it there; `test/editor/input_editor_test.dart` ("each part rebuilds on what it shows") counts the builds.
- **The file format belongs to `just_inputs`.** The editor reads with `InputActionAsset.parse` (every failure a `FormatException`) and saves with `InputActionAsset.encode()`; it never writes JSON of its own. A new field is added to `just_inputs` first, then gets its control here. A copy with new ids (a duplicate, an id repair) is read back from the definition's own JSON, so a field added there is never dropped here.
- **Ids come from the asset.** New maps, actions and bindings take their ids from `InputActionAsset.takeId`, and a duplicate gets fresh ids all the way down. Players' saved rebinds point at binding ids, so never reuse or renumber an id, or derive one from a position. The one exception is `AssetEdits.repairIds`, which the editor runs when a file opens: a `nextId` behind the ids moves past them, and an id used twice (a merge) gets a new one where it comes again.
- **References follow renames.** Join actions are saved as `map/action`, bindings name scheme groups, and on-screen bindings name a control's id. `renameMap`, `renameAction`, `updateScheme`, `deleteScheme` and `updateOnScreen` rewrite what named the old one, and deleting a map or action drops its join action. A new edit that renames or removes something needs the same, and a test in `test/asset/asset_edits_test.dart`. Names outside the asset (scene fields, game code) are never rewritten: a rename, move or delete of an action or a map goes through `CheckedEdits`, which shows what `InputReferenceFinder` finds first.
- **The editor has its own input.** Listen and the live test run on `InputEditorHarness`, a private `InputService` that runs the asset as it is being edited; only its pads are shared with the game. An update that throws stops it (`runError`) until the next asset, rather than throwing every frame. Only a save of the game's asset (`InputEditorModule.assetPath`) reaches the running engine, through `InputEditorModule.apply`, which keeps a save that takes an action away until a play-test stops, and loads the old asset back when the engine cannot run the new one.
- **Refuse what the input system cannot run.** A typed value validation would call an error — a setting out of `InputSettingsDef.params`' range, a min not below its max (`InputSettingsDef.ranges`, `StepInfo.ranges`) — is refused and said (`InputEditorSession.say`), and what a hand-edited file still holds is shown where it is edited: each `AssetIssue` carries its step (`stepKind`, `stepIndex`) and setting (`param`).
- **A save never leaves half a file.** `FileInputAssetStore.save` writes `<file>.saving` and renames it over the file. Paths are project-relative with forward slashes, and `PackageAssetPaths` finds them on disk.
- **`InputEditor` takes everything from its host** through its constructor: the store, the path, `onSaved`, `setCloseGuard`, the gamepads, the reference finder, the changed files (`fileChanges`). That is how it runs inside the engine editor and on its own, with no state shared between editors. Engine-editor code belongs in `InputEditorModule`.
- **Steps and composites come from `just_inputs`' catalogue**: interactions from `StepCatalog.interactions`, processors from `InputProcessors.all` (which knows a vector's from the others), composites — their parts, labels and the value they make — from `StepCatalog.composites`. Each setting's field is drawn from its `ParamInfo`. One a game registers shows up here with no change. The name rule is `InputNames`.
- **Save and close wait for what is pending.** A rename, move or delete still waiting on the reference check counts as `InputEditorSession.isChecking`; `save()` and the close guard flush what is being typed (`PendingFieldEdits.flush`) and wait for `idle` first.
- **The store's names are fixed.** `just_store.json` names `InputEditorModule` in `package:just_input_editor/just_input_editor.dart`, and the store's generated `store_modules.g.dart` calls `InputEditorModule()`. Keep the class, the library and a constructor that needs no arguments. Keep `version` in `just_store.json` equal to the one in `pubspec.yaml`: the Asset Store refuses a package whose versions differ.

---

## Layout

`lib/src/` has three features, each a top-level folder with one barrel named after it that the public library exports whole. From the bottom up:

| Layer | Feature | May import |
|-------|---------|------------|
| 0 | `asset` | `dart:`, `just_inputs`' public library, `just_editor_core` (for `PackageAssetPaths`) and `meta`: no widgets |
| 1 | `session` | `asset`, plus `flutter/foundation.dart` and `flutter/gestures.dart`: still no widgets |
| 2 | `editor` | everything below |

A feature imports only its own layer or below, so there are no loops. Inside `editor/`, `look/` is below `panels/` and `views/`, which never import each other, and the editor and its module are above them all.

- **Exported or internal.** Every public declaration under `lib/src/` is either exported by its barrel or marked `@internal` (from `meta`): `CheckedEdits`, and everything under `editor/look/`, `editor/panels/` and `editor/views/`. Barrels export only their own folder; nothing else exports.
- **The guard.** `test/library_layout_test.dart` checks all of this, from the directives of every file. A new folder takes its place in its `_layers`.
- **Tests mirror `lib/src/`**: a test of `lib/src/editor/panels/step_list_editor.dart` is `test/editor/panels/step_list_editor_test.dart`, named for what it tests.

---

## Running the Tests

Run every command from the repository root. `test/library_layout_test.dart` and `test/library_boundary_test.dart` read `lib/` from disk and expect that working directory.

```bash
# The whole suite.
flutter test

# One file.
flutter test test/asset/asset_edits_test.dart
```

**The layout.** `test/library_layout_test.dart` checks the [Layout](#layout). `test/library_boundary_test.dart` walks every import that `just_input_editor.dart` reaches, and fails if `lib/` imports a `src/` file of `just_inputs` or its `testing.dart`.

**Writing tests.** Test an edit in `test/asset/asset_edits_test.dart`: call the `AssetEdits` function on `sampleAsset()`, check the result, and check `validateAsset` where it matters; a new edit also gets a line in its "round trips" group. For the widgets, `openEditor` (in `test/support/`) opens an `InputEditor` on a `MemoryInputAssetStore` that holds `sampleAsset().encode()`, at 1600 × 1000 and a device pixel ratio of 1. When a test needs pads, pass a `FakeGamepadSource` from `package:just_inputs/testing.dart`; no test reads a real controller. `ThrowingSteps` registers interactions the input system cannot run, for the paths that must survive one. `test/editor/input_editor_module_test.dart` boots a real `Engine` and writes to a temporary folder: work that needs real time or real files goes inside `tester.runAsync`. Make a test's folder with `tempFolder(prefix)` (`test/support/temp_folder.dart`): it is removed when the test ends, and the test fails, naming it, when it cannot be (on Windows, a read the code never finished).

---

## Coding Guidelines

- **Formatting.** Code is formatted with `dart format`. This must report no changes:

  ```bash
  dart format --output=none --set-exit-if-changed lib test
  ```

- **Analysis.** `flutter analyze` must report no issues at all: no errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`, and `public_member_api_docs`.
- **Design time only.** Nothing here ships in a game, and the library imports `dart:io`, so it does not build for the web. Code a game needs at run time belongs in `just_inputs`.
- **Look.** Build on `just_editor_core`'s kit (`package:just_editor_core/kit.dart`) and draw in `EditorTheme`'s colours, so the editor follows the host's palette, accent and accessibility settings. `InputEditorTheme` holds only what is the input editor's own: action colours, the type and layout icons, and its text styles. Hard-code a colour only in a drawing of a device, like the phone's frame. Use `InputTextField` (the kit's `CommitTextField`) for typed values: it commits on Enter or when the field is left, Esc puts back what was there, and a value the owner refuses is shown as it was — so a rename is one undo step.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update [README.md](README.md) if the public API changes.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Keep to the [Layout](#layout): no widgets in `asset/` or `session/`. Export new public API through its feature's barrel, or mark it `@internal`; the layout test fails on a file that is neither.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b fix/rename-keeps-join-action
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze
   flutter test
   ```
4. Commit with a [conventional commit message](#commit-message-convention).
5. Push to your fork and open a pull request against `main`. Say what changed and why, and list any unpublished `just_*` version it needs. For a change you can see, add before and after screenshots.
6. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Use the area as the scope: `core`, `maps`, `tree`, `properties`, `views` (the keyboard, gamepad and touch views and the live test), `module` or `theme`. Mark a change that breaks the public API with `!` and a `BREAKING CHANGE:` footer.

**Examples:**
```
fix(tree): keep a composite's parts open after an undo
feat(views): draw the keyboard view in an AZERTY layout
docs(contributing): explain where input bugs belong
```

---

## License

By contributing to Just Input Editor you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).
