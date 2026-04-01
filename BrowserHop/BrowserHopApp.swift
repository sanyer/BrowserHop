//
//  BrowserHopApp.swift
//  BrowserHop
//
//  Created by Roman Zhuzha on 1/4/26.
//

import SwiftUI
import SwiftData

@main
struct BrowserHopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RuleModel.self,
            ConditionSet.self,
            Criteria.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private let browserManager = BrowserManager()

    @Environment(\.openWindow) private var openWindow

    init() {
        appDelegate.browserManager = browserManager
        appDelegate.modelContainer = sharedModelContainer
    }

    var body: some Scene {
        Window("BrowserHop", id: "settings") {
            SettingsView()
                .environmentObject(browserManager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .modelContainer(sharedModelContainer)

        MenuBarExtra("BrowserHop", image: "MenuBarIcon") {
            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    NSApp.windows.first(where: { $0.canBecomeKey })?.orderFrontRegardless()
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit BrowserHop") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
