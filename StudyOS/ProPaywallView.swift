import SwiftUI
import StoreKit

struct ProPaywallView: View {
    var trigger: UpsellTrigger? = nil
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String?

    private let features: [(String, String)] = [
        ("graduationcap.fill", "Google Classroom & Canvas import"),
        ("timer", "Focus Sprints with streak tracking"),
        ("chart.bar.fill", "Analytics & completion insights"),
    ]

    private let fakeAssignments: [(String, String)] = [
        ("AP Calc – Chapter 9 Problem Set", "Due Mon, Apr 28"),
        ("English Lit Essay – Final Draft", "Due Tue, Apr 29"),
        ("Chemistry Lab Report", "Due Wed, Apr 30"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.largeSection) {
                    headerSection
                    blurredPreview
                    featureList
                    ctaSection
                }
                .padding(.horizontal, DS.Spacing.standard)
                .padding(.top, DS.Spacing.section)
                .padding(.bottom, DS.Spacing.largeSection)
            }
            .background(DS.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { handleDismiss() }
                }
            }
            .alert("Purchase failed", isPresented: Binding(
                get: { purchaseError != nil },
                set: { if !$0 { purchaseError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: DS.Spacing.standard) {
            ProBadge(size: .standard)

            VStack(spacing: DS.Spacing.xs) {
                Text(trigger?.headline ?? "Unlock Struc Pro")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(trigger?.subtext ?? "Get the full Struc experience.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var blurredPreview: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(Array(fakeAssignments.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: DS.Spacing.standard) {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.0)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(item.1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.standard)
                    .padding(.vertical, 13)
                    if index < fakeAssignments.count - 1 {
                        Divider().padding(.leading, DS.Spacing.standard)
                    }
                }
            }
            .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Border.color, lineWidth: DS.Border.width)
            )
            .blur(radius: 5)
            .allowsHitTesting(false)

            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.title2.weight(.semibold))
                Text("Pro feature")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: DS.Spacing.standard) {
                    Image(systemName: feature.0)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 28)
                    Text(feature.1)
                        .font(.body)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, DS.Spacing.standard)
                .padding(.vertical, DS.Spacing.micro)

                if index < features.count - 1 {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .elevatedCard()
    }

    private var ctaSection: some View {
        VStack(spacing: DS.Spacing.micro) {
            Button {
                Task { await buy() }
            } label: {
                ZStack {
                    if subscriptionManager.isPurchasing {
                        ProgressView().tint(DS.Colors.primaryButtonFg)
                    } else {
                        Text(ctaLabel)
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(DS.Colors.primaryButtonFg)
                .background(
                    DS.Colors.primaryButtonBg,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(subscriptionManager.isPurchasing || subscriptionManager.product == nil)

            Text(pricingSubtext)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Restore Purchase") {
                Task {
                    await subscriptionManager.restore()
                    if subscriptionManager.isPremium { dismiss() }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, DS.Spacing.xs)

            Button("Maybe later") { handleDismiss() }
                .font(.footnote)
                .foregroundStyle(DS.Colors.secondaryText)

            Text("7-day free trial, then billed monthly. Cancel anytime in Settings > Apple ID > Subscriptions.")
                .font(.caption2)
                .foregroundStyle(DS.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.section)
                .padding(.top, DS.Spacing.xs)
        }
    }

    // MARK: - Helpers

    private var ctaLabel: String {
        if let product = subscriptionManager.product {
            return "Start 7-day free trial – then \(product.displayPrice)/mo"
        }
        return "Start 7-day free trial"
    }

    private var pricingSubtext: String {
        if let product = subscriptionManager.product {
            return "Then \(product.displayPrice)/mo · Cancel anytime"
        }
        return "Cancel anytime"
    }

    private func handleDismiss() {
        if trigger != nil {
            UpsellTriggerManager.shared.suppressForWeek()
        }
        onDismiss?()
        dismiss()
    }

    private func buy() async {
        do {
            try await subscriptionManager.purchase()
            if subscriptionManager.isPremium {
                onDismiss?()
                dismiss()
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
