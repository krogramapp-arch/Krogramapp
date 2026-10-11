import SwiftUI

enum EffectsLevel: String, CaseIterable, Identifiable, Codable {
    case off, balanced, full
    var id: String { rawValue }
    var titleKey: String { "effects.\(rawValue)" }
}

// MARK: - Neon glow

private struct NeonGlowModifier: ViewModifier {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let level = themes.effectiveEffects(reduceMotion: reduceMotion)
        switch level {
        case .off:
            content
        case .balanced:
            content
                .shadow(color: color.opacity(0.38), radius: radius * 0.45)
        case .full:
            content
                .shadow(color: color.opacity(0.9), radius: radius * 0.45)
                .shadow(color: color.opacity(0.62), radius: radius)
                .shadow(color: color.opacity(0.28), radius: radius * 1.8)
        }
    }
}

// MARK: - Glass

private struct GlassModifier: ViewModifier {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let radius: CGFloat

    func body(content: Content) -> some View {
        let level = themes.effectiveEffects(reduceMotion: reduceMotion)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if level == .off {
            content
                .background(Color(.secondarySystemBackground), in: shape)
        } else {
            Group {
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular, in: shape)
                } else {
                    content
                        .background {
                            ZStack {
                                shape.fill(.ultraThinMaterial)
                                shape.fill(
                                    LinearGradient(
                                        colors: [
                                            themes.current.accent.opacity(level == .full ? 0.2 : 0.09),
                                            .white.opacity(level == .full ? 0.09 : 0.04),
                                            themes.current.accent.opacity(level == .full ? 0.07 : 0.02)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                        }
                }
            }
                .overlay(
                    shape.strokeBorder(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.62),
                                themes.current.accent.opacity(level == .full ? 0.75 : 0.3),
                                .white.opacity(0.12),
                                themes.current.accent.opacity(level == .full ? 0.48 : 0.2),
                                .white.opacity(0.62)
                            ],
                            center: .center
                        ),
                        lineWidth: level == .full ? 1.1 : 0.8
                    )
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(level == .full ? 0.58 : 0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 1)
                        .padding(.horizontal, radius * 1.4)
                }
                .shadow(
                    color: themes.current.accent.opacity(level == .full ? 0.2 : 0.07),
                    radius: level == .full ? 22 : 10,
                    y: level == .full ? 8 : 4
                )
                .overlay {
                    if level == .full {
                        shape.strokeBorder(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.18),
                                    .clear,
                                    themes.current.accent.opacity(0.24),
                                    .clear
                                ],
                                center: .center
                            ),
                            lineWidth: 0.6
                        )
                    }
                }
        }
    }
}

extension View {
    func neonGlow(_ color: Color, radius: CGFloat = 10) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }

    func glass(cornerRadius: CGFloat = KroRadius.card) -> some View {
        modifier(GlassModifier(radius: cornerRadius))
    }
}

// MARK: - Backdrop

/// Soft animated color field. Static gradient at "balanced", moving blobs only at "full".
struct AuroraBackdrop: View {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let palette: [Color] = [
        Color(hex: "7A4FD6"), Color(hex: "00C2FF"), Color(hex: "FF4FA3")
    ]

    var body: some View {
        let level = themes.effectiveEffects(reduceMotion: reduceMotion)
        ZStack {
            Color(.systemBackground)
            switch level {
            case .off:
                EmptyView()
            case .balanced:
                ZStack {
                    Color(.systemBackground)
                    LinearGradient(
                        colors: [
                            themes.current.accent.opacity(0.25),
                            Self.palette[0].opacity(0.08),
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .full:
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    blobs(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blobs(time: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                blob(themes.current.accent, geo.size, time, phase: 0)
                blob(Self.palette[0], geo.size, time, phase: 2.1)
                blob(Self.palette[1], geo.size, time, phase: 4.2)
                blob(Self.palette[2], geo.size, time, phase: 5.6)
                blob(Color(hex: "FFB84D"), geo.size, time, phase: 1.2)
            }
            .blur(radius: 76)
            .overlay {
                LinearGradient(
                    colors: [.clear, Color(.systemBackground).opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func blob(_ color: Color, _ size: CGSize, _ time: Double, phase: Double) -> some View {
        let x = size.width * (0.5 + 0.32 * sin(time * 0.22 + phase))
        let y = size.height * (0.45 + 0.28 * cos(time * 0.17 + phase * 1.3))
        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.44), color.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.42
                )
            )
            .frame(width: size.width * 0.7, height: size.width * 0.7)
            .position(x: x, y: y)
    }
}

// MARK: - Transitions

/// Blur + scale + fade, used for new messages and login steps.
struct KroBlurTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : 12)
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : 0.94)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
