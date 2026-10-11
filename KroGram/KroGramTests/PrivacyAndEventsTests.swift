import XCTest
@testable import KroGram

@MainActor
final class PrivacyAndEventsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "krochat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeVM(privacy: PrivacyMode) async -> ChatsViewModel {
        let vm = ChatsViewModel(
            repository: MockChatRepository(delay: .zero),
            privacy: privacy,
            defaults: makeDefaults()
        )
        await vm.load()
        return vm
    }

    func testPrivacyPersistsAndNotifies() {
        let defaults = makeDefaults()
        let privacy = PrivacyMode(defaults: defaults)
        var notified = 0
        privacy.onChange = { notified += 1 }
        privacy.hideRead = true
        privacy.hideOnline = true
        XCTAssertEqual(notified, 2)
        XCTAssertEqual(privacy.snapshot, PrivacySnapshot(hideRead: true, hideTyping: false, hideOnline: true))

        let reloaded = PrivacyMode(defaults: defaults)
        XCTAssertTrue(reloaded.hideRead)
        XCTAssertFalse(reloaded.hideTyping)
        XCTAssertTrue(reloaded.hideOnline)
    }

    func testOpeningChatMarksReadWhenGhostIsOff() async {
        let privacy = PrivacyMode(defaults: makeDefaults())
        let vm = await makeVM(privacy: privacy)
        XCTAssertEqual(vm.chat(1)?.unread, 2)
        await vm.openChat(1)
        XCTAssertEqual(vm.chat(1)?.unread, 0)
    }

    func testGhostReadKeepsChatUnreadUntilManualMark() async {
        let privacy = PrivacyMode(defaults: makeDefaults())
        privacy.hideRead = true
        let vm = await makeVM(privacy: privacy)
        await vm.openChat(1)
        XCTAssertEqual(vm.chat(1)?.unread, 2)
        await vm.markReadNow(1)
        XCTAssertEqual(vm.chat(1)?.unread, 0)
    }

    func testNewMessageEventDedupesByRemoteID() async {
        let vm = await makeVM(privacy: PrivacyMode(defaults: makeDefaults()))
        let before = vm.chat(3)?.messages.count ?? 0
        let message = Message(text: "جديدة", isOutgoing: false, remoteID: 999)
        vm.apply(.newMessage(chatID: 3, message: message))
        vm.apply(.newMessage(chatID: 3, message: message))
        XCTAssertEqual(vm.chat(3)?.messages.count, before + 1)
    }

    func testSendSucceededUpdatesPlaceholder() async {
        let vm = await makeVM(privacy: PrivacyMode(defaults: makeDefaults()))
        let pending = Message(text: "x", isOutgoing: true, state: .sending, remoteID: 5)
        vm.apply(.newMessage(chatID: 3, message: pending))
        let confirmed = Message(text: "x", isOutgoing: true, state: .sent, remoteID: 6)
        vm.apply(.sendSucceeded(chatID: 3, oldRemoteID: 5, message: confirmed))
        let stored = vm.chat(3)?.messages.first { $0.remoteID == 6 }
        XCTAssertEqual(stored?.state, .sent)
    }

    func testDeleteIsDisabledForLiveRepositoryContract() async {
        let vm = await makeVM(privacy: PrivacyMode(defaults: makeDefaults()))
        XCTAssertTrue(vm.canDeleteChats)
        XCTAssertFalse(vm.isLive)
    }

    func testEffectiveEffectsRespectsReduceMotion() {
        let store = ThemeStore(defaults: makeDefaults())
        store.effects = .full
        XCTAssertNotEqual(store.effectiveEffects(reduceMotion: true), .full)
        store.effects = .off
        XCTAssertEqual(store.effectiveEffects(reduceMotion: false), .off)
    }
}
