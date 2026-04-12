import SwiftUI

struct GroupSettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    let group: ChatGroup

    @State private var groupName: String = ""
    @State private var members: [User] = []
    @State private var isLoading = true
    @State private var showAddMember = false
    @State private var searchText = ""
    @State private var searchResults: [User] = []

    private var isAdmin: Bool {
        auth.currentUser?.id == group.adminId
    }

    var body: some View {
        List {
            // Group info
            Section("Group Info") {
                if isAdmin {
                    HStack {
                        TextField("Group Name", text: $groupName)
                        Button("Save") {
                            Task { await renameGroup() }
                        }
                        .disabled(groupName.isEmpty || groupName == group.name)
                    }
                } else {
                    Text(group.name)
                        .font(.headline)
                }

                LabeledContent("Admin") {
                    Text(group.adminId == auth.currentUser?.id ? "You" : String((group.adminId ?? "unknown").prefix(8)))
                        .font(.caption)
                }
            }

            // Members
            Section("Members (\(members.count))") {
                ForEach(members) { user in
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(user.displayName).font(.subheadline)
                                if user.id == group.adminId {
                                    Text("Admin")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isAdmin && user.id != auth.currentUser?.id {
                            Menu {
                                Button {
                                    Task { await makeAdmin(user.id) }
                                } label: {
                                    Label("Make Admin", systemImage: "star")
                                }
                                Button(role: .destructive) {
                                    Task { await removeMember(user.id) }
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if isAdmin {
                    Button {
                        showAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                }
            }

            // Leave / Delete
            Section {
                Button(role: .destructive) {
                    Task { await leaveGroup() }
                } label: {
                    Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Group Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            groupName = group.name
            await loadMembers()
        }
        .sheet(isPresented: $showAddMember) {
            addMemberSheet
        }
    }

    // MARK: - Add Member Sheet

    private var addMemberSheet: some View {
        NavigationView {
            VStack {
                TextField("Search users…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: searchText) {
                        Task { await searchUsers() }
                    }

                List(searchResults) { user in
                    Button {
                        Task {
                            try? await chatManager.addGroupMember(groupId: group.id, userId: user.id)
                            showAddMember = false
                            await loadMembers()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.accent)
                            Text(user.displayName)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.accent)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Member")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddMember = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadMembers() async {
        isLoading = true
        var loaded: [User] = []
        for uid in group.members {
            if let user = try? await SheetsService.shared.getUser(id: uid) {
                loaded.append(user)
            }
        }
        members = loaded
        isLoading = false
    }

    private func renameGroup() async {
        guard let uid = auth.currentUser?.id else { return }
        try? await chatManager.updateGroupName(groupId: group.id, requesterId: uid, name: groupName)
    }

    private func removeMember(_ userId: String) async {
        guard let uid = auth.currentUser?.id else { return }
        try? await chatManager.removeGroupMember(groupId: group.id, userId: userId, requesterId: uid)
        members.removeAll { $0.id == userId }
    }

    private func makeAdmin(_ userId: String) async {
        guard let uid = auth.currentUser?.id else { return }
        try? await chatManager.setGroupAdmin(groupId: group.id, requesterId: uid, newAdminId: userId)
    }

    private func leaveGroup() async {
        guard let uid = auth.currentUser?.id else { return }
        try? await chatManager.removeGroupMember(groupId: group.id, userId: uid, requesterId: uid)
        dismiss()
    }

    private func searchUsers() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; return }
        do {
            let all = try await SheetsService.shared.searchUsers(query: q)
            searchResults = all.filter { user in
                !group.members.contains(user.id)
            }
        } catch {
            print("[GroupSettingsView] search error: \(error)")
        }
    }
}
