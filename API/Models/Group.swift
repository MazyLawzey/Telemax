import Foundation

struct ChatGroup: Codable, Identifiable {
    let id: String
    var name: String
    var members: [String]
    var adminId: String?
    let createdAt: Double       // milliseconds since 1970
    var avatarFileId: String?
}
