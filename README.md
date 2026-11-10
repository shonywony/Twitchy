# Twitchy

A simple Mac app that wraps twitch.tv in its own window. Built the same way as Tubey.

## Run it

Double-click `Twitchy.xcodeproj`, then press **⌘R** (or the ▶ button) in Xcode.

To install or update: quit Twitchy, choose **Product → Show Build Folder in Finder**, open `Products/Debug`, and drag `Twitchy.app` into Applications (choose Replace if asked).

## Features

- Its own window and Dock icon, and it stays logged in between launches
- Opens straight to the Twitch log-in page if you're logged out (also Navigate → "Log In to Twitch…")
- Purple top bar matching the icon; window title is always "Twitchy"
- Toolbar: Back, Forward, Home, Reload, Picture in Picture
- Keyboard shortcuts: ⌘[ back, ⌘] forward, ⌘R reload, ⇧⌘H home, ⇧⌘P picture in picture
- Trackpad swipe for back/forward, pinch to zoom
- Picture in picture for streams and videos
- Full-screen video works, and the window can go side by side with another app in full screen
- Purple theme (on by default, View → Purple Theme): recolours the Twitch site with deep purples instead of grey. The app bar isn't affected. Shades live in `PurpleTheme.css`
- Bandwidth monitor (bottom-right corner, View → Show Bandwidth Monitor): live download speed and data used this session by this app only. Click it to reset the total. It's a close estimate: it counts video/audio fed to the player plus pages, images and scripts
- Tracker blocking (always on): blocks Twitch's own analytics/telemetry (spade, countess, client event reporter) and common third-party ad and analytics trackers (Google, Amazon ads, comScore and others), and cookies from non-Twitch third parties. Rules live in `BlockRules.json` (Safari content-blocker format)
- Links to other websites open in your normal browser
- Always in dark mode
- Quits when you close the window, so audio doesn't keep playing

## Files

- `TwitchyApp.swift`: app entry point and menus
- `ContentView.swift`: window and toolbar
- `BrowserModel.swift`: the web view, navigation, link handling, log-in check, tracker blocking and picture in picture
- `WebView.swift`: connects the web view to SwiftUI
- `BlockRules.json`: tracker-blocking rules
- `TwitchyIcon.icon`: the app icon
