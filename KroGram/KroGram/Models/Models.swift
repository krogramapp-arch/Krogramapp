import Foundation

enum ChatKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case direct, group, channel, bot
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .direct: return "person.fill"
        case .group: return "person.2.fill"
        case .channel: return "megaphone.fill"
        case .bot: return "cpu"
        }
    }
}

enum DeliveryState: String, Codable, Sendable {
    case sending, sent, read, failed
}

struct Message: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String
    var date: Date
    var isOutgoing: Bool
    var state: DeliveryState
    var replyToID: UUID?
    var reactions: [String]
    var isEdited: Bool
    /// Telegram message id (nil for demo data and for messages not yet acknowledged).
    var remoteID: Int64?
    var replyToRemoteID: Int64?
    var media: MessageMedia?
    var isUnsupportedContent: Bool

    init(
        id: UUID = UUID(),
        text: String,
        date: Date = .now,
        isOutgoing: Bool,
        state: DeliveryState = .sent,
        replyToID: UUID? = nil,
        reactions: [String] = [],
        isEdited: Bool = false,
        remoteID: Int64? = nil,
        replyToRemoteID: Int64? = nil,
        media: MessageMedia? = nil,
        isUnsupportedContent: Bool = false
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.isOutgoing = isOutgoing
        self.state = state
        self.replyToID = replyToID
        self.reactions = reactions
        self.isEdited = isEdited
        self.remoteID = remoteID
        self.replyToRemoteID = replyToRemoteID
        self.media = media
        self.isUnsupportedContent = isUnsupportedContent
    }
}

enum MessageMediaKind: String, Hashable, Sendable {
    case photo, video, animation, document, audio, voice, videoNote, sticker
}

struct MessageMedia: Hashable, Sendable {
    let kind: MessageMediaKind
    let fileID: Int64
    let fileName: String?
    let mimeType: String?
    let fileSize: Int64
    let caption: String
}

struct Chat: Identifiable, Hashable, Sendable {
    let id: Int64
    var title: String
    var kind: ChatKind
    var isOnline: Bool
    var unread: Int
    var isPinned: Bool
    var isArchived: Bool
    var isHidden: Bool
    var isMuted: Bool
    var folderIDs: Set<UUID>
    var messages: [Message]
    var avatarFileID: Int64?

    init(
        id: Int64,
        title: String,
        kind: ChatKind = .direct,
        isOnline: Bool = false,
        unread: Int = 0,
        isPinned: Bool = false,
        isArchived: Bool = false,
        isHidden: Bool = false,
        isMuted: Bool = false,
        folderIDs: Set<UUID> = [],
        messages: [Message] = [],
        avatarFileID: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isOnline = isOnline
        self.unread = unread
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isHidden = isHidden
        self.isMuted = isMuted
        self.folderIDs = folderIDs
        self.messages = messages
        self.avatarFileID = avatarFileID
    }

    var lastMessageText: String { messages.last?.text ?? "" }
    var lastDate: Date { messages.last?.date ?? .distantPast }
}

struct ChatFolder: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String

    init(id: UUID = UUID(), name: String, symbol: String = "folder") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

struct Contact: Identifiable, Hashable, Sendable {
    let id: Int64
    var name: String
    var username: String?
    var isOnline: Bool
    var avatarFileID: Int64? = nil
}

struct TelegramProfile: Hashable, Sendable {
    var firstName: String
    var lastName: String
    var phoneNumber: String
    var username: String?
    var bio: String
    var avatarFileID: Int64?

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChatProfile: Hashable, Sendable {
    var chatID: Int64
    var title: String
    var kind: ChatKind
    var username: String?
    var phoneNumber: String?
    var status: String?
    var description: String
    var memberCount: Int?
    var avatarFileID: Int64?
}

// MARK: - Filters

enum ChatFilter: String, CaseIterable, Identifiable {
    case all, unread, direct, group, channel, bot
    var id: String { rawValue }
    var titleKey: String { "filter.\(rawValue)" }

    func matches(_ chat: Chat) -> Bool {
        switch self {
        case .all: return true
        case .unread: return chat.unread > 0
        case .direct: return chat.kind == .direct
        case .group: return chat.kind == .group
        case .channel: return chat.kind == .channel
        case .bot: return chat.kind == .bot
        }
    }
}

enum DateFilter: String, CaseIterable, Identifiable {
    case any, today, week, month
    var id: String { rawValue }
    var titleKey: String { "date.\(rawValue)" }

    func matches(_ date: Date, now: Date = .now) -> Bool {
        let cal = Calendar.current
        switch self {
        case .any: return true
        case .today: return cal.isDate(date, inSameDayAs: now)
        case .week: return date >= (cal.date(byAdding: .day, value: -7, to: now) ?? .distantPast)
        case .month: return date >= (cal.date(byAdding: .day, value: -30, to: now) ?? .distantPast)
        }
    }
}

enum ChatScope: Hashable {
    case unread, pinned, archived, hidden
    case folder(UUID)
}
