# Contributing to Just Input Editor

Thank you for your interest in contributing to **Just Input Editor**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
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
| Flutter | A stable release that ships Dart 3.12.2 or later |

`just_game_engine` and `just_inputs` also need Flutter 3.44.0 or later.

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

The package depends on four `just_*` packages: `just_inputs`, the core it edits; `just_gamepads`, for a pad's type in the gamepad view; and `just_game_engine` and `just_game_engine_editor`, the editor it plugs into. When a change needs an unreleased version of one, or `flutter pub get` cannot find a version, check it out next to this repository and point this package at it with a `pubspec_overrides.yaml` in the repository root. The paths below use the package names as folder names, as the monorepo does:

```yaml
# pubspec_overrides.yaml: local only, never commit it.
dependency_overrides:
  just_inputs:
    path: ../just_inputs
  just_gamepads:
    path: ../just_gamepads
  just_game_engine:
    path: ../just_game_engine
  just_game_engine_editor:
    path: ../just_game_engine_editor
```

If one of their own dependencies is unpublished too (`just_game_engine` depends on `just_physics_engine`, `just_audio_engine`, `just_game_engine_formats` and others), add an entry for it the same way. Then run `flutter pub get`. Delete the file (or the entry) and run `flutter pub get` again to go back to the published versions.

Do not change `pubspec.yaml` to a path dependency: the Asset Store refuses a package that depends on anything by path or git. If your pull request needs a version that is not published yet, say so in the pull request: this package can only be released after it.

No other `just_*` package depends on this one. Games add it as a dev dependency, because none of it may ship (the platformer template does), and the Asset Store registers its module from `just_store.json`. If you change `InputEditorModule`'s constructor or `InputEditorModule.defaultAssetPath`, say so in the pull request.

---

## How the Package Fits Together

| Path | Contents |
|------|----------|
| `lib/just_input_editor.dart` | The one library. Everything public is exported here |
| `lib/src/editor/core/` | No widgets: `InputEditorSession` (the asset, undo, selection, problems), `AssetEdits` (every edit), `InputAssetStore` with `FileInputAssetStore` and `MemoryInputAssetStore`, and `starterInputAsset` |
| `lib/src/editor/widgets/` | `InputEditor` and its parts: `MapsColumn`, `ActionsTree`, `PropertiesPanel` with `StepListEditor`, and `BottomPanel` with `KeyboardView`, `GamepadView`, `TouchLayoutView` and `LiveTestView`; `EditorHarness`; `InputEditorTheme` and `EditorTextField` |
| `lib/src/input_editor_module.dart` | `InputEditorModule`: the workspace, the play-toolbar button, the Assets dock actions and live apply |
| `just_store.json` | The Asset Store manifest: an `editor-extension` whose module is `InputEditorModule`, with `editorOnlyLibraries: ["*"]`, so none of it may reach a release build |
| `test/` | The tests; `test/sample_asset.dart` is a small platformer-shaped asset most of them share |

A few rules hold the package together. Keep them:

- **Every change is one undo step.** Widgets change the asset only through `InputEditorSession.edit` (or `apply`, `create`), and a drag between `beginGesture` and `endGesture` is one step too. History keeps whole assets, up to `InputEditorSession.maxUndo`. Put a new edit in `AssetEdits`, as a pure function (an asset in, a new asset out, no widgets, no undo), so it can be tested alone.
- **The file format belongs to `just_inputs`.** The editor reads with `InputActionAsset.parse` and saves with `InputActionAsset.encode()`; it never writes JSON of its own. A new field is added to `just_inputs` first, then gets its control here.
- **Ids come from the asset.** New maps, actions and bindings take their ids from `InputActionAsset.takeId`, and a duplicate gets fresh ids all the way down. Players' saved rebinds point at binding ids, so never reuse or renumber an id, or derive one from a position.
- **References follow renames.** Join actions are saved as `map/action`, bindings name scheme groups, and on-screen bindings name a control's id. `renameMap`, `renameAction`, `updateScheme`, `deleteScheme` and `updateOnScreen` rewrite what named the old one, and deleting a map or action drops its join action. A new edit that renames or removes something needs the same, and a test in `test/editor_core_test.dart`.
- **The editor has its own input.** Listen and the live test run on `EditorHarness`, a private `InputService` that runs the asset as it is being edited. They never touch the game's. Only a save of the game's asset (`InputEditorModule.assetPath`) reaches the running engine, through `engine.input.loadAsset`.
- **A save never leaves half a file.** `FileInputAssetStore.save` writes `<file>.saving` and renames it over the file. Paths are project-relative with forward slashes, and `PackageAssetPaths` finds them on disk.
- **`InputEditor` takes everything from its host** through its constructor: the store, the path, `onSaved`, `setCloseGuard`, the gamepads. That is how it runs inside the engine editor and on its own. Engine-editor code belongs in `InputEditorModule`, which also sets `InputEditorTheme.palette` from `EditorTheme.current` each time it builds the workspace.
- **Interactions and processors come from `just_inputs`' registries**, `InputInteractions.all` and `InputProcessors.all`, and each setting's field is drawn from the entry's `ParamInfo` list. A new one registered there shows up here with no change. Composite kinds are listed by action type in `actions_tree.dart`, from `CompositeKinds`.
- **The store's names are fixed.** `just_store.json` names `InputEditorModule` in `package:just_input_editor/just_input_editor.dart`, and the store's generated `store_modules.g.dart` calls `InputEditorModule()`. Keep the class, the library and a constructor that needs no arguments. Keep `version` in `just_store.json` equal to the one in `pubspec.yaml`: the Asset Store refuses a package whose versions differ.

---

## Running the Tests

Run every command from the repository root. `test/library_boundary_test.dart` reads `lib/` from disk and expects that working directory.

```bash
# The whole suite.
flutter test

# One file.
flutter test test/editor_core_test.dart
```

**The library boundary.** `test/library_boundary_test.dart` walks every import that `just_input_editor.dart` reaches. It fails if a file under `lib/` is not reached from it, or if `lib/` imports a `src/` file of `just_inputs` or its `testing.dart`.

**Writing tests.** Test an edit in `test/editor_core_test.dart`: call the `AssetEdits` function on `sampleAsset()`, check the result, and check `validateAsset` where it matters. For the widgets, open an `InputEditor` on a `MemoryInputAssetStore` that holds `sampleAsset().encode()`. When a test needs pads, pass a `FakeGamepadSource` from `package:just_inputs/testing.dart`; no test reads a real controller. The tests that open the whole editor set `tester.view.physicalSize` to 1600 × 1000 at a device pixel ratio of 1, so do the same. `test/input_editor_module_test.dart` boots a real `Engine` and writes to a temporary folder: work that needs real time or real files goes inside `tester.runAsync`.

---

## Coding Guidelines

- **Formatting.** Code is formatted with `dart format`. This must report no changes:

  ```bash
  dart format --output=none --set-exit-if-changed lib test
  ```

- **Analysis.** `flutter analyze` must report no issues at all: no errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`.
- **Design time only.** Nothing here ships in a game, and the library imports `dart:io`, so it does not build for the web. Code a game needs at run time belongs in `just_inputs`.
- **Look.** Draw the editor's panels, fields and text in `InputEditorTheme`'s colours and styles, so it matches the host's palette and accent. Hard-code a colour only in a drawing of a device, like the pad's body. Use `EditorTextField` for typed values: it commits on Enter or when the field is left, and Esc puts back what was there, so a rename is one undo step.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update [README.md](README.md) if the public API changes.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Match the existing folders: no widgets in `lib/src/editor/core/`. Export new public API through `lib/just_input_editor.dart`; the boundary test fails on a file nothing reaches.

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
