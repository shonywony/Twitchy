import SwiftUI

@main
struct TwitchyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var browser = BrowserModel()

    var body: some Scene {
        Window("Twitchy", id: "main") {
            ContentView()
                .environmentObject(browser)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Single-window app: hide "New Window".
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .toolbar) {
                Toggle("Purple Theme", isOn: $browser.purpleTheme)
                Toggle("Show Bandwidth Monitor", isOn: $browser.showBandwidth)
            }

            CommandMenu("Navigate") {
                Button("Back") { browser.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!browser.canGoBack)

                Button("Forward") { browser.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!browser.canGoForward)

                Divider()

                Button("Reload") { browser.reload() }
                    .keyboardShortcut("r", modifiers: .command)

                Button("Home") { browser.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Log In to Twitch…") { browser.signIn() }
            }

            CommandMenu("Video") {
                Button("Picture in Picture") { browser.togglePictureInPicture() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Always use dark mode, whatever your Mac is set to.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    // Quit when the window closes, so audio doesn't keep playing in the background.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
