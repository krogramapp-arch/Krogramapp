import SwiftUI

struct ContactsView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var query = ""

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
                            if vm.chat(contact.id) != nil {
                                NavigationLink(value: contact.id) { row(contact) }
                                    .listRowBackground(.ultraThinMaterial)
                            } else {
                                row(contact)
                                    .listRowBackground(.ultraThinMaterial)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty { ContentUnavailableView("contacts.empty", systemImage: "person.2") }
            }
            .searchable(text: $query, prompt: Text("contacts.search"))
            .navigationTitle("contacts.title")
            .navigationDestination(for: Int64.self) { ChatView(chatID: $0) }
        }
    }

    private func row(_ contact: Contact) -> some View {
        HStack(spacing: KroSpacing.md) {
            AvatarView(name: contact.name, seed: Int(truncatingIfNeeded: contact.id), size: 40, showsOnline: contact.isOnline)
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
