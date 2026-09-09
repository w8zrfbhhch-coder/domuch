// DrinkstandApp.swift
// Target membership: Drinkstand (the only target — no widget this time)

import SwiftUI
import AppKit

/// Setting .accessory activation policy hides the Dock icon and
/// Cmd+Tab entry, so the app only shows up as the menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // TEMPORARY DEBUG — prints every font Xcode actually registered.
        // Look for "GoogleSansCode" in the Xcode console output after
        // launching. Remove this whole block once the font works.
        print("=== Available font families containing 'Google' or 'Sans' ===")
        for family in NSFontManager.shared.availableFontFamilies {
            if family.localizedCaseInsensitiveContains("google")
                || family.localizedCaseInsensitiveContains("sans code") {
                print("FAMILY:", family)
            }
        }
        print("=== Available font POSTSCRIPT NAMES containing 'Google' ===")
        for font in NSFontManager.shared.availableFonts {
            if font.localizedCaseInsensitiveContains("google") {
                print("FONT:", font)
            }
        }
        print("=== End font debug ===")
    }
}

@main
struct DrinkstandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WaterStore()

    var body: some Scene {
        MenuBarExtra("Drinkstand", systemImage: "drop.fill") {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
