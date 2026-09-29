import Foundation
import StoreKit
import UIKit

/// Maneja la compra/restauracion de la suscripcion unica de Alza con
/// StoreKit 2 directo (nada de bridge nativo<->JS: la app es 100% nativa).
/// appAccountToken = auth.uid() del usuario logueado en Supabase, para que
/// la Edge Function verify-apple-receipt pueda amarrar la transaccion al
/// usuario correcto sin depender de un login adicional.
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    /// Callback inyectado por AppState: se dispara con cada transaccion
    /// verificada para que se mande a verify-apple-receipt y se refresque
    /// el estado de suscripcion.
    var onVerifiedTransaction: ((Transaction) async -> Void)?

    func start() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await self?.onVerifiedTransaction?(transaction)
                await transaction.finish()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Config.subscriptionProductId])
            product = products.first
        } catch {
            purchaseError = "No se pudo cargar el producto: \(error.localizedDescription)"
        }
    }

    func purchase(appAccountToken: UUID) async {
        guard let product else { return }
        purchaseError = nil

        do {
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "No se pudo verificar la compra."
                    return
                }
                await onVerifiedTransaction?(transaction)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "La compra quedo pendiente de aprobacion (ej. control parental)."
            @unknown default:
                purchaseError = "Resultado de compra desconocido."
            }
        } catch {
            purchaseError = "La compra fallo: \(error.localizedDescription)"
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "No se pudo restaurar: \(error.localizedDescription)"
        }
    }

    func openManageSubscriptions() async {
        guard let scene = PresentationHelper.rootViewController?.view.window?.windowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}
