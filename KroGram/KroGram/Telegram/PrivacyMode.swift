import Foundation

/// Ghost-style options. They only control what this client sends about the account
/// (read receipts, typing indicator, online status). Local preferences, no account data.
@MainActor
final class PrivacyMode: ObservableObject {
    static let shared = PrivacyMode()

    @Published var hideRead: Bool { didSet { save(); onChange?() } }
    @Published var hideTyping: Bool { didSet { save(); onChange?() } }
    @Published var hideOnline: Bool { didSet { save(); onChange?() } }

    /// Set by the view model to push changes to the active repository.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private static let key = "krochat.privacy.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        hideRead = stored["hideRead"] ?? false
        hideTyping = stored["hideTyping"] ?? false
        hideOnline = stored["hideOnline"] ?? false
    }

    var snapshot: PrivacySnapshot {
        PrivacySnapshot(hideRead: hideRead, hideTyping: hideTyping, hideOnline: hideOnline)
    }

    private func save() {
        defaults.set(["hideRead": hideRead, "hideTyping": hideTyping, "hideOnline": hideOnline], forKey: Self.key)
    }
}
