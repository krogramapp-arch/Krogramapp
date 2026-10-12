import SwiftUI
import UIKit

// MARK: - Hex colors

extension Color {
    /// Accepts "RRGGBB" or "AARRGGBB" (with or without "#").
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 6 { s = "FF" + s }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: Double((v >> 24) & 0xFF) / 255
        )
    }

    /// "RRGGBB"
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

// MARK: - Theme options

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var titleKey: String { "mode.\(rawValue)" }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ChatDensity: String, Codable, CaseIterable, Identifiable {
    case compact, regular, comfortable
    var id: String { rawValue }
    var titleKey: String { "density.\(rawValue)" }
    var rowPadding: CGFloat {
        switch self {
        case .compact: return 5
        case .regular: return 9
        case .comfortable: return 14
        }
    }
}

enum WallpaperStyle: String, Codable, CaseIterable, Identifiable {
    case plain, gradient, dots
    var id: String { rawValue }
    var titleKey: String { "wallpaper.\(rawValue)" }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced
    var id: String { rawValue }
    var titleKey: String { "font.\(rawValue)" }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

// MARK: - Theme

struct KroTheme: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

    var id: UUID
    var name: String
    var accentHex: String
    var bubbleRadius: Double
    var fontChoice: FontChoice
    var fontScale: Double
    var density: ChatDensity
    var wallpaper: WallpaperStyle
    var isBuiltIn: Bool
    var schemaVersion: Int
    var background: BackgroundConfiguration
    var neon: NeonConfiguration

    init(
        id: UUID = UUID(),
        name: String,
        accentHex: String,
        bubbleRadius: Double = 18,
        fontChoice: FontChoice = .system,
        fontScale: Double = 1.0,
        density: ChatDensity = .regular,
        wallpaper: WallpaperStyle = .gradient,
        isBuiltIn: Bool = false,
        schemaVersion: Int = KroTheme.currentSchemaVersion,
        background: BackgroundConfiguration? = nil,
        neon: NeonConfiguration = NeonConfiguration()
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.bubbleRadius = bubbleRadius
        self.fontChoice = fontChoice
        self.fontScale = fontScale
        self.density = density
        self.wallpaper = wallpaper
        self.isBuiltIn = isBuiltIn
        self.schemaVersion = schemaVersion
        self.background = background ?? .migrated(from: wallpaper, accentHex: accentHex)
        self.neon = neon
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, accentHex, bubbleRadius, fontChoice, fontScale
        case density, wallpaper, isBuiltIn, schemaVersion, background, neon
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let accentHex = try values.decodeIfPresent(String.self, forKey: .accentHex) ?? "2F6BFF"
        let wallpaper = try values.decodeIfPresent(WallpaperStyle.self, forKey: .wallpaper) ?? .gradient
        self.init(
            id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try values.decodeIfPresent(String.self, forKey: .name) ?? "Imported",
            accentHex: accentHex,
            bubbleRadius: try values.decodeIfPresent(Double.self, forKey: .bubbleRadius) ?? 18,
            fontChoice: try values.decodeIfPresent(FontChoice.self, forKey: .fontChoice) ?? .system,
            fontScale: try values.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1,
            density: try values.decodeIfPresent(ChatDensity.self, forKey: .density) ?? .regular,
            wallpaper: wallpaper,
            isBuiltIn: try values.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false,
            schemaVersion: Self.currentSchemaVersion,
            background: try values.decodeIfPresent(BackgroundConfiguration.self, forKey: .background)
                ?? .migrated(from: wallpaper, accentHex: accentHex),
            neon: try values.decodeIfPresent(NeonConfiguration.self, forKey: .neon) ?? NeonConfiguration()
        )
    }

    var accent: Color { Color(hex: accentHex) }

    /// Readable foreground (black/white) on top of the accent color.
    var onAccent: Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.62 ? .black : .white
    }

    static let presets: [KroTheme] = [
        KroTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Ocean", accentHex: "2F6BFF", wallpaper: .gradient, isBuiltIn: true),
        KroTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Emerald", accentHex: "12806A", bubbleRadius: 22, fontChoice: .rounded, wallpaper: .dots, isBuiltIn: true),
        KroTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Sunset", accentHex: "D9532F", bubbleRadius: 16, wallpaper: .gradient, isBuiltIn: true),
        KroTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Graphite", accentHex: "4B5563", bubbleRadius: 12, density: .compact, wallpaper: .plain, isBuiltIn: true)
    ]
}

// MARK: - Store

struct ThemeBundle: Codable {
    var format = "krochat-theme"
    var version = KroTheme.currentSchemaVersion
    var themes: [KroTheme]

    private enum CodingKeys: String, CodingKey {
        case format, version, themes
    }

    init(format: String = "krochat-theme", version: Int = KroTheme.currentSchemaVersion, themes: [KroTheme]) {
        self.format = format
        self.version = version
        self.themes = themes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        themes = try values.decode([KroTheme].self, forKey: .themes)
    }
}

enum ThemeImportError: Error {
    case invalid
    case tooLarge
}

/// Holds themes and appearance. Stores only visual settings (never account data).
@MainActor
final class ThemeStore: ObservableObject {
    static let maxCustomThemes = 20

    @Published private(set) var customThemes: [KroTheme]
    @Published var selectedID: UUID {
        didSet { defaults.set(selectedID.uuidString, forKey: Keys.selected) }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    @Published var effects: EffectsLevel {
        didSet { defaults.set(effects.rawValue, forKey: Keys.effects) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let custom = "krochat.themes.custom.v1"
        static let selected = "krochat.themes.selected.v1"
        static let appearance = "krochat.appearance.v1"
        static let effects = "krochat.effects.v1"
    }

    /// Visual effects are lowered automatically for Reduce Motion and Low Power Mode.
    func effectiveEffects(reduceMotion: Bool) -> EffectsLevel {
        if effects == .off { return .off }
        if ProcessInfo.processInfo.isLowPowerModeEnabled || reduceMotion { return .balanced }
        return effects
    }

    func shouldAnimate(reduceMotion: Bool) -> Bool {
        effects == .full && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        effects = defaults.string(forKey: Keys.effects).flatMap(EffectsLevel.init(rawValue:)) ?? .full
        if let data = defaults.data(forKey: Keys.custom),
           let list = try? JSONDecoder().decode([KroTheme].self, from: data) {
            customThemes = list.map { theme in
                var migrated = theme
                migrated.schemaVersion = KroTheme.currentSchemaVersion
                migrated.background = migrated.background.validated()
                migrated.neon = migrated.neon.validated()
                return migrated
            }
            if let migratedData = try? JSONEncoder().encode(customThemes) {
                defaults.set(migratedData, forKey: Keys.custom)
            }
        } else {
            customThemes = []
        }
        selectedID = defaults.string(forKey: Keys.selected).flatMap(UUID.init(uuidString:)) ?? KroTheme.presets[0].id
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    var all: [KroTheme] { KroTheme.presets + customThemes }
    var current: KroTheme { all.first { $0.id == selectedID } ?? KroTheme.presets[0] }
    var canAddTheme: Bool { customThemes.count < Self.maxCustomThemes }

    @discardableResult
    func duplicate(_ theme: KroTheme) -> KroTheme? {
        guard canAddTheme else { return nil }
        var copy = theme
        copy.id = UUID()
        copy.isBuiltIn = false
        copy.name = String(theme.name.prefix(34)) + " 2"
        customThemes.append(copy)
        persist()
        selectedID = copy.id
        return copy
    }

    func update(_ theme: KroTheme) {
        guard !theme.isBuiltIn, let i = customThemes.firstIndex(where: { $0.id == theme.id }) else { return }
        customThemes[i] = theme
        persist()
    }

    func delete(_ id: UUID) {
        customThemes.removeAll { $0.id == id }
        if selectedID == id { selectedID = KroTheme.presets[0].id }
        persist()
    }

    // MARK: Export / import (visual settings only)

    func exportJSON(for theme: KroTheme) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var exportTheme = theme
        exportTheme.background.photoID = nil
        guard let data = try? encoder.encode(ThemeBundle(themes: [exportTheme])) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    func importJSON(_ text: String) throws -> Int {
        guard text.utf8.count <= 64_000, let data = text.data(using: .utf8) else {
            throw ThemeImportError.tooLarge
        }
        guard let bundle = try? JSONDecoder().decode(ThemeBundle.self, from: data),
              bundle.format == "krochat-theme",
              (1...KroTheme.currentSchemaVersion).contains(bundle.version),
              !bundle.themes.isEmpty,
              bundle.themes.count <= 10 else {
            throw ThemeImportError.invalid
        }
        var added = 0
        for var theme in bundle.themes {
            guard canAddTheme, Self.isValidHex(theme.accentHex) else { continue }
            theme.id = UUID()
            theme.isBuiltIn = false
            let trimmed = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
            theme.name = trimmed.isEmpty ? "Imported" : String(trimmed.prefix(40))
            theme.bubbleRadius = min(max(theme.bubbleRadius, 8), 28)
            theme.fontScale = min(max(theme.fontScale, 0.85), 1.3)
            theme.schemaVersion = KroTheme.currentSchemaVersion
            theme.background = theme.background.validated()
            theme.neon = theme.neon.validated()
            customThemes.append(theme)
            added += 1
        }
        guard added > 0 else { throw ThemeImportError.invalid }
        persist()
        return added
    }

    nonisolated static func isValidHex(_ hex: String) -> Bool {
        hex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customThemes) {
            defaults.set(data, forKey: Keys.custom)
        }
    }
}

// MARK: - Typography

enum KroTextStyle {
    case title, headline, body, subheadline, footnote, caption

    var uiStyle: UIFont.TextStyle {
        switch self {
        case .title: return .title2
        case .headline: return .headline
        case .body: return .body
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        }
    }
}

private struct KroFontModifier: ViewModifier {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.dynamicTypeSize) private var dynamicType
    let style: KroTextStyle
    let weight: Font.Weight

    private var baseSize: CGFloat {
        _ = dynamicType // re-evaluate when the user changes iOS text size
        return UIFont.preferredFont(forTextStyle: style.uiStyle).pointSize
    }

    func body(content: Content) -> some View {
        let theme = themes.current
        content.font(.system(size: baseSize * theme.fontScale, weight: weight, design: theme.fontChoice.design))
    }
}

extension View {
    /// Themed font that respects both the theme's scale and iOS Dynamic Type.
    func kro(_ style: KroTextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(KroFontModifier(style: style, weight: weight))
    }
}

// MARK: - Tokens

enum KroSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum KroRadius {
    static let card: CGFloat = 16
    static let field: CGFloat = 20
}
