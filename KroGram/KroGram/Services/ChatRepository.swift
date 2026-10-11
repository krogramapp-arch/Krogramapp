import Foundation

/// Boundary between UI and data. `MockChatRepository` powers the demo;
/// `TelegramChatRepository` talks to Telegram through TDLib.
protocol ChatRepository: Sendable {
    var isReal: Bool { get }
    var events: AsyncStream<ChatEvent>? { get }

    func loadChats() async throws -> [Chat]
    func loadFolders() async throws -> [ChatFolder]
    func loadContacts() async throws -> [Contact]
    func send(text: String, chatID: Int64) async throws -> DeliveryState

    func refreshChat(_ id: Int64) async throws -> Chat?
    func loadHistory(chatID: Int64) async throws -> [Message]?
    /// Returns nil when the repository has no remote backend (demo): caller falls back to `send(text:chatID:)`.
    func sendRemote(text: String, chatID: Int64, replyToRemoteID: Int64?) async throws -> Message?
    func editRemote(chatID: Int64, messageID: Int64, text: String) async throws
    func deleteRemote(chatID: Int64, messageID: Int64) async throws
    func markRead(chatID: Int64, remoteIDs: [Int64]) async
    func setChatOpen(_ chatID: Int64, _ open: Bool) async
    func sendTyping(chatID: Int64) async
    func setPinned(chatID: Int64, pinned: Bool) async throws
    func setArchived(chatID: Int64, archived: Bool) async throws
    func apply(privacy: PrivacySnapshot) async
    func setForeground(_ foreground: Bool) async
}

extension ChatRepository {
    var isReal: Bool { false }
    var events: AsyncStream<ChatEvent>? { nil }
    func refreshChat(_ id: Int64) async throws -> Chat? { nil }
    func loadHistory(chatID: Int64) async throws -> [Message]? { nil }
    func sendRemote(text: String, chatID: Int64, replyToRemoteID: Int64?) async throws -> Message? { nil }
    func editRemote(chatID: Int64, messageID: Int64, text: String) async throws {}
    func deleteRemote(chatID: Int64, messageID: Int64) async throws {}
    func markRead(chatID: Int64, remoteIDs: [Int64]) async {}
    func setChatOpen(_ chatID: Int64, _ open: Bool) async {}
    func sendTyping(chatID: Int64) async {}
    func setPinned(chatID: Int64, pinned: Bool) async throws {}
    func setArchived(chatID: Int64, archived: Bool) async throws {}
    func apply(privacy: PrivacySnapshot) async {}
    func setForeground(_ foreground: Bool) async {}
}

enum MockRepositoryError: Error {
    case simulatedSendFailure
}

/// Demo repository. Sending text that starts with "/fail" simulates a send error.
struct MockChatRepository: ChatRepository {
    var delay: Duration = .milliseconds(400)

    func loadChats() async throws -> [Chat] {
        try await Task.sleep(for: delay)
        return MockData.chats()
    }

    func loadFolders() async throws -> [ChatFolder] {
        MockData.folders
    }

    func loadContacts() async throws -> [Contact] {
        MockData.contacts
    }

    func send(text: String, chatID: Int64) async throws -> DeliveryState {
        try await Task.sleep(for: delay)
        if text.hasPrefix("/fail") { throw MockRepositoryError.simulatedSendFailure }
        return .sent
    }
}
