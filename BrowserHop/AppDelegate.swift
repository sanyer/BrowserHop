import AppKit
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ruleEngine = RuleEngine()
    private var pickerWindow: NSWindow?

    /// Set by BrowserHopApp on launch so the delegate can access shared state.
    var browserManager: BrowserManager!
    var modelContainer: ModelContainer!

    // MARK: - URL Handling

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // Get the sending app's bundle ID from the Apple Event sender PID
        // (frontmostApplication would return BrowserHop itself at this point)
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? 0
        let sourceBundle = NSRunningApplication(processIdentifier: senderPID)?.bundleIdentifier

        Task { @MainActor in
            await loadRulesIntoEngine()
            let action = await ruleEngine.evaluate(url: url, sourceApp: sourceBundle)
            handleAction(action, for: url)
        }
    }

    // MARK: - Rule evaluation

    @MainActor
    private func loadRulesIntoEngine() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RuleModel>(sortBy: [SortDescriptor(\.order)])
        guard let rules = try? context.fetch(descriptor) else { return }
        await ruleEngine.setRules(rules)
    }

    @MainActor
    private func handleAction(_ action: RuleAction?, for url: URL) {
        switch action {
        case .openInApp(let bundleID):
            browserManager.openURL(url, inBrowserWithID: bundleID)
        case .useDefault:
            browserManager.openURLInDefaultBrowser(url)
        case .showPicker, .none:
            showPicker(for: url)
        }
    }

    // MARK: - Picker window

    @MainActor
    private func showPicker(for url: URL) {
        // Close any existing picker
        pickerWindow?.close()
        pickerWindow = nil

        let browsers = browserManager.visibleBrowsers
        guard !browsers.isEmpty else {
            browserManager.openURLInDefaultBrowser(url)
            return
        }

        let picker = HopPickerWindow(url: url, browsers: browsers) { [weak self] bundleID in
            self?.browserManager.openURL(url, inBrowserWithID: bundleID)
            self?.dismissPicker()
        }

        let hostingView = NSHostingView(rootView: picker)
        hostingView.setFrameSize(hostingView.fittingSize)

        let contentSize = hostingView.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.level = .floating
        window.isReleasedWhenClosed = false

        // Center on the screen where the mouse cursor is
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - contentSize.width / 2
            let y = screenFrame.midY - contentSize.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerWindow = window
    }

    private func dismissPicker() {
        pickerWindow?.close()
        pickerWindow = nil
    }
}
