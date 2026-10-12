import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Link detection

func linkified(_ text: String, entities: [MessageEntity] = [], revealSpoilers: Bool = false) -> AttributedString {
    var result = AttributedString(text)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].link = url
            result[attributedRange].underlineStyle = .single
        }
    }

    let utf16Count = (text as NSString).length
    for entity in entities where entity.offset <= utf16Count && entity.length <= utf16Count - entity.offset {
        let nsRange = NSRange(location: entity.offset, length: entity.length)
        guard let textRange = Range(nsRange, in: text),
              let range = Range(textRange, in: result) else { continue }
        switch entity.kind {
        case .bold:
            result[range].inlinePresentationIntent = .stronglyEmphasized
        case .italic:
            result[range].inlinePresentationIntent = .emphasized
        case .code, .pre:
            result[range].inlinePresentationIntent = .code
        case .quote:
            result[range].inlinePresentationIntent = .emphasized
        case .spoiler:
            if !revealSpoilers {
                result[range].foregroundColor = .primary
                result[range].backgroundColor = .primary
            }
        case .underline:
            result[range].underlineStyle = .single
        case .strikethrough:
            result[range].strikethroughStyle = .single
        case .textURL(let value):
            result[range].link = URL(string: value)
        case .url:
            if result[range].link == nil { result[range].link = URL(string: String(text[textRange])) }
        case .email:
            result[range].link = URL(string: "mailto:\(text[textRange])")
        case .phoneNumber:
            result[range].link = URL(string: "tel:\(text[textRange])")
        case .mention, .mentionName(_), .hashtag, .cashtag, .botCommand:
            break
        }
    }
    return result
}

// MARK: - Bubble

struct MessageBubble: View {
    let message: Message
    let replied: Message?
    let onRetry: () -> Void
    let onVotePoll: ([Int]) -> Void
    @EnvironmentObject private var themes: ThemeStore
    @State private var revealSpoilers = false
    @State private var selectedPollOptions = Set<Int>()

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
                } else if let poll = message.poll {
                    pollContent(poll)
                } else if let media = message.media {
                    MediaMessageView(media: media)
                    if !media.caption.isEmpty {
                        spoilerRevealButton(for: media.captionEntities)
                        Text(linkified(media.caption, entities: media.captionEntities, revealSpoilers: revealSpoilers))
                            .kro(.body)
                            .tint(foreground)
                    }
                } else {
                    spoilerRevealButton(for: message.entities)
                    Text(linkified(message.text, entities: message.entities, revealSpoilers: revealSpoilers))
                        .kro(.body)
                        .tint(foreground)
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

    private func pollContent(_ poll: MessagePoll) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.question).font(.body.weight(.semibold))
            ForEach(poll.options.indices, id: \.self) { index in
                let option = poll.options[index]
                let showsResults = poll.totalVoterCount > 0
                Button {
                    guard !poll.isClosed, !poll.options.contains(where: \.isChosen) else { return }
                    if poll.allowsMultipleAnswers {
                        if selectedPollOptions.contains(index) {
                            selectedPollOptions.remove(index)
                        } else {
                            selectedPollOptions.insert(index)
                        }
                    } else {
                        selectedPollOptions = [index]
                    }
                } label: {
                    HStack {
                        Image(systemName: option.isChosen || selectedPollOptions.contains(index)
                              ? "largecircle.fill.circle" : "circle")
                        Text(option.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if showsResults {
                            Text("\(option.votePercentage)%")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(poll.isClosed || poll.options.contains(where: \.isChosen))
                if showsResults {
                    ProgressView(value: Double(option.votePercentage), total: 100)
                        .tint(themes.current.accent)
                        .accessibilityLabel(Text("poll.result"))
                        .accessibilityValue("\(option.votePercentage)%")
                }
            }
            if !poll.isClosed, !poll.options.contains(where: \.isChosen) {
                Button("poll.vote") { onVotePoll(selectedPollOptions.sorted()) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPollOptions.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(String(format: L("poll.voterCount"), poll.totalVoterCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func spoilerRevealButton(for entities: [MessageEntity]) -> some View {
        if entities.contains(where: { $0.kind == .spoiler }), !revealSpoilers {
            Button("msg.revealSpoilers") { revealSpoilers = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
        }
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
    @State private var selectedVideoNote: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showChatProfile = false
    @State private var showingPollComposer = false
    @State private var showingContactPicker = false
    @State private var showingLocationShare = false
    @State private var showingStickerPicker = false
    @StateObject private var voiceRecorder = VoiceMessageRecorder()
    @State private var composerEntityKind: MessageEntityKind?
    @State private var selectingMessages = false
    @State private var selectedMessageIDs = Set<UUID>()
    @State private var showingForwardPicker = false

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
        let shown: [Message]
        if query.isEmpty {
            shown = chat.messages
        } else {
            shown = vm.searchResults(in: chatID, query: query)
                ?? chat.messages.filter { $0.text.localizedCaseInsensitiveContains(query) }
        }
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
                .overlay {
                    if !query.isEmpty, vm.searchingChats.contains(chatID), shown.isEmpty {
                        ProgressView()
                    }
                }
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
            ToolbarItem(placement: .topBarTrailing) {
                if selectingMessages && !selectedMessageIDs.isEmpty && vm.isLive {
                    Button {
                        showingForwardPicker = true
                    } label: {
                        Label("action.forward", systemImage: "arrowshape.turn.up.right")
                    }
                } else {
                    Button(selectingMessages ? "action.done" : "action.selectMessages") {
                        selectingMessages.toggle()
                        selectedMessageIDs.removeAll()
                    }
                }
            }
        }
        .sheet(isPresented: $showingForwardPicker) {
            NavigationStack {
                List(vm.mainChats.filter { $0.id != chatID }) { destination in
                    Button {
                        let ids = selectedMessageIDs.sorted { left, right in
                            let messages = vm.chat(chatID)?.messages ?? []
                            return (messages.first { $0.id == left }?.remoteID ?? 0)
                                < (messages.first { $0.id == right }?.remoteID ?? 0)
                        }
                        Task {
                            await vm.forwardMessages(ids, from: chatID, to: destination.id)
                            showingForwardPicker = false
                            selectingMessages = false
                            selectedMessageIDs.removeAll()
                        }
                    } label: {
                        Text(destination.title)
                    }
                }
                .navigationTitle("chat.forward.title")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.cancel") { showingForwardPicker = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPollComposer) {
            PollComposerView { question, options, isAnonymous, allowsMultipleAnswers in
                try await vm.sendPoll(
                    question: question,
                    options: options,
                    isAnonymous: isAnonymous,
                    allowsMultipleAnswers: allowsMultipleAnswers,
                    to: chatID
                )
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            SystemContactPicker { selection in
                showingContactPicker = false
                guard let selection else { return }
                Task {
                    do {
                        try await vm.sendContact(
                            firstName: selection.firstName,
                            lastName: selection.lastName,
                            phoneNumber: selection.phoneNumber,
                            to: chatID
                        )
                    } catch {
                        vm.setMediaError(TGErrors.message(for: error))
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingLocationShare) {
            LocationShareView { latitude, longitude in
                try await vm.sendLocation(latitude: latitude, longitude: longitude, to: chatID)
            }
        }
        .sheet(isPresented: $showingStickerPicker) {
            StickerPickerView { sticker in
                try await vm.sendSticker(sticker, to: chatID)
            }
        }
        .onAppear { text = vm.draft(for: chatID) }
        .task { await vm.openChat(chatID) }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await vm.searchMessages(in: chatID, query: query)
        }
        .onDisappear {
            vm.setDraft(text, for: chatID)
            voiceRecorder.cancel()
            if !showChatProfile { vm.closeChat(chatID) }
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty { vm.userTyped(chatID) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                vm.setDraft(text, for: chatID)
                voiceRecorder.cancel()
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task { await sendPickedPhoto(photo) }
        }
        .onChange(of: selectedVideoNote) { _, video in
            guard let video else { return }
            Task { await sendPickedVideoNote(video) }
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
        return MessageBubble(
            message: message,
            replied: replied,
            onRetry: { vm.retry(message.id, in: chatID) },
            onVotePoll: { optionIDs in vm.votePoll(message.id, in: chatID, optionIDs: optionIDs) }
        )
        .overlay(alignment: .topLeading) {
            if selectingMessages && selectedMessageIDs.contains(message.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(themes.current.accent)
                    .background(.background, in: Circle())
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard selectingMessages else { return }
            if selectedMessageIDs.contains(message.id) {
                selectedMessageIDs.remove(message.id)
            } else if selectedMessageIDs.count < 100 {
                selectedMessageIDs.insert(message.id)
            } else {
                vm.setMediaError(L("chat.forward.limit"))
            }
        })
        .contextMenu {
            if !selectingMessages {
                Button {
                    selectingMessages = true
                    selectedMessageIDs = [message.id]
                } label: {
                    Label("action.selectMessages", systemImage: "checkmark.circle")
                }
            }
            Button { replyTo = message; editing = nil } label: {
                Label("action.reply", systemImage: "arrowshape.turn.up.left")
            }
            Button { UIPasteboard.general.string = message.text } label: {
                Label("action.copy", systemImage: "doc.on.doc")
            }
            Menu {
                ForEach(Self.reactions, id: \.self) { emoji in
                    Button(emoji) { vm.toggleReaction(emoji, on: message.id, in: chatID) }
                }
            } label: {
                Label("chat.react", systemImage: "face.smiling")
            }
            if vm.isLive, message.remoteID != nil {
                Button {
                    vm.setMessagePinned(message.id, in: chatID, pinned: !message.isPinned)
                } label: {
                    Label(
                        message.isPinned ? "action.unpinMessage" : "action.pinMessage",
                        systemImage: message.isPinned ? "pin.slash" : "pin"
                    )
                }
                Button {
                    selectingMessages = true
                    selectedMessageIDs = [message.id]
                    showingForwardPicker = true
                } label: {
                    Label("action.forward", systemImage: "arrowshape.turn.up.right")
                }
            }
            if message.isOutgoing {
                Button {
                    editing = message
                    replyTo = nil
                    text = message.text
                    composerEntityKind = nil
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
                        composerEntityKind = nil
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
                    Button("format.bold") { composerEntityKind = .bold }
                    Button("format.italic") { composerEntityKind = .italic }
                    Button("format.code") { composerEntityKind = .code }
                    Button("format.quote") { composerEntityKind = .quote }
                    Button("format.spoiler") { composerEntityKind = .spoiler }
                    Button("format.none") { composerEntityKind = nil }
                } label: {
                    Image(systemName: "textformat")
                        .font(.title3)
                        .foregroundStyle(composerEntityKind == nil ? Color.secondary : themes.current.accent)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editing != nil)
                .accessibilityLabel(Text("format.title"))
                Menu {
                    if vm.isLive {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("chat.attach.photo", systemImage: "photo")
                        }
                        PhotosPicker(selection: $selectedVideoNote, matching: .videos) {
                            Label("chat.attach.videoNote", systemImage: "video.circle")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("chat.attach.file", systemImage: "doc")
                        }
                        Button {
                            showingPollComposer = true
                        } label: {
                            Label("poll.create", systemImage: "chart.bar")
                        }
                        Button {
                            showingContactPicker = true
                        } label: {
                            Label("chat.attach.contact", systemImage: "person.crop.circle")
                        }
                        Button {
                            showingLocationShare = true
                        } label: {
                            Label("chat.attach.location", systemImage: "location")
                        }
                        Button {
                            showingStickerPicker = true
                        } label: {
                            Label("sticker.title", systemImage: "face.smiling")
                        }
                        Button {
                            Task {
                                do {
                                    try await voiceRecorder.start()
                                } catch {
                                    vm.setMediaError(TGErrors.message(for: error))
                                }
                            }
                        } label: {
                            Label("chat.attach.voice", systemImage: "mic")
                        }
                    } else {
                        Text("media.realOnly")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .accessibilityLabel(Text("chat.attach.photo"))
                if voiceRecorder.isRecording {
                    Text("chat.voiceRecording")
                        .kro(.body)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .accessibilityLiveRegion(.assertive)
                } else {
                    TextField("chat.message.placeholder", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .kro(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glass(cornerRadius: KroRadius.field)
                }
                Button(action: voiceRecorder.isRecording ? finishVoiceRecording : submit) {
                    Image(systemName: voiceRecorder.isRecording
                          ? "stop.circle.fill"
                          : (editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill"))
                        .font(.title)
                }
                .disabled(!voiceRecorder.isRecording && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                composerEntityKind = nil
                vm.setDraft("", for: chatID)
                Haptics.success()
                return
            }
            vm.send(text, in: chatID, replyTo: replyTo?.id, entityKind: composerEntityKind)
            replyTo = nil
        }
        text = ""
        composerEntityKind = nil
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
    private func sendPickedVideoNote(_ item: PhotosPickerItem) async {
        defer { selectedVideoNote = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw TDError(code: -3, message: "MEDIA_READ_FAILED")
            }
            guard data.count > 0, data.count <= 25 * 1_024 * 1_024 else {
                throw TDError(code: -3, message: "FILE_TOO_LARGE")
            }
            let videoType = item.supportedContentTypes.first { $0.conforms(to: .movie) }
            let preferredExtension = videoType?.preferredFilenameExtension?.lowercased()
            let supportedExtensions = ["mov", "mp4", "m4v"]
            let ext = preferredExtension.flatMap { supportedExtensions.contains($0) ? $0 : nil } ?? "mov"
            let url = try storeOutgoingFile(data, fileExtension: ext)
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            guard duration.isFinite, duration > 0, duration <= 60 else {
                throw TDError(code: -3, message: "INVALID_MEDIA_DURATION")
            }
            let tracks = try await asset.load(.tracks)
            guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
                throw TDError(code: -3, message: "MEDIA_READ_FAILED")
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let length = Int(min(abs(naturalSize.width), abs(naturalSize.height)))
            guard length > 0 else { throw TDError(code: -3, message: "MEDIA_READ_FAILED") }
            try await vm.sendVideoNote(
                path: url.path,
                duration: Int(duration.rounded(.up)),
                length: length,
                to: chatID
            )
        } catch {
            vm.setMediaError(TGErrors.message(for: error))
        }
    }

    private func finishVoiceRecording() {
        do {
            let recording = try voiceRecorder.finish()
            let data = try Data(contentsOf: recording.url, options: .mappedIfSafe)
            let url = try storeOutgoingFile(data, fileExtension: "m4a")
            try FileManager.default.removeItem(at: recording.url)
            Task {
                do {
                    try await vm.sendVoiceNote(path: url.path, duration: recording.duration, to: chatID)
                } catch {
                    vm.setMediaError(TGErrors.message(for: error))
                }
            }
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
            if UTType(filenameExtension: source.pathExtension)?.conforms(to: .movie) == true {
                try await vm.sendVideo(path: url.path, caption: text, to: chatID)
            } else {
                try await vm.sendDocument(path: url.path, caption: text, to: chatID)
            }
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

    }

    private func loadOlderIfAtTop(_ message: Message, chat: Chat) {
        if query.isEmpty {
            guard message.id == chat.messages.first(where: { $0.remoteID != nil })?.id else { return }
            Task { await vm.loadOlderHistory(chatID: chatID) }
        } else {
            guard vm.searchResults(in: chatID, query: query)?.last?.id == message.id else { return }
            Task { await vm.searchMessages(in: chatID, query: query, loadMore: true) }
        }
    }
}
