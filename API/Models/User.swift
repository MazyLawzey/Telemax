import Foundation

struct User: Codable, Identifiable {
    let id: String              // SHA-256 hash of public key
    var username: String
    var displayName: String
    var publicKey: String       // Base64-encoded DER
    var avatarFileId: String?
    let createdAt: Double       // milliseconds since 1970
    var lastSeen: Double?       // milliseconds since 1970
    
    // Computed property: is user currently online (within 2 minutes)
    var isOnline: Bool {
        guard let last = lastSeen else { return false }
        let now = Date().timeIntervalSince1970 * 1000
        return (now - last) < 2 * 60 * 1000  // 2 minutes in milliseconds
    }
    
    // Computed property: formatted "last seen" text
    var lastSeenText: String {
        guard let last = lastSeen else { return "Never" }
        if isOnline { return "Online" }
        
        let now = Date().timeIntervalSince1970 * 1000
        let diffMs = now - last
        let diffSec = Int(diffMs / 1000)
        let diffMin = diffSec / 60
        let diffHour = diffMin / 60
        let diffDay = diffHour / 24
        
        if diffSec < 60 { return "Just now" }
        if diffMin < 60 { return "\(diffMin)m ago" }
        if diffHour < 24 { return "\(diffHour)h ago" }
        return "\(diffDay)d ago"
    }
}
