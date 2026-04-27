import SwiftUI

struct LockedFeatureModifier: ViewModifier {
    let isPro: Bool
    let trigger: UpsellTrigger
    var cornerRadius: CGFloat = DS.Radius.card

    @State private var showUpsell = false

    func body(content: Content) -> some View {
        if isPro {
            content
        } else {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { ProBadge(size: .standard) }
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .onTapGesture { showUpsell = true }
                }
                .sheet(isPresented: $showUpsell) {
                    ProPaywallView(trigger: trigger) { showUpsell = false }
                }
        }
    }
}

extension View {
    func lockedIfNotPro(
        isPro: Bool,
        trigger: UpsellTrigger,
        cornerRadius: CGFloat = DS.Radius.card
    ) -> some View {
        modifier(LockedFeatureModifier(isPro: isPro, trigger: trigger, cornerRadius: cornerRadius))
    }
}
