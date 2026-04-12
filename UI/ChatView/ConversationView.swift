import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
private let systemGray6 = NSColor.quaternarySystemFill
#else
import UIKit
private let systemGray6 = UIColor.systemGray6
#endif

struct ConversationView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var chatManager: ChatManager

    let chat: Chat
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showAttachMenu = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var editingMessage: DecryptedMessage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(chatManager.currentMessages) { msg in
                            messageBubble(for: msg)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chatManager.currentMessages.count) {
                    if let last = chatManager.currentMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Edit mode banner
            if editingMessage != nil {
                Divider()
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(.accent)
                    Text("Editing message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingMessage = nil
                        messageText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(systemGray6))
            }
            
            // Input bar
            messageComposer
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                chatTitleView
            }
        }
        #else
        .navigationTitle(chatTitle)
        #endif
        .onAppear {
            chatManager.openChat(chat.id)
        }
        .onDisappear {
            chatManager.closeChat()
        }
        .onChange(of: selectedPhoto) {
            if let item = selectedPhoto {
                Task { await uploadPhoto(item) }
                selectedPhoto = nil
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { urls in
                if let url = urls.first {
                    Task { await uploadFile(url) }
                }
            }
        }
        #endif
    }

    @State private var showAttachSheet = false

    private var messageComposer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                // Attach file button
                Button {
                    showAttachSheet = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 22))
                        .foregroundStyle(.accent)
                        .frame(width: 32, height: 32)
                }
                .padding(.bottom, 4)
                .confirmationDialog("Attach", isPresented: $showAttachSheet) {
                    Button("File") {
                        pickFile()
                    }
                }

                // Photo picker
                PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.accent)
                        .frame(width: 32, height: 32)
                }
                .padding(.bottom, 4)

                // Text field
                TextField("Message…", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Send / confirm edit button
                Button {
                    if editingMessage != nil {
                        submitEdit()
                    } else {
                        sendMessage()
                    }
                } label: {
                    if isSending {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: editingMessage != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accent)
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background)
        }
    }

    private var chatTitle: String {
        if let name = chat.groupName { return name }
        let others = chat.participants.filter { $0 != auth.currentUser?.id }
        if let otherId = others.first, let name = chatManager.contactNames[otherId] {
            return name
        }
        return others.first?.prefix(8).description ?? "Chat"
    }

    private var chatTitleView: some View {
        VStack(spacing: 2) {
            Text(chatTitle)
                .font(.system(size: 16, weight: .semibold))
            
            // Show status only for DM chats, not groups
            if !chat.isGroup {
                let others = chat.participants.filter { $0 != auth.currentUser?.id }
                if let otherId = others.first, let user = chatManager.userPresence[otherId] {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(user.isOnline ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        
                        Text(user.lastSeenText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Loading…")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func messageBubble(for msg: DecryptedMessage) -> some View {
        let isMe = msg.senderId == auth.currentUser?.id
        
        return MessageBubbleView(
            message: msg,
            isMe: isMe,
            onEdit: { handleEditMessage(msg) },
            onDeleteForMe: { handleDeleteForMe(msg) },
            onDeleteForEveryone: { handleDeleteForEveryone(msg) },
            onCopy: { handleCopyMessage(msg) }
        )
        .id(msg.id)
        .draggable(msg.content)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let uid = auth.currentUser?.id else { return }
        messageText = ""

        chatManager.sendMessage(
            content: text,
            chatId: chat.id,
            participants: chat.participants,
            currentUserId: uid
        )
    }

    private func submitEdit() {
        guard let editing = editingMessage else { return }
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let uid = auth.currentUser?.id else { return }
        messageText = ""
        editingMessage = nil

        chatManager.editMessage(
            messageId: editing.id,
            newContent: text,
            chatId: chat.id,
            participants: chat.participants,
            currentUserId: uid
        )
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        guard let uid = auth.currentUser?.id else { return }
        isSending = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not load the selected photo."
                isSending = false
                return
            }

            // Compress to JPEG for reliable upload
            let jpegData: Data
            #if os(macOS)
            if let nsImage = NSImage(data: data),
               let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let compressed = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                jpegData = compressed
            } else {
                jpegData = data
            }
            #else
            if let uiImage = UIImage(data: data),
               let compressed = uiImage.jpegData(compressionQuality: 0.7) {
                jpegData = compressed
            } else {
                jpegData = data
            }
            #endif

            let fileId = try await SheetsService.shared.uploadFile(
                data: jpegData, fileName: "photo_\(UUID().uuidString).jpg", mimeType: "image/jpeg"
            )
            chatManager.sendMessage(
                content: "📷 Photo",
                chatId: chat.id,
                participants: chat.participants,
                currentUserId: uid,
                type: .image,
                fileId: fileId
            )
        } catch {
            errorMessage = "Photo upload failed: \(error.localizedDescription)"
        }
        isSending = false
    }

    private func uploadFile(_ url: URL) async {
        guard let uid = auth.currentUser?.id else { return }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isSending = true
        do {
            let data = try Data(contentsOf: url)
            let mime = url.mimeType
            let fileId = try await SheetsService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent, mimeType: mime
            )
            chatManager.sendMessage(
                content: "📎 \(url.lastPathComponent)",
                chatId: chat.id,
                participants: chat.participants,
                currentUserId: uid,
                type: .file,
                fileId: fileId
            )
        } catch {
            errorMessage = "File upload failed: \(error.localizedDescription)"
        }
        isSending = false
    }

    private func pickFile() {
        #if os(iOS)
        showDocumentPicker = true
        #else
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await uploadFile(url) }
        }
        #endif
    }

    private func handleEditMessage(_ message: DecryptedMessage) {
        editingMessage = message
        messageText = message.content
    }

    private func handleDeleteForMe(_ message: DecryptedMessage) {
        chatManager.deleteMessage(
            messageId: message.id,
            senderId: auth.currentUser?.id ?? "",
            forEveryone: false
        )
    }

    private func handleDeleteForEveryone(_ message: DecryptedMessage) {
        chatManager.deleteMessage(
            messageId: message.id,
            senderId: auth.currentUser?.id ?? "",
            forEveryone: true
        )
    }

    private func handleCopyMessage(_ message: DecryptedMessage) {
        #if os(iOS)
        UIPasteboard.general.string = message.content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
    }
}

// MARK: - Document Picker

#if os(iOS)
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
#endif

// MARK: - URL MIME helper

extension URL {
    var mimeType: String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "pdf":         return "application/pdf"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        default:            return "application/octet-stream"
        }
    }
}


#Preview {
    let auth = AuthManager()
    auth.currentUser = User(
        id: "f37aa3c1068fc54e3e82283c9c4da742831cae298beaa513d3d464e656b79276",
        username: "mazylawzey",
        displayName: "Mazy",
        publicKey: "MIIBCgKCAQEAkKDKe9jFjXJv163ZvS87asH6FIaQj2Si+y5D6oxuaCuQI21UXvU5leCvf3EywJ6mKAEPfl24lK8DQvLjgO29zHBzM16FZm6Kn/VeCnYQ31NEAvN8i+v1vCN55Wio699ExiGgOnfzyZ8yW8zQm3rZWTkyrcvLaXWJ8gRXGVAa5j9oeOY+cplYC0/7mqM/vva4WUrTvrQikcz8bFvLQ70RurpB1Mt77hsogIuG08B9xkRjfdDIKE16O6dJzuU5tPX11GPK4DAEq9yUwIb6maFOrsDYMm0oGrOtqvmf3H3xNw/2ySer1FQt5KOLqK2HwJyAjeLUY/I0374l5keEvgAzvwIDAQAB",
        avatarFileId: nil,
        createdAt: Date().timeIntervalSince1970 * 1000
    )
    
    let chatManager = ChatManager()
    
    return ConversationView(chat: Chat(id: "chat1", isGroup: false, participants: ["user1", "user2"], groupName: nil))
        .environmentObject(auth)
        .environmentObject(chatManager)
}

