import SwiftUI

struct ProSettingsRow: View {
    let isPro: Bool
    var onUpgradeTap: () -> Void = {}

    var body: some View {
        if isPro {
            HStack(spacing: DS.Spacing.micro) {
                Label("Struc Pro", systemImage: "star.fill")
                    .foregroundStyle(Color(hex: "#F5A623"))
                Spacer()
                ProBadge(size: .small)
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } else {
            Button(action: onUpgradeTap) {
                HStack {
                    Label("Plan", systemImage: "person.circle")
                    Spacer()
                    Text("Free")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Upgrade to Pro")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: "#F5A623"))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
