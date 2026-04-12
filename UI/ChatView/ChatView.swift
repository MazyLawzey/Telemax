//
//  ChatView.swift
//  Telemax
//
//  Created by Mazy Lawzey on 05.04.2026.
//

import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var chatManager: ChatManager
    @State private var showProfile = false
    @State private var showNewGroup = false

    var body: some View {
        NavigationStack {
            Group {
                if chatManager.chats.isEmpty && !chatManager.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("No chats yet")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Search for users to start chatting")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        ForEach(chatManager.chats) { chat in
                            NavigationLink {
                                ConversationView(chat: chat)
                            } label: {
                                ChatRowView(chat: chat, currentUserId: auth.currentUser?.id ?? "", contactNames: chatManager.contactNames, userPresence: chatManager.userPresence)
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                let chat = chatManager.chats[idx]
                                Task {
                                    try? await chatManager.deleteChat(chatId: chat.id)
                                }
                            }
                        }
                    }
                    .refreshable {
                        if let uid = auth.currentUser?.id {
                            await chatManager.loadChats(userId: uid)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showNewGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button {
                        showNewGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                #endif
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {}) {
                            Text("Switch Account")
                            Image(systemName: "arrow.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } primaryAction: {
                        showProfile = true
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: {}) {
                            Text("Switch Account")
                            Image(systemName: "arrow.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } primaryAction: {
                        showProfile = true
                    }
                }
                #endif
            }
            .onAppear {
                if let uid = auth.currentUser?.id {
                    chatManager.startChatsPolling(userId: uid)
                }
            }
            .onDisappear {
                chatManager.stopChatsPolling()
            }
            .sheet(isPresented: $showNewGroup) {
                NewGroupView()
            }
        }
    }
}

// MARK: - Chat Row

struct ChatRowView: View {
    let chat: Chat
    let currentUserId: String
    var contactNames: [String: String] = [:]
    var userPresence: [String: User] = [:]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chat.isGroup ? "person.3.fill" : "person.circle.fill")
                .resizable()
                .frame(width: 44, height: 44)
                .foregroundStyle(.accent)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chatTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // Show online status for direct messages
                    if !chat.isGroup {
                        let others = chat.participants.filter { $0 != currentUserId }
                        if let otherId = others.first, let user = userPresence[otherId] {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(user.isOnline ? Color.green : Color.gray)
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }

                if let last = chat.lastMessage {
                    Text(last)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let ts = chat.lastMessageTime {
                Text(formatTime(ts))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var chatTitle: String {
        if let name = chat.groupName { return name }
        let others = chat.participants.filter { $0 != currentUserId }
        if let otherId = others.first, let name = contactNames[otherId] {
            return name
        }
        return others.first?.prefix(8).description ?? "Chat"
    }

    private func formatTime(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    ChatView()
        .environmentObject(AuthManager.shared)
        .environmentObject(ChatManager())
}
