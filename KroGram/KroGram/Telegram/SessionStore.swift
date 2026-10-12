import Foundation
import Security
import SwiftUI

/// Decides what the user sees at launch: welcome, login steps, demo, or the live account.
@MainActor
final class SessionStore: ObservableObject {
    enum Phase: Equatable {
        case welcome
        case credentials
        case connecting
        case login(AuthStep)
        case live
        case demo
    }

    @Published private(set) var phase: Phase = .welcome
    @Published private(set) var isBusy = false
    @Published var errorText: String?
    @Published private(set) var sessionIssue: String?

    private let chats: ChatsViewModel
    private let privacy: PrivacyMode
    private let defaults: UserDefaults
    private var service: TelegramService?
    private var stepsTask: Task<Void, Never>?
    private var restoringLiveSession = false
    private var explicitLogoutRequested = false

    private static let credentialsKey = "tg.credentials"
    private static let modeKey = "krochat.lastmode.v1"

    init(chats: ChatsViewModel, privacy: PrivacyMode, defaults: UserDefaults = .standard) {
        self.chats = chats
        self.privacy = privacy
        self.defaults = defaults
    }

    var hasSavedCredentials: Bool { (try? Self.loadCredentials()) != nil }

    // MARK: Launch

    func bootstrap() async {
        switch defaults.string(forKey: Self.modeKey) {
        case "live":
            restoringLiveSession = true
            do {
                if let credentials = try Self.loadCredentials() {
                    startService(credentials, restoring: true)
                } else {
                    sessionIssue = L("session.credentialsUnavailable")
                    errorText = sessionIssue
                    phase = .login(.failed(sessionIssue ?? ""))
                }
            } catch {
                sessionIssue = L("session.keychainUnavailable")
                phase = .live
            }
        case "demo":
            await enterDemo()
        default:
            do {
                phase = Self.initialSetupPhase(hasSavedCredentials: try Self.loadCredentials() != nil)
            } catch {
                sessionIssue = L("session.keychainUnavailable")
                phase = .credentials
            }
        }
    }

    static func initialSetupPhase(hasSavedCredentials: Bool) -> Phase {
        hasSavedCredentials ? .welcome : .credentials
    }

    static func shouldClearLiveMode(afterClosedState explicitLogoutRequested: Bool) -> Bool {
        explicitLogoutRequested
    }

    func retryConnection() {
        guard restoringLiveSession || defaults.string(forKey: Self.modeKey) == "live" else { return }
        do {
            guard let credentials = try Self.loadCredentials() else {
                sessionIssue = L("session.credentialsUnavailable")
                return
            }
            startService(credentials, restoring: true)
        } catch {
            sessionIssue = L("session.keychainUnavailable")
        }
    }

    // MARK: Navigation between login steps

    func beginLogin() {
        errorText = nil
        do {
            if let credentials = try Self.loadCredentials() {
                startService(credentials)
            } else {
                phase = .credentials
            }
        } catch {
            errorText = L("session.keychainUnavailable")
        }
    }

    func backToWelcome() {
        errorText = nil
        teardown()
        phase = .welcome
    }

    func enterDemo() async {
        teardown()
        defaults.set("demo", forKey: Self.modeKey)
        chats.attach(MockChatRepository())
        phase = .demo
        await chats.reload()
    }

    // MARK: Credentials

    func saveCredentials(apiIDText: String, apiHash: String) {
        let hash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(apiIDText.trimmingCharacters(in: .whitespacesAndNewlines)),
              TelegramCredentials.isValid(apiID: id, apiHash: hash) else {
            errorText = L("login.creds.invalid")
            return
        }
        let credentials = TelegramCredentials(apiID: id, apiHash: hash.lowercased())
        do {
            let data = try JSONEncoder().encode(credentials)
            try Keychain.set(data, for: Self.credentialsKey)
        } catch {
            errorText = L("err.generic")
            return
        }
        errorText = nil
        startService(credentials)
    }

    /// Removes the API credentials from this device (Keychain).
    func forgetCredentials() {
        Keychain.remove(Self.credentialsKey)
        objectWillChange.send()
    }

    private static func loadCredentials() throws -> TelegramCredentials? {
        guard let data = try Keychain.get(credentialsKey) else { return nil }
        return try? JSONDecoder().decode(TelegramCredentials.self, from: data)
    }

    static func databaseKey(
        read: () throws -> Data?,
        write: (Data) throws -> Void,
        random: (inout [UInt8]) -> OSStatus,
        databaseExists: () throws -> Bool
    ) throws -> Data {
        if let existing = try read() { return existing }
        let hasExistingDatabase = try databaseExists()
        guard !hasExistingDatabase else { throw KeychainError.existingDatabaseKeyMissing }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = random(&bytes)
        guard status == errSecSuccess else { throw KeychainError.failed(status) }
        let key = Data(bytes)
        try write(key)
        return key
    }

    private static func databaseKey() throws -> Data {
        try databaseKey(
            read: { try Keychain.get("tg.dbkey") },
            write: { try Keychain.set($0, for: "tg.dbkey") },
            random: { bytes in SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) },
            databaseExists: {
                let directory = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("KroGram/tdlib", isDirectory: true)
                do {
                    return !(try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty
                } catch {
                    let nsError = error as NSError
                    if nsError.code == NSFileReadNoSuchFileError { return false }
                    throw error
                }
            }
        )
    }

    // MARK: Telegram session

    private func startService(_ credentials: TelegramCredentials, restoring: Bool = false) {
        teardown()
        let key: Data
        do {
            key = try Self.databaseKey()
        } catch {
            if let keychainError = error as? KeychainError,
               case .existingDatabaseKeyMissing = keychainError {
                sessionIssue = L("session.databaseKeyMissing")
            } else {
                sessionIssue = L("session.keychainUnavailable")
            }
            if !restoring { errorText = sessionIssue }
            phase = restoring ? .live : .login(.failed(sessionIssue ?? ""))
            return
        }
        sessionIssue = nil
        explicitLogoutRequested = false
        restoringLiveSession = restoring
        let newService = TelegramService(credentials: credentials, dbKey: key)
        service = newService
        if restoring {
            chats.attach(TelegramChatRepository(service: newService))
            phase = .live
        } else {
            phase = .connecting
        }
        let steps = newService.authSteps
        stepsTask = Task { [weak self] in
            for await step in steps {
                await self?.handle(step)
            }
        }
        let snapshot = privacy.snapshot
        Task {
            await newService.apply(privacy: snapshot)
            await newService.start()
        }
    }

    private func handle(_ step: AuthStep) async {
        isBusy = false
        switch step {
        case .starting:
            if !restoringLiveSession { phase = .connecting }
        case .databaseReady:
            if restoringLiveSession { await chats.load() }
        case .ready:
            guard let service else { return }
            defaults.set("live", forKey: Self.modeKey)
            chats.attach(TelegramChatRepository(service: service))
            phase = .live
            restoringLiveSession = false
            sessionIssue = nil
            await chats.reload()
        case .closed:
            if Self.shouldClearLiveMode(afterClosedState: explicitLogoutRequested) {
                explicitLogoutRequested = false
                restoringLiveSession = false
                defaults.removeObject(forKey: Self.modeKey)
                teardown()
                chats.attach(MockChatRepository())
                phase = .welcome
            } else {
                sessionIssue = L("session.connectionInterrupted")
                if restoringLiveSession { phase = .live }
            }
        case .failed(let message):
            if restoringLiveSession {
                sessionIssue = message
                phase = .live
            } else {
                errorText = message
                phase = .login(step)
            }
        case .waitPhone, .waitCode, .waitPassword, .unsupported:
            errorText = nil
            if restoringLiveSession, case .waitPhone = step {
                restoringLiveSession = false
                defaults.removeObject(forKey: Self.modeKey)
                sessionIssue = L("session.terminated")
                phase = .login(step)
            } else if !restoringLiveSession {
                phase = .login(step)
            }
        }
    }

    private func teardown() {
        stepsTask?.cancel()
        stepsTask = nil
        service = nil
    }

    // MARK: Auth actions

    func submitPhone(_ phone: String) {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        run { try await $0.submitPhone(trimmed) }
    }

    func submitCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        run { try await $0.submitCode(trimmed) }
    }

    func submitPassword(_ password: String) {
        run { try await $0.submitPassword(password) }
    }

    private func run(_ operation: @escaping (TelegramService) async throws -> Void) {
        guard let service, !isBusy else { return }
        isBusy = true
        errorText = nil
        Task {
            do {
                try await operation(service)
            } catch {
                errorText = TGErrors.message(for: error)
            }
            isBusy = false
        }
    }

    func logOut() async {
        guard let service else { return }
        explicitLogoutRequested = true
        do {
            try await service.logOut()
        } catch {
            explicitLogoutRequested = false
            errorText = TGErrors.message(for: error)
        }
    }
}
