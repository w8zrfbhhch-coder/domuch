//
//  Drinkstand_iosApp.swift
//  Drinkstand ios
//
//  iOS entry point — plain WindowGroup, no AppKit. Shares
//  ContentView.swift/WaterStore.swift with the macOS menu-bar target
//  (both are pure SwiftUI/Foundation, no platform-specific code).
//

import SwiftUI

@main
struct Drinkstand_iosApp: App {
    @StateObject private var store = WaterStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
