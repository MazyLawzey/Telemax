import SwiftUI

#if os(macOS)
import AppKit
private let systemGray5 = NSColor.quinarySystemFill
private let systemGray6 = NSColor.quaternarySystemFill
#else
import UIKit
private let systemGray5 = UIColor.systemGray5
private let systemGray6 = UIColor.systemGray6
#endif

struct MessageBubbleView: View {
    let message: DecryptedMessage
    let isMe: Bool
    var onEdit: (() -> Void)?
    var onDeleteForMe: (() -> Void)?
    var onDeleteForEveryone: (() -> Void)?
    var onCopy: (() -> Void)?

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if !isMe, let name = message.senderName {
                    Text(name)
                        .font(.caption2.bold())
                        .foregroundStyle(.accent)
                }

                if message.isDeleted {
                    Text("🚫 This message was deleted")
                        .italic()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(systemGray6))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    messageContent
                        .contextMenu {
                            Button {
                                onCopy?()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            if isMe {
                                Button {
                                    onEdit?()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                onDeleteForMe?()
                            } label: {
                                Label("Delete for Me", systemImage: "eye.slash")
                            }

                            if isMe {
                                Button(role: .destructive) {
                                    onDeleteForEveryone?()
                                } label: {
                                    Label("Delete for Everyone", systemImage: "trash")
                                }
                            }
                        }
                }

                HStack(spacing: 4) {
                    if message.isEdited {
                        Text("edited")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isMe {
                        // readBy includes others (not just sender) = read
                        let othersRead = message.readBy.contains(where: { $0 != message.senderId })
                        Image(systemName: othersRead ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(othersRead ? AnyShapeStyle(.accent) : AnyShapeStyle(.tertiary))
                    }
                }
            }


            if !isMe { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .image:
            if let fileId = message.fileId {
                AsyncImage(url: URL(string: SheetsService.shared.fileURL(fileId: fileId))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .draggable(image)
                    case .failure:
                        imagePlaceholder(icon: "exclamationmark.triangle", text: "Failed to load")
                    case .empty:
                        imagePlaceholder(icon: "photo", text: "Loading…")
                            .overlay(ProgressView())
                    @unknown default:
                        imagePlaceholder(icon: "photo", text: "Photo")
                    }
                }
            } else {
                textBubble
            }

        case .file:
            if let fileId = message.fileId {
                Link(destination: URL(string: SheetsService.shared.fileURL(fileId: fileId))!) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.title3)
                        Text(message.content)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color.accentColor : Color(systemGray5))
                    .foregroundStyle(isMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            } else {
                textBubble
            }

        case .text:
            textBubble
        }
    }

    private var textBubble: some View {
        Text(message.content)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isMe ? Color.accentColor : Color(systemGray5))
            .foregroundStyle(isMe ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func imagePlaceholder(icon: String, text: String) -> some View {
        VStack {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 200, height: 150)
        .background(Color(systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
