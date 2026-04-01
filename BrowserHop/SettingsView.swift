import SwiftUI
import SwiftData

/// Wrapper so `.sheet(item:)` works for both new (nil rule) and edit cases.
struct RuleEditorItem: Identifiable {
    let id = UUID()
    let rule: RuleModel?
}

// MARK: - Settings Root

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleModel.order) private var rules: [RuleModel]
    @State private var editorItem: RuleEditorItem? = nil

    var body: some View {
        TabView {
            BrowsersTab()
                .tabItem {
                    Label("Browsers", systemImage: "globe")
                }

            RulesTab(rules: rules, editorItem: $editorItem)
                .tabItem {
                    Label("Rules", systemImage: "list.bullet.rectangle.portrait")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 580, height: 420)
        .sheet(item: $editorItem) { item in
            RuleEditorSheet(rule: item.rule)
        }
    }
}

// MARK: - Rules Tab

struct RulesTab: View {
    var rules: [RuleModel]
    @Binding var editorItem: RuleEditorItem?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            if rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
            bottomBar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Rules Yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Create a rule to route URLs to specific browsers\nbased on domain, source app, or URL pattern.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create First Rule") {
                editorItem = RuleEditorItem(rule: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(rules) { rule in
                    RuleCardView(rule: rule, onEdit: {
                        editorItem = RuleEditorItem(rule: rule)
                    }, onDelete: {
                        withAnimation {
                            modelContext.delete(rule)
                        }
                    })
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(action: {
                editorItem = RuleEditorItem(rule: nil)
            }) {
                Label("Add Rule", systemImage: "plus")
            }
            Spacer()
            Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Rule Card

struct RuleCardView: View {
    @Bindable var rule: RuleModel
    @EnvironmentObject private var browserManager: BrowserManager
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: $rule.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.headline)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                Text(rule.conditionsSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                actionRow
            }

            Spacer(minLength: 4)

            // Ellipsis menu — always visible for discoverability
            Menu {
                Button(action: onEdit) {
                    Label("Edit Rule", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("Delete Rule", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered
                    ? Color(nsColor: .controlBackgroundColor).opacity(0.9)
                    : Color(nsColor: .controlBackgroundColor).opacity(rule.isEnabled ? 1 : 0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered
                    ? Color.accentColor.opacity(0.3)
                    : Color(nsColor: .separatorColor), lineWidth: isHovered ? 1 : 0.5)
        }
        .opacity(rule.isEnabled ? 1.0 : 0.7)
        .onHover { isHovered = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("Delete Rule", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(rule.name)\"? This cannot be undone.")
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        let info = rule.actionSummary
        HStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let bundleID = info.browserBundleID,
               let browser = browserManager.browsers.first(where: { $0.id == bundleID }) {
                Image(nsImage: browser.icon.resized(to: 14))
                Text("Open in \(browser.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let bundleID = info.browserBundleID, !bundleID.isEmpty {
                Text("Open in \(bundleID)")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text(info.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

// MARK: - Browsers Tab

struct BrowsersTab: View {
    @EnvironmentObject private var browserManager: BrowserManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Prioritise your browsers, with your favourite first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Reorderable list
            if browserManager.orderedBrowsers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Detecting browsers...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(browserManager.orderedBrowsers) { browser in
                        BrowserRow(
                            browser: browser,
                            isPrimary: browser.id == browserManager.orderedBrowsers.first?.id,
                            isVisible: browserManager.isBrowserVisible(browser.id),
                            onToggleVisibility: {
                                browserManager.toggleBrowserVisibility(browser.id)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        browserManager.moveBrowsers(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await browserManager.loadBrowsers()
            await browserManager.loadDefaultBrowser()
        }
    }
}

struct BrowserRow: View {
    let browser: BrowserApp
    let isPrimary: Bool
    let isVisible: Bool
    let onToggleVisibility: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 28, height: 28)

            Text(browser.displayName)
                .font(.body)
                .foregroundStyle(isVisible ? .primary : .secondary)
                .lineLimit(1)

            if isPrimary {
                Text("PRIMARY")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue))
            }

            Spacer()

            // Visibility toggle
            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.body)
                    .foregroundStyle(isVisible ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(isVisible ? "Hide from picker" : "Show in picker")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPrimary
                    ? Color.blue.opacity(0.06)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPrimary
                    ? Color.blue.opacity(0.2)
                    : Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .opacity(isVisible ? 1.0 : 0.6)
    }
}
// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)

            // App name and version
            VStack(spacing: 4) {
                Text("BrowserHop")
                    .font(.title)
                    .fontWeight(.bold)
                Text(Self.versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Description
            VStack(spacing: 8) {
                Text("A smart default browser for macOS that routes URLs\nto the right browser based on your rules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Copyright
            Text(Self.copyrightString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private static var copyrightString: String {
        if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
            return copyright
        }
        let year = Calendar.current.component(.year, from: Date())
        return "Copyright \u{00A9} \(year). All rights reserved."
    }
}

