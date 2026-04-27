import StoreKit
import Foundation
import Combine

@MainActor
final class SubscriptionManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    static let productId = "struc.struc.premium.monthly"

    @Published private(set) var isPremium = false
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = nil
        transactionListener = listenForTransactions()
        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func purchase() async throws {
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refresh()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    private func refresh() async {
        if let products = try? await Product.products(for: [Self.productId]) {
            product = products.first
        }

        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.productId,
               tx.revocationDate == nil {
                entitled = true
            }
        }
        isPremium = entitled
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refresh()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

enum SubscriptionError: Error {
    case failedVerification
}
