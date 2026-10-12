import SwiftUI
import UIKit

// MARK: - Avatar

struct AvatarView: View {
    let name: String
    let seed: Int
    var size: CGFloat = 48
    var showsOnline = false
    var image: UIImage? = nil
    @EnvironmentObject private var themes: ThemeStore

    private static let palettes: [[Color]] = [
        [Color(hex: "5B8CFF"), Color(hex: "2F6BFF")],
        [Color(hex: "35C9A5"), Color(hex: "12806A")],
        [Color(hex: "FF9A62"), Color(hex: "D9532F")],
        [Color(hex: "B58CFF"), Color(hex: "7A4FD6")],
        [Color(hex: "FF7BA9"), Color(hex: "D6407A")],
        [Color(hex: "7FD1E8"), Color(hex: "2D8FB0")]
    ]

    private var colors: [Color] {
        Self.palettes[Int(UInt(bitPattern: seed) % UInt(Self.palettes.count))]
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        Text(initial)
                            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1))
                .neonGlow(colors.last ?? themes.current.accent, radius: size * 0.2)
            if showsOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Badge

struct UnreadBadge: View {
    let count: Int
    var muted = false
    @EnvironmentObject private var themes: ThemeStore

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(muted ? Color.white : themes.current.onAccent)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(muted ? Color.gray : themes.current.accent, in: Capsule())
            .neonGlow(muted ? .clear : themes.current.accent, radius: 8)
    }
}

// MARK: - Demo banner

struct DemoBanner: View {
    var body: some View {
        HStack(spacing: KroSpacing.sm) {
            Image(systemName: "testtube.2")
            Text("demo.banner").kro(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tint)
        .padding(KroSpacing.md)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KroRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card & buttons

struct KroCardModifier: ViewModifier {
    @EnvironmentObject private var themes: ThemeStore

    func body(content: Content) -> some View {
        content
            .padding(KroSpacing.lg)
            .glass(cornerRadius: KroRadius.card)
            .neonGlow(themes.current.accent, radius: 12)
    }
}

extension View {
    func kroCard() -> some View { modifier(KroCardModifier()) }
}

struct KroPrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(themes.current.onAccent)
            .padding(.horizontal, KroSpacing.xl)
            .padding(.vertical, KroSpacing.md)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                themes.current.accent.opacity(0.82),
                                themes.current.accent,
                                themes.current.accent.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.36), lineWidth: 1))
            .neonGlow(themes.current.accent, radius: 14)
            .scaleEffect(configuration.isPressed && themes.shouldAnimate(reduceMotion: reduceMotion) ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let label: Text
    let isOn: Bool
    let action: () -> Void
    @EnvironmentObject private var themes: ThemeStore

    var body: some View {
        Button(action: action) {
            label
                .kro(.subheadline, weight: .medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? themes.current.onAccent : Color.primary)
                .background(isOn ? themes.current.accent : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Undo banner

struct UndoBannerView: View {
    let banner: ChatsViewModel.UndoBanner
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: KroSpacing.md) {
            Text(banner.text).kro(.subheadline)
            Spacer(minLength: KroSpacing.sm)
            Button("action.undo", action: onUndo)
                .kro(.subheadline, weight: .semibold)
        }
        .padding(.horizontal, KroSpacing.lg)
        .padding(.vertical, KroSpacing.md)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

// MARK: - Wallpaper

struct ChatWallpaper: View {
    private let configuration: BackgroundConfiguration
    let accent: Color
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(style: WallpaperStyle, accent: Color) {
        self.configuration = .migrated(from: style, accentHex: accent.toHex())
        self.accent = accent
    }

    init(configuration: BackgroundConfiguration, accent: Color) {
        self.configuration = configuration.validated()
        self.accent = accent
    }

    private var colors: [Color] {
        configuration.gradientHexes.map { Color(hex: $0) }
    }

    @ViewBuilder
    private var gradient: some View {
        switch configuration.gradientKind {
        case .linear:
            let radians = configuration.angle * .pi / 180
            let dx = cos(radians) / 2
            let dy = sin(radians) / 2
            LinearGradient(
                colors: colors,
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            )
        case .radial:
            RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 520)
        case .angular:
            AngularGradient(colors: colors, center: .center)
        }
    }

    private var shouldAnimate: Bool {
        themes.shouldAnimate(reduceMotion: reduceMotion)
    }

    var body: some View {
        let config = configuration.validated()
        ZStack {
            switch config.kind {
            case .solid:
                Color(hex: config.solidHex)
            case .gradient:
                gradient
            case .aurora:
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldAnimate)) { timeline in
                    auroraCanvas(size: timeline.date.timeIntervalSinceReferenceDate)
                }
            case .mesh:
                meshCanvas
            case .pattern:
                patternCanvas
            case .photo:
                Color(hex: config.solidHex)
            }
        }
        .accessibilityHidden(true)
    }

    private func auroraCanvas(size time: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(colors: colors),
                startPoint: .zero,
                endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
            ))
            let count = configuration.auroraBlobCount.clamped(to: 2...8)
            let phase = shouldAnimate ? time * configuration.auroraSpeed : 0
            for index in 0..<count {
                let angle = phase + Double(index) * (.pi * 2 / Double(count))
                let center = CGPoint(
                    x: canvasSize.width * (0.5 + 0.32 * cos(angle)),
                    y: canvasSize.height * (0.5 + 0.3 * sin(angle * 0.83))
                )
                let radius = max(canvasSize.width, canvasSize.height) * configuration.auroraSize * 0.42
                let color = colors[index % colors.count]
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.62), color.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .blur(radius: configuration.auroraBlur)
    }

    private var meshCanvas: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(hex: configuration.solidHex)))
            for point in configuration.meshPoints.prefix(16) {
                let center = CGPoint(x: size.width * point.x, y: size.height * point.y)
                let radius = max(size.width, size.height) * 0.72
                let color = Color(hex: point.hex)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.9), color.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
    }

    private var patternCanvas: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(hex: configuration.solidHex))
            )
            let step = CGFloat(48 - configuration.patternDensity * 34)
            let color = accent.opacity(configuration.patternOpacity)
            switch configuration.pattern {
            case .dots:
                for y in stride(from: CGFloat(0), through: size.height, by: step) {
                    for x in stride(from: CGFloat(0), through: size.width, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(color))
                    }
                }
            case .lines:
                for y in stride(from: CGFloat(0), through: size.height, by: step) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y + 24))
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }
            case .grid:
                for x in stride(from: CGFloat(0), through: size.width, by: step) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(color), lineWidth: 0.7)
                }
                for y in stride(from: CGFloat(0), through: size.height, by: step) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(color), lineWidth: 0.7)
                }
            case .geometric:
                for y in stride(from: CGFloat(0), through: size.height, by: step * 1.5) {
                    for x in stride(from: CGFloat(0), through: size.width, by: step * 1.5) {
                        let rect = CGRect(x: x, y: y, width: step * 0.55, height: step * 0.55)
                        var path = Path()
                        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                        path.closeSubpath()
                        context.stroke(path, with: .color(color), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Date formatting

extension Date {
    var chatListString: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        } else if cal.isDateInYesterday(self) {
            return RelativeDateTimeFormatter().localizedString(for: self, relativeTo: .now)
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
