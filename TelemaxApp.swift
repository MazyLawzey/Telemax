//
//  TelemaxApp.swift
//  Telemax
//
//  Created by Mazy Lawzey on 05.04.2026.
//

import SwiftUI

@main
struct TelemaxApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var chatManager = ChatManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(chatManager)
        }
    }
}
