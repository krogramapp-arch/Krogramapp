import Foundation

/// `ChatRepository` backed by a real Telegram session (TDLib).
struct TelegramChatRepository: ChatRepository {
    let service: TelegramService

    var isReal: Bool { true }
    var events: AsyncStream<ChatEvent>? { service.events }

    func loadChats() async throws -> [Chat] { try await service.loadChats() }
    func loadFolders() async throws -> [ChatFolder] { [] }
    func loadContacts() async throws -> [Contact] { try await service.loadContacts() }
    func send(text: String, chatID: Int64) async throws -> DeliveryState { .sent }

    func refreshChat(_ id: Int64) async throws -> Chat? { try await service.chat(id) }
    func loadHistory(chatID: Int64) async throws -> [Message]? { try await service.loadHistory(chatID: chatID) }

    func sendRemote(text: String, chatID: Int64, replyToRemoteID: Int64?) async throws -> Message? {
        try await service.sendText(chatID: chatID, text: text, replyToRemoteID: replyToRemoteID)
    }

    func editRemote(chatID: Int64, messageID: Int64, text: String) async throws {
        try await service.editText(chatID: chatID, messageID: messageID, text: text)
    }

    func deleteRemote(chatID: Int64, messageID: Int64) async throws {
        try await service.deleteMessage(chatID: chatID, messageID: messageID)
    }

    func markRead(chatID: Int64, remoteIDs: [Int64]) async {
        await service.markRead(chatID: chatID, messageIDs: remoteIDs)
    }

    func setChatOpen(_ chatID: Int64, _ open: Bool) async { await service.setChatOpen(chatID, open) }
    func sendTyping(chatID: Int64) async { await service.sendTyping(chatID: chatID) }
    func setPinned(chatID: Int64, pinned: Bool) async throws { try await service.setPinned(chatID: chatID, pinned: pinned) }
    func setArchived(chatID: Int64, archived: Bool) async throws { try await service.setArchived(chatID: chatID, archived: archived) }
    func apply(privacy: PrivacySnapshot) async { await service.apply(privacy: privacy) }
    func setForeground(_ foreground: Bool) async { await service.setForeground(foreground) }
}
