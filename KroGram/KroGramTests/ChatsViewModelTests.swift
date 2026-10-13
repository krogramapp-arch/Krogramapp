import XCTest
@testable import KroGram

private struct SearchPagingRepository: ChatRepository {
    var isReal: Bool { true }

    func loadChats() async throws -> [Chat] { [] }
    func loadFolders() async throws -> [ChatFolder] { [] }
    func loadContacts() async throws -> [Contact] { [] }
    func send(text: String, chatID: Int64) async throws -> DeliveryState { .sent }

    func searchMessages(chatID: Int64, query: String, fromMessageID: Int64, limit: Int) async throws -> [Message]? {
        XCTAssertEqual(query, "needle")
        XCTAssertEqual(limit, 50)
        if fromMessageID == 0 {
            return [
                Message(text: "needle new", isOutgoing: false, remoteID: 30),
                Message(text: "needle middle", isOutgoing: false, remoteID: 20)
            ]
        }
        XCTAssertEqual(fromMessageID, 20)
        return [
            Message(text: "needle middle", isOutgoing: false, remoteID: 20),
            Message(text: "needle old", isOutgoing: false, remoteID: 10)
        ]
    }
}

@MainActor
final class ChatsViewModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "krochat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeVM() async -> ChatsViewModel {
        let vm = ChatsViewModel(repository: MockChatRepository(delay: .zero), defaults: makeDefaults())
        await vm.load()
        return vm
    }

    func testLoadExcludesArchivedAndHidden() async {
        let vm = await makeVM()
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertFalse(vm.mainChats.contains { $0.isArchived || $0.isHidden })
    }

    func testPinnedChatsSortFirst() async {
        let vm = await makeVM()
        let firstUnpinned = vm.mainChats.firstIndex { !$0.isPinned }
        let lastPinned = vm.mainChats.lastIndex { $0.isPinned }
        if let firstUnpinned, let lastPinned {
            XCTAssertLessThan(lastPinned, firstUnpinned)
        }
    }

    func testSearchMatchesTitleAndMessageText() async {
        let vm = await makeVM()
        vm.searchText = "فريق"
        XCTAssertEqual(vm.visibleChats.map(\.id), [2])
        vm.searchText = "المراجعة"
        XCTAssertEqual(vm.visibleChats.map(\.id), [1])
    }

    func testMessageSearchLoadsOlderPagesWithoutDuplicates() async {
        let vm = ChatsViewModel(repository: SearchPagingRepository(), defaults: makeDefaults())

        await vm.searchMessages(in: 1, query: "needle")
        XCTAssertEqual(vm.searchResults(in: 1, query: "needle")?.compactMap(\.remoteID), [30, 20])
        XCTAssertEqual(vm.searchResults(in: 1, query: " needle ")?.compactMap(\.remoteID), [30, 20])

        await vm.searchMessages(in: 1, query: "needle", loadMore: true)
        XCTAssertEqual(vm.searchResults(in: 1, query: "needle")?.compactMap(\.remoteID), [30, 20, 10])
    }

    func testUnreadFilter() async {
        let vm = await makeVM()
        vm.filter = .unread
        XCTAssertTrue(vm.visibleChats.allSatisfy { $0.unread > 0 })
    }

    func testDeleteThenUndoRestoresChat() async {
        let vm = await makeVM()
        vm.delete([3])
        XCTAssertNil(vm.chat(3))
        XCTAssertNotNil(vm.undoBanner)
        vm.undo()
        XCTAssertNotNil(vm.chat(3))
        XCTAssertNil(vm.undoBanner)
    }

    func testArchiveThenUndo() async {
        let vm = await makeVM()
        vm.update([1]) { $0.isArchived = true }
        XCTAssertEqual(vm.chat(1)?.isArchived, true)
        vm.undo()
        XCTAssertEqual(vm.chat(1)?.isArchived, false)
    }

    func testSendMarksMessageSentThenFailureOnDemandPrefix() async throws {
        let vm = await makeVM()
        vm.send("hello", in: 3, replyTo: nil)
        XCTAssertEqual(vm.chat(3)?.messages.last?.state, .sending)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.chat(3)?.messages.last?.state, .sent)

        vm.send("/fail please", in: 3, replyTo: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.chat(3)?.messages.last?.state, .failed)
    }

    func testDraftsPersistAndClear() async {
        let vm = await makeVM()
        vm.setDraft("نص غير مكتمل", for: 1)
        XCTAssertEqual(vm.draft(for: 1), "نص غير مكتمل")
        vm.setDraft("   ", for: 1)
        XCTAssertEqual(vm.draft(for: 1), "")
    }

    func testFoldersPersistAcrossViewModelRecreation() async {
        let defaults = makeDefaults()
        let first = ChatsViewModel(repository: MockChatRepository(delay: .zero), defaults: defaults)
        first.addFolder(name: "الملاحظات", symbol: "note")
        let second = ChatsViewModel(repository: MockChatRepository(delay: .zero), defaults: defaults)
        XCTAssertTrue(second.folders.contains { $0.name == "الملاحظات" })
        XCTAssertEqual(first.folders, second.folders)
    }

    func testDateFilterToday() {
        XCTAssertTrue(DateFilter.today.matches(.now))
        XCTAssertFalse(DateFilter.today.matches(Date().addingTimeInterval(-3 * 86_400)))
        XCTAssertTrue(DateFilter.week.matches(Date().addingTimeInterval(-3 * 86_400)))
    }
}
