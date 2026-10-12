import AVKit
import SwiftUI
import UIKit

struct MediaMessageView: View {
    let media: MessageMedia
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var data: Data?
    @State private var localURL: URL?
    @State private var player: AVPlayer?

    private let maxDownloadBytes: Int64 = 25 * 1_024 * 1_024

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data, [.photo, .sticker].contains(media.kind), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let player, [.video, .animation, .videoNote].contains(media.kind) {
                VideoPlayer(player: player)
                    .frame(maxWidth: 260)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if localURL != nil, [.audio, .voice].contains(media.kind) {
                Button {
                    if player?.timeControlStatus == .playing {
                        player?.pause()
                    } else {
                        player?.play()
                    }
                } label: {
                    Label("media.playAudio", systemImage: player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                }
            } else if let localURL {
                ShareLink(item: localURL) {
                    Label(media.fileName ?? L("media.downloaded"), systemImage: "square.and.arrow.up")
                }
            } else {
                downloadControl
            }
            if media.fileSize > maxDownloadBytes {
                Text("media.tooLarge").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            guard let cached = vm.cachedFileData(fileID: media.fileID) else { return }
            do {
                try displayDownloaded(cached)
            } catch {
                vm.setMediaError(TGErrors.message(for: error))
            }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if media.fileSize > maxDownloadBytes {
            Label("media.tooLarge", systemImage: "exclamationmark.triangle")
                .font(.footnote)
        } else if let progress = vm.mediaProgress[media.fileID] {
            HStack(spacing: 8) {
                if progress.total > 0 {
                    ProgressView(value: Double(progress.downloaded), total: Double(progress.total))
                } else {
                    ProgressView()
                }
                Button("media.cancel") { vm.cancelFileDownload(fileID: media.fileID) }
                    .font(.caption)
            }
            .frame(maxWidth: 200)
        } else {
            Button {
                Task { await download() }
            } label: {
                if let fileName = media.fileName {
                    Label(fileName, systemImage: symbol)
                } else {
                    Label(labelKey, systemImage: symbol)
                }
            }
            .font(.footnote)
        }
    }

    private var labelKey: LocalizedStringKey {
        switch media.kind {
        case .photo: return "msg.photo"
        case .video, .videoNote: return "msg.video"
        case .animation: return "msg.gif"
        case .audio, .voice: return "msg.audio"
        case .sticker: return "msg.sticker"
        case .document: return "msg.file"
        }
    }

    private var symbol: String {
        switch media.kind {
        case .photo: return "photo"
        case .video, .videoNote, .animation: return "play.rectangle"
        case .audio, .voice: return "waveform"
        case .sticker: return "face.smiling"
        case .document: return "doc"
        }
    }

    @MainActor
    private func download() async {
        do {
            let downloaded = try await vm.downloadFile(fileID: media.fileID, limit: maxDownloadBytes)
            try displayDownloaded(downloaded)
        } catch {
            vm.setMediaError(TGErrors.message(for: error))
        }
    }

    @MainActor
    private func displayDownloaded(_ downloaded: Data) throws {
        data = downloaded
        let url = try vm.cacheFileURL(
            fileID: media.fileID,
            data: downloaded,
            fileName: media.fileName,
            mimeType: media.mimeType
        )
        localURL = url
        if [.video, .animation, .videoNote, .audio, .voice].contains(media.kind) {
            player = AVPlayer(url: url)
        }
    }
}
