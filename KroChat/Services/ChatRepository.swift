import Foundation

/// Boundary between UI and data. Phase 1 uses `MockChatRepository`;
/// Phase 2 adds a Telegram-backed implementation behind the same protocol.
protocol ChatRepository: Sendable {
    func loadChats() async throws -> [Chat]
    func loadFolders() async throws -> [ChatFolder]
    func loadContacts() async throws -> [Contact]
    func send(text: String, chatID: Int64) async throws -> DeliveryState
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
