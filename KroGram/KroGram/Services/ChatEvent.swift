import Foundation

enum ConnectionState: Sendable, Equatable {
    case ready, connecting, waitingForNetwork, updating
}

/// Live updates pushed by a repository (empty for the demo repository).
enum ChatEvent: Sendable {
    case chatChanged(Int64)
    case newMessage(chatID: Int64, message: Message)
    case messageContent(chatID: Int64, remoteID: Int64, text: String)
    case sendSucceeded(chatID: Int64, oldRemoteID: Int64, message: Message)
    case sendFailed(chatID: Int64, oldRemoteID: Int64)
    case deleted(chatID: Int64, remoteIDs: [Int64])
    case userStatus(userID: Int64, isOnline: Bool)
    case connection(ConnectionState)
}

/// What this client may send about the account itself. Nothing here touches other people's content.
struct PrivacySnapshot: Sendable, Equatable {
    var hideRead = false
    var hideTyping = false
    var hideOnline = false
}
