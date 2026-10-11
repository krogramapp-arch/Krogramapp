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

    private let chats: ChatsViewModel
    private let privacy: PrivacyMode
    private let defaults: UserDefaults
    private var service: TelegramService?
    private var stepsTask: Task<Void, Never>?

    private static let credentialsKey = "tg.credentials"
    private static let databaseKeyName = "tg.dbkey"
    private static let modeKey = "krochat.lastmode.v1"

    init(chats: ChatsViewModel, privacy: PrivacyMode, defaults: UserDefaults = .standard) {
        self.chats = chats
        self.privacy = privacy
        self.defaults = defaults
    }

    var hasSavedCredentials: Bool { Self.loadCredentials() != nil }

    // MARK: Launch

    func bootstrap() async {
        switch defaults.string(forKey: Self.modeKey) {
        case "live":
            if let credentials = Self.loadCredentials() {
                startService(credentials)
            } else {
                phase = Self.initialSetupPhase(hasSavedCredentials: false)
            }
        case "demo":
            await enterDemo()
        default:
            phase = Self.initialSetupPhase(hasSavedCredentials: Self.loadCredentials() != nil)
        }
    }

    static func initialSetupPhase(hasSavedCredentials: Bool) -> Phase {
        hasSavedCredentials ? .welcome : .credentials
    }

    // MARK: Navigation between login steps

    func beginLogin() {
        errorText = nil
        if let credentials = Self.loadCredentials() {
            startService(credentials)
        } else {
            phase = .credentials
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
        guard let data = try? JSONEncoder().encode(credentials),
              (try? Keychain.set(data, for: Self.credentialsKey)) != nil else {
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

    private static func loadCredentials() -> TelegramCredentials? {
        guard let data = Keychain.get(credentialsKey) else { return nil }
        return try? JSONDecoder().decode(TelegramCredentials.self, from: data)
    }

    private static func databaseKey() -> Data {
        if let existing = Keychain.get(databaseKeyName) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let key = Data(bytes)
        try? Keychain.set(key, for: databaseKeyName)
        return key
    }

    // MARK: Telegram session

    private func startService(_ credentials: TelegramCredentials) {
        teardown()
        let newService = TelegramService(credentials: credentials, dbKey: Self.databaseKey())
        service = newService
        phase = .connecting
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
            phase = .connecting
        case .ready:
            guard let service else { return }
            defaults.set("live", forKey: Self.modeKey)
            chats.attach(TelegramChatRepository(service: service))
            phase = .live
            await chats.reload()
        case .closed:
            teardown()
            defaults.removeObject(forKey: Self.modeKey)
            chats.attach(MockChatRepository())
            phase = .welcome
        case .failed(let message):
            errorText = message
            phase = .login(step)
        case .waitPhone, .waitCode, .waitPassword, .unsupported:
            errorText = nil
            phase = .login(step)
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
        await service.logOut()
    }
}
