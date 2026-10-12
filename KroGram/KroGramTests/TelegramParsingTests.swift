import XCTest
@testable import KroGram

final class TelegramParsingTests: XCTestCase {
    func testTextMessageParsing() {
        let json: JSON = [
            "id": 4_194_304,
            "chat_id": 777,
            "is_outgoing": true,
            "date": 1_700_000_000,
            "edit_date": 0,
            "content": ["@type": "messageText", "text": ["@type": "formattedText", "text": "مرحبا"]],
            "reply_to": ["@type": "messageReplyToMessage", "message_id": 4_000_000]
        ]
        let message = TGParse.message(json, lastReadOutbox: 0)
        XCTAssertEqual(message.text, "مرحبا")
        XCTAssertEqual(message.remoteID, 4_194_304)
        XCTAssertEqual(message.replyToRemoteID, 4_000_000)
        XCTAssertTrue(message.isOutgoing)
        XCTAssertEqual(message.state, .sent)
        XCTAssertFalse(message.isEdited)
    }

    func testOutgoingReadStateFollowsLastReadOutbox() {
        let json: JSON = [
            "id": 100, "is_outgoing": true, "date": 1,
            "content": ["@type": "messageText", "text": ["text": "x"]]
        ]
        XCTAssertEqual(TGParse.message(json, lastReadOutbox: 100).state, .read)
        XCTAssertEqual(TGParse.message(json, lastReadOutbox: 99).state, .sent)
    }

    func testSendingStates() {
        var json: JSON = [
            "id": 1, "is_outgoing": true, "date": 1,
            "sending_state": ["@type": "messageSendingStatePending"],
            "content": ["@type": "messageText", "text": ["text": "x"]]
        ]
        XCTAssertEqual(TGParse.message(json, lastReadOutbox: 0).state, .sending)
        json["sending_state"] = ["@type": "messageSendingStateFailed"]
        XCTAssertEqual(TGParse.message(json, lastReadOutbox: 0).state, .failed)
    }

    func testChatKindsAndFlags() {
        let channel: JSON = [
            "id": -1_001_234_567_890,
            "title": "News",
            "type": ["@type": "chatTypeSupergroup", "is_channel": true],
            "unread_count": 7,
            "notification_settings": ["mute_for": 3600],
            "positions": [
                ["list": ["@type": "chatListMain"], "order": "1", "is_pinned": true]
            ]
        ]
        let chat = TGParse.chat(channel, lastReadOutbox: 0)
        XCTAssertEqual(chat.id, -1_001_234_567_890)
        XCTAssertEqual(chat.kind, .channel)
        XCTAssertEqual(chat.unread, 7)
        XCTAssertTrue(chat.isMuted)
        XCTAssertTrue(chat.isPinned)
        XCTAssertFalse(chat.isArchived)

        let archivedGroup: JSON = [
            "id": -5, "title": "G",
            "type": ["@type": "chatTypeBasicGroup"],
            "positions": [["list": ["@type": "chatListArchive"], "order": "2", "is_pinned": false]]
        ]
        let group = TGParse.chat(archivedGroup, lastReadOutbox: 0)
        XCTAssertEqual(group.kind, .group)
        XCTAssertTrue(group.isArchived)
    }

    func testUserParsing() {
        let bot: JSON = [
            "first_name": "Weather", "last_name": "Bot",
            "type": ["@type": "userTypeBot"],
            "status": ["@type": "userStatusOnline"],
            "usernames": ["active_usernames": ["weather_bot"]]
        ]
        let user = TGParse.user(bot)
        XCTAssertEqual(user.name, "Weather Bot")
        XCTAssertTrue(user.isBot)
        XCTAssertTrue(user.isOnline)
        XCTAssertEqual(user.username, "weather_bot")
    }

    func testPhotoAndDocumentMediaMetadataArePreserved() {
        let photo = TGParse.media([
            "@type": "messagePhoto",
            "photo": [
                "sizes": [
                    ["photo": ["id": 12, "size": 400]],
                    ["photo": ["id": 13, "size": 1_200]]
                ]
            ],
            "caption": ["text": "caption"]
        ])
        XCTAssertEqual(photo?.kind, .photo)
        XCTAssertEqual(photo?.fileID, 13)
        XCTAssertEqual(photo?.caption, "caption")

        let document = TGParse.media([
            "@type": "messageDocument",
            "document": [
                "file_name": "report.pdf",
                "mime_type": "application/pdf",
                "document": ["id": 42, "size": 8_192]
            ],
            "caption": ["text": ""]
        ])
        XCTAssertEqual(document?.kind, .document)
        XCTAssertEqual(document?.fileID, 42)
        XCTAssertEqual(document?.fileName, "report.pdf")
        XCTAssertEqual(document?.fileSize, 8_192)
    }

    func testUnsupportedMessageContentIsFlagged() {
        XCTAssertTrue(TGParse.isUnsupportedContent(["@type": "messagePoll"]))
        XCTAssertFalse(TGParse.isUnsupportedContent(["@type": "messageText"]))
    }

    func testChatPhotoFileIDIsParsed() {
        let chat = TGParse.chat([
            "id": -42,
            "title": "Group",
            "photo": ["small": ["id": 91]],
            "type": ["@type": "chatTypeBasicGroup"]
        ], lastReadOutbox: 0)
        XCTAssertEqual(chat.avatarFileID, 91)
    }

    func testProfileParsing() {
        let profile = TGParse.profile(
            user: [
                "first_name": "Ada",
                "last_name": "Lovelace",
                "phone_number": "12345",
                "usernames": ["active_usernames": ["ada"]]
            ],
            fullInfo: ["bio": ["text": "Analyst"]]
        )
        XCTAssertEqual(profile.displayName, "Ada Lovelace")
        XCTAssertEqual(profile.phoneNumber, "12345")
        XCTAssertEqual(profile.username, "ada")
        XCTAssertEqual(profile.bio, "Analyst")
    }

    func testFloodWaitMessageContainsSeconds() {
        let message = TGErrors.message(for: TDError(code: 429, message: "Too Many Requests: retry after 42"))
        XCTAssertTrue(message.contains("42"))
    }

    func testCredentialsValidation() {
        XCTAssertTrue(TelegramCredentials.isValid(apiID: 12345, apiHash: String(repeating: "a1", count: 16)))
        XCTAssertFalse(TelegramCredentials.isValid(apiID: 0, apiHash: String(repeating: "a1", count: 16)))
        XCTAssertFalse(TelegramCredentials.isValid(apiID: 1, apiHash: "short"))
        XCTAssertFalse(TelegramCredentials.isValid(apiID: 1, apiHash: String(repeating: "z", count: 32)))
    }
}
