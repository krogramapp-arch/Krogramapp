import SwiftUI
import UIKit

struct ContactsView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var query = ""
    @State private var avatarImages: [Int64: UIImage] = [:]

    private var filtered: [Contact] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return vm.contacts }
        return vm.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.username ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var sections: [(letter: String, items: [Contact])] {
        let grouped = Dictionary(grouping: filtered) { String($0.name.prefix(1)).uppercased() }
        return grouped.keys.sorted().map { key in
            (key, (grouped[key] ?? []).sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = vm.mediaError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if !vm.isLive {
                    Section {
                        DemoBanner()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.items) { contact in
                            contactEntry(for: contact)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if vm.contactsLoading {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView("contacts.empty", systemImage: "person.2")
                }
            }
            .searchable(text: $query, prompt: Text("contacts.search"))
            .navigationTitle("contacts.title")
            .navigationDestination(for: Int64.self) { ChatView(chatID: $0) }
            .task { await vm.loadContacts() }
        }
    }

    @ViewBuilder
    private func contactEntry(for contact: Contact) -> some View {
        if vm.chat(contact.id) != nil {
            contactChatLink(for: contact)
        } else {
            row(contact)
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                .task(id: contact.avatarFileID) { await loadAvatar(contact) }
        }
    }

    private func contactChatLink(for contact: Contact) -> some View {
        let chatID: Int64 = contact.id
        let contactRow = row(contact)
        return NavigationLink(value: chatID, label: { contactRow })
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            .task(id: contact.avatarFileID) { await loadAvatar(contact) }
    }

    private func loadAvatar(_ contact: Contact) async {
        guard let fileID = contact.avatarFileID else {
            avatarImages[contact.id] = nil
            return
        }
        if let data = vm.cachedFileData(fileID: fileID) {
            avatarImages[contact.id] = UIImage(data: data)
            return
        }
        do {
            let data = try await vm.downloadFile(fileID: fileID, limit: 2 * 1_024 * 1_024)
            avatarImages[contact.id] = UIImage(data: data)
        } catch {}
    }

    private func row(_ contact: Contact) -> some View {
        HStack(spacing: KroSpacing.md) {
            AvatarView(
                name: contact.name,
                seed: Int(truncatingIfNeeded: contact.id),
                size: 40,
                showsOnline: contact.isOnline,
                image: avatarImages[contact.id]
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).kro(.body, weight: .medium)
                if let username = contact.username {
                    Text(verbatim: "@\(username)").kro(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
