import SwiftUI
import AppKit

struct HopPickerWindow: View {
    let url: URL
    let browsers: [BrowserApp]
    let onSelect: (String) -> Void

    @State private var hoveredBrowserID: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Open link in...")
                .font(.title3)
                .fontWeight(.semibold)

            // URL display with copy button
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(url.absoluteString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy URL")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    Button(action: {
                        onSelect(browser.id)
                    }) {
                        VStack(spacing: 6) {
                            Image(nsImage: browser.icon)
                                .resizable()
                                .frame(width: 48, height: 48)
                            Text(browser.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            if index < 9 {
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.3))
                                    )
                            }
                        }
                        .padding(10)
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(hoveredBrowserID == browser.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(hoveredBrowserID == browser.id
                                    ? Color.accentColor.opacity(0.5)
                                    : Color.clear, lineWidth: 1.5)
                        )
                        .scaleEffect(hoveredBrowserID == browser.id ? 1.03 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: hoveredBrowserID)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredBrowserID = isHovered ? browser.id : nil
                    }
                    .modifier(OptionalKeyboardShortcut(index: index))
                }
            }
        }
        .padding(30)
        .background(VisualEffectView().ignoresSafeArea())
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
