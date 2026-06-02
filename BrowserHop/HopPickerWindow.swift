import SwiftUI
import AppKit

struct HopPickerWindow: View {
    let url: URL
    let browsers: [BrowserApp]
    let onSelect: (String) -> Void

    @State private var hoveredBrowserID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Browser row
            HStack(spacing: 12) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    Button(action: {
                        onSelect(browser.id)
                    }) {
                        VStack(spacing: 4) {
                            Image(nsImage: browser.icon)
                                .resizable()
                                .frame(width: 40, height: 40)
                            Text(browser.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(hoveredBrowserID == browser.id ? .primary : .secondary)
                        }
                        .frame(width: 64)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(hoveredBrowserID == browser.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear)
                        )
                        .scaleEffect(hoveredBrowserID == browser.id ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.12), value: hoveredBrowserID)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredBrowserID = isHovered ? browser.id : nil
                    }
                    .modifier(OptionalKeyboardShortcut(index: index))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            // Domain display
            HStack(spacing: 4) {
                Image(systemName: url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                    .font(.caption2)
                    .foregroundStyle(url.scheme == "https" ? Color.secondary : Color.orange)
                Text(url.host ?? url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 8)
        }
        .background(VisualEffectView().ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Only assigns keyboard shortcuts for the first 9 browsers.
private struct OptionalKeyboardShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        } else {
            content
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
