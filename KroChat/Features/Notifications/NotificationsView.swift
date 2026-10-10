import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var vm: ChatsViewModel

    var body: some View {
        NavigationStack {
            let unread = vm.chats(in: .unread)
            List {
                Section {
                    DemoBanner().listRowSeparator(.hidden)
                }
                Section("notifications.unread") {
                    ForEach(unread) { chat in
                        NavigationLink(value: chat.id) {
                            HStack(spacing: KroSpacing.md) {
                                AvatarView(name: chat.title, seed: Int(truncatingIfNeeded: chat.id), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title).kro(.body, weight: .medium)
                                    Text(chat.lastMessageText).kro(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                UnreadBadge(count: chat.unread, muted: chat.isMuted)
                            }
                        }
                    }
                }
                Section {
                    Text("notifications.note").kro(.footnote).foregroundStyle(.secondary)
                }
            }
            .overlay {
                if unread.isEmpty { ContentUnavailableView("notifications.empty", systemImage: "bell") }
            }
            .navigationTitle("notifications.title")
            .navigationDestination(for: Int64.self) { ChatView(chatID: $0) }
        }
    }
}
