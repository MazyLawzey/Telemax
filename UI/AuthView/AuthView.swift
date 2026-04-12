import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthManager

    @State private var username    = ""
    @State private var displayName = ""
    @State private var serverURL   = ""
    @State private var showSetup   = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    Image(systemName: "lock.shield.fill")
                        .resizable()
                        .frame(width: 70, height: 80)
                        .foregroundStyle(.accent)

                    Text("Telemax")
                        .font(.largeTitle.bold())

                    Text("End-to-End Encrypted Messenger")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // --- Server URL ---
                    if showSetup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Apps Script URL")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("https://script.google.com/macros/s/…/exec", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                        }
                    }

                    // --- Username ---
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("@username", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    // --- Display name ---
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display Name")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Your Name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // --- Error ---
                    if let err = auth.error {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // --- Button ---
                    Button {
                        Task {
                            if showSetup {
                                SheetsService.shared.setBaseURL(serverURL)
                            }
                            await auth.register(username: username, displayName: displayName)
                        }
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView()
                            } else {
                                Text("Create Account")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(formInvalid)

                    Text("Your identity is a cryptographic key pair generated on-device.\nNo email or password needed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }

    private var formInvalid: Bool {
        username.isEmpty || displayName.isEmpty || (showSetup && serverURL.isEmpty) || auth.isLoading
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}
