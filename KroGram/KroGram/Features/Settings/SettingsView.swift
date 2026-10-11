import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themes: ThemeStore
    @EnvironmentObject private var privacy: PrivacyMode
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var chats: ChatsViewModel
    @EnvironmentObject private var commander: CommanderStore
    @State private var showImport = false
    @State private var confirmLogout = false

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "-"
        let b = info?["CFBundleVersion"] as? String ?? "-"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.appearance") {
                    Picker("settings.mode", selection: $themes.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                }

                Section("settings.account") {
                    if chats.isLive {
                        Label("session.live", systemImage: "checkmark.seal.fill")
                        Button(role: .destructive) { confirmLogout = true } label: {
                            Label("session.logout", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Label("session.demo", systemImage: "testtube.2")
                        Button {
                            session.beginLogin()
                        } label: {
                            Label("session.signin", systemImage: "person.badge.key")
                        }
                    }
                    if session.hasSavedCredentials {
                        Button("session.forget", role: .destructive) { session.forgetCredentials() }
                    }
                }

                Section {
                    Toggle("commander.enabled", isOn: $commander.isEnabled)
                    if commander.isEnabled {
                        Toggle("commander.calculator", isOn: $commander.calculatorEnabled)
                        Toggle("commander.textTools", isOn: $commander.textToolsEnabled)
                        Toggle("commander.chatInfo", isOn: $commander.chatInfoEnabled)
                        Toggle("commander.chatActions", isOn: $commander.chatActionsEnabled)
                        Toggle("commander.funGames", isOn: $commander.funGamesEnabled)
                        Text("commander.commands.hint")
                            .kro(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("commander.title")
                } footer: {
                    Text("commander.note")
                }

                Section {
                    Toggle("privacy.hideRead", isOn: $privacy.hideRead)
                    Toggle("privacy.hideTyping", isOn: $privacy.hideTyping)
                    Toggle("privacy.hideOnline", isOn: $privacy.hideOnline)
                } header: {
                    Text("privacy.title")
                } footer: {
                    Text("privacy.note")
                }

                Section {
                    Picker("effects.level", selection: $themes.effects) {
                        ForEach(EffectsLevel.allCases) { level in
                            Text(LocalizedStringKey(level.titleKey)).tag(level)
                        }
                    }
                    HStack(spacing: KroSpacing.md) {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(themes.current.accent)
                            .neonGlow(themes.current.accent, radius: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("effects.preview.title").kro(.subheadline, weight: .semibold)
                            Text("effects.preview.note")
                                .kro(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(themes.current.accent)
                            .frame(width: 10, height: 10)
                            .neonGlow(themes.current.accent, radius: 8)
                    }
                    .padding(KroSpacing.md)
                    .glass(cornerRadius: 18)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("effects.title")
                } footer: {
                    Text("effects.note")
                }

                Section("settings.themes") {
                    ForEach(themes.all) { theme in
                        Button {
                            themes.selectedID = theme.id
                        } label: {
                            HStack {
                                Circle().fill(theme.accent).frame(width: 20, height: 20)
                                Text(verbatim: theme.name).foregroundStyle(.primary)
                                Spacer()
                                if themes.selectedID == theme.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions {
                            if !theme.isBuiltIn {
                                Button(role: .destructive) { themes.delete(theme.id) } label: {
                                    Label("action.delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    if !themes.current.isBuiltIn {
                        NavigationLink {
                            ThemeEditorView(theme: themes.current)
                        } label: {
                            Label("settings.editCurrent", systemImage: "paintbrush")
                        }
                    }
                    Button {
                        themes.duplicate(themes.current)
                    } label: {
                        Label("settings.duplicate", systemImage: "plus.square.on.square")
                    }
                    .disabled(!themes.canAddTheme)
                    if !themes.canAddTheme {
                        Text("settings.themeLimit").kro(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("settings.themeData") {
                    ShareLink(item: themes.exportJSON(for: themes.current)) {
                        Label("theme.export", systemImage: "square.and.arrow.up")
                    }
                    Button { showImport = true } label: {
                        Label("theme.import", systemImage: "square.and.arrow.down")
                    }
                }

                Section("settings.language") {
                    Text("settings.language.hint").kro(.footnote).foregroundStyle(.secondary)
                    Button("settings.language.open") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("settings.about") {
                    Text("about.unofficial").kro(.footnote)
                    LabeledContent("about.version") { Text(verbatim: versionString) }
                    Text("about.phase").kro(.footnote).foregroundStyle(.secondary)
                    Text("about.encryption").kro(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("settings.title")
            .sheet(isPresented: $showImport) { ImportThemeSheet() }
            .confirmationDialog("session.logout", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("session.logout", role: .destructive) {
                    Task { await session.logOut() }
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("session.logout.confirm")
            }
        }
    }
}

// MARK: - Theme editor

struct ThemeEditorView: View {
    @EnvironmentObject private var themes: ThemeStore
    @State private var draft: KroTheme

    init(theme: KroTheme) {
        _draft = State(initialValue: theme)
    }

    var body: some View {
        Form {
            Section {
                ThemePreviewCard(theme: draft)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("theme.name", text: $draft.name)
                ColorPicker("theme.accent", selection: Binding(
                    get: { Color(hex: draft.accentHex) },
                    set: { draft.accentHex = $0.toHex() }
                ), supportsOpacity: false)
                VStack(alignment: .leading) {
                    Text("theme.radius")
                    Slider(value: $draft.bubbleRadius, in: 8...28, step: 1)
                }
                Picker("theme.font", selection: $draft.fontChoice) {
                    ForEach(FontChoice.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("theme.fontScale")
                    Slider(value: $draft.fontScale, in: 0.85...1.3, step: 0.05)
                }
                Picker("theme.density", selection: $draft.density) {
                    ForEach(ChatDensity.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                }
                Picker("theme.wallpaper", selection: $draft.wallpaper) {
                    ForEach(WallpaperStyle.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                }
            }
        }
        .navigationTitle("theme.editor")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, new in themes.update(new) }
    }
}

struct ThemePreviewCard: View {
    let theme: KroTheme

    private func font(_ size: CGFloat) -> Font {
        .system(size: size * theme.fontScale, design: theme.fontChoice.design)
    }

    var body: some View {
        ZStack {
            ChatWallpaper(style: theme.wallpaper, accent: theme.accent)
            VStack(spacing: 8) {
                HStack {
                    Text("theme.preview.in")
                        .font(font(16))
                        .padding(10)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
                    Spacer()
                }
                HStack {
                    Spacer()
                    Text("theme.preview.out")
                        .font(font(16))
                        .padding(10)
                        .foregroundStyle(theme.onAccent)
                        .background(theme.accent,
                                    in: RoundedRectangle(cornerRadius: theme.bubbleRadius, style: .continuous))
                }
            }
            .padding()
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: KroRadius.card, style: .continuous))
    }
}

// MARK: - Import

struct ImportThemeSheet: View {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("theme.import.hint").kro(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 200)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("action.paste") { text = UIPasteboard.general.string ?? "" }
                }
                if let message {
                    Section { Text(message).kro(.footnote) }
                }
            }
            .navigationTitle("theme.import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save", action: runImport)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func runImport() {
        do {
            let count = try themes.importJSON(text)
            message = String(format: L("theme.import.ok"), count)
            text = ""
        } catch {
            message = L("theme.import.invalid")
        }
    }
}
