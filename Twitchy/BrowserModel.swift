import AppKit
import SwiftUI
import WebKit

/// Owns the web view and exposes its state to the UI.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    static let homeURL = URL(string: "https://www.twitch.tv")!

    /// Twitch's log-in page. After logging in it returns you to the Twitch home page.
    static let signInURL = URL(string: "https://www.twitch.tv/login")!

    /// Cookie Twitch sets only when you're logged in.
    private static let signedInCookieNames: Set<String> = ["auth-token"]

    /// Sites that open inside the app. Anything else opens in your default browser.
    private static let inAppHosts = ["twitch.tv", "ttvnw.net", "jtvnw.net", "twitchcdn.net", "twitchsvc.net"]

    let webView: WKWebView

    /// Counts the data this app downloads, for the bandwidth badge.
    let bandwidth = BandwidthMonitor()

    /// On by default. Shows the bandwidth badge in the bottom-right corner (the counting always runs).
    @Published var showBandwidth = UserDefaults.standard.object(forKey: "showBandwidth") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBandwidth, forKey: "showBandwidth") }
    }

    private static let bandwidthScript = BandwidthMonitor.pageScript(
        handlerName: "twitchyBandwidth", mediaHosts: ["ttvnw.net"]
    )

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false

    /// On by default. Recolours Twitch with deep purples (PurpleTheme.css). The app bar isn't affected.
    @Published var purpleTheme = UserDefaults.standard.object(forKey: "purpleTheme") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(purpleTheme, forKey: "purpleTheme")
            applyUserScripts()
            webView.reload()
        }
    }

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        // The default data store is saved to disk, so you stay logged in between launches.
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Picture in picture is off by default in app web views on the Mac (Safari turns it on).
        // This WebKit setting isn't public, so only set it if this macOS version has it.
        if config.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }

        webView = WKWebView(frame: .zero, configuration: config)
        // Present as Safari so Twitch serves the full desktop site.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Force dark mode, and a black background so pages don't flash white while loading.
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.underPageBackgroundColor = NSColor(red: 0x0e/255, green: 0x09/255, blue: 0x18/255, alpha: 1)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(bandwidth, name: "twitchyBandwidth")

        observations = [
            webView.observe(\.canGoBack) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
            webView.observe(\.canGoForward) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
        ]

        applyUserScripts()
        openStartPage()
    }

    /// On launch: Twitch if you're logged in, otherwise straight to the log-in page.
    private func openStartPage() {
        Task {
            // Turn tracker blocking on before the first page loads.
            if let rules = await Self.compileRules(named: "BlockRules") {
                webView.configuration.userContentController.add(rules)
            }

            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let signedIn = cookies.contains {
                $0.domain.hasSuffix("twitch.tv") && Self.signedInCookieNames.contains($0.name)
            }
            webView.load(URLRequest(url: signedIn ? Self.homeURL : Self.signInURL))
        }
    }

    // MARK: - Actions

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func goHome() { webView.load(URLRequest(url: Self.homeURL)) }
    func signIn() { webView.load(URLRequest(url: Self.signInURL)) }

    /// Pops the playing stream into a floating picture-in-picture window, or brings it back.
    func togglePictureInPicture() {
        let script = """
        (function () {
          const videos = Array.from(document.querySelectorAll('video'));
          const v = videos.find(x => !x.paused) || videos[0];
          if (!v) return 'no-video';
          v.disablePictureInPicture = false;
          if (v.webkitSupportsPresentationMode && !v.webkitSupportsPresentationMode('picture-in-picture')) {
            return 'not-supported-by-webview';
          }
          if (v.webkitSetPresentationMode) {
            const inPip = v.webkitPresentationMode === 'picture-in-picture';
            v.webkitSetPresentationMode(inPip ? 'inline' : 'picture-in-picture');
            return 'ok';
          }
          if (document.pictureInPictureElement) { document.exitPictureInPicture(); return 'ok'; }
          if (v.requestPictureInPicture) { v.requestPictureInPicture(); return 'ok'; }
          return 'unsupported';
        })();
        """
        webView.evaluateJavaScript(script) { result, error in
            let outcome = (result as? String) ?? "error: \(error?.localizedDescription ?? "unknown")"
            print("Twitchy: picture in picture → \(outcome)")
            if outcome != "ok" {
                NSSound.beep()
            }
        }
    }

    // MARK: - Purple theme

    private func applyUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(source: Self.bandwidthScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        if purpleTheme, let script = Self.purpleThemeScript {
            controller.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
        }
    }

    /// Adds PurpleTheme.css to every Twitch page and keeps it there.
    private static let purpleThemeScript: String? = {
        guard let url = Bundle.main.url(forResource: "PurpleTheme", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8),
              let data = try? JSONEncoder().encode(css),
              let cssLiteral = String(data: data, encoding: .utf8) else {
            print("Twitchy: PurpleTheme.css not found")
            return nil
        }
        return """
            (() => {
              if (!/(^|\\.)twitch\\.tv$/.test(location.hostname)) return;
              const css = \(cssLiteral);
              const addStyle = () => {
                if (document.getElementById('twitchy-purple-theme')) return;
                const style = document.createElement('style');
                style.id = 'twitchy-purple-theme';
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
              };
              addStyle();
              document.addEventListener('DOMContentLoaded', addStyle);
            })();
            """
    }()

    // MARK: - Tracker blocking

    /// Uses the same rule format as Safari content blockers. Edit BlockRules.json to add or remove rules.
    private static func compileRules(named name: String) async -> WKContentRuleList? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            print("Twitchy: \(name).json not found")
            return nil
        }
        do {
            return try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "Twitchy-" + name, encodedContentRuleList: json)
        } catch {
            print("Twitchy: couldn't load \(name).json: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    /// Web links to sites other than Twitch, which open in your default browser.
    private static func externalTarget(of url: URL) -> URL? {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        let inApp = inAppHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        return inApp ? nil : url
    }
}

// MARK: - WebKit delegates

extension BrowserModel: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame,
           navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let external = Self.externalTarget(of: url) {
            NSWorkspace.shared.open(external)
            return .cancel
        }
        return .allow
    }

    /// Links that try to open a new window load in this one instead (or in your browser if external).
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if let external = Self.externalTarget(of: url) {
                NSWorkspace.shared.open(external)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}
