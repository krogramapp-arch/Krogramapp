import Foundation

enum AuthStep: Sendable, Equatable {
    case starting
    case databaseReady
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
    private var loadedChatIDs: [String: [Int64]] = [:]
    private var knownFileIDs: Set<Int64> = []
    private var cachedDownloadedSizes: [Int64: Int64] = [:]
    private var downloadedFileOrder: [Int64] = []
    private var activeDownloadIDs: Set<Int64> = []
    private let chatPageSize = 25
    private let historyPageSize = 50
    private let mediaCacheLimit: Int64 = 100 * 1_024 * 1_024

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

    func logOut() async throws {
        _ = try await call(["@type": "logOut"])
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
        let directory: String
        do {
            directory = try Self.databaseDirectory()
        } catch {
            authOut.yield(.failed(TGErrors.message(for: error)))
            return
        }
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
            authOut.yield(.databaseReady)
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
                let parsed = TGParse.message(message, lastReadOutbox: lastReadOutbox[chatID] ?? 0)
                registerFiles(in: [parsed])
                eventOut.yield(.newMessage(chatID: chatID, message: parsed))
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

        case "updateFile":
            guard let file = update["file"] as? JSON else { break }
            let id = TGParse.int64(file["id"])
            knownFileIDs.insert(id)
            let local = file["local"] as? JSON ?? [:]
            if (local["is_downloading_completed"] as? Bool) == true {
                recordCachedFile(id, size: TGParse.int64(local["downloaded_size"]))
            }
            eventOut.yield(.fileProgress(
                fileID: id,
                downloaded: TGParse.int64(local["downloaded_size"]),
                total: TGParse.int64(file["size"]),
                completed: (local["is_downloading_completed"] as? Bool) == true
            ))

        default:
            break
        }
    }

    // MARK: Chats

    func loadChats(limit: Int = 25) async throws -> [Chat] {
        try await loadChatPage(limit: min(max(limit, 1), chatPageSize), loadMore: false)
    }

    func loadMoreChats() async throws -> [Chat] {
        try await loadChatPage(limit: chatPageSize, loadMore: true)
    }

    private func loadChatPage(limit: Int, loadMore: Bool) async throws -> [Chat] {
        var pageIDs: [Int64] = []
        let perListLimit = (limit + 1) / 2
        for list in ["chatListMain", "chatListArchive"] {
            let listObject: JSON = ["@type": list]
            let previouslyLoaded = loadedChatIDs[list] ?? []
            let desiredCount = loadMore
                ? previouslyLoaded.count + perListLimit
                : max(previouslyLoaded.count, perListLimit)
            var result = try await call([
                "@type": "getChats",
                "chat_list": listObject,
                "limit": desiredCount
            ])
            var found = ((result["chat_ids"] as? [NSNumber]) ?? []).map(\.int64Value)
            if found.count < desiredCount, authReady {
                do {
                    _ = try await call([
                        "@type": "loadChats",
                        "chat_list": listObject,
                        "limit": perListLimit
                    ])
                    result = try await call([
                        "@type": "getChats",
                        "chat_list": listObject,
                        "limit": desiredCount
                    ])
                    found = ((result["chat_ids"] as? [NSNumber]) ?? []).map(\.int64Value)
                } catch {
                    if found.isEmpty { throw error }
                }
            }
            loadedChatIDs[list] = found
            let eligible = loadMore ? found.filter { !previouslyLoaded.contains($0) } : Array(found.prefix(limit))
            pageIDs.append(contentsOf: eligible)
        }

        var chats: [Chat] = []
        for id in pageIDs where !chats.contains(where: { $0.id == id }) {
            do {
                chats.append(try await self.chat(id))
            } catch {
                if chats.isEmpty { throw error }
            }
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
                result.avatarFileID = info.avatarFileID
            }
        }
        if let fileID = result.avatarFileID { knownFileIDs.insert(fileID) }
        registerFiles(in: result.messages)
        return result
    }

    private func user(_ id: Int64) async -> TGUser? {
        if let cached = userCache[id] { return cached }
        guard let object = try? await call(["@type": "getUser", "user_id": id]) else { return nil }
        let user = TGParse.user(object)
        userCache[id] = user
        if let fileID = user.avatarFileID { knownFileIDs.insert(fileID) }
        return user
    }

    func myProfile() async throws -> TelegramProfile {
        let user = try await call(["@type": "getMe"])
        let userID = TGParse.int64(user["id"])
        let fullInfo = try await call(["@type": "getUserFullInfo", "user_id": userID])
        let profile = TGParse.profile(user: user, fullInfo: fullInfo)
        if let fileID = profile.avatarFileID { knownFileIDs.insert(fileID) }
        return profile
    }

    func chatProfile(chatID: Int64) async throws -> ChatProfile {
        let object = try await call(["@type": "getChat", "chat_id": chatID])
        let chat = TGParse.chat(object, lastReadOutbox: lastReadOutbox[chatID] ?? 0)
        let type = object["type"] as? JSON ?? [:]
        var profile = ChatProfile(
            chatID: chatID,
            title: chat.title,
            kind: chat.kind,
            username: nil,
            phoneNumber: nil,
            status: nil,
            description: "",
            memberCount: nil,
            avatarFileID: chat.avatarFileID
        )
        switch TGParse.string(type["@type"]) {
        case "chatTypePrivate":
            let userID = TGParse.int64(type["user_id"])
            let user = try await call(["@type": "getUser", "user_id": userID])
            let full = try await call(["@type": "getUserFullInfo", "user_id": userID])
            let userProfile = TGParse.profile(user: user, fullInfo: full)
            profile.username = userProfile.username
            profile.phoneNumber = userProfile.phoneNumber
            profile.description = userProfile.bio
            profile.status = TGParse.string((user["status"] as? JSON)?["@type"])
            profile.avatarFileID = userProfile.avatarFileID
        case "chatTypeBasicGroup":
            let groupID = TGParse.int64(type["basic_group_id"])
            let full = try await call(["@type": "getBasicGroupFullInfo", "basic_group_id": groupID])
            profile.description = TGParse.string(full["description"])
        case "chatTypeSupergroup":
            let groupID = TGParse.int64(type["supergroup_id"])
            let full = try await call(["@type": "getSupergroupFullInfo", "supergroup_id": groupID])
            profile.description = TGParse.string(full["description"])
            let memberCount = TGParse.int64(full["member_count"])
            profile.memberCount = memberCount > 0 ? Int(memberCount) : nil
        default:
            break
        }
        if let fileID = profile.avatarFileID { knownFileIDs.insert(fileID) }
        return profile
    }

    func updateMyProfile(firstName: String, lastName: String, bio: String) async throws {
        _ = try await call([
            "@type": "setName",
            "first_name": firstName,
            "last_name": lastName
        ])
        _ = try await call([
            "@type": "setBio",
            "bio": ["@type": "formattedText", "text": bio] as JSON
        ])
    }

    func loadContacts(limit: Int = 300) async throws -> [Contact] {
        let result = try await call(["@type": "getContacts"])
        let ids = ((result["user_ids"] as? [NSNumber]) ?? []).map(\.int64Value).prefix(limit)
        var contacts: [Contact] = []
        for id in ids {
            if let info = await self.user(id) {
                contacts.append(Contact(
                    id: id,
                    name: info.name,
                    username: info.username,
                    isOnline: info.isOnline,
                    avatarFileID: info.avatarFileID
                ))
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
        let messages = list.reversed().map { TGParse.message($0, lastReadOutbox: readOutbox) }
        registerFiles(in: messages)
        return messages
    }

    func loadOlderHistory(chatID: Int64, before messageID: Int64) async throws -> [Message] {
        let result = try await call([
            "@type": "getChatHistory",
            "chat_id": chatID,
            "from_message_id": messageID,
            "offset": 0,
            "limit": historyPageSize,
            "only_local": false
        ])
        let readOutbox = lastReadOutbox[chatID] ?? 0
        let messages = ((result["messages"] as? [JSON]) ?? [])
            .reversed()
            .map { TGParse.message($0, lastReadOutbox: readOutbox) }
        registerFiles(in: messages)
        return messages
    }

    private func registerFiles(in messages: [Message]) {
        for id in messages.compactMap({ $0.media?.fileID }) { knownFileIDs.insert(id) }
    }

    func downloadFileData(fileID: Int64, limit: Int64) async throws -> Data {
        let file = try await call(["@type": "getFile", "file_id": fileID])
        let remoteSize = TGParse.int64(file["size"])
        guard remoteSize <= limit else {
            throw TDError(code: -3, message: "FILE_TOO_LARGE")
        }
        knownFileIDs.insert(fileID)

        if let data = try localFileData(file, limit: limit) {
            try await makeMediaCacheRoom(for: fileID, expectedSize: Int64(data.count))
            recordCachedFile(fileID, size: Int64(data.count))
            return data
        }
        try await makeMediaCacheRoom(
            for: fileID,
            expectedSize: remoteSize > 0 ? remoteSize : limit
        )
        _ = try await call([
            "@type": "downloadFile",
            "file_id": fileID,
            "priority": 32,
            "offset": 0,
            "limit": limit,
            "synchronous": false
        ])
        activeDownloadIDs.insert(fileID)
        defer { activeDownloadIDs.remove(fileID) }

        for _ in 0..<240 {
            try Task.checkCancellation()
            let current = try await call(["@type": "getFile", "file_id": fileID])
            let currentSize = TGParse.int64(current["size"])
            if currentSize > limit {
                try await cancelFileDownload(fileID: fileID)
                throw TDError(code: -3, message: "FILE_TOO_LARGE")
            }
            if let data = try localFileData(current, limit: limit) {
                try await makeMediaCacheRoom(for: fileID, expectedSize: Int64(data.count))
                recordCachedFile(fileID, size: Int64(data.count))
                return data
            }
            let downloaded = TGParse.int64((current["local"] as? JSON)?["downloaded_size"])
            if downloaded > limit {
                try await cancelFileDownload(fileID: fileID)
                throw TDError(code: -3, message: "FILE_TOO_LARGE")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw TDError(code: -4, message: "FILE_DOWNLOAD_TIMEOUT")
    }

    private func localFileData(_ file: JSON, limit: Int64) throws -> Data? {
        let local = file["local"] as? JSON ?? [:]
        guard (local["is_downloading_completed"] as? Bool) == true else { return nil }
        let path = TGParse.string(local["path"])
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= limit else { throw TDError(code: -3, message: "FILE_TOO_LARGE") }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func makeMediaCacheRoom(for fileID: Int64, expectedSize: Int64) async throws {
        guard expectedSize > 0 else { return }
        guard expectedSize <= mediaCacheLimit else {
            throw TDError(code: -5, message: "MEDIA_CACHE_FULL")
        }
        var total = cachedDownloadedSizes
            .filter { $0.key != fileID }
            .values
            .reduce(0, +)
        while total + expectedSize > mediaCacheLimit {
            guard let index = downloadedFileOrder.firstIndex(where: { $0 != fileID }) else { break }
            let id = downloadedFileOrder[index]
            guard let size = cachedDownloadedSizes[id] else {
                downloadedFileOrder.remove(at: index)
                continue
            }
            _ = try await call(["@type": "deleteFile", "file_id": id])
            cachedDownloadedSizes[id] = nil
            downloadedFileOrder.remove(at: index)
            total -= size
        }
        guard total + expectedSize <= mediaCacheLimit else {
            throw TDError(code: -5, message: "MEDIA_CACHE_FULL")
        }
    }

    private func recordCachedFile(_ id: Int64, size: Int64) {
        cachedDownloadedSizes[id] = size
        downloadedFileOrder.removeAll { $0 == id }
        downloadedFileOrder.append(id)
    }

    func cancelFileDownload(fileID: Int64) async throws {
        _ = try await call([
            "@type": "cancelDownloadFile",
            "file_id": fileID,
            "only_if_pending": false
        ])
        eventOut.yield(.fileCancelled(fileID: fileID))
    }

    func sendPhoto(chatID: Int64, path: String, caption: String) async throws {
        try validateOutgoingFile(path, limit: 10 * 1_024 * 1_024)
        _ = try await call([
            "@type": "sendMessage",
            "chat_id": chatID,
            "input_message_content": [
                "@type": "inputMessagePhoto",
                "photo": ["@type": "inputFileLocal", "path": path] as JSON,
                "thumbnail": NSNull(),
                "added_sticker_file_ids": [],
                "width": 0,
                "height": 0,
                "caption": ["@type": "formattedText", "text": caption] as JSON,
                "show_caption_above_media": false,
                "self_destruct_type": NSNull(),
                "has_spoiler": false
            ] as JSON
        ])
    }

    func sendDocument(chatID: Int64, path: String, caption: String) async throws {
        try validateOutgoingFile(path, limit: 25 * 1_024 * 1_024)
        _ = try await call([
            "@type": "sendMessage",
            "chat_id": chatID,
            "input_message_content": [
                "@type": "inputMessageDocument",
                "document": ["@type": "inputFileLocal", "path": path] as JSON,
                "thumbnail": NSNull(),
                "caption": ["@type": "formattedText", "text": caption] as JSON,
                "disable_content_type_detection": false
            ] as JSON
        ])
    }

    private func validateOutgoingFile(_ path: String, limit: Int64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= limit else {
            throw TDError(code: -3, message: "FILE_TOO_LARGE")
        }
    }

    func clearMediaCache() async throws {
        let downloads = activeDownloadIDs
        for id in downloads {
            try await cancelFileDownload(fileID: id)
        }
        let fileIDs = knownFileIDs
        for id in fileIDs {
            let file = try await call(["@type": "getFile", "file_id": id])
            let local = file["local"] as? JSON ?? [:]
            guard (local["is_downloading_completed"] as? Bool) == true else { continue }
            _ = try await call(["@type": "deleteFile", "file_id": id])
        }
        knownFileIDs.removeAll()
        cachedDownloadedSizes.removeAll()
        downloadedFileOrder.removeAll()
        activeDownloadIDs.removeAll()
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

    private static func databaseDirectory() throws -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KroGram/tdlib", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }
}
