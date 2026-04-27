import SwiftUI
import SwiftData

struct InsightsRootScreen: View {
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \FocusSprint.startTime, order: .reverse) private var sprints: [FocusSprint]
    @Query(sort: \ConsistencySnapshot.date, order: .reverse) private var snapshots: [ConsistencySnapshot]
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    private let consistencyService = ConsistencyService()
    private let weeklyFocusTarget = 150.0

    private var analytics: AnalyticsService {
        AnalyticsService(assignments: assignments, sprints: sprints)
    }

    private var trend: ConsistencyService.WeekTrend {
        consistencyService.weekTrend(sprints: sprints)
    }

    private var dailyStreak: Int {
        consistencyService.calculateDailyStreak(from: snapshots)
    }

    private var weeklyStreak: Int {
        consistencyService.calculateWeeklyStreak(from: snapshots)
    }

    private var insight: (headline: String, action: String) {
        consistencyService.behaviorInsight(analytics: analytics, trend: trend, dailyStreak: dailyStreak)
    }

    private var focusProgress: Double {
        min(1, Double(analytics.totalFocusedMinutesThisWeek) / weeklyFocusTarget)
    }

    private var onTimeProgress: Double {
        guard let percent = analytics.percentageCompletedOnTime else { return 0 }
        return Double(percent) / 100
    }

    private var trendDelta: Int {
        trend.currentMinutes - trend.previousMinutes
    }

    @State private var showPaywall = false

    var body: some View {
        Group {
            if subscriptionManager.isPremium {
                insightsContent
            } else {
                lockedInsightsView
            }
        }
        .background(DS.screenBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(trigger: .analytics)
                .environmentObject(subscriptionManager)
        }
    }

    private var lockedInsightsView: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.largeSection) {
                Spacer(minLength: 40)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(DS.Colors.secondaryText)

                VStack(spacing: DS.Spacing.micro) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text("Insights")
                            .font(.title.weight(.bold))
                        ProBadge(size: .small)
                    }
                    Text("Track your focus minutes, streaks,\ncompletion rates, and behavior trends.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    InsightsLockedRow(icon: "timer", text: "Weekly focus minutes & targets")
                    InsightsLockedRow(icon: "flame.fill", text: "Daily & weekly streaks")
                    InsightsLockedRow(icon: "checkmark.circle", text: "On-time completion rate")
                    InsightsLockedRow(icon: "lightbulb.fill", text: "Personalized behavior insights")
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()

                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Insights")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.primaryButtonFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.section)
            .padding(.bottom, 100)
        }
    }

    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Insights")
                        .font(.largeTitle.weight(.bold))
                    Text("Your weekly focus and consistency at a glance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    SectionHeader("This week")
                    metricProgressRow(
                        title: "Focused minutes",
                        valueText: analytics.totalFocusedMinutesThisWeek == 0
                            ? "None yet"
                            : "\(analytics.totalFocusedMinutesThisWeek)",
                        subtitle: "of \(Int(weeklyFocusTarget)) min target",
                        progress: focusProgress
                    )
                    Divider().overlay(DS.Border.color)
                    metricProgressRow(
                        title: "On-time completion",
                        valueText: analytics.percentageCompletedOnTime.map { "\($0)%" } ?? "No data yet",
                        subtitle: analytics.totalAssignmentsCompleted == 0
                            ? "Complete a task to see on-time rate"
                            : "\(analytics.totalAssignmentsCompleted) completed tasks",
                        progress: onTimeProgress
                    )
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()
                .transition(.opacity)

                VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                    SectionHeader("Consistency")
                        .padding(.bottom, DS.Spacing.micro)
                    consistencyRow(
                        title: "Daily streak",
                        value: dailyStreak == 0
                            ? "Complete a task to start your streak"
                            : "\(dailyStreak) day\(dailyStreak == 1 ? "" : "s")",
                        valueIsEmpty: dailyStreak == 0
                    )
                    Divider().overlay(DS.Border.color)
                    consistencyRow(
                        title: "Weekly streak",
                        value: weeklyStreak == 0
                            ? "No data yet"
                            : "\(weeklyStreak) week\(weeklyStreak == 1 ? "" : "s")",
                        valueIsEmpty: weeklyStreak == 0
                    )
                    Divider().overlay(DS.Border.color)
                    consistencyRow(
                        title: "Trend",
                        value: trendDelta == 0
                            ? "No change yet"
                            : "\(trend.direction) \(trendDelta > 0 ? "+" : "")\(trendDelta) min",
                        valueIsEmpty: trendDelta == 0
                    )
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()
                .transition(.opacity)

                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(DS.Colors.accent)
                        .frame(width: 3)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                        Text("Behavior Insight")
                            .font(.headline)
                        Text(insight.headline)
                            .font(.body)
                        Text("Try this: \(insight.action)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()
                .transition(.opacity)

                NavigationLink {
                    AnalyticsDashboardScreen()
                } label: {
                    Text("Open full analytics")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.primary)
                        .background(DS.Colors.secondaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.top, DS.Spacing.standard)
            .padding(.bottom, 100)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: analytics.totalFocusedMinutesThisWeek)
    }

    // MARK: - Sub-views

    private func metricProgressRow(title: String, valueText: String, subtitle: String, progress: Double) -> some View {
        let clamped = min(1, max(0, progress))
        return VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.Colors.progressTrack)
                        .frame(height: 6)
                    Capsule()
                        .fill(DS.Colors.accent)
                        .frame(width: max(4, geo.size.width * clamped), height: 6)
                }
            }
            .frame(height: 6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func consistencyRow(title: String, value: String, valueIsEmpty: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(valueIsEmpty ? .caption : .body.weight(.semibold))
                .foregroundStyle(valueIsEmpty ? DS.Colors.secondaryText : Color.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}

private struct InsightsLockedRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.standard) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
