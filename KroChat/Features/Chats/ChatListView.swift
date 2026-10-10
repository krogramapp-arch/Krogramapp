import SwiftUI

struct ChatRow: View {
    let chat: Chat
    let draft: String
    @EnvironmentObject private var themes: ThemeStore

    var body: some View {
        HStack(spacing: KroSpacing.md) {
            AvatarView(
                name: chat.title,
                seed: Int(truncatingIfNeeded: chat.id),
                size: 52,
                showsOnline: chat.kind == .direct && chat.isOnline
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if chat.kind != .direct {
                        Image(systemName: chat.kind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(chat.title).kro(.headline, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(chat.lastDate.chatListString)
                        .kro(.caption)
                        .foregroundStyle(chat.unread > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                HStack(spacing: 6) {
                    preview
                    Spacer(minLength: 4)
                    if chat.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if chat.isPinned && chat.unread == 0 {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if chat.unread > 0 {
                        UnreadBadge(count: chat.unread, muted: chat.isMuted)
                    }
                }
            }
        }
        .padding(.vertical, themes.current.density.rowPadding)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        if !draft.isEmpty {
            (Text("chats.draft").foregroundColor(.red) + Text(" ") + Text(draft))
                .kro(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(chat.lastMessageText)
                .kro(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// Used as the long-press preview. Takes the theme as a value because
/// context-menu previews are rendered outside the normal environment.
struct ChatPreview: View {
    let chat: Chat
    let theme: KroTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chat.title).font(.headline)
            Divider()
            ForEach(chat.messages.suffix(5)) { message in
                HStack {
                    if message.isOutgoing { Spacer(minLength: 24) }
                    Text(message.text)
                        .font(.subheadline)
                        .padding(8)
                        .foregroundStyle(message.isOutgoing ? theme.onAccent : Color.primary)
                        .background(
                            message.isOutgoing ? theme.accent : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: min(theme.bubbleRadius, 16), style: .continuous)
                        )
                    if !message.isOutgoing { Spacer(minLength: 24) }
                }
            }
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

struct ChatListView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @EnvironmentObject private var themes: ThemeStore
    @State private var selection = Set<Int64>()
    @State private var editMode: EditMode = .inactive
    @State private var pendingDelete = Set<Int64>()
    @State private var showDeleteDialog = false

    private var isEditing: Bool { editMode == .active }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    DemoBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    filterBar
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                ForEach(vm.visibleChats) { chat in
                    NavigationLink(value: chat.id) {
                        ChatRow(chat: chat, draft: vm.draft(for: chat.id))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            askDelete([chat.id])
                        } label: { Label("action.delete", systemImage: "trash") }
                        Button {
                            vm.update([chat.id]) { $0.isArchived = true }
                        } label: { Label("action.archive", systemImage: "archivebox") }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            vm.update([chat.id]) { $0.isPinned.toggle() }
                        } label: {
                            Label(chat.isPinned ? "action.unpin" : "action.pin",
                                  systemImage: chat.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(themes.current.accent)
                        Button {
                            vm.update([chat.id]) { $0.isHidden = true }
                        } label: { Label("action.hide", systemImage: "eye.slash") }
                        .tint(.gray)
                    }
                    .contextMenu {
                        Button {
                            vm.update([chat.id]) { $0.isPinned.toggle() }
                        } label: {
                            Label(chat.isPinned ? "action.unpin" : "action.pin",
                                  systemImage: chat.isPinned ? "pin.slash" : "pin")
                        }
                        folderMenu(for: chat)
                        Button {
                            vm.update([chat.id]) { $0.isArchived = true }
                        } label: { Label("action.archive", systemImage: "archivebox") }
                        Button(role: .destructive) {
                            askDelete([chat.id])
                        } label: { Label("action.delete", systemImage: "trash") }
                    } preview: {
                        ChatPreview(chat: chat, theme: themes.current)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.reload() }
            .overlay { stateOverlay }
            .searchable(text: $vm.searchText, prompt: Text("chats.search.prompt"))
            .navigationTitle("chats.title")
            .navigationDestination(for: Int64.self) { ChatView(chatID: $0) }
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "action.done" : "action.select") {
                        withAnimation {
                            editMode = isEditing ? .inactive : .active
                            selection.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("date.title", selection: $vm.dateFilter) {
                            ForEach(DateFilter.allCases) { option in
                                Text(LocalizedStringKey(option.titleKey)).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: vm.dateFilter == .any ? "calendar" : "calendar.badge.clock")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditing && !selection.isEmpty { bulkBar }
            }
            .confirmationDialog("delete.title", isPresented: $showDeleteDialog, titleVisibility: .visible) {
                Button("action.delete", role: .destructive) {
                    vm.delete(pendingDelete)
                    selection.removeAll()
                }
                Button("action.hide") {
                    vm.update(pendingDelete) { $0.isHidden = true }
                    selection.removeAll()
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text(String(format: L("delete.preview"), pendingDelete.count) + "\n" + L("delete.hint"))
            }
        }
    }

    // MARK: Pieces

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KroSpacing.sm) {
                ForEach(ChatFilter.allCases) { option in
                    FilterChip(label: Text(LocalizedStringKey(option.titleKey)), isOn: vm.filter == option) {
                        withAnimation(.snappy) { vm.filter = option }
                    }
                }
                ForEach(vm.folders) { folder in
                    FilterChip(label: Text(verbatim: folder.name), isOn: vm.selectedFolderID == folder.id) {
                        withAnimation(.snappy) {
                            vm.selectedFolderID = vm.selectedFolderID == folder.id ? nil : folder.id
                        }
                    }
                }
            }
            .padding(.horizontal, KroSpacing.lg)
            .padding(.vertical, KroSpacing.xs)
        }
    }

    private var bulkBar: some View {
        HStack {
            Button { vm.update(selection) { $0.isPinned = true }; selection.removeAll() } label: {
                Label("action.pin", systemImage: "pin")
            }
            Spacer()
            Button { vm.update(selection) { $0.isArchived = true }; selection.removeAll() } label: {
                Label("action.archive", systemImage: "archivebox")
            }
            Spacer()
            Button { vm.update(selection) { $0.isHidden = true }; selection.removeAll() } label: {
                Label("action.hide", systemImage: "eye.slash")
            }
            Spacer()
            Button(role: .destructive) { askDelete(selection) } label: {
                Label("action.delete", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, KroSpacing.xl)
        .padding(.vertical, KroSpacing.md)
        .background(.bar)
    }

    @ViewBuilder
    private func folderMenu(for chat: Chat) -> some View {
        if !vm.folders.isEmpty {
            Menu {
                ForEach(vm.folders) { folder in
                    let isIn = chat.folderIDs.contains(folder.id)
                    Button {
                        vm.setFolder(folder.id, contains: !isIn, for: chat.id)
                    } label: {
                        Label(folder.name, systemImage: isIn ? "checkmark" : folder.symbol)
                    }
                }
            } label: {
                Label("action.moveToFolder", systemImage: "folder.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if vm.chats.isEmpty && (vm.loadState == .idle || vm.loadState == .loading) {
            ProgressView()
        } else if vm.chats.isEmpty && vm.loadState == .failed {
            VStack(spacing: KroSpacing.md) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                Text("chats.loadFailed").kro(.headline)
                Button("chats.retry") { Task { await vm.reload() } }
                    .buttonStyle(KroPrimaryButtonStyle())
            }
        } else if vm.visibleChats.isEmpty {
            ContentUnavailableView("chats.empty", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private func askDelete(_ ids: Set<Int64>) {
        pendingDelete = ids
        showDeleteDialog = true
    }
}
