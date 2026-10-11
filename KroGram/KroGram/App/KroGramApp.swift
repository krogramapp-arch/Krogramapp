import SwiftUI

@main
@MainActor
struct KroGramApp: App {
    @StateObject private var themes: ThemeStore
    @StateObject private var privacy: PrivacyMode
    @StateObject private var chats: ChatsViewModel
    @StateObject private var session: SessionStore
    @StateObject private var commander: CommanderStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let privacyMode = PrivacyMode.shared
        let chatsModel = ChatsViewModel(repository: MockChatRepository(), privacy: privacyMode)
        _themes = StateObject(wrappedValue: ThemeStore())
        _privacy = StateObject(wrappedValue: privacyMode)
        _chats = StateObject(wrappedValue: chatsModel)
        _session = StateObject(wrappedValue: SessionStore(chats: chatsModel, privacy: privacyMode))
        _commander = StateObject(wrappedValue: CommanderStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themes)
                .environmentObject(privacy)
                .environmentObject(chats)
                .environmentObject(session)
                .environmentObject(commander)
                .tint(themes.current.accent)
                .preferredColorScheme(themes.appearance.scheme)
                .task { await session.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    chats.setForeground(phase == .active)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch session.phase {
            case .live, .demo:
                if themes.shouldAnimate(reduceMotion: reduceMotion) {
                    RootTabView()
                        .transition(KroBlurTransition())
                } else {
                    RootTabView()
                        .transition(.identity)
                }
            default:
                if themes.shouldAnimate(reduceMotion: reduceMotion) {
                    LoginView()
                        .transition(KroBlurTransition())
                } else {
                    LoginView()
                        .transition(.identity)
                }
            }
        }
        .animation(themes.shouldAnimate(reduceMotion: reduceMotion) ? .smooth : nil, value: isInApp)
    }

    private var isInApp: Bool {
        session.phase == .live || session.phase == .demo
    }
}
