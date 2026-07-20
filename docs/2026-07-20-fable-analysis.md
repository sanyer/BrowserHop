# BrowserHop Code Analysis — 2026-07-20

A full read-through of the codebase (all 7 app source files, tests, `project.yml`, Makefile, scripts) with an assessment of what's working well and what needs attention. Findings are ordered by severity within each section.

## Snapshot

~1,500 lines of Swift across 7 source files. Menu bar app, no dependencies, SwiftData persistence, XcodeGen project generation. The architecture matches the documentation in `AGENTS.md` exactly, which is itself a good sign.

---

## The Good

### Architecture & scope discipline

- **Small, single-responsibility files.** Each file maps to one concern (event handling, rule evaluation, browser discovery, UI). There is no "Utils" junk drawer and no premature abstraction. The whole app can be held in one's head.
- **`RuleEngine` is pure logic.** It's an `actor` with `static` evaluation functions that take plain inputs (`URL`, `String?`) and return a value. No I/O, no globals, no SwiftData queries inside. This is exactly the part of the app that most needs to be testable, and it is (see the test gap below, though).
- **Zero third-party dependencies.** For an app whose job is to be a trusted default browser, this is a meaningful trust and maintenance win.
- **XcodeGen with `.xcodeproj` gitignored.** Eliminates the classic project-file merge-conflict tax. `project.yml` is clean and readable.

### Correctness details done right

- **Sender PID attribution** (`AppDelegate.swift:31`) reads `keySenderPIDAttr` from the Apple Event instead of `frontmostApplication`, with a comment explaining why the naive approach fails. This is the kind of hard-won knowledge that deserves the comment it got.
- **Vacuous-truth handling** in `RuleEngine.swift:32` — empty condition sets match for `.all` but not for `.any`/`.none`, with the reasoning documented. The rule editor UI agrees ("This rule will match all URLs"), so model and UI tell the same story.
- **Input sanitization on save** (`RuleEditorSheet.sanitizedCriteria`): empty values are dropped and regex patterns are compile-checked before persisting, so the engine never sees garbage criteria.
- **Graceful fallbacks**: `openURL(_:inBrowserWithID:)` falls back to `urlForApplication(withBundleIdentifier:)` and then the default browser if the chosen browser was uninstalled; the picker falls back when no browsers are visible.
- **Edit-path cleanup**: `saveRule()` explicitly deletes old `Criteria` objects before replacing them, showing awareness that SwiftData doesn't clean up after array replacement (though this awareness is incomplete elsewhere — see below).

### Concurrency posture

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY` is the right modern default for a UI app: everything is main-actor unless deliberately opted out, and the two opt-outs (`RuleEngine` actor, `discoverAppURLs` nonisolated) are explicit and intentional.

### UI polish

- The picker window is genuinely well done: positioned at the cursor and clamped to screen bounds, keyboard shortcuts 1–9 for the first nine browsers, hover states, HTTPS/HTTP lock indicator, middle-truncated host display.
- Destructive actions (rule deletion) are confirmed with an alert; the ellipsis menu is always visible "for discoverability" rather than hover-only.
- BrowserHop hides itself from its own picker by default (`BrowserManager.init`) — a footgun someone clearly stepped on once.

### Tooling

- The Makefile covers the real lifecycle including the obscure parts: `lsregister` re-registration on install and an `unregister` target to purge stale Launch Services entries — the #1 source of "why is the wrong copy handling my links" bugs for default-browser apps.
- CodeQL workflow present for a hobby-sized project.

---

## The Bad

### 1. `.useDefault` can loop back into BrowserHop *(correctness — highest priority)*

`openURLInDefaultBrowser` (`BrowserManager.swift:180`) calls `NSWorkspace.shared.open(url)`, which routes through the **system default handler for the scheme** — and once the user has set BrowserHop as their default browser (the entire premise of the app), that handler is BrowserHop itself. A rule with the "Use Default Browser" action, or the empty-browser-list picker fallback (`AppDelegate.swift:73`), would re-deliver the Apple Event to BrowserHop and evaluate the same rule again — an infinite loop.

The fix direction already exists in the code: `BrowserManager` tracks an ordered list with a "PRIMARY" browser, and `loadDefaultBrowser` exists (though it too would report BrowserHop). "Default" should mean *the user's primary visible browser*, not the system handler. This needs a loop guard at minimum.

### 2. The picker window probably can't receive its keyboard shortcuts *(correctness)*

The picker is a plain `NSWindow` with `.borderless` style (`AppDelegate.swift:86-91`). Borderless `NSWindow`s return `false` from `canBecomeKey`, so `makeKeyAndOrderFront` orders it front but cannot make it key — meaning the 1–9 keyboard shortcuts in `HopPickerWindow` likely never fire, and neither would Escape-to-dismiss if added. The standard fix is a tiny `NSPanel`/`NSWindow` subclass overriding `canBecomeKey` to return `true`.

### 3. Zero real tests *(quality)*

`BrowserHopTests.swift` is the Xcode template placeholder. This is the single biggest gap given how testable `RuleEngine` is: pure static functions covering non-trivial semantics (vacuous truth, `.none` logic, case-insensitive matching, nil-host behavior, regex failure handling). A dozen `@Test` cases would lock down the app's core contract at near-zero cost. The UI test targets are also untouched templates and currently just add build time.

### 4. SwiftData models cross an actor boundary *(concurrency)*

`AppDelegate.loadRulesIntoEngine` fetches `RuleModel` objects on the main actor and hands the **live model objects** to the `RuleEngine` actor, which then traverses `rule.rootSet` / `criteria` off the main actor. `@Model` classes are not `Sendable` and are backed by a `ModelContext` that is not thread-safe; reading them from another actor is a data race waiting for a lazy-fault to trigger it. The clean fix is to snapshot rules into plain `Sendable` value types (structs mirroring `RuleModel`/`ConditionSet`/`Criteria`) at the boundary — which would also make `RuleEngine` trivially testable without SwiftData.

### 5. Deleting a rule orphans its condition tree *(data integrity)*

Relationships (`RuleModel.rootSet`, `ConditionSet.criteria`, `ConditionSet.subgroups`) are declared without `@Relationship(deleteRule: .cascade)`, so SwiftData defaults to nullify. `modelContext.delete(rule)` in `SettingsView.swift:91` leaves the `ConditionSet` and `Criteria` rows orphaned in the store forever. The edit path works around this manually for criteria (`RuleEditorSheet.swift:235-237`), which is evidence the problem is known — cascade rules would fix both sites declaratively. Relatedly, SwiftData to-many arrays are **unordered** by default; `criteria`/`subgroups` order isn't guaranteed to persist (harmless today since all/any/none are order-independent, but a trap for anyone adding order-sensitive logic).

### 6. Rules have priority, but the user can't set it *(feature gap / UX)*

The engine is first-match-wins over `order`-sorted rules, and new rules get `max(order) + 1`. But the Rules tab has no `onMove` — there is no way to reorder rules in the UI. For overlapping rules ("github.com → Chrome" vs "links from Slack → picker"), precedence silently equals creation order. Browsers got drag-to-reorder; rules need it more.

### 7. The model supports more than the UI can express *(dead capability)*

`ConditionSet` is recursive (`subgroups`) and supports `.none` logic, and the engine faithfully evaluates both — including with a parallel task group. But `RuleEditorSheet` only edits a flat list of root criteria with all/any, and `conditionsSummary` ignores subgroups entirely. Nothing can ever create a subgroup or a `.none` set. Either the editor should grow to match the model, or the model/engine should shrink to match the editor; carrying untested, unreachable evaluation paths is the worst of both. (The task-group parallelism for subgroup evaluation is also over-engineering — these are microsecond string comparisons; sequential evaluation with short-circuiting would be simpler *and* faster.)

### 8. Silent failure everywhere *(observability)*

There is not a single log statement in the app. `handleGetURL` silently drops unparseable URLs; `loadRulesIntoEngine` uses `try?` and silently evaluates against stale rules if the fetch fails; `sanitizedCriteria` silently discards an invalid regex the user typed — turning their intended rule into a match-everything rule with no warning. For an app whose failures manifest as "my link opened in the wrong browser," an `os.Logger` category per subsystem plus editor-side validation feedback (mark the bad regex red instead of dropping it) would pay for itself on the first support question.

### 9. Misleading `async` and main-thread file I/O *(performance / clarity)*

`loadBrowsers`, `loadInstalledApps`, and `loadDefaultBrowser` are declared `async` but never suspend — every line runs synchronously on the main actor. Worse, `loadInstalledApps` synchronously enumerates `/Applications`, `/System/Applications`, and `~/Applications` (`discoverAppURLs` is `nonisolated` but *called* from the main actor, so the isolation opt-out buys nothing) and then constructs a `Bundle` and icon for every app found — all while blocking the UI. The work also runs twice at startup: once from `BrowserManager.init`'s fire-and-forget `Task` and again from `BrowsersTab.task`. Move discovery to a background task (`Task.detached` or a nonisolated async function that's actually awaited across the boundary) and drop one of the duplicate triggers.

### 10. Smaller items

- **Regex recompiled per evaluation** (`RuleEngine.swift:66`): `NSRegularExpression(pattern:)` runs on every URL for every regex criterion. Cache compiled patterns keyed by pattern string, or move to Swift's native typed `Regex`.
- **Nil-field semantics of negative operators**: a URL with no host returns `false` even for "domain *is not* X" / "*doesn't contain* X" (`RuleEngine.swift:47-49`). Arguably a mailto-less edge case, but "is not" failing when the field is absent will surprise someone; worth a deliberate decision and a test.
- **`Criteria.op` is ignored for `.regex`** (`RuleEngine.swift:51`): the engine hard-codes `.matches`. The UI enforces the same, but the model happily stores other operators that would be silently coerced.
- **`defaultBrowserID` is published but unused** by any view or logic path.
- **Settings uses a `Window` scene** plus `NSApp.activate` / `DispatchQueue.main.async` / `orderFrontRegardless` gymnastics (`BrowserHopApp.swift:52-57`) instead of the `Settings` scene + `SettingsLink`; some of that ceremony is LSUIElement-related, but it deserves a comment or simplification.
- **`onDelete: { criteria.remove(at: index) }`** (`RuleEditorSheet.swift:143`) removes by captured index inside a `ForEach` — safe today because SwiftUI rebuilds on change, but fragile; remove by `id` instead.
- **`applyOrder`** is O(n·m) with `savedOrder.contains` in a loop — irrelevant at ~10 browsers, but a `Set` is a one-line fix.
- **Version bumps are manual** in `project.yml` (`MARKETING_VERSION`), with dedicated release commits; `CURRENT_PROJECT_VERSION` is stuck at "1" so builds are indistinguishable within a version.

---

## Suggested priorities

1. Guard the `.useDefault` → self-loop (correctness, ships wrong behavior today for anyone using that action).
2. Fix picker key-window handling so the advertised keyboard shortcuts work.
3. Write `RuleEngine` tests — cheap, high value, and prerequisite confidence for item 4.
4. Introduce `Sendable` snapshot types at the `RuleEngine` boundary.
5. Add cascade delete rules; add rule reordering UI.
6. Adopt `os.Logger` and surface regex-validation errors in the editor.

Overall: a well-shaped, carefully detailed codebase whose core evaluation logic is better than its safety net. The bones are good; the gaps are almost all in the space between "works on my machine" and "provably keeps working" — tests, logging, and a couple of default-browser-specific edge cases.
