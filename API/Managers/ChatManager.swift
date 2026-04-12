import Foundation
import Combine

@MainActor
final class ChatManager: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var currentMessages: [DecryptedMessage] = []
    @Published var isLoading = false
    @Published var contactNames: [String: String] = [:]
    @Published var userPresence: [String: User] = [:]  // userId -> User (with lastSeen info)

    private let crypto = CryptoService.shared
    private let api    = SheetsService.shared

    private var pollingTimer: Timer?
    private var chatsPollingTimer: Timer?
    private var presencePollingTimer: Timer?
    private var currentChatId: String?
    private var lastFetchMs: Double = 0

    private var publicKeyCache: [String: SecKey] = [:]
    private var userCache: [String: User] = [:]

    // Pending message IDs (optimistic, not yet confirmed by server)
    private var pendingMessageIds: Set<String> = []

    init() {
        loadChatsFromCache()
    }

    // MARK: - Cache keys

    private let chatsCacheKey = "cachedChats"
    private func messagesCacheKey(for chatId: String) -> String { "cachedMessages_\(chatId)" }

    // MARK: - Chat list

    func loadChats(userId: String) async {
        do {
            let loadedChats = try await api.getChats(userId: userId)
            let groups = (try? await api.getGroups(userId: userId)) ?? []
            let merged = mergeChatsAndGroups(loadedChats, groups: groups)

            if merged != chats {
                chats = merged
                saveChatsToCache()
            }

            // Resolve display names for DM participants
            for chat in merged where !chat.isGroup {
                let others = chat.participants.filter { $0 != userId }
                for uid in others where contactNames[uid] == nil {
                    if let name = try? await fetchUserName(uid) {
                        contactNames[uid] = name
                    }
                }
            }
        } catch {
            print("[ChatManager] loadChats error: \(error)")
        }
    }

    func startChatsPolling(userId: String) {
        stopChatsPolling()
        chatsPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadChats(userId: userId)
            }
        }
        Task { await loadChats(userId: userId) }
    }

    func stopChatsPolling() {
        chatsPollingTimer?.invalidate()
        chatsPollingTimer = nil
    }

    // MARK: - Open / close chat

    func openChat(_ chatId: String) {
        currentChatId = chatId
        loadMessagesFromCache(chatId: chatId)
        lastFetchMs = 0
        startPolling()
        startPresencePolling(for: chatId)
    }

    func closeChat() {
        if let chatId = currentChatId {
            saveMessagesToCache(chatId: chatId)
        }
        stopPolling()
        stopPresencePolling()
        currentChatId = nil
        currentMessages = []
    }

    // MARK: - Send (optimistic + fire-and-forget)

    func sendMessage(
        content: String,
        chatId: String,
        participants: [String],
        currentUserId: String,
        type: EncryptedMessage.MessageType = .text,
        fileId: String? = nil
    ) {
        let msgId = UUID().uuidString
        let now = Date()

        // 1. Optimistic insert — message appears instantly
        let optimistic = DecryptedMessage(
            id: msgId,
            chatId: chatId,
            senderId: currentUserId,
            content: content,
            timestamp: now,
            type: type,
            fileId: fileId,
            senderName: AuthManager.shared.currentUser?.displayName,
            isEdited: false,
            isDeleted: false,
            readBy: [currentUserId]
        )
        currentMessages.append(optimistic)
        pendingMessageIds.insert(msgId)

        // 2. Fire-and-forget — encrypt and send in background
        Task { [weak self] in
            guard let self else { return }
            do {
                var keys: [String: SecKey] = [:]
                for uid in participants {
                    keys[uid] = try await self.fetchPublicKey(uid)
                }
                keys[currentUserId] = try self.crypto.getPublicKey()

                guard let data = content.data(using: .utf8) else { return }
                let (encKeys, encContent) = try self.crypto.encrypt(message: data, forRecipients: keys)

                let msg = EncryptedMessage(
                    id: msgId,
                    chatId: chatId,
                    senderId: currentUserId,
                    encryptedKeys: encKeys,
                    encryptedContent: encContent,
                    timestamp: now.timeIntervalSince1970 * 1000,
                    type: type,
                    fileId: fileId
                )

                try await self.api.sendMessage(msg)
                self.pendingMessageIds.remove(msgId)
            } catch {
                print("[ChatManager] send error: \(error)")
                // Mark as failed — could add UI indicator later
                self.pendingMessageIds.remove(msgId)
            }
        }
    }

    // MARK: - Fetch

    func fetchMessages(currentUserId: String) async {
        guard let chatId = currentChatId else { return }
        do {
            let encrypted = try await api.getMessages(chatId: chatId, since: lastFetchMs)

            // User switched chats while we were awaiting — discard results
            guard currentChatId == chatId else { return }

            var decrypted: [DecryptedMessage] = []
            for msg in encrypted {
                // Check again inside loop (fetchUserName is async)
                guard currentChatId == chatId else { return }

                if msg.isDeleted == true {
                    decrypted.append(DecryptedMessage(
                        id: msg.id, chatId: msg.chatId, senderId: msg.senderId,
                        content: "This message was deleted", timestamp: Date(timeIntervalSince1970: msg.timestamp / 1000),
                        type: msg.type, fileId: nil, senderName: try? await fetchUserName(msg.senderId),
                        isEdited: false, isDeleted: true, readBy: msg.readBy ?? []
                    ))
                    continue
                }
                guard let ek = msg.encryptedKeys[currentUserId] else { continue }
                do {
                    let plain = try crypto.decrypt(encryptedContent: msg.encryptedContent, encryptedKey: ek)
                    let text  = String(data: plain, encoding: .utf8) ?? ""
                    let name  = try? await fetchUserName(msg.senderId)
                    decrypted.append(DecryptedMessage(
                        id: msg.id,
                        chatId: msg.chatId,
                        senderId: msg.senderId,
                        content: text,
                        timestamp: Date(timeIntervalSince1970: msg.timestamp / 1000),
                        type: msg.type,
                        fileId: msg.fileId,
                        senderName: name,
                        isEdited: msg.isEdited ?? false,
                        isDeleted: false,
                        readBy: msg.readBy ?? []
                    ))
                } catch {
                    print("[ChatManager] decrypt error: \(error)")
                }
            }

            // Final check before mutating state
            guard currentChatId == chatId else { return }

            // Merge: replace pending with server-confirmed, add truly new
            let existingIDs = Set(currentMessages.map { $0.id })
            for msg in decrypted {
                if existingIDs.contains(msg.id) {
                    // Replace optimistic with server version
                    if let idx = currentMessages.firstIndex(where: { $0.id == msg.id }) {
                        currentMessages[idx] = msg
                    }
                } else {
                    currentMessages.append(msg)
                }
            }
            currentMessages.sort { $0.timestamp < $1.timestamp }

            if let last = encrypted.last { lastFetchMs = last.timestamp }

            // Mark unread messages as read
            let unreadIds = decrypted
                .filter { $0.senderId != currentUserId && !$0.readBy.contains(currentUserId) }
                .map { $0.id }
            if !unreadIds.isEmpty {
                Task {
                    try? await api.markRead(messageIds: unreadIds, userId: currentUserId)
                    // Update local state
                    for id in unreadIds {
                        if let idx = currentMessages.firstIndex(where: { $0.id == id }) {
                            if !currentMessages[idx].readBy.contains(currentUserId) {
                                currentMessages[idx].readBy.append(currentUserId)
                            }
                        }
                    }
                }
            }

            saveMessagesToCache(chatId: chatId)
        } catch {
            print("[ChatManager] fetchMessages error: \(error)")
        }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let uid = AuthManager.shared.currentUser?.id else { return }
                await self.fetchMessages(currentUserId: uid)
            }
        }
        Task {
            guard let uid = AuthManager.shared.currentUser?.id else { return }
            await fetchMessages(currentUserId: uid)
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Helpers

    static func dmChatId(user1: String, user2: String) -> String {
        [user1, user2].sorted().joined(separator: "-")
    }

    // MARK: - Edit Message

    func editMessage(
        messageId: String,
        newContent: String,
        chatId: String,
        participants: [String],
        currentUserId: String
    ) {
        // Optimistic update
        if let idx = currentMessages.firstIndex(where: { $0.id == messageId }) {
            currentMessages[idx].content = newContent
            currentMessages[idx].isEdited = true
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                var keys: [String: SecKey] = [:]
                for uid in participants {
                    keys[uid] = try await self.fetchPublicKey(uid)
                }
                keys[currentUserId] = try self.crypto.getPublicKey()

                guard let data = newContent.data(using: .utf8) else { return }
                let (encKeys, encContent) = try self.crypto.encrypt(message: data, forRecipients: keys)

                try await self.api.editMessage(
                    messageId: messageId,
                    senderId: currentUserId,
                    encryptedKeys: encKeys,
                    encryptedContent: encContent
                )
            } catch {
                print("[ChatManager] edit error: \(error)")
            }
        }
    }

    // MARK: - Delete Message

    func deleteMessage(messageId: String, senderId: String, forEveryone: Bool) {
        currentMessages.removeAll { $0.id == messageId }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteMessage(messageId: messageId, senderId: senderId, forEveryone: forEveryone)
            } catch {
                print("[ChatManager] delete error: \(error)")
            }
        }
    }

    // MARK: - Delete Chat

    func deleteChat(chatId: String) async throws {
        try await api.deleteChat(chatId: chatId)
        chats.removeAll { $0.id == chatId }
        clearMessagesCache(chatId: chatId)
        saveChatsToCache()
    }

    // MARK: - Groups

    func createGroup(name: String, members: [String], adminId: String) async throws -> ChatGroup {
        let group = ChatGroup(
            id: UUID().uuidString,
            name: name,
            members: members,
            adminId: adminId,
            createdAt: Date().timeIntervalSince1970 * 1000,
            avatarFileId: nil
        )
        return try await api.createGroup(group)
    }

    func updateGroupName(groupId: String, requesterId: String, name: String) async throws {
        try await api.updateGroup(groupId: groupId, requesterId: requesterId, name: name)
    }

    func addGroupMember(groupId: String, userId: String) async throws {
        try await api.addGroupMember(groupId: groupId, userId: userId)
    }

    func removeGroupMember(groupId: String, userId: String, requesterId: String) async throws {
        try await api.removeGroupMember(groupId: groupId, userId: userId, requesterId: requesterId)
    }

    func setGroupAdmin(groupId: String, requesterId: String, newAdminId: String) async throws {
        try await api.setGroupAdmin(groupId: groupId, requesterId: requesterId, newAdminId: newAdminId)
    }

    // MARK: - Cache: Chats

    private func saveChatsToCache() {
        if let data = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(data, forKey: chatsCacheKey)
        }
    }

    private func loadChatsFromCache() {
        guard let data = UserDefaults.standard.data(forKey: chatsCacheKey),
              let cached = try? JSONDecoder().decode([Chat].self, from: data) else { return }
        chats = cached
    }

    // MARK: - Cache: Messages

    private struct CachedMessage: Codable {
        let id, chatId, senderId, content: String
        let timestamp: Double
        let type: EncryptedMessage.MessageType
        let fileId: String?
        let senderName: String?
        let isEdited, isDeleted: Bool
        let readBy: [String]
    }

    private func saveMessagesToCache(chatId: String) {
        let cached = currentMessages.map {
            CachedMessage(
                id: $0.id, chatId: $0.chatId, senderId: $0.senderId, content: $0.content,
                timestamp: $0.timestamp.timeIntervalSince1970, type: $0.type,
                fileId: $0.fileId, senderName: $0.senderName,
                isEdited: $0.isEdited, isDeleted: $0.isDeleted,
                readBy: $0.readBy
            )
        }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: messagesCacheKey(for: chatId))
        }
    }

    private func loadMessagesFromCache(chatId: String) {
        guard let data = UserDefaults.standard.data(forKey: messagesCacheKey(for: chatId)),
              let cached = try? JSONDecoder().decode([CachedMessage].self, from: data) else {
            currentMessages = []
            return
        }
        currentMessages = cached.map {
            DecryptedMessage(
                id: $0.id, chatId: $0.chatId, senderId: $0.senderId, content: $0.content,
                timestamp: Date(timeIntervalSince1970: $0.timestamp), type: $0.type,
                fileId: $0.fileId, senderName: $0.senderName,
                isEdited: $0.isEdited, isDeleted: $0.isDeleted,
                readBy: $0.readBy
            )
        }
    }

    private func clearMessagesCache(chatId: String) {
        UserDefaults.standard.removeObject(forKey: messagesCacheKey(for: chatId))
    }

    // MARK: - Private helpers

    private func fetchPublicKey(_ userId: String) async throws -> SecKey {
        if let cached = publicKeyCache[userId] { return cached }
        let user = try await api.getUser(id: userId)
        let key  = try crypto.importPublicKey(from: user.publicKey)
        publicKeyCache[userId] = key
        userCache[userId] = user
        userPresence[userId] = user  // Update presence cache
        return key
    }

    private func fetchUserName(_ userId: String) async throws -> String {
        if let cached = userCache[userId] { return cached.displayName }
        let user = try await api.getUser(id: userId)
        userCache[userId] = user
        userPresence[userId] = user  // Update presence cache
        return user.displayName
    }

    // MARK: - Presence Polling

    private func startPresencePolling(for chatId: String) {
        stopPresencePolling()
        guard let chat = chats.first(where: { $0.id == chatId }) else { return }
        
        // Fetch initial presence for all participants
        for uid in chat.participants {
            Task {
                if let user = try? await self.api.getUser(id: uid) {
                    await MainActor.run {
                        self.userPresence[uid] = user
                    }
                }
            }
        }
        
        // Poll every 5 seconds to get fresh lastSeen data
        presencePollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshPresence(for: chatId)
            }
        }
    }

    private func stopPresencePolling() {
        presencePollingTimer?.invalidate()
        presencePollingTimer = nil
    }

    private func refreshPresence(for chatId: String) async {
        guard let chat = chats.first(where: { $0.id == chatId }) else { return }
        
        for uid in chat.participants {
            do {
                let user = try await api.getUser(id: uid)
                userPresence[uid] = user
            } catch {
                print("[ChatManager] refreshPresence error for \(uid): \(error)")
            }
        }
    }

    private func mergeChatsAndGroups(_ loadedChats: [Chat], groups: [ChatGroup]) -> [Chat] {
        var merged = loadedChats
        let existingIds = Set(merged.map(\.id))

        for group in groups where !existingIds.contains(group.id) {
            merged.append(Chat(
                id: group.id,
                isGroup: true,
                participants: group.members,
                groupName: group.name,
                lastMessage: nil,
                lastMessageTime: group.createdAt
            ))
        }

        merged.sort { ($0.lastMessageTime ?? 0) > ($1.lastMessageTime ?? 0) }
        return merged
    }
}
