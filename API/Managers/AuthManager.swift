import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?

    private let crypto = CryptoService.shared
    private let api    = SheetsService.shared

    init() {
        if crypto.hasKeyPair, let data = UserDefaults.standard.data(forKey: "currentUser"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            currentUser = user
            isAuthenticated = true
        }
    }

    // MARK: - Register (generates new key pair)

    func register(username: String, displayName: String) async {
        isLoading = true
        error = nil

        do {
            let (_, pub) = try crypto.generateKeyPair()
            let uid   = try crypto.userId(from: pub)
            let pubB64 = try crypto.exportPublicKey(pub)

            let user = try await api.register(
                userId: uid,
                username: username,
                displayName: displayName,
                publicKey: pubB64
            )

            save(user)
            currentUser = user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
            crypto.deletePrivateKey()
        }

        isLoading = false
    }

    // MARK: - Login (verify existing key pair on server)

    func login() async {
        isLoading = true
        error = nil

        do {
            let pub = try crypto.getPublicKey()
            let uid = try crypto.userId(from: pub)
            let user = try await api.getUser(id: uid)
            save(user)
            currentUser = user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Logout

    func logout() {
        crypto.deletePrivateKey()
        UserDefaults.standard.removeObject(forKey: "currentUser")
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Helpers

    private func save(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "currentUser")
        }
    }
}
