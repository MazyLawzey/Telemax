import SwiftUI

#if os(macOS)
import AppKit
private let systemGray5 = NSColor.quinarySystemFill
private let systemGray6 = NSColor.quaternarySystemFill
private let systemBackground = NSColor.windowBackgroundColor
#else
import UIKit
private let systemGray5 = UIColor.systemGray5
private let systemGray6 = UIColor.systemGray6
private let systemBackground = UIColor.systemBackground
#endif

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    // Banner
                    Color(systemGray5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)

                    // Avatar
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.accentColor)
                        .background(Color(systemGray6))
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(systemBackground), lineWidth: 4))
                        .offset(y: 50)
                        .contextMenu {
                            Button(action: {}) {
                                Label("View Picture", systemImage: "eye")
                            }
                            Button(action: {}) {
                                Label("Change Picture", systemImage: "photo")
                            }
                            Divider()
                            Button(role: .destructive, action: {}) {
                                Label("Remove Picture", systemImage: "trash")
                            }
                        }
                }

                // User info
                VStack(spacing: 6) {
                    if let user = auth.currentUser {
                        Text(user.displayName)
                            .font(.title2.bold())
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not logged in")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 60)

                Spacer()
            }
        }
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


#Preview {
    NavigationView {
        ProfileView()
            .environmentObject(AuthManager.shared)
    }
}
