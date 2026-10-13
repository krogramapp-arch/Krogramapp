import Foundation
import SwiftUI

@MainActor
final class ChatsViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    struct UndoBanner: Identifiable {
        let id = UUID()
        let text: String
        /// Previous state of only the affected chats.
        let restore: [Chat]
    }

    @Published private(set) var chats: [Chat] = []
    @Published private(set) var folders: [ChatFolder] = []
    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var contactsLoading = false
    @Published private(set) var isLoadingMoreChats = false
    @Published private(set) var mediaProgress: [Int64: (downloaded: Int64, total: Int64)] = [:]
    @Published private(set) var mediaError: String?
    @Published private(set) var profile: TelegramProfile?
    @Published private(set) var profileLoading = false
    @Published private(set) var drafts: [Int64: String] = [:]
    @Published private(set) var messageSearchResults: [Int64: [Message]] = [:]
    @Published private(set) var messageSearchQueries: [Int64: String] = [:]
    @Published private(set) var searchingChats: Set<Int64> = []
    @Published private(set) var stickers: [TelegramSticker] = []
    @Published private(set) var stickersLoading = false
    @Published private(set) var connection: ConnectionState = .ready
    @Published var searchText = ""
    @Published var filter: ChatFilter = .all
    @Published var dateFilter: DateFilter = .any
    @Published var selectedFolderID: UUID?
    @Published var undoBanner: UndoBanner?

    private var repository: ChatRepository
    private let privacy: PrivacyMode
    private let defaults: UserDefaults
    private var undoTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var hiddenIDs: Set<Int64>
    private var lastTyping: [Int64: Date] = [:]
    private var historyLoading: Set<Int64> = []
    private var historyExhausted: Set<Int64> = []
    private var searchCursors: [Int64: Int64] = [:]
    private var searchExhausted: Set<Int64> = []
    private var searchTokens: [Int64: UUID] = [:]
    private var activeChatID: Int64?
    private var moreChatsExhausted = false
    private var contactsLoaded = false
    private var stickersLoaded = false
    private var mediaTasks: [Int64: Task<Data, Error>] = [:]
    private var dataCache: [Int64: Data] = [:]
    private var dataCacheOrder: [Int64] = []
    private var dataCacheBytes = 0
    private let maxDataCacheBytes = 50 * 1_024 * 1_024

    private static let draftsKey = "krochat.drafts.v1"
    private static let hiddenKey = "krochat.hidden.v1"
    private static let maxDrafts = 100

    init(repository: ChatRepository, privacy: PrivacyMode? = nil, defaults: UserDefaults = .standard) {
        self.repository = repository
        let privacy = privacy ?? .shared
        self.privacy = privacy
        self.defaults = defaults
        let storedDrafts = (defaults.dictionary(forKey: Self.draftsKey) as? [String: String]) ?? [:]
        var restored: [Int64: String] = [:]
        for (key, value) in storedDrafts {
            if let id = Int64(key) { restored[id] = value }
        }
        drafts = restored
        hiddenIDs = Set((defaults.array(forKey: Self.hiddenKey) as? [NSNumber] ?? []).map(\.int64Value))
        privacy.onChange = { [weak self] in self?.pushPrivacy() }
        startEvents()
    }

    var isLive: Bool { repository.isReal }
    var canDeleteChats: Bool { !repository.isReal }

    // MARK: Repository switching

    /// Replaces the data source (demo <-> live) and clears state.
    func attach(_ newRepository: ChatRepository) {
        eventTask?.cancel()
        eventTask = nil
        repository = newRepository
        chats = []
        folders = []
        contacts = []
        stickers = []
        loadState = .idle
        contactsLoading = false
        contactsLoaded = false
        stickersLoaded = false
        stickersLoading = false
        isLoadingMoreChats = false
        historyLoading.removeAll()
        historyExhausted.removeAll()
        activeChatID = nil
        moreChatsExhausted = false
        mediaProgress.removeAll()
        dataCache.removeAll()
        dataCacheOrder.removeAll()
        dataCacheBytes = 0
        profile = nil
        connection = .ready
        selectedFolderID = nil
        startEvents()
        pushPrivacy()
    }

    func pushPrivacy() {
        let snapshot = privacy.snapshot
        let repo = repository
        Task { await repo.apply(privacy: snapshot) }
    }

    func setForeground(_ foreground: Bool) {
        let repo = repository
        Task { await repo.setForeground(foreground) }
    }

    private func startEvents() {
        guard let stream = repository.events else { return }
        eventTask = Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    // MARK: Loading

    func load() async {
        guard loadState == .idle || loadState == .failed else { return }
        loadState = .loading
        do {
            let repo = repository
            async let loadedChats = repo.loadChats()
            async let loadedFolders = repo.loadFolders()
            let (c, f) = try await (loadedChats, loadedFolders)
            var merged = c
            if repo.isReal {
                for i in merged.indices where hiddenIDs.contains(merged[i].id) { merged[i].isHidden = true }
            }
            chats = merged
            folders = f
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    func loadMoreChats() async {
        guard repository.isReal, !isLoadingMoreChats, !moreChatsExhausted else { return }
        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }
        do {
            let additional = try await repository.loadMoreChats()
            if additional.isEmpty {
                moreChatsExhausted = true
                return
            }
            for var chat in additional where !chats.contains(where: { $0.id == chat.id }) {
                chat.isHidden = hiddenIDs.contains(chat.id)
                chats.append(chat)
            }
        } catch {
            loadState = .failed
        }
    }

    func loadContacts() async {
        guard !contactsLoaded, !contactsLoading else { return }
        contactsLoading = true
        defer { contactsLoading = false }
        do {
            contacts = try await repository.loadContacts()
            contactsLoaded = true
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    func reload() async {
        guard loadState != .loading else { return }
        loadState = .idle
        await load()
    }

    // MARK: Queries

    private func sorted(_ list: [Chat]) -> [Chat] {
        list.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.lastDate > b.lastDate
        }
    }

    var mainChats: [Chat] {
        let visible = chats.filter { !$0.isArchived && !$0.isHidden }
        return repository.isReal ? visible : sorted(visible)
    }
    var totalUnread: Int { mainChats.filter { !$0.isMuted }.reduce(0) { $0 + $1.unread } }

    var visibleChats: [Chat] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mainChats.filter { chat in
            guard filter.matches(chat), dateFilter.matches(chat.lastDate) else { return false }
            if let folderID = selectedFolderID, !chat.folderIDs.contains(folderID) { return false }
            if query.isEmpty { return true }
            return chat.title.localizedCaseInsensitiveContains(query)
                || chat.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    func chat(_ id: Int64) -> Chat? { chats.first { $0.id == id } }

    func chats(in scope: ChatScope) -> [Chat] {
        switch scope {
        case .unread: return mainChats.filter { $0.unread > 0 }
        case .pinned: return mainChats.filter { $0.isPinned }
        case .archived:
            let archived = chats.filter(\.isArchived)
            return repository.isReal ? archived : sorted(archived)
        case .hidden:
            let hidden = chats.filter(\.isHidden)
            return repository.isReal ? hidden : sorted(hidden)
        case .folder(let id): return mainChats.filter { $0.folderIDs.contains(id) }
        }
    }

    func title(for scope: ChatScope) -> String {
        switch scope {
        case .unread: return L("organize.list.unread")
        case .pinned: return L("organize.list.pinned")
        case .archived: return L("organize.list.archived")
        case .hidden: return L("organize.list.hidden")
        case .folder(let id): return folders.first { $0.id == id }?.name ?? ""
        }
    }

    // MARK: Chat actions (all with undo)

    func update(_ ids: Set<Int64>, undoKey: String = "undo.changed", _ change: (inout Chat) -> Void) {
        let before = chats.filter { ids.contains($0.id) }
        guard !before.isEmpty else { return }
        for i in chats.indices where ids.contains(chats[i].id) {
            change(&chats[i])
        }
        persistHidden(for: ids)
        pushRemoteFlags(before: before)
        presentUndo(String(format: L(undoKey), before.count), restore: before)
    }

    /// Demo only. Deleting real chats is intentionally disabled to protect the account.
    func delete(_ ids: Set<Int64>) {
        guard canDeleteChats else { return }
        let before = chats.filter { ids.contains($0.id) }
        guard !before.isEmpty else { return }
        chats.removeAll { ids.contains($0.id) }
        presentUndo(String(format: L("undo.deleted"), before.count), restore: before)
    }

    func undo() {
        guard let banner = undoBanner else { return }
        let ids = Set(banner.restore.map(\.id))
        let current = chats.filter { ids.contains($0.id) }
        for old in banner.restore {
            if let i = chats.firstIndex(where: { $0.id == old.id }) {
                chats[i] = old
            } else {
                chats.append(old)
            }
        }
        persistHidden(for: ids)
        pushRemoteFlags(before: current)
        dismissUndo()
    }

    func dismissUndo() {
        undoTask?.cancel()
        undoBanner = nil
    }

    private func presentUndo(_ text: String, restore: [Chat]) {
        undoTask?.cancel()
        undoBanner = UndoBanner(text: text, restore: restore)
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoBanner = nil
        }
    }

    private func persistHidden(for ids: Set<Int64>) {
        guard repository.isReal else { return }
        for chat in chats where ids.contains(chat.id) {
            if chat.isHidden { hiddenIDs.insert(chat.id) } else { hiddenIDs.remove(chat.id) }
        }
        defaults.set(hiddenIDs.map { NSNumber(value: $0) }, forKey: Self.hiddenKey)
    }

    /// Pin and archive are real Telegram actions when connected.
    private func pushRemoteFlags(before: [Chat]) {
        guard repository.isReal else { return }
        let repo = repository
        for old in before {
            guard let now = chats.first(where: { $0.id == old.id }) else { continue }
            if old.isPinned != now.isPinned {
                Task { try? await repo.setPinned(chatID: old.id, pinned: now.isPinned) }
            }
            if old.isArchived != now.isArchived {
                Task { try? await repo.setArchived(chatID: old.id, archived: now.isArchived) }
            }
        }
    }

    // MARK: Folders (local to this app)

    func addFolder(name: String, symbol: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders.append(ChatFolder(name: String(trimmed.prefix(30)), symbol: symbol))
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for i in chats.indices { chats[i].folderIDs.remove(id) }
        if selectedFolderID == id { selectedFolderID = nil }
    }

    func setFolder(_ folderID: UUID, contains: Bool, for chatID: Int64) {
        mutateChat(chatID) { chat in
            if contains { chat.folderIDs.insert(folderID) } else { chat.folderIDs.remove(folderID) }
        }
    }

    // MARK: Opening chats / read state

    private func mutateChat(_ id: Int64, _ change: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[i])
    }

    private func message(_ id: UUID, in chatID: Int64) -> Message? {
        chat(chatID)?.messages.first { $0.id == id }
            ?? messageSearchResults[chatID]?.first { $0.id == id }
    }

    private func mutateMessage(_ id: UUID, in chatID: Int64, _ change: (inout Message) -> Void) {
        if let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
           let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == id }) {
            change(&chats[chatIndex].messages[messageIndex])
            return
        }
        guard var results = messageSearchResults[chatID],
              let index = results.firstIndex(where: { $0.id == id }) else { return }
        change(&results[index])
        messageSearchResults[chatID] = results
    }

    func openChat(_ id: Int64) async {
        activeChatID = id
        let repo = repository
        await repo.setChatOpen(id, true)
        if let history = try? await repo.loadHistory(chatID: id), !history.isEmpty {
            guard activeChatID == id else { return }
            mutateChat(id) { chat in
                let pending = chat.messages.filter { $0.remoteID == nil && $0.isOutgoing && $0.state != .sent }
                chat.messages = Array((history + pending).suffix(200))
            }
            if history.count < 50 { historyExhausted.insert(id) }
        }
        if !privacy.hideRead { await markReadNow(id) }
    }

    func closeChat(_ id: Int64) {
        if activeChatID == id { activeChatID = nil }
        let repo = repository
        Task { await repo.setChatOpen(id, false) }
        mutateChat(id) { chat in
            let latest = chat.messages.last
            let pending = chat.messages.filter { $0.remoteID == nil && $0.isOutgoing && $0.state != .sent }.suffix(50)
            chat.messages = (latest.map { [$0] } ?? []) + pending.filter { $0.id != latest?.id }
        }
    }

    func loadOlderHistory(chatID: Int64) async {
        guard repository.isReal, !historyExhausted.contains(chatID),
              !historyLoading.contains(chatID),
              let first = chat(chatID)?.messages.first(where: { $0.remoteID != nil }),
              let remoteID = first.remoteID else { return }
        historyLoading.insert(chatID)
        defer { historyLoading.remove(chatID) }
        do {
            guard let older = try await repository.loadOlderHistory(chatID: chatID, before: remoteID) else { return }
            guard activeChatID == chatID else { return }
            if older.count < 50 { historyExhausted.insert(chatID) }
            guard !older.isEmpty else { return }
            mutateChat(chatID) { chat in
                let existingIDs = Set(chat.messages.compactMap(\.remoteID))
                let unique = older.filter { message in
                    guard let id = message.remoteID else { return true }
                    return !existingIDs.contains(id)
                }
                chat.messages = Array((unique + chat.messages).suffix(200))
            }
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    func loadMyProfile() async {
        guard !profileLoading else { return }
        profileLoading = true
        defer { profileLoading = false }
        do {
            profile = try await repository.loadMyProfile()
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    func updateMyProfile(firstName: String, lastName: String, bio: String) async throws {
        do {
            try await repository.updateMyProfile(firstName: firstName, lastName: lastName, bio: bio)
            profile = try await repository.loadMyProfile()
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func loadChatProfile(chatID: Int64) async throws -> ChatProfile? {
        try await repository.loadChatProfile(chatID: chatID)
    }

    func setMediaError(_ message: String?) {
        mediaError = message
    }

    func cachedFileData(fileID: Int64) -> Data? {
        guard let data = dataCache[fileID] else { return nil }
        dataCacheOrder.removeAll { $0 == fileID }
        dataCacheOrder.append(fileID)
        return data
    }

    func cacheFileURL(fileID: Int64, data: Data, fileName: String?, mimeType: String?) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KroGram/Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let extensionName = Self.safeExtension(fileName: fileName, mimeType: mimeType)
        let destination = directory.appendingPathComponent("\(fileID).\(extensionName)")
        try data.write(to: destination, options: .atomic)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        var entries: [(url: URL, size: Int, modified: Date)] = []
        for url in files where url != destination {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            entries.append((url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        var total = data.count + entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.modified < $1.modified }) where total > maxDataCacheBytes {
            try FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
        return destination
    }

    private static func safeExtension(fileName: String?, mimeType: String?) -> String {
        if let ext = fileName.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }),
           !ext.isEmpty, ext.count <= 8,
           ext.range(of: "^[a-z0-9]+$", options: .regularExpression) != nil {
            return ext
        }
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "video/mp4": return "mp4"
        case "audio/mpeg": return "mp3"
        case "audio/ogg": return "ogg"
        default: return "bin"
        }
    }

    func downloadFile(fileID: Int64, limit: Int64) async throws -> Data {
        if let cached = cachedFileData(fileID: fileID) { return cached }
        if let existing = mediaTasks[fileID] { return try await existing.value }
        mediaError = nil
        let repo = repository
        let task = Task<Data, Error> {
            try await withTaskCancellationHandler {
                try await repo.downloadFileData(fileID: fileID, limit: limit)
            } onCancel: {
                Task {
                    do {
                        try await repo.cancelFileDownload(fileID: fileID)
                    } catch {
                        await MainActor.run { self.mediaError = TGErrors.message(for: error) }
                    }
                }
            }
        }
        mediaTasks[fileID] = task
        do {
            let data = try await task.value
            mediaTasks[fileID] = nil
            cache(data, for: fileID)
            mediaProgress[fileID] = nil
            mediaError = nil
            return data
        } catch {
            mediaTasks[fileID] = nil
            if !(error is CancellationError) { mediaError = TGErrors.message(for: error) }
            throw error
        }
    }

    func cancelFileDownload(fileID: Int64) {
        mediaTasks[fileID]?.cancel()
        mediaProgress[fileID] = nil
    }

    private func cache(_ data: Data, for fileID: Int64) {
        guard data.count <= maxDataCacheBytes else { return }
        if let old = dataCache[fileID] { dataCacheBytes -= old.count }
        dataCache[fileID] = data
        dataCacheBytes += data.count
        dataCacheOrder.removeAll { $0 == fileID }
        dataCacheOrder.append(fileID)
        while dataCacheBytes > maxDataCacheBytes, let oldest = dataCacheOrder.first {
            dataCacheOrder.removeFirst()
            dataCacheBytes -= dataCache.removeValue(forKey: oldest)?.count ?? 0
        }
    }

    func sendPhoto(path: String, caption: String, to chatID: Int64) async throws {
        do {
            try await repository.sendPhoto(chatID: chatID, path: path, caption: caption)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendVideo(path: String, caption: String, to chatID: Int64) async throws {
        do {
            try await repository.sendVideo(chatID: chatID, path: path, caption: caption)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendVideoNote(path: String, duration: Int, length: Int, to chatID: Int64) async throws {
        do {
            try await repository.sendVideoNote(chatID: chatID, path: path, duration: duration, length: length)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendVoiceNote(path: String, duration: Int, to chatID: Int64) async throws {
        do {
            try await repository.sendVoiceNote(chatID: chatID, path: path, duration: duration)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendPoll(question: String, options: [String], isAnonymous: Bool, allowsMultipleAnswers: Bool, to chatID: Int64) async throws {
        do {
            try await repository.sendPoll(
                chatID: chatID,
                question: question,
                options: options,
                isAnonymous: isAnonymous,
                allowsMultipleAnswers: allowsMultipleAnswers
            )
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendContact(firstName: String, lastName: String, phoneNumber: String, to chatID: Int64) async throws {
        do {
            try await repository.sendContact(
                chatID: chatID,
                firstName: firstName,
                lastName: lastName,
                phoneNumber: phoneNumber
            )
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendLocation(latitude: Double, longitude: Double, to chatID: Int64) async throws {
        do {
            try await repository.sendLocation(chatID: chatID, latitude: latitude, longitude: longitude)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func loadStickers() async {
        guard isLive, !stickersLoaded, !stickersLoading else { return }
        stickersLoading = true
        defer { stickersLoading = false }
        do {
            stickers = try await repository.loadStickers()
            stickersLoaded = !stickers.isEmpty
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    func sendSticker(_ sticker: TelegramSticker, to chatID: Int64) async throws {
        do {
            try await repository.sendSticker(chatID: chatID, sticker: sticker)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func sendDocument(path: String, caption: String, to chatID: Int64) async throws {
        do {
            try await repository.sendDocument(chatID: chatID, path: path, caption: caption)
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
            throw error
        }
    }

    func clearMediaCache() async {
        do {
            try await repository.clearMediaCache()
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KroGram/Media", isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            dataCache.removeAll()
            dataCacheOrder.removeAll()
            dataCacheBytes = 0
            mediaProgress.removeAll()
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    /// Sends a read receipt for incoming messages (explicit user action or ghost mode off).
    func markReadNow(_ id: Int64) async {
        guard let chat = chat(id) else { return }
        let ids = chat.messages.filter { !$0.isOutgoing }.compactMap(\.remoteID).suffix(50)
        await repository.markRead(chatID: id, remoteIDs: Array(ids))
        mutateChat(id) { $0.unread = 0 }
    }

    func userTyped(_ chatID: Int64) {
        guard repository.isReal, !privacy.hideTyping else { return }
        let now = Date()
        if let last = lastTyping[chatID], now.timeIntervalSince(last) < 4 { return }
        lastTyping[chatID] = now
        let repo = repository
        Task { await repo.sendTyping(chatID: chatID) }
    }

    // MARK: Live events

    func apply(_ event: ChatEvent) {
        switch event {
        case .chatChanged(let id):
            Task { await refresh(id) }

        case .newMessage(let chatID, let message):
            guard let ci = chats.firstIndex(where: { $0.id == chatID }) else {
                Task { await refresh(chatID) }
                return
            }
            if let remote = message.remoteID, chats[ci].messages.contains(where: { $0.remoteID == remote }) { return }
            if message.isOutgoing,
               let pi = chats[ci].messages.firstIndex(where: { $0.remoteID == nil && $0.state == .sending && $0.text == message.text }) {
                chats[ci].messages[pi].remoteID = message.remoteID
                return
            }
            if activeChatID == chatID {
                chats[ci].messages.append(message)
                chats[ci].messages = Array(chats[ci].messages.suffix(200))
            } else {
                let pending = chats[ci].messages.filter {
                    $0.remoteID == nil && $0.isOutgoing && $0.state != .sent
                }.suffix(50)
                chats[ci].messages = [message] + pending
            }

        case .messageContent(let chatID, let remoteID, let text):
            mutateChat(chatID) { chat in
                if let i = chat.messages.firstIndex(where: { $0.remoteID == remoteID }) {
                    chat.messages[i].text = text
                    chat.messages[i].isEdited = true
                }
            }

        case .sendSucceeded(let chatID, let oldID, let message):
            mutateChat(chatID) { chat in
                if let i = chat.messages.firstIndex(where: { $0.remoteID == oldID }) {
                    chat.messages[i].remoteID = message.remoteID
                    chat.messages[i].state = .sent
                    chat.messages[i].date = message.date
                }
            }

        case .sendFailed(let chatID, let oldID):
            mutateChat(chatID) { chat in
                if let i = chat.messages.firstIndex(where: { $0.remoteID == oldID }) {
                    chat.messages[i].state = .failed
                }
            }

        case .deleted(let chatID, let ids):
            mutateChat(chatID) { chat in
                chat.messages.removeAll { message in
                    guard let remote = message.remoteID else { return false }
                    return ids.contains(remote)
                }
            }

        case .userStatus(let userID, let online):
            mutateChat(userID) { $0.isOnline = online }

        case .fileProgress(let fileID, let downloaded, let total, let completed):
            if completed {
                mediaProgress[fileID] = nil
            } else {
                mediaProgress[fileID] = (downloaded, total)
            }

        case .fileCancelled(let fileID):
            mediaProgress[fileID] = nil

        case .connection(let state):
            connection = state
        }
    }

    private func refresh(_ id: Int64) async {
        guard let fresh = try? await repository.refreshChat(id) else { return }
        var merged = fresh
        if let i = chats.firstIndex(where: { $0.id == id }) {
            merged.folderIDs = chats[i].folderIDs
            merged.isHidden = chats[i].isHidden || hiddenIDs.contains(id)
            if chats[i].messages.count > 1 { merged.messages = chats[i].messages }
            chats[i] = merged
        } else {
            merged.isHidden = hiddenIDs.contains(id)
            chats.append(merged)
        }
    }

    // MARK: Sending

    func send(_ text: String, in chatID: Int64, replyTo: UUID?, entityKind: MessageEntityKind? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let replyRemote = replyTo.flatMap { id in
            message(id, in: chatID)?.remoteID
        }
        let entities = entityKind.map {
            [MessageEntity(offset: 0, length: (trimmed as NSString).length, kind: $0)]
        } ?? []
        let outgoingMessage = Message(
            text: trimmed,
            isOutgoing: true,
            state: .sending,
            replyToID: replyTo,
            replyToRemoteID: replyRemote,
            entities: entities
        )
        mutateChat(chatID) { chat in
            chat.messages.append(outgoingMessage)
            chat.messages = Array(chat.messages.suffix(200))
        }
        Task {
            await deliver(
                localID: outgoingMessage.id,
                text: trimmed,
                chatID: chatID,
                replyRemote: replyRemote,
                entities: entities
            )
        }
    }

    func retry(_ messageID: UUID, in chatID: Int64) {
        guard let message = chat(chatID)?.messages.first(where: { $0.id == messageID }) else { return }
        setState(.sending, messageID: messageID, chatID: chatID)
        let text = message.text
        let reply = message.replyToRemoteID
        let entities = message.entities
        Task {
            await deliver(
                localID: messageID,
                text: text,
                chatID: chatID,
                replyRemote: reply,
                entities: entities
            )
        }
    }

    private func deliver(
        localID: UUID,
        text: String,
        chatID: Int64,
        replyRemote: Int64?,
        entities: [MessageEntity]
    ) async {
        do {
            if let remote = try await repository.sendRemote(
                text: text,
                chatID: chatID,
                replyToRemoteID: replyRemote,
                entities: entities
            ) {
                adopt(remote, for: localID, chatID: chatID)
            } else {
                let state = try await repository.send(text: text, chatID: chatID)
                setState(state, messageID: localID, chatID: chatID)
            }
        } catch {
            setState(.failed, messageID: localID, chatID: chatID)
        }
    }

    /// Links the local placeholder to the Telegram message (or drops it if the update already added it).
    private func adopt(_ remote: Message, for localID: UUID, chatID: Int64) {
        mutateChat(chatID) { chat in
            guard let li = chat.messages.firstIndex(where: { $0.id == localID }) else { return }
            if let remoteID = remote.remoteID,
               let existing = chat.messages.firstIndex(where: { $0.remoteID == remoteID }), existing != li {
                chat.messages.remove(at: li)
            } else {
                chat.messages[li].remoteID = remote.remoteID
                chat.messages[li].date = remote.date
                if chat.messages[li].state == .sending { chat.messages[li].state = remote.state }
            }
        }
    }

    private func setState(_ state: DeliveryState, messageID: UUID, chatID: Int64) {
        mutateChat(chatID) { chat in
            if let i = chat.messages.firstIndex(where: { $0.id == messageID }) {
                chat.messages[i].state = state
            }
        }
    }

    func edit(_ messageID: UUID, in chatID: Int64, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let target = message(messageID, in: chatID) else { return }
        mutateMessage(messageID, in: chatID) { message in
            message.text = trimmed
            message.isEdited = true
            message.entities = []
        }
        if let remoteID = target.remoteID {
            let repo = repository
            Task { try? await repo.editRemote(chatID: chatID, messageID: remoteID, text: trimmed) }
        }
    }

    func deleteMessage(_ messageID: UUID, in chatID: Int64) {
        let remoteID = message(messageID, in: chatID)?.remoteID
        if let chatIndex = chats.firstIndex(where: { $0.id == chatID }) {
            chats[chatIndex].messages.removeAll { $0.id == messageID }
        }
        if var results = messageSearchResults[chatID] {
            results.removeAll { $0.id == messageID }
            messageSearchResults[chatID] = results
        }
        if let remoteID {
            let repo = repository
            Task { try? await repo.deleteRemote(chatID: chatID, messageID: remoteID) }
        }
    }

    func toggleReaction(_ emoji: String, on messageID: UUID, in chatID: Int64) {
        guard let message = message(messageID, in: chatID) else { return }
        if repository.isReal {
            guard let remoteID = message.remoteID else { return }
            let reaction = message.chosenReactions.contains(emoji) ? nil : emoji
            let repo = repository
            Task {
                do {
                    let reactions = try await repo.setMessageReaction(
                        chatID: chatID,
                        messageID: remoteID,
                        emoji: reaction
                    )
                    guard let reactions else { return }
                    mutateMessage(messageID, in: chatID) { message in
                        message.reactions = reactions
                        message.chosenReactions = reaction.map { [$0] } ?? []
                    }
                    mediaError = nil
                } catch {
                    mediaError = TGErrors.message(for: error)
                }
            }
            return
        }
        mutateMessage(messageID, in: chatID) { message in
            if let r = message.reactions.firstIndex(of: emoji) {
                message.reactions.remove(at: r)
            } else {
                message.reactions.append(emoji)
            }
        }
    }

    func setMessagePinned(_ messageID: UUID, in chatID: Int64, pinned: Bool) {
        guard let message = message(messageID, in: chatID) else { return }
        guard repository.isReal, let remoteID = message.remoteID else {
            mutateMessage(messageID, in: chatID) { message in
                message.isPinned = pinned
            }
            return
        }
        let repo = repository
        Task {
            do {
                try await repo.setMessagePinned(chatID: chatID, messageID: remoteID, pinned: pinned)
                mutateMessage(messageID, in: chatID) { message in
                    message.isPinned = pinned
                }
                mediaError = nil
            } catch {
                mediaError = TGErrors.message(for: error)
            }
        }
    }

    func votePoll(_ messageID: UUID, in chatID: Int64, optionIDs: [Int]) {
        guard let message = message(messageID, in: chatID),
              let remoteID = message.remoteID,
              let poll = message.poll,
              !poll.isClosed,
              !optionIDs.isEmpty,
              optionIDs.allSatisfy({ poll.options.indices.contains($0) }),
              poll.allowsMultipleAnswers || optionIDs.count <= 1 else { return }
        let repo = repository
        Task {
            do {
                if let fresh = try await repo.votePoll(chatID: chatID, messageID: remoteID, optionIDs: optionIDs) {
                    mutateMessage(messageID, in: chatID) { $0.poll = fresh.poll }
                }
                mediaError = nil
            } catch {
                mediaError = TGErrors.message(for: error)
            }
        }
    }

    func forwardMessages(_ messageIDs: [UUID], from sourceChatID: Int64, to destinationChatID: Int64) async {
        let remoteIDs = messageIDs.compactMap { id in message(id, in: sourceChatID)?.remoteID }
        guard !remoteIDs.isEmpty, remoteIDs.count == messageIDs.count else {
            mediaError = L("chat.forward.unavailable")
            return
        }
        do {
            try await repository.forwardMessages(
                fromChatID: sourceChatID,
                toChatID: destinationChatID,
                messageIDs: remoteIDs
            )
            mediaError = nil
        } catch {
            mediaError = TGErrors.message(for: error)
        }
    }

    func searchMessages(in chatID: Int64, query: String, loadMore: Bool = false) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            messageSearchResults[chatID] = nil
            messageSearchQueries[chatID] = nil
            searchCursors[chatID] = nil
            searchTokens[chatID] = nil
            searchingChats.remove(chatID)
            searchExhausted.remove(chatID)
            return
        }
        if loadMore {
            guard !searchingChats.contains(chatID), !searchExhausted.contains(chatID),
                  messageSearchQueries[chatID] == trimmed else { return }
        } else {
            messageSearchQueries[chatID] = trimmed
            messageSearchResults[chatID] = []
            searchCursors[chatID] = nil
            searchTokens[chatID] = nil
            searchExhausted.remove(chatID)
        }
        let requestToken = UUID()
        searchTokens[chatID] = requestToken
        searchingChats.insert(chatID)
        defer {
            if searchTokens[chatID] == requestToken {
                searchingChats.remove(chatID)
                searchTokens[chatID] = nil
            }
        }

        if !repository.isReal {
            guard searchTokens[chatID] == requestToken else { return }
            messageSearchResults[chatID] = (chat(chatID)?.messages ?? [])
                .filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
            searchExhausted.insert(chatID)
            return
        }

        let fromID = loadMore ? (searchCursors[chatID] ?? 0) : 0
        do {
            guard let page = try await repository.searchMessages(
                chatID: chatID,
                query: trimmed,
                fromMessageID: fromID,
                limit: 50
            ), messageSearchQueries[chatID] == trimmed,
                 searchTokens[chatID] == requestToken else { return }
            let existingIDs = Set((messageSearchResults[chatID] ?? []).compactMap(\.remoteID))
            let unique = page.filter { message in
                guard let remoteID = message.remoteID else { return true }
                return !existingIDs.contains(remoteID)
            }
            messageSearchResults[chatID, default: []].append(contentsOf: unique)
            if let oldest = unique.compactMap(\.remoteID).min() { searchCursors[chatID] = oldest }
            if page.count < 50 || unique.isEmpty { searchExhausted.insert(chatID) }
            mediaError = nil
        } catch {
            guard searchTokens[chatID] == requestToken else { return }
            mediaError = TGErrors.message(for: error)
        }
    }

    func searchResults(in chatID: Int64, query: String) -> [Message]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, messageSearchQueries[chatID] == trimmed else { return nil }
        return messageSearchResults[chatID]
    }

    // MARK: Drafts (local only, capped)

    func draft(for chatID: Int64) -> String { drafts[chatID] ?? "" }

    func setDraft(_ text: String, for chatID: Int64) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.removeValue(forKey: chatID)
        } else {
            drafts[chatID] = String(text.prefix(4000))
            if drafts.count > Self.maxDrafts, let victim = drafts.keys.first(where: { $0 != chatID }) {
                drafts.removeValue(forKey: victim)
            }
        }
        persistDrafts()
    }

    private func persistDrafts() {
        var stored: [String: String] = [:]
        for (id, text) in drafts { stored[String(id)] = text }
        defaults.set(stored, forKey: Self.draftsKey)
    }
}
