import XCTest
@testable import KroGram

@MainActor
final class ChatsViewModelTests: XCTestCase {
    private func makeVM() async -> ChatsViewModel {
        let name = "krochat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let vm = ChatsViewModel(repository: MockChatRepository(delay: .zero), defaults: defaults)
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

    func testDateFilterToday() {
        XCTAssertTrue(DateFilter.today.matches(.now))
        XCTAssertFalse(DateFilter.today.matches(Date().addingTimeInterval(-3 * 86_400)))
        XCTAssertTrue(DateFilter.week.matches(Date().addingTimeInterval(-3 * 86_400)))
    }
}
