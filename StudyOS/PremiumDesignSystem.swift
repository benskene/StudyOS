import SwiftUI

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Design Tokens

enum DS {

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let micro: CGFloat = 8
        static let standard: CGFloat = 16
        static let section: CGFloat = 24
        static let largeSection: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 14
        static let chip: CGFloat = 20
        static let inner: CGFloat = 10
    }

    // MARK: Border
    enum Border {
        static let color = Color(UIColor.separator).opacity(0.4)
        static let width: CGFloat = 1
    }

    // MARK: Colors
    enum Colors {
        // ── Brand (use for interactive elements and progress) ──────────────
        static let brand     = Color(hex: "#7B61FF")   // purple — gradient start
        static let brandAlt  = Color(hex: "#0A84FF")   // blue   — gradient end / legacy accent
        static let accent    = Color(hex: "#0A84FF")   // alias kept for backward compat

        // ── Pro / promotional (ONLY for upsell surfaces, never real content) ─
        static let proAccent = Color(hex: "#F5A623")   // amber — visually distinct from brand

        // ── Semantic ───────────────────────────────────────────────────────
        static let success     = Color(hex: "#30D158")
        static let warning     = Color(hex: "#FF9F0A")
        static let destructive = Color(hex: "#FF453A")
        static let destructiveBg = Color(hex: "#3A1A1A")

        // ── Daily plan slot priorities ─────────────────────────────────────
        static let must     = Color(hex: "#FF453A")    // vivid red
        static let should   = Color(hex: "#FF9F0A")    // vivid amber
        static let quickWin = Color(hex: "#30D158")    // vivid green

        // ── Energy levels ──────────────────────────────────────────────────
        static let energyLow    = Color(hex: "#30D158")
        static let energyMedium = Color(hex: "#0A84FF")
        static let energyHigh   = Color(hex: "#BF5AF2")

        // ── Text hierarchy ─────────────────────────────────────────────────
        static let secondaryText = Color(hex: "#8E8E93")
        static let tertiaryText  = Color(hex: "#48484A")

        // ── Adaptive button surfaces ───────────────────────────────────────
        static let primaryButtonBg   = Color(UIColor.label)
        static let primaryButtonFg   = Color(UIColor.systemBackground)
        static let secondaryButtonBg = Color(UIColor.tertiarySystemFill)

        // ── Progress track ─────────────────────────────────────────────────
        static let progressTrack = Color(hex: "#2C2C2E")
    }

    // MARK: Gradients
    enum Gradient {
        /// Signature brand gradient — purple → blue. Apply to progress, CTAs, active indicators.
        static let brand = LinearGradient(
            colors: [Color(hex: "#7B61FF"), Color(hex: "#0A84FF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let brandHorizontal = LinearGradient(
            colors: [Color(hex: "#7B61FF"), Color(hex: "#0A84FF")],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// Animated greeting variant — set on State and drive withAnimation
        static func brandAnimated(start: UnitPoint, end: UnitPoint) -> LinearGradient {
            LinearGradient(
                colors: [Color(hex: "#7B61FF"), Color(hex: "#0A84FF"), Color(hex: "#FF375F")],
                startPoint: start,
                endPoint: end
            )
        }
        static let success = LinearGradient(
            colors: [Color(hex: "#30D158"), Color(hex: "#34C759")],
            startPoint: .leading, endPoint: .trailing
        )
        static let warning = LinearGradient(
            colors: [Color(hex: "#FF9F0A"), Color(hex: "#FF6B00")],
            startPoint: .leading, endPoint: .trailing
        )
        static let proGold = LinearGradient(
            colors: [Color(hex: "#F5A623"), Color(hex: "#F7C948")],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: Typography scale
    enum Typography {
        static let hero           = Font.largeTitle.weight(.bold)
        static let screenTitle    = Font.title2.weight(.bold)
        static let sectionHeader  = Font.title3.weight(.semibold)
        static let bodyMedium     = Font.body.weight(.medium)
        static let body           = Font.body
        static let label          = Font.caption.weight(.medium)
        static let caption        = Font.caption
        static let microLabel     = Font.caption2.weight(.semibold)
        static let metric         = Font.system(size: 28, weight: .bold, design: .rounded)
        static let metricSmall    = Font.system(size: 20, weight: .semibold, design: .rounded)
    }

    // MARK: Surfaces
    /// Darkest — screen background
    static let screenBackground      = Color(UIColor.systemGroupedBackground)
    /// Elevated — primary cards
    static let cardBackground        = Color(UIColor.secondarySystemGroupedBackground)
    /// Further elevated — nested surfaces (rows inside cards, input fields)
    static let nestedCardBackground  = Color(UIColor.tertiarySystemGroupedBackground)
    /// Legacy alias
    static let cardBorder            = Color(hex: "#2C2C2E")
}

// MARK: - Primary Card

struct ElevatedCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.cardBackground)
                    .shadow(
                        color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                        radius: 12, x: 0, y: 3
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.07)
                            : Color.black.opacity(0.05),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Nested Card (for surfaces inside primary cards)

struct NestedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.nestedCardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                    .stroke(DS.Border.color, lineWidth: 0.5)
            )
    }
}

// MARK: - Promo Card (for upsell/promotional content — subordinate visual weight)

struct PromoCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Colors.proAccent.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Colors.proAccent.opacity(0.28), lineWidth: 1)
            )
    }
}

extension View {
    func elevatedCard() -> some View  { modifier(ElevatedCardModifier()) }
    func nestedCard() -> some View    { modifier(NestedCardModifier()) }
    func promoCard() -> some View     { modifier(PromoCardModifier()) }

    /// Brand gradient CTA. Apply to content inside a Button label.
    func brandButtonLabel(radius: CGFloat = DS.Radius.control) -> some View {
        self
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(DS.Gradient.brandHorizontal, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glowing(color: DS.Colors.brand, radius: 5)
    }

    /// Secondary / ghost CTA. Apply to content inside a Button label.
    func secondaryButtonLabel(radius: CGFloat = DS.Radius.control) -> some View {
        self
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.primary)
            .background(DS.Colors.secondaryButtonBg, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Button Styles

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let actionLabel: String?
    let action: (() -> Void)?

    init(
        _ title: String,
        subtitle: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Type.sectionHeader)
                if let subtitle {
                    Text(subtitle).font(DS.Type.caption).foregroundStyle(.secondary)
                }
            }
            if let actionLabel, let action {
                Spacer()
                Button(actionLabel, action: action)
                    .font(DS.Type.label)
                    .foregroundStyle(DS.Colors.brandAlt)
            }
        }
    }
}

// MARK: - Empty State

/// Consistent no-data component used across every screen.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var ctaLabel: String? = nil
    var action: (() -> Void)? = nil
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? DS.Spacing.micro : DS.Spacing.standard) {
            Image(systemName: icon)
                .font(.system(size: compact ? 26 : 38, weight: .light))
                .foregroundStyle(DS.Gradient.brand)
                .padding(.bottom, DS.Spacing.xs)

            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(compact ? DS.Type.bodyMedium : DS.Type.sectionHeader)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(compact ? DS.Type.caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let ctaLabel, let action {
                Button(action: action) {
                    Text(ctaLabel)
                        .brandButtonLabel()
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.horizontal, compact ? DS.Spacing.section : DS.Spacing.largeSection)
                .padding(.top, DS.Spacing.xs)
            }
        }
        .padding(compact ? DS.Spacing.standard : DS.Spacing.largeSection)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Slot Badge

struct SlotBadge: View {
    let slot: DailyPlanSlotType

    private var label: String {
        switch slot {
        case .must:     return "Must Do"
        case .should:   return "Should"
        case .quickWin: return "Quick Win"
        }
    }

    private var color: Color {
        switch slot {
        case .must:     return DS.Colors.must
        case .should:   return DS.Colors.should
        case .quickWin: return DS.Colors.quickWin
        }
    }

    var body: some View {
        Text(label)
            .font(DS.Type.microLabel)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Energy Badge

struct EnergyBadge: View {
    let level: AssignmentEnergyLevel

    private var label: String {
        switch level {
        case .low: return "Low"; case .medium: return "Medium"; case .high: return "High"
        }
    }

    private var color: Color {
        switch level {
        case .low: return DS.Colors.energyLow; case .medium: return DS.Colors.energyMedium; case .high: return DS.Colors.energyHigh
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(DS.Type.microLabel).foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Progress Ring (gradient stroke)

struct ProgressRing: View {
    let value: Double
    let label: String
    let valueText: String
    var tint: Color = DS.Colors.brandAlt
    var gradientColors: [Color]? = nil

    private var clampedValue: Double { min(1, max(0, value)) }
    private var colors: [Color] { gradientColors ?? [DS.Colors.brand, DS.Colors.brandAlt] }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(valueText).font(DS.Type.metricSmall)
                Text(label).font(DS.Type.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 126, height: 126)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: clampedValue)
    }
}

// MARK: - Metric Bar

struct MetricBar: View {
    let title: String
    let valueText: String
    let progress: Double
    var tint: Color = DS.Colors.brandAlt

    private var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            HStack {
                Text(title).font(DS.Type.body)
                Spacer()
                Text(valueText).font(DS.Type.bodyMedium)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.progressTrack)
                    Capsule()
                        .fill(LinearGradient(colors: [DS.Colors.brand, DS.Colors.brandAlt], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, proxy.size.width * clampedProgress))
                }
            }
            .frame(height: 6)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: clampedProgress)
    }
}

// MARK: - Gradient Progress Bar

struct GradientProgressBar: View {
    let progress: Double
    var colors: [Color] = [DS.Colors.brand, DS.Colors.brandAlt]

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * clamped))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: clamped)
    }
}

// MARK: - Glow

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius / 2)
            .shadow(color: color.opacity(0.35), radius: radius)
            .shadow(color: color.opacity(0.15), radius: radius * 2)
    }
}

extension View {
    func glowing(color: Color = DS.Colors.brand, radius: CGFloat = 8) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}

// MARK: - Pulse Ring

struct PulseRingModifier: ViewModifier {
    let color: Color
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color.opacity(0.3))
                    .scaleEffect(pulsing ? 2.2 : 1)
                    .opacity(pulsing ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulsing)
            )
            .onAppear { pulsing = true }
    }
}

extension View {
    func pulseRing(color: Color) -> some View { modifier(PulseRingModifier(color: color)) }
}

// MARK: - Card Entrance

struct CardEntranceModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.82).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func cardEntrance(delay: Double = 0) -> some View { modifier(CardEntranceModifier(delay: delay)) }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.4), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Confetti

private struct ConfettiParticle: View {
    let symbol: String
    let xOffset: CGFloat
    let delay: Double
    @State private var fly = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 22))
            .offset(x: xOffset, y: fly ? -100 : 0)
            .opacity(fly ? 0 : 1)
            .scaleEffect(fly ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).delay(delay)) { fly = true }
            }
    }
}

struct ConfettiView: View {
    private let particles: [(String, CGFloat, Double)] = [
        ("🎉", -70, 0.0), ("⭐", -35, 0.08), ("✨", 5, 0.17),
        ("🎊", 42, 0.12), ("🌟", 78, 0.04), ("🎯", -55, 0.22),
    ]

    var body: some View {
        ZStack {
            ForEach(particles.indices, id: \.self) { i in
                ConfettiParticle(symbol: particles[i].0, xOffset: particles[i].1, delay: particles[i].2)
            }
        }
        .allowsHitTesting(false)
    }
}
