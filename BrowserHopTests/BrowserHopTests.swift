import Testing
@testable import BrowserHop

@MainActor
struct FallbackTargetTests {
    private let own = "ZhuzhaTech.BrowserHop"

    @Test func usesSystemHandlerWhenItIsAnotherBrowser() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: "com.apple.Safari",
            ownBundleID: own,
            visibleBrowserIDs: ["org.mozilla.firefox", "com.google.Chrome"]
        )
        #expect(target == .systemHandler)
    }

    @Test func routesToPrimaryBrowserWhenBrowserHopIsTheSystemHandler() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: own,
            ownBundleID: own,
            visibleBrowserIDs: ["com.google.Chrome", "com.apple.Safari"]
        )
        #expect(target == .browser(bundleID: "com.google.Chrome"))
    }

    @Test func routesToPrimaryBrowserWhenHandlerCannotBeResolved() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: nil,
            ownBundleID: own,
            visibleBrowserIDs: ["com.google.Chrome"]
        )
        #expect(target == .browser(bundleID: "com.google.Chrome"))
    }

    @Test func neverPicksBrowserHopFromTheVisibleList() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: own,
            ownBundleID: own,
            visibleBrowserIDs: [own, "com.apple.Safari"]
        )
        #expect(target == .browser(bundleID: "com.apple.Safari"))
    }

    @Test func fallsBackToSafariWhenOnlyBrowserHopIsVisible() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: own,
            ownBundleID: own,
            visibleBrowserIDs: [own]
        )
        #expect(target == .safari)
    }

    @Test func fallsBackToSafariWhenNothingIsAvailable() {
        let target = BrowserManager.resolveFallbackTarget(
            systemHandlerID: nil,
            ownBundleID: own,
            visibleBrowserIDs: []
        )
        #expect(target == .safari)
    }
}
