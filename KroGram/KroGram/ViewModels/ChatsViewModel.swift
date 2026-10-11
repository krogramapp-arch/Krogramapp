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
    @Published private(set) var drafts: [Int64: String] = [:]
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

    private static let draftsKey = "krochat.drafts.v1"
    private static let hiddenKey = "krochat.hidden.v1"
    private static let maxDrafts = 100

    init(repository: ChatRepository, privacy: PrivacyMode = .shared, defaults: UserDefaults = .standard) {
        self.repository = repository
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
        loadState = .idle
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
            async let loadedContacts = repo.loadContacts()
            let (c, f, k) = try await (loadedChats, loadedFolders, loadedContacts)
            var merged = c
            if repo.isReal {
                for i in merged.indices where hiddenIDs.contains(merged[i].id) { merged[i].isHidden = true }
            }
            chats = merged
            folders = f
            contacts = k
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    func reload() async {
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

    var mainChats: [Chat] { sorted(chats.filter { !$0.isArchived && !$0.isHidden }) }
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
        case .archived: return sorted(chats.filter { $0.isArchived })
        case .hidden: return sorted(chats.filter { $0.isHidden })
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

    func openChat(_ id: Int64) async {
        let repo = repository
        await repo.setChatOpen(id, true)
        if let history = try? await repo.loadHistory(chatID: id), !history.isEmpty {
            mutateChat(id) { chat in
                let pending = chat.messages.filter { $0.remoteID == nil && $0.isOutgoing && $0.state != .sent }
                chat.messages = history + pending
            }
        }
        if !privacy.hideRead { await markReadNow(id) }
    }

    func closeChat(_ id: Int64) {
        let repo = repository
        Task { await repo.setChatOpen(id, false) }
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
            chats[ci].messages.append(message)

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

    func send(_ text: String, in chatID: Int64, replyTo: UUID?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let replyRemote = replyTo.flatMap { id in
            chat(chatID)?.messages.first { $0.id == id }?.remoteID
        }
        let message = Message(text: trimmed, isOutgoing: true, state: .sending, replyToID: replyTo, replyToRemoteID: replyRemote)
        mutateChat(chatID) { $0.messages.append(message) }
        Task { await deliver(localID: message.id, text: trimmed, chatID: chatID, replyRemote: replyRemote) }
    }

    func retry(_ messageID: UUID, in chatID: Int64) {
        guard let message = chat(chatID)?.messages.first(where: { $0.id == messageID }) else { return }
        setState(.sending, messageID: messageID, chatID: chatID)
        let text = message.text
        let reply = message.replyToRemoteID
        Task { await deliver(localID: messageID, text: text, chatID: chatID, replyRemote: reply) }
    }

    private func deliver(localID: UUID, text: String, chatID: Int64, replyRemote: Int64?) async {
        do {
            if let remote = try await repository.sendRemote(text: text, chatID: chatID, replyToRemoteID: replyRemote) {
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
        var remoteID: Int64?
        mutateChat(chatID) { chat in
            if let i = chat.messages.firstIndex(where: { $0.id == messageID }) {
                chat.messages[i].text = trimmed
                chat.messages[i].isEdited = true
                remoteID = chat.messages[i].remoteID
            }
        }
        if let remoteID {
            let repo = repository
            Task { try? await repo.editRemote(chatID: chatID, messageID: remoteID, text: trimmed) }
        }
    }

    func deleteMessage(_ messageID: UUID, in chatID: Int64) {
        var remoteID: Int64?
        mutateChat(chatID) { chat in
            remoteID = chat.messages.first { $0.id == messageID }?.remoteID
            chat.messages.removeAll { $0.id == messageID }
        }
        if let remoteID {
            let repo = repository
            Task { try? await repo.deleteRemote(chatID: chatID, messageID: remoteID) }
        }
    }

    /// Reactions are local-only in demo mode; hidden when connected (not yet sent to Telegram).
    func toggleReaction(_ emoji: String, on messageID: UUID, in chatID: Int64) {
        guard !repository.isReal else { return }
        mutateChat(chatID) { chat in
            guard let i = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
            if let r = chat.messages[i].reactions.firstIndex(of: emoji) {
                chat.messages[i].reactions.remove(at: r)
            } else {
                chat.messages[i].reactions.append(emoji)
            }
        }
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
