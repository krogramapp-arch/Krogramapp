import SwiftUI
import UIKit

struct ChatProfileView: View {
    let chatID: Int64
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var profile: ChatProfile?
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let profile {
                profileContent(profile)
            } else {
                ContentUnavailableView("profile.unavailable", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func profileContent(_ profile: ChatProfile) -> some View {
        List {
            Section {
                VStack(spacing: KroSpacing.md) {
                    AvatarView(
                        name: profile.title,
                        seed: Int(truncatingIfNeeded: profile.chatID),
                        size: 92,
                        image: image
                    )
                    Text(profile.title).kro(.title2, weight: .semibold)
                    if let username = profile.username {
                        Text(verbatim: "@\(username)").foregroundStyle(.secondary)
                    } else if let status = profile.status {
                        Text(LocalizedStringKey(statusKey(status))).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, KroSpacing.lg)
                .listRowBackground(Color.clear)
            }
            Section {
                if let phoneNumber = profile.phoneNumber {
                    LabeledContent("profile.phone", value: phoneNumber.isEmpty ? "—" : phoneNumber)
                }
                if let memberCount = profile.memberCount {
                    LabeledContent("profile.members", value: "\(memberCount)")
                }
                if !profile.description.isEmpty {
                    Text(profile.description).textSelection(.enabled)
                }
            }
            Section("profile.sharedMedia") {
                Text("profile.sharedMediaUnavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func statusKey(_ status: String) -> String {
        switch status {
        case "userStatusOnline": return "profile.status.online"
        case "userStatusOffline": return "profile.status.offline"
        default: return "profile.status.recently"
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            profile = try await vm.loadChatProfile(chatID: chatID)
            if let fileID = profile?.avatarFileID {
                let data = try await vm.downloadFile(fileID: fileID, limit: 2 * 1_024 * 1_024)
                image = UIImage(data: data)
            }
        } catch {
            errorMessage = TGErrors.message(for: error)
        }
    }
}
