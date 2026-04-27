//
//  PremiumDesignSystem.swift
//  Struc
//

import SwiftUI

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Design Tokens

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let micro: CGFloat = 8
        static let standard: CGFloat = 16
        static let section: CGFloat = 24
        static let largeSection: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 14
        static let chip: CGFloat = 20
    }

    enum Border {
        static let color = Color(UIColor.separator).opacity(0.45)
        static let width: CGFloat = 1
    }

    /// Semantic palette — use these instead of hard-coding opacity values.
    enum Colors {
        // Daily plan slot priorities
        static let must      = Color.red
        static let should    = Color.orange
        static let quickWin  = Color.green

        // Assignment energy levels
        static let energyLow    = Color.green
        static let energyMedium = Color.blue
        static let energyHigh   = Color.purple

        // Adaptive button colors — inverts correctly in dark mode
        /// Use as the background of any solid primary CTA button.
        static let primaryButtonBg  = Color(UIColor.label)
        /// Use as the foreground/text of any solid primary CTA button.
        static let primaryButtonFg  = Color(UIColor.systemBackground)
        /// Use as the background of any secondary/ghost button.
        static let secondaryButtonBg = Color(UIColor.tertiarySystemFill)

        // Dark-mode accent and semantic action colors
        static let accent        = Color(hex: "#0A84FF")
        static let destructive   = Color(hex: "#FF453A")
        static let destructiveBg = Color(hex: "#3A1A1A")

        // Text hierarchy
        static let secondaryText = Color(hex: "#8E8E93")
        static let tertiaryText  = Color(hex: "#48484A")

        // Progress
        static let progressTrack = Color(hex: "#2C2C2E")
    }

    /// Adaptive: light gray in light mode, dark grouped in dark mode.
    static let screenBackground = Color(UIColor.systemGroupedBackground)
    /// Adaptive: white in light mode, elevated dark surface in dark mode.
    static let cardBackground   = Color(UIColor.secondarySystemGroupedBackground)
    /// Explicit card border color for dark mode.
    static let cardBorder       = Color(hex: "#2C2C2E")
}

// MARK: - Elevated Card

struct ElevatedCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.cardBackground)
                    .shadow(
                        color: colorScheme == .dark
                            ? .clear
                            : .black.opacity(0.05),
                        radius: 8, x: 0, y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Border.color, lineWidth: DS.Border.width)
            )
    }
}

extension View {
    func elevatedCard() -> some View {
        modifier(ElevatedCardModifier())
    }
}

// MARK: - Button Styles

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

// MARK: - Section Header

/// Flexible section header that optionally displays a trailing action button.
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
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let actionLabel, let action {
                Spacer()
                Button(actionLabel, action: action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Slot Badge

/// Colored pill badge for daily plan slot types (Must Do / Should / Quick Win).
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
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Energy Badge

/// Small dot + label badge for assignment energy levels.
struct EnergyBadge: View {
    let level: AssignmentEnergyLevel

    private var label: String {
        switch level {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private var color: Color {
        switch level {
        case .low:    return DS.Colors.energyLow
        case .medium: return DS.Colors.energyMedium
        case .high:   return DS.Colors.energyHigh
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let value: Double
    let label: String
    let valueText: String
    var tint: Color = .accentColor

    private var clampedValue: Double { min(1, max(0, value)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: clampedValue)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(valueText)
                        .font(.title2.weight(.semibold))
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 126, height: 126)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: clampedValue)
    }
}

// MARK: - Metric Bar

struct MetricBar: View {
    let title: String
    let valueText: String
    let progress: Double
    var tint: Color = .accentColor

    private var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            HStack {
                Text(title).font(.body)
                Spacer()
                Text(valueText).font(.body.weight(.semibold))
            }
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.progressTrack)
                    Capsule().fill(tint).frame(width: max(4, w * clampedProgress))
                }
            }
            .frame(height: 6)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: clampedProgress)
    }
}
