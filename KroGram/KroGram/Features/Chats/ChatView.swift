import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Link detection

func linkified(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return result
    }
    let nsText = text as NSString
    let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    for match in matches {
        guard let url = match.url,
              let stringRange = Range(match.range, in: text),
              let attributedRange = Range(stringRange, in: result) else { continue }
        result[attributedRange].link = url
        result[attributedRange].underlineStyle = .single
    }
    return result
}

// MARK: - Bubble

struct MessageBubble: View {
    let message: Message
    let replied: Message?
    let onRetry: () -> Void
    @EnvironmentObject private var themes: ThemeStore

    var body: some View {
        let theme = themes.current
        let foreground: Color = message.isOutgoing ? theme.onAccent : .primary
        HStack {
            if message.isOutgoing { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                if let replied {
                    HStack(spacing: 6) {
                        Rectangle().fill(foreground.opacity(0.6)).frame(width: 3)
                        Text(replied.text)
                            .kro(.footnote)
                            .lineLimit(2)
                            .opacity(0.8)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if message.isUnsupportedContent {
                    Label("msg.unsupported", systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                } else if let media = message.media {
                    MediaMessageView(media: media)
                    if !media.caption.isEmpty {
                        Text(linkified(media.caption)).kro(.body).tint(foreground)
                    }
                } else {
                    Text(linkified(message.text)).kro(.body).tint(foreground)
                }
                footer(foreground)
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions, id: \.self) { Text($0).font(.footnote) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(foreground.opacity(0.15), in: Capsule())
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.isOutgoing ? theme.accent : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous)
            )
            .neonGlow(message.isOutgoing ? theme.accent : .clear, radius: 8)
            if !message.isOutgoing { Spacer(minLength: 48) }
        }
        .onTapGesture { if message.state == .failed { onRetry() } }
    }

    private func footer(_ foreground: Color) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if message.isEdited {
                Text("chat.edited").kro(.caption)
            }
            Text(message.date.formatted(date: .omitted, time: .shortened)).kro(.caption)
            if message.isOutgoing { stateIcon }
        }
        .opacity(0.75)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch message.state {
        case .sending:
            Image(systemName: "clock").font(.caption2).accessibilityLabel(Text("chat.state.sending"))
        case .sent:
            Image(systemName: "checkmark").font(.caption2).accessibilityLabel(Text("chat.state.sent"))
        case .read:
            Image(systemName: "checkmark.circle.fill").font(.caption2).accessibilityLabel(Text("chat.state.read"))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .accessibilityLabel(Text("chat.state.failed"))
        }
    }
}

// MARK: - Chat screen

struct ChatView: View {
    let chatID: Int64
    @EnvironmentObject private var vm: ChatsViewModel
    @EnvironmentObject private var themes: ThemeStore
    @EnvironmentObject private var privacy: PrivacyMode
    @EnvironmentObject private var commander: CommanderStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var replyTo: Message?
    @State private var editing: Message?
    @State private var query = ""
    @State private var isSearching = false
    @State private var commanderResponse: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showChatProfile = false

    private static let reactions = ["👍", "❤️", "😂", "🔥"]

    var body: some View {
        if let chat = vm.chat(chatID) {
            content(chat)
        } else {
            ContentUnavailableView("chats.empty", systemImage: "bubble.left")
        }
    }

    private func content(_ chat: Chat) -> some View {
        let theme = themes.current
        let shown = query.isEmpty ? chat.messages : chat.messages.filter { $0.text.localizedCaseInsensitiveContains(query) }
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shown) { message in
                            if themes.shouldAnimate(reduceMotion: reduceMotion) {
                                bubble(message, in: chat)
                                    .id(message.id)
                                    .transition(KroBlurTransition())
                                    .onAppear { loadOlderIfAtTop(message, chat: chat) }
                            } else {
                                bubble(message, in: chat)
                                    .id(message.id)
                                    .transition(.identity)
                                    .onAppear { loadOlderIfAtTop(message, chat: chat) }
                            }
                        }
                    }
                    .animation(themes.shouldAnimate(reduceMotion: reduceMotion) ? .snappy : nil, value: shown.count)
                    .padding(.horizontal, KroSpacing.md)
                    .padding(.vertical, KroSpacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToEnd(proxy, chat) }
                .onChange(of: chat.messages.last?.id) { _, _ in scrollToEnd(proxy, chat) }
            }
            if let commanderResponse {
                commanderResult(commanderResponse)
                    .padding(.horizontal, KroSpacing.md)
                    .padding(.bottom, KroSpacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let mediaError = vm.mediaError {
                HStack {
                    Text(mediaError).kro(.footnote).foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, KroSpacing.md)
            }
            if editing == nil, replyTo == nil, !commanderSuggestions.isEmpty {
                commandSuggestions
            }
            composer
        }
        .background(ChatWallpaper(configuration: theme.background, accent: theme.accent).ignoresSafeArea())
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showChatProfile) {
            ChatProfileView(chatID: chatID)
        }
        .searchable(text: $query, isPresented: $isSearching, prompt: Text("chat.search"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showChatProfile = true } label: {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                .accessibilityHint(Text("profile.openChat"))
            }
            if chat.unread > 0 && privacy.hideRead {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        Task { await vm.markReadNow(chatID) }
                    } label: {
                        Label("action.markRead", systemImage: "checkmark.message")
                    }
                }
            }
        }
        .onAppear { text = vm.draft(for: chatID) }
        .task { await vm.openChat(chatID) }
        .onDisappear {
            vm.setDraft(text, for: chatID)
            if !showChatProfile { vm.closeChat(chatID) }
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty { vm.userTyped(chatID) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.setDraft(text, for: chatID) }
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task { await sendPickedPhoto(photo) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            Task { await importSelectedFile(result) }
        }
    }

    private func bubble(_ message: Message, in chat: Chat) -> some View {
        let replied = chat.messages.first { candidate in
            if let localID = message.replyToID, candidate.id == localID { return true }
            if let remote = message.replyToRemoteID, candidate.remoteID == remote { return true }
            return false
        }
        return MessageBubble(message: message, replied: replied) {
            vm.retry(message.id, in: chatID)
        }
        .contextMenu {
            Button { replyTo = message; editing = nil } label: {
                Label("action.reply", systemImage: "arrowshape.turn.up.left")
            }
            Button { UIPasteboard.general.string = message.text } label: {
                Label("action.copy", systemImage: "doc.on.doc")
            }
            if !vm.isLive {
                Menu {
                    ForEach(Self.reactions, id: \.self) { emoji in
                        Button(emoji) { vm.toggleReaction(emoji, on: message.id, in: chatID) }
                    }
                } label: {
                    Label("chat.react", systemImage: "face.smiling")
                }
            }
            if message.isOutgoing {
                Button {
                    editing = message
                    replyTo = nil
                    text = message.text
                } label: { Label("action.edit", systemImage: "pencil") }
                Button(role: .destructive) {
                    vm.deleteMessage(message.id, in: chatID)
                } label: { Label("action.delete", systemImage: "trash") }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let target = replyTo ?? editing {
                HStack(spacing: KroSpacing.sm) {
                    Image(systemName: editing != nil ? "pencil" : "arrowshape.turn.up.left")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(editing != nil ? "chat.editing" : "chat.replying")
                            .kro(.caption, weight: .semibold)
                            .foregroundStyle(.tint)
                        Text(target.text).kro(.footnote).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if editing != nil { text = "" }
                        replyTo = nil
                        editing = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("action.cancel"))
                }
                .padding(.horizontal, KroSpacing.lg)
                .padding(.vertical, KroSpacing.sm)
            }
            HStack(alignment: .bottom, spacing: KroSpacing.sm) {
                Menu {
                    if vm.isLive {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("chat.attach.photo", systemImage: "photo")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("chat.attach.file", systemImage: "doc")
                        }
                    } else {
                        Text("media.realOnly")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .accessibilityLabel(Text("chat.attach.photo"))
                TextField("chat.message.placeholder", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .kro(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glass(cornerRadius: KroRadius.field)
                Button(action: submit) {
                    Image(systemName: editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.title)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, KroSpacing.md)
            .padding(.vertical, KroSpacing.sm)
        }
        .background(.bar)
    }

    private var commanderSuggestions: [String] {
        CommanderCommandEngine.suggestions(for: text, preferences: commander.preferences)
    }

    private var commandSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KroSpacing.sm) {
                ForEach(commanderSuggestions, id: \.self) { command in
                    Button {
                        text = command
                        commanderResponse = nil
                    } label: {
                        Text(command)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .glass(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KroSpacing.md)
            .padding(.vertical, KroSpacing.xs)
        }
        .accessibilityLabel(Text("commander.suggestions"))
    }

    private func commanderResult(_ result: String) -> some View {
        HStack(alignment: .top, spacing: KroSpacing.sm) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(themes.current.accent)
                .neonGlow(themes.current.accent, radius: 8)
            Text(result)
                .kro(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                commanderResponse = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("action.dismiss"))
        }
        .padding(KroSpacing.md)
        .glass(cornerRadius: KroRadius.card)
    }

    private func submit() {
        if let editing {
            vm.edit(editing.id, in: chatID, text: text)
            self.editing = nil
        } else {
            if replyTo == nil,
               let chat = vm.chat(chatID),
               let result = CommanderCommandEngine.execute(
                   text,
                   chat: chat,
                   preferences: commander.preferences
               ) {
                switch result {
                case .local(let message):
                    commanderResponse = message
                case .pin(let pinned):
                    guard chat.isPinned != pinned else {
                        commanderResponse = L(pinned ? "commander.result.alreadyPinned" : "commander.result.alreadyUnpinned")
                        text = ""
                        vm.setDraft("", for: chatID)
                        return
                    }
                    vm.update([chatID]) { $0.isPinned = pinned }
                    commanderResponse = L(pinned ? "commander.result.pinned" : "commander.result.unpinned")
                case .archive(let archived):
                    guard chat.isArchived != archived else {
                        commanderResponse = L(archived ? "commander.result.alreadyArchived" : "commander.result.alreadyUnarchived")
                        text = ""
                        vm.setDraft("", for: chatID)
                        return
                    }
                    vm.update([chatID]) { $0.isArchived = archived }
                    commanderResponse = L(archived ? "commander.result.archived" : "commander.result.unarchived")
                }
                text = ""
                vm.setDraft("", for: chatID)
                Haptics.success()
                return
            }
            vm.send(text, in: chatID, replyTo: replyTo?.id)
            replyTo = nil
        }
        text = ""
        vm.setDraft("", for: chatID)
    }

    @MainActor
    private func sendPickedPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                vm.setMediaError(L("err.generic"))
                return
            }
            guard data.count <= 10 * 1_024 * 1_024 else {
                vm.setMediaError(L("media.tooLarge"))
                return
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = try storeOutgoingFile(data, fileExtension: ext)
            try await vm.sendPhoto(path: url.path, caption: text, to: chatID)
            text = ""
        } catch {
            vm.setMediaError(TGErrors.message(for: error))
        }
    }

    @MainActor
    private func importSelectedFile(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let hasAccess = source.startAccessingSecurityScopedResource()
            defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0, size <= 25 * 1_024 * 1_024 else {
                vm.setMediaError(L("media.tooLarge"))
                return
            }
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            let url = try storeOutgoingFile(data, fileExtension: source.pathExtension)
            try await vm.sendDocument(path: url.path, caption: text, to: chatID)
            text = ""
        } catch {
            vm.setMediaError(TGErrors.message(for: error))
        }
    }

    private func storeOutgoingFile(_ data: Data, fileExtension ext: String) throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KroGram/outgoing", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let currentSize = try existing.reduce(Int64.zero) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values.fileSize ?? 0)
        }
        guard currentSize + Int64(data.count) <= 100 * 1_024 * 1_024 else {
            throw TDError(code: -6, message: "OUTGOING_STORAGE_FULL")
        }
        let safeExtension = ext.range(of: "^[a-zA-Z0-9]{1,8}$", options: .regularExpression) == nil ? "bin" : ext
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(safeExtension)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, _ chat: Chat) {
        guard let last = chat.messages.last else { return }
        if themes.shouldAnimate(reduceMotion: reduceMotion) {
            withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }

        private func loadOlderIfAtTop(_ message: Message, chat: Chat) {
            guard query.isEmpty,
                  message.id == chat.messages.first(where: { $0.remoteID != nil })?.id else { return }
            Task { await vm.loadOlderHistory(chatID: chatID) }
        }
    }
}
