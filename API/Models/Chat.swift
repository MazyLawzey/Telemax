import Foundation

struct Chat: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let isGroup: Bool
    var participants: [String]
    var groupName: String?
    var lastMessage: String?
    var lastMessageTime: Double?    // milliseconds since 1970
}
