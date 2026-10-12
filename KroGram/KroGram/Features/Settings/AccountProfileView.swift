import SwiftUI
import UIKit

struct AccountProfileView: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var avatarImage: UIImage?

    var body: some View {
        Group {
            if vm.profileLoading && vm.profile == nil {
                ProgressView()
            } else if let profile = vm.profile {
                profileContent(profile)
            } else {
                ContentUnavailableView("profile.unavailable", systemImage: "person.crop.circle")
            }
            if let mediaError = vm.mediaError {
                Text(mediaError).font(.footnote).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile = vm.profile {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountProfileEditor(profile: profile)
                    } label: {
                        Text("action.edit")
                    }
                }
            }
        }
        .task {
            await vm.loadMyProfile()
            guard let fileID = vm.profile?.avatarFileID else { return }
            do {
                let data = try await vm.downloadFile(fileID: fileID, limit: 2 * 1_024 * 1_024)
                avatarImage = UIImage(data: data)
            } catch {}
        }
    }

    private func profileContent(_ profile: TelegramProfile) -> some View {
        List {
            Section {
                VStack(spacing: KroSpacing.md) {
                    AvatarView(
                        name: profile.displayName,
                        seed: Int(truncatingIfNeeded: profile.avatarFileID ?? 0),
                        size: 92,
                        image: avatarImage
                    )
                    Text(profile.displayName).kro(.title2, weight: .semibold)
                    if let username = profile.username {
                        Text(verbatim: "@\(username)").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, KroSpacing.lg)
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("profile.phone", value: profile.phoneNumber.isEmpty ? "—" : profile.phoneNumber)
                LabeledContent("profile.username", value: profile.username.map { "@\($0)" } ?? "—")
                VStack(alignment: .leading, spacing: 5) {
                    Text("profile.bio").foregroundStyle(.secondary)
                    Text(profile.bio.isEmpty ? "—" : profile.bio)
                        .textSelection(.enabled)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct AccountProfileEditor: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var bio: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: TelegramProfile) {
        _firstName = State(initialValue: profile.firstName)
        _lastName = State(initialValue: profile.lastName)
        _bio = State(initialValue: profile.bio)
    }

    var body: some View {
        Form {
            Section("profile.name") {
                TextField("profile.firstName", text: $firstName)
                TextField("profile.lastName", text: $lastName)
            }
            Section("profile.bio") {
                TextField("profile.bio", text: $bio, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Text("profile.editLimited").kro(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("profile.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.save") {
                    Task { await save() }
                }
                .disabled(isSaving || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await vm.updateMyProfile(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bio
            )
            dismiss()
        } catch {
            errorMessage = TGErrors.message(for: error)
        }
    }
}
