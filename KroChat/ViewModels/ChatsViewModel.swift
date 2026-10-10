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
    @Published var searchText = ""
    @Published var filter: ChatFilter = .all
    @Published var dateFilter: DateFilter = .any
    @Published var selectedFolderID: UUID?
    @Published var undoBanner: UndoBanner?

    private let repository: ChatRepository
    private let defaults: UserDefaults
    private var undoTask: Task<Void, Never>?
    private static let draftsKey = "krochat.drafts.v1"
    private static let maxDrafts = 100

    init(repository: ChatRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        let stored = (defaults.dictionary(forKey: Self.draftsKey) as? [String: String]) ?? [:]
        var restored: [Int64: String] = [:]
        for (key, value) in stored {
            if let id = Int64(key) { restored[id] = value }
        }
        drafts = restored
    }

    // MARK: Loading

    func load() async {
        guard loadState == .idle || loadState == .failed else { return }
        loadState = .loading
        do {
            async let loadedChats = repository.loadChats()
            async let loadedFolders = repository.loadFolders()
            async let loadedContacts = repository.loadContacts()
            let (c, f, k) = try await (loadedChats, loadedFolders, loadedContacts)
            chats = c
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
    var totalUnread: Int { mainChats.reduce(0) { $0 + $1.unread } }

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
        presentUndo(String(format: L(undoKey), before.count), restore: before)
    }

    func delete(_ ids: Set<Int64>) {
        let before = chats.filter { ids.contains($0.id) }
        guard !before.isEmpty else { return }
        chats.removeAll { ids.contains($0.id) }
        if selectedFolderID != nil, !folders.contains(where: { $0.id == selectedFolderID }) {
            selectedFolderID = nil
        }
        presentUndo(String(format: L("undo.deleted"), before.count), restore: before)
    }

    func undo() {
        guard let banner = undoBanner else { return }
        for old in banner.restore {
            if let i = chats.firstIndex(where: { $0.id == old.id }) {
                chats[i] = old
            } else {
                chats.append(old)
            }
        }
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

    // MARK: Folders

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

    // MARK: Messages

    private func mutateChat(_ id: Int64, _ change: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[i])
    }

    func markRead(_ chatID: Int64) {
        mutateChat(chatID) { $0.unread = 0 }
    }

    func send(_ text: String, in chatID: Int64, replyTo: UUID?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = Message(text: trimmed, isOutgoing: true, state: .sending, replyToID: replyTo)
        mutateChat(chatID) { $0.messages.append(message) }
        Task { await deliver(messageID: message.id, text: trimmed, chatID: chatID) }
    }

    func retry(_ messageID: UUID, in chatID: Int64) {
        guard let text = chat(chatID)?.messages.first(where: { $0.id == messageID })?.text else { return }
        setState(.sending, messageID: messageID, chatID: chatID)
        Task { await deliver(messageID: messageID, text: text, chatID: chatID) }
    }

    private func deliver(messageID: UUID, text: String, chatID: Int64) async {
        do {
            let state = try await repository.send(text: text, chatID: chatID)
            setState(state, messageID: messageID, chatID: chatID)
        } catch {
            setState(.failed, messageID: messageID, chatID: chatID)
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
        mutateChat(chatID) { chat in
            if let i = chat.messages.firstIndex(where: { $0.id == messageID }) {
                chat.messages[i].text = trimmed
                chat.messages[i].isEdited = true
            }
        }
    }

    func deleteMessage(_ messageID: UUID, in chatID: Int64) {
        mutateChat(chatID) { $0.messages.removeAll { $0.id == messageID } }
    }

    func toggleReaction(_ emoji: String, on messageID: UUID, in chatID: Int64) {
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
