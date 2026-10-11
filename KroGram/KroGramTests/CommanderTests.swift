import XCTest
@testable import KroGram

@MainActor
final class CommanderTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "krochat.commander.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func chat() -> Chat {
        Chat(id: 42, title: "Test")
    }

    func testCommanderIsDisabledByDefaultAndPersistsSettings() {
        let defaults = makeDefaults()
        let first = CommanderStore(defaults: defaults)
        XCTAssertFalse(first.isEnabled)

        first.isEnabled = true
        first.calculatorEnabled = false
        let restored = CommanderStore(defaults: defaults)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertFalse(restored.calculatorEnabled)
    }

    func testHelpAndChatInfoAreLocalResults() throws {
        let store = CommanderStore(defaults: makeDefaults())
        store.isEnabled = true

        guard case .local(let help)? = CommanderCommandEngine.execute(
            "/help",
            chat: chat(),
            preferences: store.preferences
        ) else {
            return XCTFail("Expected local help result")
        }
        XCTAssertTrue(help.contains("/calc"))

        guard case .local(let id)? = CommanderCommandEngine.execute(
            "/id",
            chat: chat(),
            preferences: store.preferences
        ) else {
            return XCTFail("Expected local chat ID")
        }
        XCTAssertTrue(id.contains("42"))
    }

    func testCalculatorUsesRestrictedArithmeticParser() throws {
        let store = CommanderStore(defaults: makeDefaults())
        store.isEnabled = true

        guard case .local(let result)? = CommanderCommandEngine.execute(
            "/calc 2*(3+4)",
            chat: chat(),
            preferences: store.preferences
        ) else {
            return XCTFail("Expected calculator result")
        }
        XCTAssertTrue(result.contains("14"))

        guard case .local(let invalid)? = CommanderCommandEngine.execute(
            "/calc 1/0",
            chat: chat(),
            preferences: store.preferences
        ) else {
            return XCTFail("Expected calculator error")
        }
        XCTAssertEqual(invalid, L("commander.error.calculation"))

        guard case .local(let rejected)? = CommanderCommandEngine.execute(
            "/calc __import__('os')",
            chat: chat(),
            preferences: store.preferences
        ) else {
            return XCTFail("Expected unsafe expression to be rejected")
        }
        XCTAssertEqual(rejected, L("commander.error.calculation"))
    }

    func testTextToolsAndChatActionsAreFeatureGated() {
        let store = CommanderStore(defaults: makeDefaults())
        store.isEnabled = true

        XCTAssertEqual(
            CommanderCommandEngine.execute(
                "/upper hello",
                chat: chat(),
                preferences: store.preferences
            ),
            .local("HELLO")
        )
        XCTAssertEqual(
            CommanderCommandEngine.execute(
                "/archive",
                chat: chat(),
                preferences: store.preferences
            ),
            .archive(true)
        )

        store.textToolsEnabled = false
        store.chatActionsEnabled = false
        XCTAssertNil(CommanderCommandEngine.execute(
            "/upper hello",
            chat: chat(),
            preferences: store.preferences
        ))
        XCTAssertNil(CommanderCommandEngine.execute(
            "/archive",
            chat: chat(),
            preferences: store.preferences
        ))
    }

    func testUnknownSlashCommandsRemainTelegramMessages() {
        let store = CommanderStore(defaults: makeDefaults())
        store.isEnabled = true
        XCTAssertNil(CommanderCommandEngine.execute(
            "/telegram-bot-command value",
            chat: chat(),
            preferences: store.preferences
        ))
        XCTAssertNil(CommanderCommandEngine.execute(
            "/help",
            chat: chat(),
            preferences: CommanderPreferences(
                isEnabled: false,
                calculatorEnabled: true,
                textToolsEnabled: true,
                chatActionsEnabled: true,
                chatInfoEnabled: true,
                funGamesEnabled: true
            )
        ))
    }

    func testSuggestionsReflectFeatureSettingsAndOnlyMatchCommandNames() {
        let store = CommanderStore(defaults: makeDefaults())
        store.isEnabled = true
        store.calculatorEnabled = false

        let suggestions = CommanderCommandEngine.suggestions(
            for: "/",
            preferences: store.preferences
        )
        XCTAssertFalse(suggestions.contains("/calc "))
        XCTAssertEqual(
            CommanderCommandEngine.suggestions(for: "/calc 1", preferences: store.preferences),
            []
        )
    }

    func testFunCommandsReturnLocalResultsAndRespectFeatureToggle() {
        let preferences = CommanderPreferences(
            isEnabled: true,
            calculatorEnabled: true,
            textToolsEnabled: true,
            chatActionsEnabled: true,
            chatInfoEnabled: true,
            funGamesEnabled: true
        )
        for command in ["/coin", "/dice", "/8ball will it work?", "/rps rock"] {
            guard case .local? = CommanderCommandEngine.execute(
                command,
                chat: chat(),
                preferences: preferences
            ) else {
                return XCTFail("Expected a local game result for \(command)")
            }
        }
        let disabled = CommanderPreferences(
            isEnabled: true,
            calculatorEnabled: true,
            textToolsEnabled: true,
            chatActionsEnabled: true,
            chatInfoEnabled: true,
            funGamesEnabled: false
        )
        XCTAssertNil(CommanderCommandEngine.execute("/coin", chat: chat(), preferences: disabled))
    }
}
