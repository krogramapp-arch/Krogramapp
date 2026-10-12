import Foundation

struct TGUser: Sendable, Equatable {
    var name: String
    var username: String?
    var isBot: Bool
    var isOnline: Bool
    var avatarFileID: Int64?
}

/// Pure functions that turn TDLib JSON objects into app models.
enum TGParse {
    static func int64(_ value: Any?) -> Int64 { (value as? NSNumber)?.int64Value ?? 0 }
    static func string(_ value: Any?) -> String { value as? String ?? "" }

    static func contentText(_ content: JSON) -> String {
        let type = string(content["@type"])
        let caption = string((content["caption"] as? JSON)?["text"])
        func labeled(_ key: String) -> String {
            caption.isEmpty ? L(key) : L(key) + " " + caption
        }
        switch type {
        case "messageText": return string((content["text"] as? JSON)?["text"])
        case "messagePhoto": return labeled("msg.photo")
        case "messageVideo": return labeled("msg.video")
        case "messageAnimation": return labeled("msg.gif")
        case "messageDocument": return labeled("msg.file")
        case "messageAudio": return labeled("msg.audio")
        case "messageVoiceNote": return labeled("msg.voice")
        case "messageVideoNote": return L("msg.videoNote")
        case "messageSticker": return L("msg.sticker")
        case "messagePoll": return L("msg.poll")
        case "messageContact": return L("msg.contact")
        case "messageLocation", "messageVenue": return L("msg.location")
        default: return L("msg.unsupported")
        }
    }

    static func media(_ content: JSON) -> MessageMedia? {
        let type = string(content["@type"])
        let mediaKind: MessageMediaKind
        let file: JSON
        var fileName: String?
        var mimeType: String?
        var fileSize: Int64 = 0

        switch type {
        case "messagePhoto":
            mediaKind = .photo
            let photo = content["photo"] as? JSON ?? [:]
            let sizes = photo["sizes"] as? [JSON] ?? []
            file = (sizes.last?["photo"] as? JSON) ?? [:]
            fileSize = int64(file["size"])
        case "messageVideo":
            mediaKind = .video
            let item = content["video"] as? JSON ?? [:]
            file = item["video"] as? JSON ?? [:]
            fileName = string(item["file_name"])
            mimeType = string(item["mime_type"])
            fileSize = int64(file["size"])
        case "messageAnimation":
            mediaKind = .animation
            let item = content["animation"] as? JSON ?? [:]
            file = item["animation"] as? JSON ?? [:]
            fileName = string(item["file_name"])
            mimeType = string(item["mime_type"])
            fileSize = int64(file["size"])
        case "messageDocument":
            mediaKind = .document
            let item = content["document"] as? JSON ?? [:]
            file = item["document"] as? JSON ?? [:]
            fileName = string(item["file_name"])
            mimeType = string(item["mime_type"])
            fileSize = int64(file["size"])
        case "messageAudio":
            mediaKind = .audio
            let item = content["audio"] as? JSON ?? [:]
            file = item["audio"] as? JSON ?? [:]
            fileName = string(item["file_name"])
            mimeType = string(item["mime_type"])
            fileSize = int64(file["size"])
        case "messageVoiceNote":
            mediaKind = .voice
            let item = content["voice_note"] as? JSON ?? [:]
            file = item["voice"] as? JSON ?? [:]
            mimeType = string(item["mime_type"])
            fileSize = int64(file["size"])
        case "messageVideoNote":
            mediaKind = .videoNote
            let item = content["video_note"] as? JSON ?? [:]
            file = item["video"] as? JSON ?? [:]
            fileSize = int64(file["size"])
        case "messageSticker":
            mediaKind = .sticker
            let item = content["sticker"] as? JSON ?? [:]
            file = item["sticker"] as? JSON ?? [:]
            fileSize = int64(file["size"])
        default:
            return nil
        }

        static func isUnsupportedContent(_ content: JSON) -> Bool {
            ![
                "messageText", "messagePhoto", "messageVideo", "messageAnimation",
                "messageDocument", "messageAudio", "messageVoiceNote",
                "messageVideoNote", "messageSticker"
            ].contains(string(content["@type"]))
        }

        let id = int64(file["id"])
        guard id != 0 else { return nil }
        return MessageMedia(
            kind: mediaKind,
            fileID: id,
            fileName: fileName.flatMap { $0.isEmpty ? nil : $0 },
            mimeType: mimeType.flatMap { $0.isEmpty ? nil : $0 },
            fileSize: fileSize,
            caption: string((content["caption"] as? JSON)?["text"])
        )
    }

    static func message(_ m: JSON, lastReadOutbox: Int64) -> Message {
        let id = int64(m["id"])
        let outgoing = (m["is_outgoing"] as? Bool) ?? false
        var state: DeliveryState = .sent
        if let sending = m["sending_state"] as? JSON {
            state = string(sending["@type"]) == "messageSendingStateFailed" ? .failed : .sending
        } else if outgoing && id <= lastReadOutbox {
            state = .read
        }
        let replyID = int64((m["reply_to"] as? JSON)?["message_id"])
        return Message(
            text: contentText(m["content"] as? JSON ?? [:]),
            date: Date(timeIntervalSince1970: TimeInterval(int64(m["date"]))),
            isOutgoing: outgoing,
            state: state,
            isEdited: int64(m["edit_date"]) > 0,
            remoteID: id,
            replyToRemoteID: replyID == 0 ? nil : replyID,
            media: media(m["content"] as? JSON ?? [:]),
            isUnsupportedContent: isUnsupportedContent(m["content"] as? JSON ?? [:])
        )
    }

    static func chat(_ c: JSON, lastReadOutbox: Int64) -> Chat {
        let type = c["type"] as? JSON ?? [:]
        var kind: ChatKind = .direct
        switch string(type["@type"]) {
        case "chatTypeSupergroup":
            kind = ((type["is_channel"] as? Bool) ?? false) ? .channel : .group
        case "chatTypeBasicGroup":
            kind = .group
        default:
            kind = .direct
        }

        var pinned = false
        var archived = false
        for position in (c["positions"] as? [JSON]) ?? [] {
            let listType = string((position["list"] as? JSON)?["@type"])
            if listType == "chatListArchive" { archived = true }
            if listType == "chatListMain" || listType == "chatListArchive" {
                if (position["is_pinned"] as? Bool) == true { pinned = true }
            }
        }

        let muteFor = int64((c["notification_settings"] as? JSON)?["mute_for"])
        var messages: [Message] = []
        if let last = c["last_message"] as? JSON {
            messages = [message(last, lastReadOutbox: lastReadOutbox)]
        }

        return Chat(
            id: int64(c["id"]),
            title: string(c["title"]),
            kind: kind,
            unread: Int(int64(c["unread_count"])),
            isPinned: pinned,
            isArchived: archived,
            isMuted: muteFor > 0,
            messages: messages,
            avatarFileID: int64(((c["photo"] as? JSON)?["small"] as? JSON)?["id"]).nonZero
        )
    }

    static func user(_ u: JSON) -> TGUser {
        let first = string(u["first_name"])
        let last = string(u["last_name"])
        let name = (first + " " + last).trimmingCharacters(in: .whitespaces)
        let usernames = (u["usernames"] as? JSON)?["active_usernames"] as? [String]
        let isBot = string((u["type"] as? JSON)?["@type"]) == "userTypeBot"
        let isOnline = string((u["status"] as? JSON)?["@type"]) == "userStatusOnline"
        let avatarID = int64(((u["profile_photo"] as? JSON)?["small"] as? JSON)?["id"])
        return TGUser(
            name: name,
            username: usernames?.first,
            isBot: isBot,
            isOnline: isOnline,
            avatarFileID: avatarID == 0 ? nil : avatarID
        )
    }

    static func profile(user: JSON, fullInfo: JSON) -> TelegramProfile {
        let username = (user["usernames"] as? JSON)?["active_usernames"] as? [String]
        let bioValue = fullInfo["bio"]
        let bio = (bioValue as? JSON).map { string($0["text"]) } ?? string(bioValue)
        let avatarID = int64(((user["profile_photo"] as? JSON)?["small"] as? JSON)?["id"])
        return TelegramProfile(
            firstName: string(user["first_name"]),
            lastName: string(user["last_name"]),
            phoneNumber: string(user["phone_number"]),
            username: username?.first,
            bio: bio,
            avatarFileID: avatarID == 0 ? nil : avatarID
        )
    }
}

/// Maps TDLib errors to short, user-facing messages. Never retries automatically.
enum TGErrors {
    private static let known: [String: String] = [
        "PHONE_NUMBER_INVALID": "err.phone",
        "PHONE_CODE_INVALID": "err.code",
        "PHONE_CODE_EMPTY": "err.code",
        "PHONE_CODE_EXPIRED": "err.codeExpired",
        "PASSWORD_HASH_INVALID": "err.password",
        "PHONE_NUMBER_BANNED": "err.banned"
    ]

    static func message(for error: Error) -> String {
        guard let td = error as? TDError else { return L("err.generic") }
        switch td.message {
        case "FILE_TOO_LARGE": return L("err.fileTooLarge")
        case "MEDIA_CACHE_FULL": return L("err.mediaCacheFull")
        case "FILE_DOWNLOAD_TIMEOUT": return L("err.fileDownloadTimeout")
        case "OUTGOING_STORAGE_FULL": return L("err.outgoingStorageFull")
        default: break
        }
        if td.code == 429 || td.message.hasPrefix("FLOOD_WAIT") {
            let digits = td.message.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let seconds = Int(digits) { return String(format: L("err.flood"), seconds) }
        }

        private extension Int64 {
            var nonZero: Int64? { self == 0 ? nil : self }
        }
        if let key = known[td.message] { return L(key) }
        return L("err.generic")
    }
}
