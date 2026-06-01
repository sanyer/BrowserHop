# BrowserHop

BrowserHop is a lightweight macOS utility that intercepts HTTP/HTTPS links and routes them based on user-defined rules. It runs as a Menu Bar app and acts as a "Router" between macOS and your installed web browsers.

## Features

- **URL Interception:** Captures system-wide `http` and `https` links.
- **Dynamic Discovery:** Automatically detects installed web-capable applications.
- **SwiftData Rules:** Define complex "All/Any/None" logic to match source app, domain, or regex.
- **Hop Picker:** Provides a beautiful, fast, borderless selection UI if no single browser is specified.
- **Privacy-First:** 100% local, no analytics. Strict Swift 6.3 concurrency.

## Development

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`. The `.xcodeproj` file is not committed to source control.

### Prerequisites

Install XcodeGen via Homebrew:

```sh
brew install xcodegen
```

### Getting Started

```sh
make generate   # generate BrowserHop.xcodeproj from project.yml
make open       # generate and open in Xcode
make clean      # delete the generated .xcodeproj
```

When adding or removing source files, just drop them in the appropriate folder — XcodeGen picks them up automatically on the next `make generate`. Only edit `project.yml` when changing build settings, targets, capabilities, or dependencies.

## Setting Up BrowserHop as Default Browser

In order for BrowserHop to intercept links clicked in other apps (like Mail, Messages, Slack), you must set it as the system's default web browser.

1. **Launch BrowserHop.** You will see it appear in your Menu Bar.
2. Open **System Settings** on your Mac (Apple menu  > System Settings).
3. Navigate to **Desktop & Dock** in the sidebar.
4. Scroll down to the **Default web browser** dropdown menu.
5. Select **BrowserHop** from the list.

Now, whenever you click a link outside of a browser, BrowserHop will intercept it and evaluate it against your rules in `< 100ms`, routing it immediately or showing the Hop Picker.
