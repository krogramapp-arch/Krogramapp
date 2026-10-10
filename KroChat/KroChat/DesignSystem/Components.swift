import SwiftUI

// MARK: - Avatar

struct AvatarView: View {
    let name: String
    let seed: Int
    var size: CGFloat = 48
    var showsOnline = false

    private static let palettes: [[Color]] = [
        [Color(hex: "5B8CFF"), Color(hex: "2F6BFF")],
        [Color(hex: "35C9A5"), Color(hex: "12806A")],
        [Color(hex: "FF9A62"), Color(hex: "D9532F")],
        [Color(hex: "B58CFF"), Color(hex: "7A4FD6")],
        [Color(hex: "FF7BA9"), Color(hex: "D6407A")],
        [Color(hex: "7FD1E8"), Color(hex: "2D8FB0")]
    ]

    private var colors: [Color] {
        Self.palettes[abs(seed) % Self.palettes.count]
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
                    Text(initial)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
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
    func body(content: Content) -> some View {
        content
            .padding(KroSpacing.lg)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: KroRadius.card, style: .continuous))
    }
}

extension View {
    func kroCard() -> some View { modifier(KroCardModifier()) }
}

struct KroPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, KroSpacing.xl)
            .padding(.vertical, KroSpacing.md)
            .background(.tint, in: Capsule())
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
    let style: WallpaperStyle
    let accent: Color

    var body: some View {
        switch style {
        case .plain:
            Color(.systemBackground)
        case .gradient:
            LinearGradient(
                colors: [accent.opacity(0.14), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
        case .dots:
            ZStack {
                Color(.systemBackground)
                Canvas { context, size in
                    let step: CGFloat = 28
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)),
                                with: .color(accent.opacity(0.18))
                            )
                            x += step
                        }
                        y += step
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
