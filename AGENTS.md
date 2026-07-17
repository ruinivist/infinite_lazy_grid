# Repository Guidelines

## Project Structure & Module Organization

This repository is a Flutter package. Public exports start in `lib/infinite_lazy_grid.dart`; implementation code lives under `lib/core/`, with controller types in `lib/core/controller/` and shared extensions and helpers in `lib/utils/`. The fragment shader is `shaders/dot_grid.frag`. Package tests live in `test/`, mirroring source areas where useful (for example, `test/core/spatial_hashing_test.dart`). The runnable Flutter showcase is in `example/`; its platform folders are generated Flutter host projects. `demo.gif` and example web icons are documentation assets.

## Build, Test, and Development Commands

- `flutter pub get`: install package dependencies.
- `flutter analyze`: run `flutter_lints` checks from `analysis_options.yaml`.
- `flutter test`: run all unit and widget tests.
- `flutter test test/core/spatial_hashing_test.dart`: run one focused test file.
- `dart format lib test example/lib`: format maintained Dart sources.
- `make dev`: launch the example app in Chrome (`cd example && flutter run -d chrome`).

Run analysis and tests before opening a pull request.

## Coding Style & Naming Conventions

Use standard Dart formatting with two-space indentation and trailing commas where they improve formatter output. Name types in `UpperCamelCase`, members and files in `lowerCamelCase` and `snake_case.dart`, respectively. Prefer `const` widgets and values when possible. Keep the package's public surface in `lib/infinite_lazy_grid.dart`; do not export internal helpers without a concrete consumer. Follow the existing controller/background abstractions instead of adding parallel APIs.

## Testing Guidelines

Tests use `flutter_test`. Name files `*_test.dart`, group related unit cases with `group`, and use `testWidgets` for rendering or interaction behavior. Add a focused regression test for bug fixes and cover visible behavior rather than private implementation details. No coverage threshold is configured; prioritize spatial indexing, transforms, lazy rendering, and controller state transitions.

## Commit & Pull Request Guidelines

History uses short, direct subjects. Use lowercase conventional commits with no more than eight words, such as `fix: correct zoom transform`. Keep commits scoped to one change. Pull requests should explain the user-visible effect, list validation commands, and link relevant issues. Include a screenshot or short recording for example-app or rendering changes, and note any shader or platform-specific impact.
