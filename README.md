<div align="center">
  <img width="200" src="https://github.com/MazyLawzey/Telemax/blob/c0de964eb165c0b7969e92ccf8c34b369b20441b/AppIcon.icon/Assets/Frame%202.png"/>

  # Telemax
  
</div>

A secure, end-to-end encrypted messaging application built with SwiftUI. Telemax provides privacy-focused communication with advanced encryption, group chat support, and real-time messaging capabilities.

## How to start?

SETUP:
1. Create a new Google Sheets.
2. Extensions → Apps Script.
3. Paste all this code into [AppsScript/Code.gs](./AppsScript/Code.gs)
5. Deploy → New Version → Web Application:
• Run as: Me
• Who has access: Anyone
6. Copy the URL and paste it into Telemax during registration.

## Features

### 🔐 Security
- **End-to-End Encryption**: All messages are encrypted using RSA-2048 (key exchange) and AES-256-GCM (message encryption)
- **Secure Key Storage**: Private keys are securely stored in the device's Keychain
- **Public Key Infrastructure**: User identities derived from SHA-256 hashes of public keys
- **Zero-Knowledge Architecture**: Server has no access to decrypted message content

### 💬 Messaging
- **Direct Messages**: One-on-one encrypted conversations
- **Group Chats**: Create and manage group conversations with multiple participants
- **Real-Time Updates**: Live message polling and chat list synchronization
- **Message Features**:
  - Text, image, and file attachments
  - Message editing and deletion
  - Read receipts (track who has read messages)
  - Timestamp tracking

### 👥 Presence & Contacts
- **User Presence**: Real-time online status tracking (online/offline)
- **Last Seen**: View when users were last active
- **Contact Management**: Search and add users to start conversations

### 🎨 User Interface
- **Tab-Based Navigation**: Quick access to Chats, Search, and Settings
- **Conversation View**: Full-featured chat interface with message bubbles
- **Search**: Find and discover users across the platform
- **Settings**: Manage account preferences and profile information
- **Profile View**: View and edit user profile details

## Project Structure

```
Telemax/
├── API/
│   ├── Managers/
│   │   ├── AuthManager.swift       # Authentication & login/register logic
│   │   └── ChatManager.swift       # Chat operations & message management
│   ├── Models/
│   │   ├── User.swift              # User data model
│   │   ├── Chat.swift              # Chat/conversation data model
│   │   ├── Message.swift           # Message data model (encrypted/decrypted)
│   │   └── Group.swift             # Group chat data model
│   └── Services/
│       ├── CryptoService.swift     # RSA/AES encryption & key management
│       └── SheetsService.swift     # Backend API (Google Sheets integration)
├── UI/
│   ├── AuthView/
│   │   └── AuthView.swift          # Login & registration screen
│   ├── ChatView/
│   │   ├── ChatView.swift          # Main chat list view
│   │   ├── ConversationView.swift  # Single conversation interface
│   │   ├── MessageBubbleView.swift # Message display component
│   │   ├── GroupSettingsView.swift # Group management screen
│   │   └── NewGroupView.swift      # Create new group screen
│   ├── SearchView/
│   │   └── SearchView.swift        # User search interface
│   ├── ProfileView/
│   │   └── ProfileView.swift       # User profile display
│   └── SettingsView/
│       └── SettingsView.swift      # App settings & preferences
├── TelemaxApp.swift                # App entry point
└── ContentView.swift               # Root view with tab navigation
```

## Architecture

### State Management
- **AuthManager**: Handles user authentication, registration, login, and logout
- **ChatManager**: Manages chat state, message polling, presence tracking, and caching
- Uses SwiftUI's `@EnvironmentObject` and `@Published` for reactive updates

### Encryption Pipeline
1. **Message Composition**: User composes a message
2. **Symmetric Encryption**: Content is encrypted using AES-256-GCM with a random key
3. **Key Distribution**: The AES key is encrypted separately for each recipient using their RSA public key
4. **Transmission**: Encrypted content and encrypted keys are sent to the server
5. **Message Retrieval**: Recipients fetch the encrypted message
6. **Key Decryption**: The RSA-encrypted AES key is decrypted using the recipient's private key
7. **Message Decryption**: The AES key is used to decrypt the message content

### Caching
- Chat lists are cached locally for fast access
- Messages are cached per conversation
- Contact names and user presence are cached to reduce API calls

### Real-Time Features
- **Message Polling**: Periodic checks for new messages (0.5s interval)
- **Chat List Polling**: Automatic refresh of chat list
- **Presence Polling**: User online status updates
- Implements exponential backoff to reduce server load

## Core Classes

### AuthManager
Manages user authentication and session state.
- `register(username:displayName:)`: Create new user account
- `login()`: Verify existing private key and login
- `logout()`: Clear session and delete private key

### ChatManager
Handles all chat operations and real-time synchronization.
- `loadChats(userId:)`: Fetch user's chats
- `openChat(_:)`: Open conversation and start polling messages
- `sendMessage(_:toChat:)`: Send encrypted message
- `deleteChat(chatId:)`: Remove chat conversation
- Message caching and decryption

### CryptoService
Provides encryption/decryption functionality.
- RSA-2048 key pair generation and management
- AES-256-GCM encryption/decryption
- Key import/export
- Private key storage in Keychain
- User ID generation from public keys

### SheetsService
Backend API integration (uses Google Sheets as database).
- User registration and retrieval
- Chat and message operations
- Group management
- File storage

## Requirements

- iOS 15.0+
- Swift 5.5+
- Xcode 13.0+

## Dependencies

- SwiftUI (iOS native framework)
- Combine (for reactive programming)
- Security framework (for cryptography)
- CryptoKit (for AES encryption)

## Authentication Flow

1. **Registration**:
   - App generates RSA-2048 key pair
   - Private key stored in Keychain
   - Public key sent to server with username
   - User ID derived from public key hash

2. **Login**:
   - Retrieve public key from Keychain
   - Verify key pair exists with server
   - Establish session

3. **Logout**:
   - Delete private key from Keychain
   - Clear user session

## Security Considerations

- **Private Key**: Never leaves the device except in encrypted form
- **Encryption**: Industry-standard algorithms (RSA-2048, AES-256-GCM)
- **Message Integrity**: Each message is authenticated via GCM
- **Perfect Forward Secrecy**: Each message uses a unique symmetric key
- **Key Storage**: Keychain provides hardware-backed security on modern devices

## Future Enhancements

- Message delivery confirmation
- Voice/video calling
- Message reactions and threading
- Rich text formatting
- Link previews
- Typing indicators
- Custom user avatars
- End-to-end encrypted file transfer with progress tracking
- Message expiration (disappearing messages)
- Screenshot detection
- Backup and recovery mechanisms

