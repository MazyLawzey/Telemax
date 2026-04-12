import SwiftUI

struct NewGroupView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var selectedMembers: [User] = []
    @State private var isCreating = false
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Group name
                TextField("Group Name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Selected members
                if !selectedMembers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedMembers) { user in
                                HStack(spacing: 4) {
                                    Text(user.displayName)
                                        .font(.caption)
                                    Button {
                                        selectedMembers.removeAll { $0.id == user.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                Divider()

                // Search members
                TextField("Search users…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .onChange(of: searchText) {
                        Task { await search() }
                    }

                // Results
                List(searchResults) { user in
                    Button {
                        toggleMember(user)
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .foregroundStyle(.accent)

                            VStack(alignment: .leading) {
                                Text(user.displayName).font(.headline)
                                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedMembers.contains(where: { $0.id == user.id }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .listStyle(.plain)
            }
            .navigationTitle("New Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await createGroup() }
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(groupName.isEmpty || selectedMembers.isEmpty || isCreating)
                }
            }
        }
    }

    private func search() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; return }

        isSearching = true
        do {
            let all = try await SheetsService.shared.searchUsers(query: q)
            searchResults = all.filter { $0.id != auth.currentUser?.id }
        } catch {
            print("[NewGroupView] search error: \(error)")
        }
        isSearching = false
    }

    private func toggleMember(_ user: User) {
        if let idx = selectedMembers.firstIndex(where: { $0.id == user.id }) {
            selectedMembers.remove(at: idx)
        } else {
            selectedMembers.append(user)
        }
    }

    private func createGroup() async {
        guard let myId = auth.currentUser?.id else { return }
        isCreating = true

        do {
            var memberIds = selectedMembers.map(\.id)
            memberIds.append(myId)

            let group = try await chatManager.createGroup(
                name: groupName,
                members: memberIds,
                adminId: myId
            )

            // Add group chat to list
            let chat = Chat(
                id: group.id,
                isGroup: true,
                participants: memberIds,
                groupName: group.name,
                lastMessage: nil,
                lastMessageTime: nil
            )
            chatManager.chats.insert(chat, at: 0)
            dismiss()
        } catch {
            print("[NewGroupView] create error: \(error)")
        }
        isCreating = false
    }
}
