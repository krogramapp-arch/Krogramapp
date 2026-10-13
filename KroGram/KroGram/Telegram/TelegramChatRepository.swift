import Foundation

/// `ChatRepository` backed by a real Telegram session (TDLib).
struct TelegramChatRepository: ChatRepository {
    let service: TelegramService
    private static let foldersKey = "krochat.folders.v1"

    var isReal: Bool { true }
    var events: AsyncStream<ChatEvent>? { service.events }

    func loadChats() async throws -> [Chat] { try await service.loadChats() }
    func loadMoreChats() async throws -> [Chat] { try await service.loadMoreChats() }
    func loadFolders() async throws -> [ChatFolder] {
        guard let data = UserDefaults.standard.data(forKey: Self.foldersKey),
              let folders = try? JSONDecoder().decode([ChatFolder].self, from: data) else {
            return []
        }
        return folders
    }
    func loadContacts() async throws -> [Contact] { try await service.loadContacts() }
    func send(text: String, chatID: Int64) async throws -> DeliveryState { .sent }

    func refreshChat(_ id: Int64) async throws -> Chat? { try await service.chat(id) }
    func loadHistory(chatID: Int64) async throws -> [Message]? { try await service.loadHistory(chatID: chatID) }
    func loadOlderHistory(chatID: Int64, before messageID: Int64) async throws -> [Message]? {
        try await service.loadOlderHistory(chatID: chatID, before: messageID)
    }
    func loadMyProfile() async throws -> TelegramProfile? { try await service.myProfile() }
    func loadChatProfile(chatID: Int64) async throws -> ChatProfile? {
        try await service.chatProfile(chatID: chatID)
    }
    func updateMyProfile(firstName: String, lastName: String, bio: String) async throws {
        try await service.updateMyProfile(firstName: firstName, lastName: lastName, bio: bio)
    }
    func downloadFileData(fileID: Int64, limit: Int64) async throws -> Data {
        try await service.downloadFileData(fileID: fileID, limit: limit)
    }
    func cancelFileDownload(fileID: Int64) async throws {
        try await service.cancelFileDownload(fileID: fileID)
    }
    func sendPhoto(chatID: Int64, path: String, caption: String) async throws {
        try await service.sendPhoto(chatID: chatID, path: path, caption: caption)
    }
    func sendVideo(chatID: Int64, path: String, caption: String) async throws {
        try await service.sendVideo(chatID: chatID, path: path, caption: caption)
    }
    func sendVideoNote(chatID: Int64, path: String, duration: Int, length: Int) async throws {
        try await service.sendVideoNote(chatID: chatID, path: path, duration: duration, length: length)
    }
    func sendVoiceNote(chatID: Int64, path: String, duration: Int) async throws {
        try await service.sendVoiceNote(chatID: chatID, path: path, duration: duration)
    }
    func sendPoll(chatID: Int64, question: String, options: [String], isAnonymous: Bool, allowsMultipleAnswers: Bool) async throws {
        try await service.sendPoll(
            chatID: chatID,
            question: question,
            options: options,
            isAnonymous: isAnonymous,
            allowsMultipleAnswers: allowsMultipleAnswers
        )
    }
    func sendContact(chatID: Int64, firstName: String, lastName: String, phoneNumber: String) async throws {
        try await service.sendContact(
            chatID: chatID,
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phoneNumber
        )
    }
    func sendLocation(chatID: Int64, latitude: Double, longitude: Double) async throws {
        try await service.sendLocation(chatID: chatID, latitude: latitude, longitude: longitude)
    }
    func votePoll(chatID: Int64, messageID: Int64, optionIDs: [Int]) async throws -> Message? {
        try await service.votePoll(chatID: chatID, messageID: messageID, optionIDs: optionIDs)
    }
    func loadStickers() async throws -> [TelegramSticker] {
        try await service.loadStickers()
    }
    func sendSticker(chatID: Int64, sticker: TelegramSticker) async throws {
        try await service.sendSticker(chatID: chatID, sticker: sticker)
    }
    func sendDocument(chatID: Int64, path: String, caption: String) async throws {
        try await service.sendDocument(chatID: chatID, path: path, caption: caption)
    }
    func clearMediaCache() async throws { try await service.clearMediaCache() }

    func sendRemote(text: String, chatID: Int64, replyToRemoteID: Int64?, entities: [MessageEntity]) async throws -> Message? {
        try await service.sendText(
            chatID: chatID,
            text: text,
            replyToRemoteID: replyToRemoteID,
            entities: entities
        )
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
    func setPinned(chatID: Int64, pinned: Bool, archived: Bool = false) async throws {
        try await service.setPinned(chatID: chatID, pinned: pinned, archived: archived)
    }
    func setArchived(chatID: Int64, archived: Bool) async throws { try await service.setArchived(chatID: chatID, archived: archived) }
    func setMessageReaction(chatID: Int64, messageID: Int64, emoji: String?) async throws -> [String]? {
        try await service.setMessageReaction(chatID: chatID, messageID: messageID, emoji: emoji)
    }
    func setMessagePinned(chatID: Int64, messageID: Int64, pinned: Bool) async throws {
        try await service.setMessagePinned(chatID: chatID, messageID: messageID, pinned: pinned)
    }
    func forwardMessages(fromChatID: Int64, toChatID: Int64, messageIDs: [Int64]) async throws {
        try await service.forwardMessages(fromChatID: fromChatID, toChatID: toChatID, messageIDs: messageIDs)
    }
    func searchMessages(chatID: Int64, query: String, fromMessageID: Int64, limit: Int) async throws -> [Message]? {
        try await service.searchMessages(chatID: chatID, query: query, fromMessageID: fromMessageID, limit: limit)
    }
    func apply(privacy: PrivacySnapshot) async { await service.apply(privacy: privacy) }
    func setForeground(_ foreground: Bool) async { await service.setForeground(foreground) }
}
