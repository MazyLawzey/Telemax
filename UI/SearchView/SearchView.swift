//
//  SearchView.swift
//  Telemax
//
//  Created by Mazy Lawzey on 05.04.2026.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var chatManager: ChatManager

    @State private var searchText = ""
    @State private var results: [User] = []
    @State private var isSearching = false
    @State private var selectedChat: Chat?

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Find people to chat with")
                            .foregroundStyle(.secondary)
                    }
                } else if isSearching {
                    ProgressView()
                } else {
                    List(results) { user in
                        Button {
                            startChat(with: user)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.headline)
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "bubble.left.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Username or name…")
            .onChange(of: searchText) {
                Task { await search() }
            }
            .navigationDestination(item: $selectedChat) { chat in
                ConversationView(chat: chat)
            }
        }
    }

    private func search() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; return }

        isSearching = true
        do {
            let all = try await SheetsService.shared.searchUsers(query: q)
            results = all.filter { $0.id != auth.currentUser?.id }
        } catch {
            print("[SearchView] search error: \(error)")
        }
        isSearching = false
    }

    private func startChat(with user: User) {
        guard let myId = auth.currentUser?.id else { return }
        let chatId = ChatManager.dmChatId(user1: myId, user2: user.id)
        let chat = Chat(
            id: chatId,
            isGroup: false,
            participants: [myId, user.id],
            groupName: nil,
            lastMessage: nil,
            lastMessageTime: nil
        )
        // Add to chats list if not already there
        if !chatManager.chats.contains(where: { $0.id == chatId }) {
            chatManager.chats.insert(chat, at: 0)
        }
        // Store contact name for display
        chatManager.contactNames[user.id] = user.displayName
        // Navigate to conversation
        selectedChat = chat
    }
}

#Preview {
    SearchView()
        .environmentObject(AuthManager.shared)
        .environmentObject(ChatManager())
}
