import SwiftUI

struct ProBadge: View {
    enum Size { case small, standard }

    var size: Size = .standard
    var onTap: (() -> Void)? = nil

    private var font: Font {
        size == .small ? .system(size: 9, weight: .black) : .caption.weight(.black)
    }

    private var hPad: CGFloat { size == .small ? 5 : 8 }
    private var vPad: CGFloat { size == .small ? 2 : 3 }

    var body: some View {
        let label = Text("PRO")
            .font(font)
            .foregroundStyle(.black)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(DS.Gradient.proGold, in: Capsule())

        if let onTap {
            Button(action: onTap) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }
}
