import Foundation

enum NeonMode: String, Codable, CaseIterable, Identifiable {
    case automatic, manual, hybrid
    var id: String { rawValue }
    var titleKey: String { "neon.mode.\(rawValue)" }
}

enum NeonElement: String, Codable, CaseIterable, Identifiable {
    case outgoingBubble, incomingBubble, header, composer, sendButton
    case unreadBadge, avatar, card, primaryButton, tabBar

    var id: String { rawValue }
    var titleKey: String { "neon.element.\(rawValue)" }
}

struct NeonOffsets: Codable, Equatable {
    var hue: Double = 28
    var saturation: Double = 0
    var brightness: Double = 0
}

struct NeonElementStyle: Codable, Equatable {
    var isEnabled = true
    var colorHex = "37E6FF"
    var gradientHex: String?
    var intensity = 0.45
    var glowRadius = 12.0
    var layers = 2
    var spread = 1.0
    var opacity = 0.7
    var borderWidth = 0.0
    var borderHex = "37E6FF"
    var pulseSpeed = 0.3
    var pulseAmplitude = 0.15
    var breathing = false
    var hueRotation = false
    var touchReaction = false

    func validated() -> Self {
        var copy = self
        if !ThemeStore.isValidHex(colorHex) { copy.colorHex = "37E6FF" }
        if let gradientHex, !ThemeStore.isValidHex(gradientHex) { copy.gradientHex = nil }
        if !ThemeStore.isValidHex(borderHex) { copy.borderHex = copy.colorHex }
        copy.intensity = intensity.clamped(to: 0...1)
        copy.glowRadius = glowRadius.clamped(to: 0...32)
        copy.layers = layers.clamped(to: 1...4)
        copy.spread = spread.clamped(to: 0...2)
        copy.opacity = opacity.clamped(to: 0...1)
        copy.borderWidth = borderWidth.clamped(to: 0...4)
        copy.pulseSpeed = pulseSpeed.clamped(to: 0.05...1)
        copy.pulseAmplitude = pulseAmplitude.clamped(to: 0...0.3)
        return copy
    }
}

struct NeonConfiguration: Codable, Equatable {
    var mode: NeonMode = .automatic
    var manualHex = "37E6FF"
    var lightHex = "37E6FF"
    var darkHex = "37E6FF"
    var offsets = NeonOffsets()
    var elements: [NeonElement: NeonElementStyle] = [:]

    func style(for element: NeonElement) -> NeonElementStyle {
        (elements[element] ?? NeonElementStyle()).validated()
    }

    func validated() -> Self {
        var copy = self
        if !ThemeStore.isValidHex(manualHex) { copy.manualHex = "37E6FF" }
        if !ThemeStore.isValidHex(lightHex) { copy.lightHex = copy.manualHex }
        if !ThemeStore.isValidHex(darkHex) { copy.darkHex = copy.manualHex }
        copy.offsets.hue = offsets.hue.clamped(to: -180...180)
        copy.offsets.saturation = offsets.saturation.clamped(to: -1...1)
        copy.offsets.brightness = offsets.brightness.clamped(to: -1...1)
        copy.elements = elements.mapValues { $0.validated() }
        return copy
    }

    static func preset(_ preset: NeonPreset) -> NeonConfiguration {
        let color: String
        let isCalm: Bool
        switch preset {
        case .cyber: color = "37E6FF"; isCalm = false
        case .pastel: color = "E4A7FF"; isCalm = false
        case .fire: color = "FF7043"; isCalm = false
        case .ice: color = "81D4FA"; isCalm = false
        case .pureOLED: color = "8A5CFF"; isCalm = true
        case .calm: color = "808080"; isCalm = true
        }
        var result = NeonConfiguration(mode: .manual, manualHex: color, lightHex: color, darkHex: color)
        result.elements = Dictionary(uniqueKeysWithValues: NeonElement.allCases.map { element in
            var style = NeonElementStyle(colorHex: color, borderHex: color)
            style.isEnabled = !isCalm
            if isCalm { style.intensity = 0; style.glowRadius = 0; style.borderWidth = 0 }
            return (element, style)
        })
        return result
    }
}

enum NeonPreset: String, Codable, CaseIterable, Identifiable {
    case cyber, pastel, fire, ice, pureOLED, calm
    var id: String { rawValue }
    var titleKey: String { "neon.preset.\(rawValue)" }
}

enum ThemeScope: Hashable, Codable {
    case global
    case chatType(ChatKind)
    case chat(Int64)
}

struct ThemeScopeAssignment: Codable, Equatable {
    var scope: ThemeScope
    var themeID: UUID
}
