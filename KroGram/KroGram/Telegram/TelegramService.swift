import Foundation

enum AuthStep: Sendable, Equatable {
    case starting
    case waitPhone
    case waitCode
    case waitPassword(hint: String)
    case unsupported(String)
    case failed(String)
    case ready
    case closed
}

/// Owns the TDLib session: authorization, chats, messages, privacy options.
/// All Telegram traffic goes through TDLib (official library); nothing is sent to other servers.
actor TelegramService {
    nonisolated let authSteps: AsyncStream<AuthStep>
    nonisolated let events: AsyncStream<ChatEvent>

    private let authOut: AsyncStream<AuthStep>.Continuation
    private let eventOut: AsyncStream<ChatEvent>.Continuation
    private let client = TDJSONClient.shared
    private let credentials: TelegramCredentials
    private let dbKey: Data

    private var consumer: Task<Void, Never>?
    private var authReady = false
    private var isForeground = true
    private var privacy = PrivacySnapshot()
    private var userCache: [Int64: TGUser] = [:]
    private var lastReadOutbox: [Int64: Int64] = [:]

    init(credentials: TelegramCredentials, dbKey: Data) {
        self.credentials = credentials
        self.dbKey = dbKey
        var authContinuation: AsyncStream<AuthStep>.Continuation!
        authSteps = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { authContinuation = $0 }
        authOut = authContinuation
        var eventContinuation: AsyncStream<ChatEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(500)) { eventContinuation = $0 }
        eventOut = eventContinuation
    }

    // MARK: Lifecycle

    func start() {
        guard consumer == nil else { return }
        var continuation: AsyncStream<TDObject>.Continuation!
        let stream = AsyncStream<TDObject>(bufferingPolicy: .unbounded) { continuation = $0 }
        client.startSession(sink: continuation)
        authOut.yield(.starting)
        consumer = Task { [weak self] in
            for await object in stream {
                await self?.handle(object)
            }
        }
    }

    func logOut() async {
        _ = try? await call(["@type": "logOut"])
    }

    // MARK: Authorization

    func submitPhone(_ phone: String) async throws {
        _ = try await call(["@type": "setAuthenticationPhoneNumber", "phone_number": phone])
    }

    func submitCode(_ code: String) async throws {
        _ = try await call(["@type": "checkAuthenticationCode", "code": code])
    }

    func submitPassword(_ password: String) async throws {
        _ = try await call(["@type": "checkAuthenticationPassword", "password": password])
    }

    private func sendParameters() async {
        let directory = Self.databaseDirectory()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let query: JSON = [
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": directory,
            "files_directory": directory + "/files",
            "database_encryption_key": dbKey.base64EncodedString(),
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": credentials.apiID,
            "api_hash": credentials.apiHash,
            "system_language_code": Locale.current.language.languageCode?.identifier ?? "en",
            "device_model": "iPhone",
            "system_version": "",
            "application_version": version
        ]
        do {
            _ = try await call(query)
        } catch {
            authOut.yield(.failed(TGErrors.message(for: error)))
        }
    }

    private func handleAuthorization(_ state: JSON) async {
        let type = TGParse.string(state["@type"])
        switch type {
        case "authorizationStateWaitTdlibParameters":
            await sendParameters()
        case "authorizationStateWaitPhoneNumber":
            authReady = false
            authOut.yield(.waitPhone)
        case "authorizationStateWaitCode":
            authOut.yield(.waitCode)
        case "authorizationStateWaitPassword":
            authOut.yield(.waitPassword(hint: TGParse.string(state["password_hint"])))
        case "authorizationStateReady":
            authReady = true
            authOut.yield(.ready)
            await applyOnlineStatus()
        case "authorizationStateLoggingOut":
            authReady = false
        case "authorizationStateClosing":
            authReady = false
        case "authorizationStateClosed":
            authReady = false
            authOut.yield(.closed)
        default:
            authOut.yield(.unsupported(type))
        }
    }

    // MARK: Updates

    private func handle(_ object: TDObject) async {
        let update = object.json
        let type = TGParse.string(update["@type"])
        switch type {
        case "updateAuthorizationState":
            if let state = update["authorization_state"] as? JSON { await handleAuthorization(state) }

        case "updateConnectionState":
            let state = TGParse.string((update["state"] as? JSON)?["@type"])
            switch state {
            case "connectionStateReady": eventOut.yield(.connection(.ready))
            case "connectionStateWaitingForNetwork": eventOut.yield(.connection(.waitingForNetwork))
            case "connectionStateUpdating": eventOut.yield(.connection(.updating))
            default: eventOut.yield(.connection(.connecting))
            }

        case "updateNewChat":
            if let chat = update["chat"] as? JSON { eventOut.yield(.chatChanged(TGParse.int64(chat["id"]))) }

        case "updateChatLastMessage", "updateChatReadInbox", "updateChatPosition",
             "updateChatTitle", "updateChatNotificationSettings":
            eventOut.yield(.chatChanged(TGParse.int64(update["chat_id"])))

        case "updateChatReadOutbox":
            let id = TGParse.int64(update["chat_id"])
            lastReadOutbox[id] = TGParse.int64(update["last_read_outbox_message_id"])
            eventOut.yield(.chatChanged(id))

        case "updateNewMessage":
            if let message = update["message"] as? JSON {
                let chatID = TGParse.int64(message["chat_id"])
                eventOut.yield(.newMessage(
                    chatID: chatID,
                    message: TGParse.message(message, lastReadOutbox: lastReadOutbox[chatID] ?? 0)
                ))
            }

        case "updateMessageContent":
            if let content = update["new_content"] as? JSON {
                eventOut.yield(.messageContent(
                    chatID: TGParse.int64(update["chat_id"]),
                    remoteID: TGParse.int64(update["message_id"]),
                    text: TGParse.contentText(content)
                ))
            }

        case "updateMessageSendSucceeded":
            if let message = update["message"] as? JSON {
                let chatID = TGParse.int64(message["chat_id"])
                eventOut.yield(.sendSucceeded(
                    chatID: chatID,
                    oldRemoteID: TGParse.int64(update["old_message_id"]),
                    message: TGParse.message(message, lastReadOutbox: lastReadOutbox[chatID] ?? 0)
                ))
            }

        case "updateMessageSendFailed":
            if let message = update["message"] as? JSON {
                eventOut.yield(.sendFailed(
                    chatID: TGParse.int64(message["chat_id"]),
                    oldRemoteID: TGParse.int64(update["old_message_id"])
                ))
            }

        case "updateDeleteMessages":
            let permanent = (update["is_permanent"] as? Bool) ?? false
            let fromCache = (update["from_cache"] as? Bool) ?? false
            if permanent && !fromCache {
                let ids = ((update["message_ids"] as? [NSNumber]) ?? []).map(\.int64Value)
                eventOut.yield(.deleted(chatID: TGParse.int64(update["chat_id"]), remoteIDs: ids))
            }

        case "updateUserStatus":
            let userID = TGParse.int64(update["user_id"])
            let online = TGParse.string((update["status"] as? JSON)?["@type"]) == "userStatusOnline"
            if var cached = userCache[userID] {
                cached.isOnline = online
                userCache[userID] = cached
            }
            eventOut.yield(.userStatus(userID: userID, isOnline: online))

        default:
            break
        }
    }

    // MARK: Chats

    func loadChats(limit: Int = 100) async throws -> [Chat] {
        var ids: [Int64] = []
        for list in ["chatListMain", "chatListArchive"] {
            let listObject: JSON = ["@type": list]
            _ = try? await call(["@type": "loadChats", "chat_list": listObject, "limit": limit])
            if let result = try? await call(["@type": "getChats", "chat_list": listObject, "limit": limit]) {
                let found = ((result["chat_ids"] as? [NSNumber]) ?? []).map(\.int64Value)
                for id in found where !ids.contains(id) { ids.append(id) }
            }
        }
        var chats: [Chat] = []
        for id in ids {
            if let fetched = try? await self.chat(id) { chats.append(fetched) }
        }
        return chats
    }

    func chat(_ id: Int64) async throws -> Chat {
        let object = try await call(["@type": "getChat", "chat_id": id])
        let readOutbox = TGParse.int64(object["last_read_outbox_message_id"])
        lastReadOutbox[id] = readOutbox
        var result = TGParse.chat(object, lastReadOutbox: readOutbox)
        if let type = object["type"] as? JSON, TGParse.string(type["@type"]) == "chatTypePrivate" {
            let userID = TGParse.int64(type["user_id"])
            if let info = await self.user(userID) {
                result.isOnline = info.isOnline
                if info.isBot { result.kind = .bot }
            }
        }
        return result
    }

    private func user(_ id: Int64) async -> TGUser? {
        if let cached = userCache[id] { return cached }
        guard let object = try? await call(["@type": "getUser", "user_id": id]) else { return nil }
        let user = TGParse.user(object)
        userCache[id] = user
        return user
    }

    func loadContacts(limit: Int = 300) async throws -> [Contact] {
        let result = try await call(["@type": "getContacts"])
        let ids = ((result["user_ids"] as? [NSNumber]) ?? []).map(\.int64Value).prefix(limit)
        var contacts: [Contact] = []
        for id in ids {
            if let info = await self.user(id) {
                contacts.append(Contact(id: id, name: info.name, username: info.username, isOnline: info.isOnline))
            }
        }
        return contacts
    }

    func setPinned(chatID: Int64, pinned: Bool) async throws {
        _ = try await call([
            "@type": "toggleChatIsPinned",
            "chat_list": ["@type": "chatListMain"] as JSON,
            "chat_id": chatID,
            "is_pinned": pinned
        ])
    }

    func setArchived(chatID: Int64, archived: Bool) async throws {
        _ = try await call([
            "@type": "addChatToList",
            "chat_id": chatID,
            "chat_list": ["@type": archived ? "chatListArchive" : "chatListMain"] as JSON
        ])
    }

    // MARK: Messages

    func loadHistory(chatID: Int64, limit: Int = 50) async throws -> [Message] {
        var list: [JSON] = []
        for attempt in 0..<2 {
            let result = try await call([
                "@type": "getChatHistory",
                "chat_id": chatID,
                "from_message_id": 0,
                "offset": 0,
                "limit": limit,
                "only_local": false
            ])
            list = (result["messages"] as? [JSON]) ?? []
            if list.count > 1 || attempt == 1 { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let readOutbox = lastReadOutbox[chatID] ?? 0
        return list.reversed().map { TGParse.message($0, lastReadOutbox: readOutbox) }
    }

    func sendText(chatID: Int64, text: String, replyToRemoteID: Int64?) async throws -> Message {
        let content: JSON = [
            "@type": "inputMessageText",
            "text": ["@type": "formattedText", "text": text] as JSON
        ]
        var query: JSON = ["@type": "sendMessage", "chat_id": chatID, "input_message_content": content]
        if let reply = replyToRemoteID, reply != 0 {
            query["reply_to"] = ["@type": "inputMessageReplyToMessage", "message_id": reply] as JSON
        }
        let sent = try await call(query)
        return TGParse.message(sent, lastReadOutbox: lastReadOutbox[chatID] ?? 0)
    }

    func editText(chatID: Int64, messageID: Int64, text: String) async throws {
        let content: JSON = [
            "@type": "inputMessageText",
            "text": ["@type": "formattedText", "text": text] as JSON
        ]
        _ = try await call([
            "@type": "editMessageText",
            "chat_id": chatID,
            "message_id": messageID,
            "input_message_content": content
        ])
    }

    func deleteMessage(chatID: Int64, messageID: Int64) async throws {
        _ = try await call([
            "@type": "deleteMessages",
            "chat_id": chatID,
            "message_ids": [messageID],
            "revoke": true
        ])
    }

    /// Sends a read receipt. Called only when the user opted in (or tapped "mark as read").
    func markRead(chatID: Int64, messageIDs: [Int64]) async {
        guard !messageIDs.isEmpty else { return }
        _ = try? await call([
            "@type": "viewMessages",
            "chat_id": chatID,
            "message_ids": messageIDs,
            "source": ["@type": "messageSourceChatHistory"] as JSON,
            "force_read": true
        ])
    }

    /// Tells TDLib the chat is open (needed for live updates in groups/channels). Does not mark anything as read.
    func setChatOpen(_ chatID: Int64, _ open: Bool) async {
        _ = try? await call(["@type": open ? "openChat" : "closeChat", "chat_id": chatID])
    }

    func sendTyping(chatID: Int64) async {
        guard !privacy.hideTyping, authReady else { return }
        _ = try? await call([
            "@type": "sendChatAction",
            "chat_id": chatID,
            "action": ["@type": "chatActionTyping"] as JSON
        ])
    }

    // MARK: Presence / privacy

    func apply(privacy snapshot: PrivacySnapshot) async {
        privacy = snapshot
        await applyOnlineStatus()
    }

    func setForeground(_ foreground: Bool) async {
        isForeground = foreground
        await applyOnlineStatus()
    }

    private func applyOnlineStatus() async {
        guard authReady else { return }
        let online = isForeground && !privacy.hideOnline
        _ = try? await call([
            "@type": "setOption",
            "name": "online",
            "value": ["@type": "optionValueBoolean", "value": online] as JSON
        ])
    }

    // MARK: Helpers

    private func call(_ query: JSON) async throws -> JSON {
        try await client.request(query).json
    }

    private static func databaseDirectory() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KroGram/tdlib", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }
}
