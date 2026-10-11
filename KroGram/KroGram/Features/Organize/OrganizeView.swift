import SwiftUI

struct OrganizeView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var showNewFolder = false

    private let smartLists: [(scope: ChatScope, key: String, symbol: String)] = [
        (.unread, "organize.list.unread", "envelope.badge"),
        (.pinned, "organize.list.pinned", "star"),
        (.archived, "organize.list.archived", "archivebox"),
        (.hidden, "organize.list.hidden", "eye.slash")
    ]

    var body: some View {
        NavigationStack {
            List {
                smartListsSection
                foldersSection
                noteSection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("organize.title")
            .navigationDestination(for: ChatScope.self) { ChatCollectionView(scope: $0) }
            .navigationDestination(for: Int64.self) { ChatView(chatID: $0) }
            .sheet(isPresented: $showNewFolder) { NewFolderSheet() }
        }
    }

    private var smartListsSection: some View {
        Section("organize.smart") {
            ForEach(smartLists, id: \.key) { item in
                NavigationLink(value: item.scope) {
                    HStack {
                        Label(LocalizedStringKey(item.key), systemImage: item.symbol)
                        Spacer()
                        Text("\(vm.chats(in: item.scope).count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }
        }
    }

    private var foldersSection: some View {
        Section("organize.folders") {
            ForEach(vm.folders) { folder in
                NavigationLink(value: ChatScope.folder(folder.id)) {
                    HStack {
                        Label(folder.name, systemImage: folder.symbol)
                        Spacer()
                        Text("\(vm.chats(in: .folder(folder.id)).count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }
            .onDelete { offsets in
                let ids = offsets.map { vm.folders[$0].id }
                ids.forEach { vm.deleteFolder($0) }
            }
            Button { showNewFolder = true } label: {
                Label("organize.newFolder", systemImage: "plus.circle")
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
    }

    private var noteSection: some View {
        Section {
            Text("organize.note")
                .kro(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
    }
}

struct ChatCollectionView: View {
    let scope: ChatScope
    @EnvironmentObject private var vm: ChatsViewModel

    var body: some View {
        let items = vm.chats(in: scope)
        List(items) { chat in
            NavigationLink(value: chat.id) {
                ChatRow(chat: chat, draft: vm.draft(for: chat.id))
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            .swipeActions(edge: .trailing) {
                switch scope {
                case .archived:
                    Button { vm.update([chat.id]) { $0.isArchived = false } } label: {
                        Label("action.unarchive", systemImage: "tray.and.arrow.up")
                    }.tint(.orange)
                case .hidden:
                    Button { vm.update([chat.id]) { $0.isHidden = false } } label: {
                        Label("action.unhide", systemImage: "eye")
                    }.tint(.gray)
                case .folder(let id):
                    Button { vm.setFolder(id, contains: false, for: chat.id) } label: {
                        Label("action.removeFromFolder", systemImage: "folder.badge.minus")
                    }.tint(.orange)
                default:
                    EmptyView()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if items.isEmpty { ContentUnavailableView("organize.empty", systemImage: "tray") }
        }
        .navigationTitle(vm.title(for: scope))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewFolderSheet: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "folder"

    private let symbols = ["folder", "star", "briefcase", "house", "heart", "book", "gamecontroller", "cart"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("organize.folderName", text: $name)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: KroSpacing.md) {
                    ForEach(symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s)
                                .font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(symbol == s ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("organize.newFolder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.add") {
                        vm.addFolder(name: name, symbol: symbol)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
