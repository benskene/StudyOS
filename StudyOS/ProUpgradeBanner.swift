import SwiftUI

struct ProUpgradeBanner: View {
    let onDismiss: () -> Void

    @State private var valueProp = ""
    @State private var showPaywall = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.standard) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    ProBadge(size: .small)
                    Text("Upgrade to Struc Pro")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "#F5A623"))
                }
                Text(valueProp)
                    .font(.subheadline.weight(.medium))
                Button("See what's included →") {
                    UpsellTriggerManager.shared.markSessionUpsellShown()
                    showPaywall = true
                }
                .font(.caption)
                .foregroundStyle(DS.Colors.accent)
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(DS.Spacing.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.standard)
        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(Color(hex: "#F5A623").opacity(0.35), lineWidth: 1)
        )
        .onAppear { valueProp = UpsellTriggerManager.shared.nextValueProp() }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(trigger: .homeBanner) {
                UpsellTriggerManager.shared.suppressForWeek()
            }
        }
    }
}
