//
//  ContentView.swift
//  Telemax
//
//  Created by Mazy Lawzey on 05.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            if auth.isAuthenticated {
                TabView {
                    Tab("Chats", systemImage: "archivebox") {
                        ChatView()
                    }

                    Tab("Settings", systemImage: "gear") {
                        SettingsView()
                    }

                    Tab("Search", systemImage: "magnifyingglass", role: .search) {
                        SearchView()
                    }
                }
            } else {
                AuthView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
