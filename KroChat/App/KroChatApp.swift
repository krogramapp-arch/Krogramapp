import SwiftUI

@main
struct KroChatApp: App {
    @StateObject private var themes = ThemeStore()
    @StateObject private var chats = ChatsViewModel(repository: MockChatRepository())

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(themes)
                .environmentObject(chats)
                .tint(themes.current.accent)
                .preferredColorScheme(themes.appearance.scheme)
                .task { await chats.load() }
        }
    }
}
