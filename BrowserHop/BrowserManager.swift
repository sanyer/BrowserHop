import Foundation
import AppKit
import Combine
import SwiftUI

struct BrowserApp: Identifiable, Equatable {
    let id: String           // Bundle identifier
    let displayName: String
    let bundleURL: URL
    let icon: NSImage
}

struct InstalledApp: Identifiable, Equatable {
    let id: String           // Bundle identifier
    let displayName: String
    let icon: NSImage
}

@MainActor
final class BrowserManager: ObservableObject {
    @Published private(set) var browsers: [BrowserApp] = []
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var defaultBrowserID: String? = nil

    /// Browsers in user-defined priority order.
    @Published private(set) var orderedBrowsers: [BrowserApp] = []
    /// Bundle IDs the user has hidden from the picker.
    @Published private(set) var hiddenBrowserIDs: Set<String> = []

    /// Ordered browsers that are not hidden — use this for the picker.
    var visibleBrowsers: [BrowserApp] {
        orderedBrowsers.filter { !hiddenBrowserIDs.contains($0.id) }
    }

    private static let orderKey = "BrowserOrder"
    private static let hiddenKey = "HiddenBrowsers"

    init() {
        // Load persisted hidden set
        let hidden = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        hiddenBrowserIDs = Set(hidden)

        Task {
            await self.loadBrowsers()
            await self.loadInstalledApps()
            await self.loadDefaultBrowser()
        }
    }

    func loadBrowsers() async {
        let schemes = ["http", "https"]
        var found: Set<String> = []
        var apps: [BrowserApp] = []
        let workspace = NSWorkspace.shared

        for scheme in schemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            let appURLs = workspace.urlsForApplications(toOpen: url)
            for appURL in appURLs {
                guard let bundle = Bundle(url: appURL),
                      let bundleID = bundle.bundleIdentifier,
                      !found.contains(bundleID),
                      let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String else { continue }
                found.insert(bundleID)
                let icon = workspace.icon(forFile: appURL.path)
                icon.size = NSSize(width: 64, height: 64)
                apps.append(BrowserApp(id: bundleID, displayName: name, bundleURL: appURL, icon: icon))
            }
        }
        self.browsers = apps.sorted { $0.displayName < $1.displayName }
        applyOrder()
    }

    func loadInstalledApps() async {
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        ]

        let appURLs = Self.discoverAppURLs(in: searchDirs)

        let workspace = NSWorkspace.shared
        var found: Set<String> = []
        var apps: [InstalledApp] = []

        for fileURL in appURLs {
            guard let bundle = Bundle(url: fileURL),
                  let bundleID = bundle.bundleIdentifier,
                  !found.contains(bundleID) else { continue }

            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? fileURL.deletingPathExtension().lastPathComponent

            found.insert(bundleID)
            let icon = workspace.icon(forFile: fileURL.path)
            icon.size = NSSize(width: 32, height: 32)
            apps.append(InstalledApp(id: bundleID, displayName: name, icon: icon))
        }
        self.installedApps = apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func loadDefaultBrowser() async {
        guard let url = URL(string: "https://"),
              let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            defaultBrowserID = nil
            return
        }
        defaultBrowserID = Bundle(url: defaultURL)?.bundleIdentifier
    }

    // MARK: - Ordering

    /// Applies persisted order to the detected browsers.
    /// Any newly detected browsers are appended at the end.
    private func applyOrder() {
        let savedOrder = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        let lookup = Dictionary(uniqueKeysWithValues: browsers.map { ($0.id, $0) })

        var ordered: [BrowserApp] = []
        for id in savedOrder {
            if let app = lookup[id] {
                ordered.append(app)
            }
        }
        // Append any browsers not yet in the saved order
        for browser in browsers where !savedOrder.contains(browser.id) {
            ordered.append(browser)
        }
        orderedBrowsers = ordered
    }

    private func persistOrder() {
        UserDefaults.standard.set(orderedBrowsers.map(\.id), forKey: Self.orderKey)
    }

    func moveBrowsers(from source: IndexSet, to destination: Int) {
        orderedBrowsers.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    // MARK: - Visibility

    func isBrowserVisible(_ bundleID: String) -> Bool {
        !hiddenBrowserIDs.contains(bundleID)
    }

    func toggleBrowserVisibility(_ bundleID: String) {
        if hiddenBrowserIDs.contains(bundleID) {
            hiddenBrowserIDs.remove(bundleID)
        } else {
            hiddenBrowserIDs.insert(bundleID)
        }
        UserDefaults.standard.set(Array(hiddenBrowserIDs), forKey: Self.hiddenKey)
    }

    // MARK: - File discovery

    private nonisolated static func discoverAppURLs(in searchDirs: [URL]) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for dir in searchDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                urls.append(fileURL)
            }
        }
        return urls
    }
}

