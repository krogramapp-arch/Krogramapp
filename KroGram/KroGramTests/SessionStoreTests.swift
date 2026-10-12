import XCTest
import Security
@testable import KroGram

@MainActor
final class SessionStoreTests: XCTestCase {
    func testFirstLaunchRequiresAPISetupBeforeLogin() {
        XCTAssertEqual(
            SessionStore.initialSetupPhase(hasSavedCredentials: false),
            .credentials
        )
    }

    func testSavedAPICredentialsKeepWelcomeChoice() {
        XCTAssertEqual(
            SessionStore.initialSetupPhase(hasSavedCredentials: true),
            .welcome
        )
    }

    func testConnectionClosureDoesNotClearLiveModeWithoutExplicitLogout() {
        XCTAssertFalse(SessionStore.shouldClearLiveMode(afterClosedState: false))
        XCTAssertTrue(SessionStore.shouldClearLiveMode(afterClosedState: true))
    }

    func testDatabaseKeyReusesSavedValueWithoutGeneratingAnother() throws {
        let saved = Data(repeating: 7, count: 32)
        let key = try SessionStore.databaseKey(
            read: { saved },
            write: { _ in XCTFail("A saved key must not be overwritten") },
            random: { _ in XCTFail("A saved key must not be regenerated"); return errSecSuccess },
            databaseExists: { XCTFail("The database should not be checked when the key exists"); return true }
        )
        XCTAssertEqual(key, saved)
    }

    func testMissingKeyWithExistingDatabaseDoesNotGenerateReplacement() {
        XCTAssertThrowsError(try SessionStore.databaseKey(
            read: { nil },
            write: { _ in XCTFail("A replacement key must not be written") },
            random: { _ in XCTFail("A replacement key must not be generated"); return errSecSuccess },
            databaseExists: { true }
        ))
    }

    func testKeychainReadFailureDoesNotGenerateReplacement() {
        XCTAssertThrowsError(try SessionStore.databaseKey(
            read: { throw KeychainError.failed(errSecInteractionNotAllowed) },
            write: { _ in XCTFail("A replacement key must not be written") },
            random: { _ in XCTFail("A replacement key must not be generated"); return errSecSuccess },
            databaseExists: { false }
        ))
    }
}
