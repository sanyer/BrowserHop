import AppKit

/// A borderless `NSWindow` refuses key status (`canBecomeKey` is false), which
/// leaves the picker's 1–9 keyboard shortcuts dead. A non-activating panel can
/// become key and receive keystrokes without activating the whole app, so the
/// app the user clicked the link in keeps focus.
final class PickerPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    // Escape dismisses the picker.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
