import XCTest
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
}
