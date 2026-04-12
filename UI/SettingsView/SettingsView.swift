//
//  SettingsView.swift
//  Telemax
//
//  Created by Mazy Lawzey on 05.04.2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager

    @State private var showServerURL = false
    @State private var serverURL = SheetsService.shared.isConfigured
        ? (UserDefaults.standard.string(forKey: "appsScriptURL") ?? "")
        : ""

    var body: some View {
        NavigationView {
            List {
                // Account
                Section("Account") {
                    if let user = auth.currentUser {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .foregroundStyle(.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        LabeledContent("User ID") {
                            Text(String(user.id.prefix(12)) + "…")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Security
                Section("Security") {
                    LabeledContent("Encryption") {
                        Text("RSA-2048 + AES-256-GCM")
                            .font(.caption)
                    }
                    LabeledContent("Key Storage") {
                        Text("iOS Keychain")
                            .font(.caption)
                    }
                }

                // Server
                Section("Server") {
                    Button {
                        showServerURL.toggle()
                    } label: {
                        Label("Apps Script URL", systemImage: "server.rack")
                    }

                    if showServerURL {
                        TextField("URL", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        Button("Save") {
                            SheetsService.shared.setBaseURL(serverURL)
                            showServerURL = false
                        }
                        .disabled(serverURL.isEmpty)
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Label("Delete Account & Logout", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager.shared)
}
