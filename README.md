<p align="center">
  <img src="BrowserHop/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="BrowserHop icon" />
</p>

<h1 align="center">BrowserHop</h1>

<p align="center">
  A smart default browser for macOS that routes URLs to the right browser based on your rules.
</p>

---

## What It Actually Does

When you set BrowserHop as your system default browser, every link clicked outside a browser (Mail, Slack, Messages, Terminal, etc.) flows through it. BrowserHop evaluates the URL against your rules in under 100ms, then either:

- Opens it directly in the matched browser
- Opens it in the system default browser
- Shows a fast, keyboard-driven picker so you choose on the spot

No analytics, no network calls, no background daemons. Pure local routing.

## Link Sources

BrowserHop intercepts links via macOS Apple Events (`http`/`https` URL schemes). It identifies the **source application** that opened the link by reading the sender PID from the event, allowing rules like "links from Slack → Chrome" or "links from Mail → Safari".

## Installing

1. Download the latest release from [Releases](https://github.com/sanyer/BrowserHop/releases)
2. Move `BrowserHop.app` to `/Applications`
3. Launch it — appears in the menu bar only (no Dock icon)
4. Set as default browser: **System Settings → Desktop & Dock → Default web browser → BrowserHop**

## Building

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
```

```sh
make generate   # generate .xcodeproj from project.yml
make open       # generate + open in Xcode
make clean      # remove generated .xcodeproj
```

Or build from CLI:

```sh
xcodebuild -scheme BrowserHop -configuration Release build
```

Run tests:

```sh
xcodebuild -scheme BrowserHop -configuration Debug test
```

## Rules

Rules are evaluated top-to-bottom. First match wins. Each rule has:

- **Conditions** — one or more criteria combined with All/Any/None logic:
  - **Source App** — the app that opened the link (bundle ID, e.g. `com.tinyspeck.slackmacgap`)
  - **Domain** — the URL host (e.g. `github.com`)
  - **URL Regex** — full URL pattern match
- **Operators** — `is`, `is not`, `contains`, `doesn't contain`, `matches` (regex)
- **Action** — what happens when conditions match:
  - Open in a specific browser
  - Use system default browser
  - Show the Hop Picker

Rules with no conditions match everything (useful as a catch-all at the bottom).

## Settings

Access via the menu bar icon → Settings. Three tabs:

| Tab | Purpose |
|-----|---------|
| **Browsers** | Reorder detected browsers (top = primary), hide/show in picker |
| **Rules** | Create, edit, enable/disable, delete routing rules |
| **About** | Version info |

## Permissions

- **No App Sandbox** — required to open URLs in other applications and read sender app info from Apple Events
- **Hardened Runtime** — enabled for notarization compatibility
- **No special entitlements** — no accessibility, no network, no disk access beyond standard

## License

[BSD 3-Clause](LICENSE) — Copyright (c) 2026, Roman Zhuzha
