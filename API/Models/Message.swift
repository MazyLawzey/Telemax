import Foundation

struct EncryptedMessage: Codable, Identifiable {
    let id: String
    let chatId: String
    let senderId: String
    let encryptedKeys: [String: String]     // userId -> base64 RSA-encrypted AES key
    var encryptedContent: String            // base64 AES-GCM ciphertext
    let timestamp: Double                   // milliseconds since 1970
    let type: MessageType
    var fileId: String?
    var isEdited: Bool?
    var isDeleted: Bool?
    var readBy: [String]?

    enum MessageType: String, Codable {
        case text
        case image
        case file
    }
}

struct DecryptedMessage: Identifiable {
    let id: String
    let chatId: String
    let senderId: String
    var content: String
    let timestamp: Date
    let type: EncryptedMessage.MessageType
    var fileId: String?
    var senderName: String?
    var isEdited: Bool
    var isDeleted: Bool
    var readBy: [String]
}
