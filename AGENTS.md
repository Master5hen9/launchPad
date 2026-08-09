# Repository Guidelines

launchPad is a macOS app that brings back the Launchpad screen Apple removed in macOS 26. This guide explains how the repository is organized and how to contribute.

## Project Structure & Module Organization

The repository is a Swift Package targeting macOS 26:

- `Sources/launchPadCore/` — Swift/SwiftUI logic: app scanning (`Services/`), models (`Models/`), paginated fullscreen grid (`LaunchpadView.swift`, `LaunchpadPager.swift`, `ContentViewModel.swift`), overlay window and pinch handling (`LaunchpadWindowController.swift`, `PinchGestureMonitor.swift`, `PinchDetector.swift`), settings and login-item install (`AppSettings.swift`, `LoginItemInstaller.swift`)
- `Sources/launchPad/` — app entry point and settings UI: `launchPadApp.swift` (`@main` + AppDelegate), `SettingsView.swift`; the app runs without a window and opens the Launchpad on demand
- `Tests/launchPadTests/` — Swift Testing suite, run as an executable via `Runner.swift`
- `Assets/` — app icon, artwork, and bundled resources

`Assets/` is reserved but not yet created. Keep UI and logic in `launchPadCore` so search, grouping, and filtering stay testable without rendering.

## Build, Test, and Development Commands

Requires macOS 26 and Swift 6.2+ (Command Line Tools are sufficient; no Xcode needed):

```sh
swift build               # compile all targets
swift run launchPad       # build and launch (runs without a visible window)
swift run launchPad --show # launch and open the fullscreen Launchpad immediately
swift run launchPadTests  # build and run the test suite
swift run -c release launchPad --install-login-item  # install a smooth (optimized) login item
```

`swift test` does not discover Swift Testing tests under Command Line Tools only, so the suite is packaged as an executable runner; `swift run launchPadTests` exits non-zero when any test fails.

## Coding Style & Naming Conventions

- Use 4-space indentation, trailing commas, and a final newline.
- Name types with `UpperCamelCase` and variables, functions, and cases with `lowerCamelCase`; prefer descriptive names over abbreviations.
- Model Launchpad state with `@Observable` or `@State`; keep views small and reusable.
- Run SwiftLint if it is added to the project; otherwise match existing style.

## Testing Guidelines

- Use Swift Testing (`@Test` / `#expect`) in `Tests/launchPadTests/`.
- Name tests with a `test`-prefixed behavior name, e.g. `testFiltersAppsBySearchQuery`.
- Cover grouping, search, and filtering logic plus core UI flows; aim for high coverage on non-UI logic.
- Run with `swift run launchPadTests`.

## Commit & Pull Request Guidelines

Git history is new (currently a single `first commit`). Adopt Conventional Commits, e.g. `feat: add Launchpad grid view`, `fix: restore missing app icons`, `docs: update README`.

For pull requests, open a descriptive title, explain what changed and why, link any related issue, and include a screenshot or video for UI changes. Keep changes small enough to review in one sitting.

## Agent-Specific Instructions

AI agents should read `README.md` and this guide before editing, never overwrite files outside their task, and avoid inventing build commands that do not yet exist.
