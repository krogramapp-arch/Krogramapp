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
        let venue = content["venue"] as? JSON ?? [:]
        let point = (content["location"] as? JSON) ?? (venue["location"] as? JSON) ?? [:]
        let coordinates: String
        if let latitude = (point["latitude"] as? NSNumber)?.doubleValue,
           let longitude = (point["longitude"] as? NSNumber)?.doubleValue {
            coordinates = String(format: "%.5f, %.5f", latitude, longitude)
        } else {
            coordinates = ""
        }
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
        case "messagePoll":
            return L("msg.poll")
        case "messageContact":
            let contact = content["contact"] as? JSON ?? [:]
            let name = [string(contact["first_name"]), string(contact["last_name"])]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let phone = string(contact["phone_number"])
            return [L("msg.contact"), name, phone].filter { !$0.isEmpty }.joined(separator: "\n")
        case "messageLocation":
            return L("msg.location") + "\n" + coordinates
        case "messageVenue":
            let title = string(venue["title"])
            let address = string(venue["address"])
            return [L("msg.location"), title, address, coordinates].filter { !$0.isEmpty }.joined(separator: "\n")
        default: return L("msg.unsupported")
        }
    }

    static func entities(_ values: Any?) -> [MessageEntity] {
        (values as? [JSON] ?? []).compactMap { entity in
            let offset = Int(int64(entity["offset"]))
            let length = Int(int64(entity["length"]))
            guard offset >= 0, length > 0, let type = entity["type"] as? JSON else { return nil }
            let kind: MessageEntityKind
            switch string(type["@type"]) {
            case "textEntityTypeBold": kind = .bold
            case "textEntityTypeItalic": kind = .italic
            case "textEntityTypeCode": kind = .code
            case "textEntityTypePre", "textEntityTypePreCode": kind = .pre
            case "textEntityTypeBlockQuote", "textEntityTypeExpandableBlockQuote": kind = .quote
            case "textEntityTypeSpoiler": kind = .spoiler
            case "textEntityTypeUnderline": kind = .underline
            case "textEntityTypeStrikethrough": kind = .strikethrough
            case "textEntityTypeUrl": kind = .url
            case "textEntityTypeEmailAddress": kind = .email
            case "textEntityTypePhoneNumber": kind = .phoneNumber
            case "textEntityTypeMention": kind = .mention
            case "textEntityTypeHashtag": kind = .hashtag
            case "textEntityTypeCashtag": kind = .cashtag
            case "textEntityTypeBotCommand": kind = .botCommand
            case "textEntityTypeTextUrl":
                let url = string(type["url"])
                guard !url.isEmpty else { return nil }
                kind = .textURL(url)
            case "textEntityTypeMentionName":
                let userID = int64(type["user_id"])
                guard userID != 0 else { return nil }
                kind = .mentionName(userID)
            default:
                return nil
            }
            return MessageEntity(offset: offset, length: length, kind: kind)
        }
    }

    static func entityJSON(_ entity: MessageEntity) -> JSON {
        let type: JSON
        switch entity.kind {
        case .bold: type = ["@type": "textEntityTypeBold"]
        case .italic: type = ["@type": "textEntityTypeItalic"]
        case .code: type = ["@type": "textEntityTypeCode"]
        case .pre: type = ["@type": "textEntityTypePreCode", "language": ""]
        case .quote: type = ["@type": "textEntityTypeBlockQuote", "is_expandable": false]
        case .spoiler: type = ["@type": "textEntityTypeSpoiler"]
        case .underline: type = ["@type": "textEntityTypeUnderline"]
        case .strikethrough: type = ["@type": "textEntityTypeStrikethrough"]
        case .url: type = ["@type": "textEntityTypeUrl"]
        case .email: type = ["@type": "textEntityTypeEmailAddress"]
        case .phoneNumber: type = ["@type": "textEntityTypePhoneNumber"]
        case .mention: type = ["@type": "textEntityTypeMention"]
        case .hashtag: type = ["@type": "textEntityTypeHashtag"]
        case .cashtag: type = ["@type": "textEntityTypeCashtag"]
        case .botCommand: type = ["@type": "textEntityTypeBotCommand"]
        case .textURL(let url): type = ["@type": "textEntityTypeTextUrl", "url": url]
        case .mentionName(let userID): type = ["@type": "textEntityTypeMentionName", "user_id": userID]
        }
        return [
            "@type": "textEntity",
            "offset": entity.offset,
            "length": entity.length,
            "type": type
        ]
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

        let id = int64(file["id"])
        guard id != 0 else { return nil }
        return MessageMedia(
            kind: mediaKind,
            fileID: id,
            fileName: fileName.flatMap { $0.isEmpty ? nil : $0 },
            mimeType: mimeType.flatMap { $0.isEmpty ? nil : $0 },
            fileSize: fileSize,
            caption: string((content["caption"] as? JSON)?["text"]),
            captionEntities: entities((content["caption"] as? JSON)?["entities"])
        )
    }

    static func isUnsupportedContent(_ content: JSON) -> Bool {
        ![
            "messageText", "messagePhoto", "messageVideo", "messageAnimation",
            "messageDocument", "messageAudio", "messageVoiceNote",
            "messageVideoNote", "messageSticker", "messagePoll",
            "messageContact", "messageLocation", "messageVenue"
        ].contains(string(content["@type"]))
    }

    static func reactions(_ message: JSON) -> [String] {
        reactionDetails(message).all
    }

    static func poll(_ content: JSON) -> MessagePoll? {
        guard string(content["@type"]) == "messagePoll",
              let poll = content["poll"] as? JSON else { return nil }
        let question = string((poll["question"] as? JSON)?["text"])
        let options = (poll["options"] as? [JSON] ?? []).map { option in
            PollOption(
                text: string((option["text"] as? JSON)?["text"]),
                voterCount: Int(int64(option["voter_count"])),
                votePercentage: Int(int64(option["vote_percentage"])),
                isChosen: (option["is_chosen"] as? Bool) == true
            )
        }
        guard !question.isEmpty, !options.isEmpty else { return nil }
        return MessagePoll(
            question: question,
            options: options,
            totalVoterCount: Int(int64(poll["total_voter_count"])),
            allowsMultipleAnswers: (poll["allows_multiple_answers"] as? Bool) == true,
            isClosed: (poll["is_closed"] as? Bool) == true
        )
    }

    static func stickers(_ set: JSON) -> [TelegramSticker] {
        (set["stickers"] as? [JSON] ?? []).compactMap { sticker in
            let file = sticker["sticker"] as? JSON ?? [:]
            let fileID = int64(file["id"])
            guard fileID != 0 else { return nil }
            return TelegramSticker(
                id: fileID,
                emoji: string(sticker["emoji"]),
                width: Int(int64(sticker["width"])),
                height: Int(int64(sticker["height"]))
            )
        }
    }

    static func reactionDetails(_ message: JSON) -> (all: [String], chosen: [String]) {
        let interactionInfo = message["interaction_info"] as? JSON ?? [:]
        let reactions = (interactionInfo["reactions"] as? JSON)?["reactions"] as? [JSON] ?? []
        var all: [String] = []
        var chosen: [String] = []
        for item in reactions {
            let type = item["type"] as? JSON ?? [:]
            guard string(type["@type"]) == "reactionTypeEmoji" else { continue }
            let emoji = string(type["emoji"])
            guard !emoji.isEmpty else { continue }
            all.append(emoji)
            if (item["is_chosen"] as? Bool) == true { chosen.append(emoji) }
        }
        return (all, chosen)
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
        let reactionDetails = reactionDetails(m)
        return Message(
            text: contentText(m["content"] as? JSON ?? [:]),
            date: Date(timeIntervalSince1970: TimeInterval(int64(m["date"]))),
            isOutgoing: outgoing,
            state: state,
            isEdited: int64(m["edit_date"]) > 0,
            isPinned: (m["is_pinned"] as? Bool) ?? false,
            remoteID: id,
            replyToRemoteID: replyID == 0 ? nil : replyID,
            media: media(m["content"] as? JSON ?? [:]),
            isUnsupportedContent: isUnsupportedContent(m["content"] as? JSON ?? [:]),
            entities: entities(((m["content"] as? JSON)?["text"] as? JSON)?["entities"]),
            reactions: reactionDetails.all,
            chosenReactions: reactionDetails.chosen,
            poll: poll(m["content"] as? JSON ?? [:])
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
        case "FORWARD_NOT_ALLOWED": return L("err.forwardRestricted")
        case "MICROPHONE_PERMISSION_DENIED": return L("err.microphonePermission")
        case "AUDIO_RECORDING_FAILED": return L("err.audioRecording")
        case "AUDIO_RECORDING_TOO_SHORT": return L("err.audioTooShort")
        case "MEDIA_READ_FAILED": return L("err.mediaRead")
        case "INVALID_MEDIA_DURATION": return L("err.mediaDuration")
        case "INVALID_VIDEO_NOTE": return L("err.videoNote")
        case "INVALID_POLL": return L("err.invalidPoll")
        case "INVALID_POLL_ANSWER": return L("err.invalidPollAnswer")
        case "INVALID_CONTACT": return L("err.invalidContact")
        case "INVALID_LOCATION": return L("err.invalidLocation")
        default: break
        }
        if td.code == 429 || td.message.hasPrefix("FLOOD_WAIT") {
            let digits = td.message.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let seconds = Int(digits) { return String(format: L("err.flood"), seconds) }
        }

        if let key = known[td.message] { return L(key) }
        return L("err.generic")
    }
}

private extension Int64 {
    var nonZero: Int64? { self == 0 ? nil : self }
}
