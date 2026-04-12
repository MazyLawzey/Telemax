import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Apps Script URL is not configured"
        case .serverError(let m):  return m
        case .decodingError(let e): return e.localizedDescription
        }
    }
}

/// Thin HTTP client that talks to the Google Apps Script web-app proxy.
final class SheetsService {
    static let shared = SheetsService()

    private let session = URLSession.shared
    private lazy var uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "appsScriptURL") ?? ""
    }

    private init() {}

    func setBaseURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "appsScriptURL")
    }

    var isConfigured: Bool { !baseURL.isEmpty }

    // MARK: - Generic request helpers

    struct APIResponse<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let error: String?
    }

    private func get<T: Decodable>(_ action: String, params: [String: String] = [:]) async throws -> T {
        guard var comps = URLComponents(string: baseURL) else { throw APIError.invalidURL }
        var items = [URLQueryItem(name: "action", value: action)]
        for (k, v) in params { items.append(.init(name: k, value: v)) }
        comps.queryItems = items

        guard let url = comps.url else { throw APIError.invalidURL }
        let (data, _) = try await session.data(from: url)
        return try decode(data)
    }

    private func post<T: Decodable>(_ action: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: baseURL) else { throw APIError.invalidURL }

        var dict = body
        dict["action"] = action

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: dict)

        let (data, _) = try await session.data(for: req)
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let resp = try JSONDecoder().decode(APIResponse<T>.self, from: data)
        if let err = resp.error, !resp.success { throw APIError.serverError(err) }
        guard let value = resp.data else { throw APIError.serverError("Empty response") }
        return value
    }

    // MARK: - Users

    func register(userId: String, username: String, displayName: String, publicKey: String) async throws -> User {
        try await post("register", body: [
            "userId":      userId,
            "username":    username,
            "displayName": displayName,
            "publicKey":   publicKey,
            "createdAt":   Date().timeIntervalSince1970 * 1000
        ])
    }

    func getUser(id: String) async throws -> User {
        try await get("getUser", params: ["userId": id])
    }

    func searchUsers(query: String) async throws -> [User] {
        try await get("searchUsers", params: ["query": query])
    }

    // MARK: - Messages

    func sendMessage(_ msg: EncryptedMessage) async throws {
        let data = try JSONEncoder().encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let _: String = try await post("sendMessage", body: dict)
    }

    func getMessages(chatId: String, since: Double) async throws -> [EncryptedMessage] {
        try await get("getMessages", params: [
            "chatId": chatId,
            "since":  String(Int(since))
        ])
    }

    func getChats(userId: String) async throws -> [Chat] {
        try await get("getChats", params: ["userId": userId])
    }

    func editMessage(messageId: String, senderId: String, encryptedKeys: [String: String], encryptedContent: String) async throws {
        let _: String = try await post("editMessage", body: [
            "messageId": messageId,
            "senderId": senderId,
            "encryptedKeys": encryptedKeys,
            "encryptedContent": encryptedContent
        ])
    }

    func deleteMessage(messageId: String, senderId: String, forEveryone: Bool) async throws {
        let _: String = try await post("deleteMessage", body: [
            "messageId": messageId,
            "senderId": senderId,
            "forEveryone": forEveryone
        ])
    }

    func deleteChat(chatId: String) async throws {
        let _: String = try await post("deleteChat", body: ["chatId": chatId])
    }

    // MARK: - Groups

    func createGroup(_ group: ChatGroup) async throws -> ChatGroup {
        let data = try JSONEncoder().encode(group)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return try await post("createGroup", body: dict)
    }

    func getGroups(userId: String) async throws -> [ChatGroup] {
        try await get("getGroups", params: ["userId": userId])
    }

    func updateGroup(groupId: String, requesterId: String, name: String) async throws {
        let _: String = try await post("updateGroup", body: [
            "groupId": groupId, "requesterId": requesterId, "name": name
        ])
    }

    func addGroupMember(groupId: String, userId: String) async throws {
        let _: String = try await post("addGroupMember", body: [
            "groupId": groupId, "userId": userId
        ])
    }

    func removeGroupMember(groupId: String, userId: String, requesterId: String) async throws {
        let _: String = try await post("removeGroupMember", body: [
            "groupId": groupId, "userId": userId, "requesterId": requesterId
        ])
    }

    func setGroupAdmin(groupId: String, requesterId: String, newAdminId: String) async throws {
        let _: String = try await post("setGroupAdmin", body: [
            "groupId": groupId, "requesterId": requesterId, "newAdminId": newAdminId
        ])
    }

    // MARK: - Read Receipts

    func markRead(messageIds: [String], userId: String) async throws {
        let _: String = try await post("markRead", body: [
            "messageIds": messageIds,
            "userId": userId
        ])
    }

    // MARK: - Files (Google Drive via Apps Script)

    func uploadFile(data: Data, fileName: String, mimeType: String) async throws -> String {
        guard let url = URL(string: baseURL) else { throw APIError.invalidURL }

        let dict: [String: Any] = [
            "action": "uploadFile",
            "fileData": data.base64EncodedString(),
            "fileName": fileName,
            "mimeType": mimeType
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: dict)

        let (resData, _) = try await uploadSession.data(for: req)
        return try decode(resData)
    }

    func fileURL(fileId: String) -> String {
        "https://drive.google.com/uc?export=view&id=\(fileId)"
    }
}
