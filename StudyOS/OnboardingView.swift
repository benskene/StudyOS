//
//  OnboardingView.swift
//  StudyOS
//
//  Created by Ben Skene on 2/4/26.
//

import SwiftUI

enum StudyTimePreference: String, CaseIterable {
    case afternoon
    case evening
    case lateNight

    var title: String {
        switch self {
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .lateNight: return "Late Night"
        }
    }

    var icon: String {
        switch self {
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .lateNight: return "moon.stars.fill"
        }
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    let onSkip: (StudyTimePreference) -> Void
    let onAddFirstAssignment: (StudyTimePreference) -> Void
    let onExplore: (StudyTimePreference) -> Void

    @State private var currentPage = 0
    @State private var studyPreference: StudyTimePreference = .evening

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if currentPage < totalPages - 1 {
                    Button("Skip") {
                        onSkip(studyPreference)
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, DS.Spacing.section)
                    .padding(.top, DS.Spacing.standard)
                }
            }
            .frame(height: 44)

            TabView(selection: $currentPage) {
                WelcomePage().tag(0)
                SolutionPage().tag(1)
                FeaturesPage().tag(2)
                GetStartedPage(
                    studyPreference: $studyPreference,
                    onAddFirstAssignment: onAddFirstAssignment,
                    onExplore: onExplore
                ).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: currentPage)

            VStack(spacing: DS.Spacing.section) {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
                    }
                }

                if currentPage < totalPages - 1 {
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .padding(.horizontal, DS.Spacing.largeSection)
                }
            }
            .padding(.bottom, DS.Spacing.largeSection)
        }
        .background(DS.screenBackground.ignoresSafeArea())
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        OnboardingPageLayout {
            OnboardingHeroIcon(
                icon: "books.vertical.fill",
                gradient: [.blue, .indigo]
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                Text("School is a lot.\nWe make it simpler.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text("It's not that you can't do the work — it's knowing what to do right now. Struc gives you a clear plan every day.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            VStack(spacing: DS.Spacing.micro) {
                OnboardingStatRow(
                    stat: "2×",
                    label: "more likely to finish on time with a plan",
                    color: .blue
                )
                OnboardingStatRow(
                    stat: "60%",
                    label: "less last-minute stress",
                    color: .green
                )
            }
        }
    }
}

// MARK: - Page 2: Solution

private struct SolutionPage: View {
    var body: some View {
        OnboardingPageLayout {
            OnboardingHeroIcon(
                icon: "sparkles",
                gradient: [.purple, .pink]
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                Text("Your daily\nstudy copilot.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text("Struc turns your assignments into a clear daily plan and helps you start with focused sprints.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            VStack(spacing: DS.Spacing.micro) {
                OnboardingValuePill(
                    icon: "target",
                    text: "See what to work on next",
                    color: .orange
                )
                OnboardingValuePill(
                    icon: "figure.walk",
                    text: "Start with tiny steps",
                    color: .green
                )
                OnboardingValuePill(
                    icon: "chart.bar.fill",
                    text: "Understand your workload",
                    color: .blue
                )
            }
        }
    }
}

// MARK: - Page 3: Features

private struct FeaturesPage: View {
    var body: some View {
        OnboardingPageLayout {
            OnboardingHeroIcon(
                icon: "rectangle.3.group.fill",
                gradient: [.orange, .red]
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                Text("Three tabs.\nEverything you need.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }

            VStack(spacing: DS.Spacing.standard) {
                OnboardingFeatureCard(
                    icon: "checkmark.circle.fill",
                    title: "Today",
                    description: "Your daily plan and next task, ready to go.",
                    color: .blue
                )
                OnboardingFeatureCard(
                    icon: "calendar",
                    title: "Week",
                    description: "All assignments by day. Drag to reschedule.",
                    color: .orange
                )
                OnboardingFeatureCard(
                    icon: "bolt.fill",
                    title: "Sprints",
                    description: "5–20 min focused sessions with a tiny first step.",
                    color: .purple
                )
            }
        }
    }
}

// MARK: - Page 4: Get Started

private struct GetStartedPage: View {
    @Binding var studyPreference: StudyTimePreference
    let onAddFirstAssignment: (StudyTimePreference) -> Void
    let onExplore: (StudyTimePreference) -> Void

    var body: some View {
        OnboardingPageLayout {
            OnboardingHeroIcon(
                icon: "rocket.fill",
                gradient: [.green, .teal]
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                Text("Ready to\nget started?")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text("One quick question, then you're all set.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                Text("When do you usually study?")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: DS.Spacing.micro) {
                    ForEach(StudyTimePreference.allCases, id: \.rawValue) { option in
                        Button {
                            studyPreference = option
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.title3)
                                Text(option.title)
                                    .font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .fill(studyPreference == option ? Color.accentColor.opacity(0.12) : Color(UIColor.tertiarySystemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .strokeBorder(studyPreference == option ? Color.accentColor : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(studyPreference == option ? Color.accentColor : .primary)
                    }
                }
            }

            VStack(spacing: DS.Spacing.micro) {
                Button { onAddFirstAssignment(studyPreference) } label: {
                    Text("Add First Assignment")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.primaryButtonFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())

                Button { onExplore(studyPreference) } label: {
                    Text("Just explore the app")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared Components

private struct OnboardingPageLayout<Hero: View, Content: View>: View {
    let hero: Hero
    let content: Content

    init(@ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content) {
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                hero
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.section)

                content
            }
            .padding(.horizontal, DS.Spacing.largeSection)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingHeroIcon: View {
    let icon: String
    let gradient: [Color]

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 44))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
}

private struct OnboardingStatRow: View {
    let stat: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Spacing.standard) {
            Text(stat)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }
}

private struct OnboardingValuePill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Spacing.standard) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(text)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }
}

private struct OnboardingFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Spacing.standard) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }
}

#Preview {
    OnboardingView(
        onSkip: { _ in },
        onAddFirstAssignment: { _ in },
        onExplore: { _ in }
    )
}
