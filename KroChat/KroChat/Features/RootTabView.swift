import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView {
            ChatListView()
                .tabItem { Label("tab.chats", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(vm.totalUnread)
            ContactsView()
                .tabItem { Label("tab.contacts", systemImage: "person.2.fill") }
            OrganizeView()
                .tabItem { Label("tab.organize", systemImage: "square.grid.2x2.fill") }
            NotificationsView()
                .tabItem { Label("tab.notifications", systemImage: "bell.fill") }
            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .bottom) {
            if let banner = vm.undoBanner {
                UndoBannerView(banner: banner) { vm.undo() }
                    .padding(.horizontal, KroSpacing.lg)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: vm.undoBanner?.id)
    }
}
