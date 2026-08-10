import AppKit
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ruleEngine = RuleEngine()
    private var pickerWindow: NSWindow?
    private var clickOutsideMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

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

        // A URL we dispatched ourselves means the system handed it right back
        // (BrowserHop is the default handler) — break the loop instead of
        // re-evaluating rules against our own event.
        if senderPID == ProcessInfo.processInfo.processIdentifier {
            browserManager.openURLInDefaultBrowser(url)
            return
        }

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
        let window = PickerPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.onCancel = { [weak self] in self?.dismissPicker() }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = hostingView
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        // Position near the mouse cursor, clamped to screen bounds
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        if let screen {
            let screenFrame = screen.visibleFrame
            // Place centered horizontally on cursor, slightly above cursor
            var x = mouseLocation.x - contentSize.width / 2
            var y = mouseLocation.y + 10
            // Clamp to screen edges
            x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - contentSize.width - 4))
            y = max(screenFrame.minY + 4, min(y, screenFrame.maxY - contentSize.height - 4))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        pickerWindow = window

        // Dismiss when user clicks outside the picker. The global monitor only
        // sees other apps' events; losing key status covers clicks on our own
        // windows and Cmd-Tab away.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPicker()
        }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissPicker() }
        }
    }

    private func dismissPicker() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
        pickerWindow?.close()
        pickerWindow = nil
    }
}
