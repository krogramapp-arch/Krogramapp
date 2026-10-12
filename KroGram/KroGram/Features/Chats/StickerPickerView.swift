import SwiftUI
import UIKit

struct StickerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var errorMessage: String?
    @State private var sendingStickerID: Int64?

    let onSend: (TelegramSticker) async throws -> Void

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.stickersLoading && vm.stickers.isEmpty {
                    ProgressView()
                } else if vm.stickers.isEmpty {
                    ContentUnavailableView {
                        Label("sticker.empty", systemImage: "face.smiling")
                    } description: {
                        if let mediaError = vm.mediaError {
                            Text(mediaError)
                        }
                    } actions: {
                        Button("location.retry") {
                            Task { await vm.loadStickers() }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(vm.stickers) { sticker in
                                Button {
                                    send(sticker)
                                } label: {
                                    StickerPreview(sticker: sticker)
                                }
                                .buttonStyle(.plain)
                                .disabled(sendingStickerID != nil)
                                .accessibilityLabel(Text("sticker.send"))
                                .accessibilityValue(sticker.emoji)
                            }
                        }
                        .padding(KroSpacing.md)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("sticker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .task { await vm.loadStickers() }
        }
    }

    private func send(_ sticker: TelegramSticker) {
        sendingStickerID = sticker.id
        errorMessage = nil
        Task {
            do {
                try await onSend(sticker)
                dismiss()
            } catch {
                errorMessage = TGErrors.message(for: error)
                sendingStickerID = nil
            }
        }
    }
}

private struct StickerPreview: View {
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var imageData: Data?
    @State private var previewError: String?

    let sticker: TelegramSticker

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Text(sticker.emoji.isEmpty ? "◇" : sticker.emoji)
                    .font(.system(size: 32))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHint(Text(previewError ?? ""))
        .task(id: sticker.id) {
            if let cached = vm.cachedFileData(fileID: sticker.id) {
                imageData = cached
                return
            }
            do {
                imageData = try await vm.downloadFile(fileID: sticker.id, limit: 2 * 1_024 * 1_024)
            } catch {
                imageData = nil
                previewError = TGErrors.message(for: error)
            }
        }
    }
}
