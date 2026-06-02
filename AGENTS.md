# AGENTS.md

Shared instructions for AI coding agents working in this repository.

## Project

BrowserHop — macOS menu bar app that acts as system default browser, routing URLs to browsers based on user-defined rules. Pure Swift, no external dependencies.

## Build & Test

```sh
brew install xcodegen          # one-time prerequisite
make generate                  # generate .xcodeproj from project.yml
make open                      # generate + open in Xcode
make clean                     # remove generated .xcodeproj
```

```sh
xcodebuild -scheme BrowserHop -configuration Debug build
xcodebuild -scheme BrowserHop -configuration Debug test
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest.

## Architecture

| File | Role |
|------|------|
| `BrowserHopApp.swift` | `@main` App entry, SwiftData ModelContainer, MenuBarExtra |
| `AppDelegate.swift` | Apple Event URL handler (`kAEGetURL`), picker window lifecycle |
| `RuleEngine.swift` | `actor` — evaluates URL + source app against rule tree |
| `RuleModels.swift` | SwiftData models: `RuleModel`, `ConditionSet`, `Criteria`; `RuleAction` enum |
| `BrowserManager.swift` | Discovers browsers, manages ordering/visibility, opens URLs |
| `SettingsView.swift` | Settings window (Browsers, Rules, About tabs) |
| `RuleEditorSheet.swift` | Rule create/edit sheet |
| `HopPickerWindow.swift` | Borderless floating picker UI |

### URL Flow

1. `AppDelegate.handleGetURL` receives Apple Event → extracts URL + sender PID
2. Fetches rules from SwiftData, passes to `RuleEngine.evaluate()`
3. `RuleEngine` walks ordered rules, evaluates recursive `ConditionSet` tree (All/Any/None logic)
4. Returns `RuleAction` → AppDelegate either opens in browser, uses default, or shows picker

## Concurrency

- Build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — everything is MainActor unless opted out
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `RuleEngine` is explicitly `actor` (off-main-actor evaluation)
- `BrowserManager` is explicitly `@MainActor`

## Code Style

- Swift 5 language version, Swift 6 concurrency features enabled
- No external linter configured — rely on compiler warnings and strict concurrency
- macOS 26.3 deployment target
- No third-party dependencies — Apple frameworks only
- SwiftUI for all UI; AppKit only where required (NSWindow for picker, NSWorkspace for browser ops)

## Project Structure Rules

- Source files go in `BrowserHop/` folder directly — XcodeGen auto-discovers them
- Only edit `project.yml` for build settings, targets, capabilities, or scheme changes
- `.xcodeproj` is gitignored and regenerated

## Verification

After any code change, confirm it compiles:

```sh
xcodebuild -scheme BrowserHop -configuration Debug build 2>&1 | tail -5
```

Do not report a task complete if build fails. Fix all errors first.

## Conventions

- App is `LSUIElement` (menu bar only, no Dock icon)
- Sandbox disabled (required for Apple Event sender PID + opening URLs in other apps)
- Hardened Runtime enabled
- Data persistence via SwiftData (RuleModel → ConditionSet → Criteria)
- User preferences (browser order, hidden set) via UserDefaults
