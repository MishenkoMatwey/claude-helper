import SwiftUI
import AppKit

// MARK: - Design tokens

enum DS {
    // MARK: Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radii
    enum Radius {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: Typography
    enum Typo {
        static let displayLarge = Font.system(size: 32, weight: .bold, design: .rounded)
        static let display = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let micro = Font.system(size: 10, weight: .medium)

        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let monoBold = Font.system(size: 12, weight: .semibold, design: .monospaced)
    }

    // MARK: Colors (adapt to light/dark)
    enum Color {
        private static func dyn(dark: NSColor, light: NSColor) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        }

        static let bg = dyn(
            dark: NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1),
            light: NSColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1)
        )
        static let surface = dyn(
            dark: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1),
            light: NSColor.white
        )
        static let surfaceElevated = dyn(
            dark: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
            light: NSColor(red: 0.99, green: 0.99, blue: 0.99, alpha: 1)
        )
        static let border = dyn(
            dark: NSColor(white: 1, alpha: 0.08),
            light: NSColor(white: 0, alpha: 0.08)
        )
        static let borderStrong = dyn(
            dark: NSColor(white: 1, alpha: 0.16),
            light: NSColor(white: 0, alpha: 0.18)
        )

        // Text hierarchy
        static let textPrimary = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let textTertiary = SwiftUI.Color.secondary.opacity(0.6)

        // Semantic accents
        static let accent = SwiftUI.Color(red: 0.36, green: 0.45, blue: 0.95)        // electric blue-violet
        static let success = SwiftUI.Color(red: 0.18, green: 0.78, blue: 0.45)
        static let warning = SwiftUI.Color(red: 0.97, green: 0.65, blue: 0.13)
        static let danger = SwiftUI.Color(red: 0.95, green: 0.32, blue: 0.32)
        static let info = SwiftUI.Color(red: 0.27, green: 0.65, blue: 0.95)
        static let purple = SwiftUI.Color(red: 0.62, green: 0.36, blue: 0.95)
        static let teal = SwiftUI.Color(red: 0.13, green: 0.69, blue: 0.78)

        // Functional
        static func semantic(forUtilization pct: Double) -> SwiftUI.Color {
            if pct >= 0.9 { return danger }
            if pct >= 0.7 { return warning }
            if pct >= 0.5 { return SwiftUI.Color(red: 0.93, green: 0.78, blue: 0.13) }
            return success
        }
    }

    // MARK: Shadows
    struct Shadow {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let sm = Shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        static let md = Shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        static let lg = Shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }
}

// MARK: - Card modifier

struct DesignCard: ViewModifier {
    var padding: CGFloat = DS.Space.l
    var radius: CGFloat = DS.Radius.l
    var shadow: DS.Shadow? = .sm

    func body(content: Content) -> some View {
        let view = content
            .padding(padding)
            .background(DS.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))

        if let s = shadow {
            return AnyView(view.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y))
        }
        return AnyView(view)
    }
}

extension View {
    func designCard(padding: CGFloat = DS.Space.l, radius: CGFloat = DS.Radius.l, shadow: DS.Shadow? = .sm) -> some View {
        modifier(DesignCard(padding: padding, radius: radius, shadow: shadow))
    }
}

// MARK: - Badge

struct StatusBadge: View {
    let text: String
    let color: SwiftUI.Color
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .font(DS.Typo.captionMedium)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12))
        .overlay(
            Capsule().stroke(color.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Button styles

struct PressableButtonStyle: ButtonStyle {
    var fill: SwiftUI.Color = DS.Color.accent
    var foreground: SwiftUI.Color = .white
    var hPadding: CGFloat = DS.Space.m
    var vPadding: CGFloat = DS.Space.s
    var radius: CGFloat = DS.Radius.s

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.bodyMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(fill)
                    .opacity(configuration.isPressed ? 0.78 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .focusEffectDisabled()
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: SwiftUI.Color = DS.Color.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.bodyMedium)
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .focusEffectDisabled()
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var tint: SwiftUI.Color = DS.Color.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.bodyMedium)
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(configuration.isPressed ? DS.Color.borderStrong.opacity(0.5) : DS.Color.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .focusEffectDisabled()
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(configuration.isPressed
                          ? DS.Color.borderStrong.opacity(0.6)
                          : SwiftUI.Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
            .focusEffectDisabled()
    }
}

/// Subtle text button — for secondary actions like Cancel.
struct SubtleTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.bodyMedium)
            .foregroundStyle(configuration.isPressed ? DS.Color.textPrimary : DS.Color.textSecondary)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .contentShape(Rectangle())
            .focusEffectDisabled()
    }
}

// MARK: - Spinning refresh button

struct SpinningRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(IconButtonStyle())
        .help("Refresh — перечитать агенты, workflows, лимиты")
        .accessibilityLabel("Refresh")
        .onChange(of: isRefreshing) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    rotation = 0
                }
            }
        }
    }
}

// MARK: - Section header

struct DesignSectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let icon {
                Image(systemName: icon).foregroundStyle(DS.Color.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DS.Typo.headline)
                if let subtitle {
                    Text(subtitle).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
                .padding(DS.Space.l)
                .background(
                    Circle()
                        .fill(DS.Color.surfaceElevated)
                        .overlay(Circle().stroke(DS.Color.border, lineWidth: 1))
                )
            VStack(spacing: DS.Space.xs) {
                Text(title).font(DS.Typo.title).foregroundStyle(DS.Color.textPrimary)
                Text(subtitle).font(DS.Typo.body).foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .frame(maxWidth: 380)
        .padding(DS.Space.xxl)
    }
}

// MARK: - Progress bar

struct DesignProgressBar: View {
    let value: Double  // 0.0 ... 1.0
    var height: CGFloat = 8
    var color: SwiftUI.Color { DS.Color.semantic(forUtilization: value) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(DS.Color.borderStrong.opacity(0.5))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Skeleton loading

struct Skeleton: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(DS.Color.surfaceElevated)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: UnitPoint(x: phase, y: 0),
                    endPoint: UnitPoint(x: phase + 0.6, y: 0)
                )
                .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: width, height: height)
    }
}

// MARK: - Staggered reveal animation

struct StaggeredAppear: ViewModifier {
    let index: Int
    let delayPer: TimeInterval
    @State private var visible: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)
                    .delay(Double(index) * delayPer)) {
                    visible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int, delayPer: TimeInterval = 0.04) -> some View {
        modifier(StaggeredAppear(index: index, delayPer: delayPer))
    }
}

// MARK: - Quick tooltip (fast hover popover)

struct QuickTooltip: ViewModifier {
    let text: String
    let delay: TimeInterval
    @State private var show: Bool = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    let task = Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        if !Task.isCancelled {
                            await MainActor.run { show = true }
                        }
                    }
                    hoverTask = task
                } else {
                    show = false
                }
            }
            .overlay(alignment: .top) {
                if show {
                    Text(text)
                        .font(DS.Typo.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(SwiftUI.Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .fixedSize()
                        .offset(y: -36)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)),
                            removal: .opacity
                        ))
                        .allowsHitTesting(false)
                        .zIndex(999)
                }
            }
            .animation(.spring(response: 0.18, dampingFraction: 0.85), value: show)
    }
}

extension View {
    /// Fast tooltip (~250ms) instead of system's ~1.5s.
    func quickTooltip(_ text: String, delay: TimeInterval = 0.25) -> some View {
        modifier(QuickTooltip(text: text, delay: delay))
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var color: SwiftUI.Color = DS.Color.accent

    var body: some View {
        GeometryReader { geo in
            if values.isEmpty {
                EmptyView()
            } else {
                let max = (values.max() ?? 1)
                let normalized = values.map { max > 0 ? $0 / max : 0 }
                Path { p in
                    for (i, v) in normalized.enumerated() {
                        let x = geo.size.width * (Double(i) / Double(values.count - 1))
                        let y = geo.size.height * (1 - v)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                Path { p in
                    for (i, v) in normalized.enumerated() {
                        let x = geo.size.width * (Double(i) / Double(values.count - 1))
                        let y = geo.size.height * (1 - v)
                        if i == 0 { p.move(to: CGPoint(x: x, y: geo.size.height)); p.addLine(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.20), color.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
    }
}
