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

    /// Si la suscripcion activa se va a renovar sola o no (el usuario la
    /// cancelo desde Ajustes de iOS / el sheet de administrar suscripcion,
    /// algo que pasa FUERA de la app, no hay forma de que lo sepamos salvo
    /// preguntandole a StoreKit). nil = todavia no se ha podido consultar.
    @Published private(set) var willAutoRenew: Bool?
    /// Fecha en que termina el periodo pagado actual — si willAutoRenew es
    /// false, es la fecha en que el usuario pierde el acceso (no antes:
    /// Apple nunca corta el acceso a mitad del periodo ya pagado).
    @Published private(set) var currentPeriodEndDate: Date?

    /// "Prueba gratis 1 semana, luego $X / mes" cuando el producto tiene una
    /// oferta introductoria de tipo prueba gratis Y el usuario todavia es
    /// elegible para ella (nunca la ha usado). nil si no aplica — en ese
    /// caso el paywall muestra solo el precio normal.
    @Published private(set) var freeTrialOfferDescription: String?

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
            if product == nil {
                purchaseError = "No se encontro el producto \"\(Config.subscriptionProductId)\". Revisa que exista en App Store Connect (o en el archivo .storekit local) con ese Product ID exacto."
            }
            await refreshRenewalInfo()
            await refreshFreeTrialEligibility()
        } catch {
            purchaseError = "No se pudo cargar el producto: \(error.localizedDescription)"
        }
    }

    /// Arma el texto de "prueba gratis" solo si el producto trae una oferta
    /// introductoria de tipo prueba gratis Y StoreKit confirma que el
    /// usuario todavia no la ha usado (isEligibleForIntroOffer) — alguien
    /// que ya tuvo una suscripcion antes no vuelve a ver la prueba gratis,
    /// asi StoreKit evita que la misma persona la reclame dos veces.
    private func refreshFreeTrialEligibility() async {
        guard
            let subscriptionInfo = product?.subscription,
            let offer = subscriptionInfo.introductoryOffer,
            offer.paymentMode == .freeTrial
        else {
            freeTrialOfferDescription = nil
            return
        }

        guard await subscriptionInfo.isEligibleForIntroOffer else {
            freeTrialOfferDescription = nil
            return
        }

        let duration = Self.formattedPeriod(offer.period)
        let price = product?.displayPrice ?? ""
        freeTrialOfferDescription = "Prueba gratis \(duration), luego \(price) / mes"
    }

    private static func formattedPeriod(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day: return value == 1 ? "1 dia" : "\(value) dias"
        case .week: return value == 1 ? "1 semana" : "\(value) semanas"
        case .month: return value == 1 ? "1 mes" : "\(value) meses"
        case .year: return value == 1 ? "1 año" : "\(value) años"
        @unknown default: return "\(value)"
        }
    }

    /// Le pregunta a StoreKit (directo, sin pasar por nuestro backend) si
    /// la suscripcion activa se va a renovar sola y cuando termina el
    /// periodo pagado actual. StoreKit siempre tiene esto al dia porque lo
    /// sincroniza con Apple solo — asi nos enteramos de una cancelacion
    /// hecha fuera de la app (Ajustes de iOS, el sheet de "Administrar
    /// suscripcion") sin necesitar un webhook de App Store Server
    /// Notifications en el backend.
    func refreshRenewalInfo() async {
        guard let subscriptionInfo = product?.subscription else { return }

        do {
            let statuses = try await subscriptionInfo.status
            guard let status = statuses.first else {
                willAutoRenew = nil
                currentPeriodEndDate = nil
                return
            }

            if case .verified(let renewalInfo) = status.renewalInfo {
                willAutoRenew = renewalInfo.willAutoRenew
            }
            if case .verified(let transaction) = status.transaction {
                currentPeriodEndDate = transaction.expirationDate
            }
        } catch {
            // Deja los valores anteriores — se reintenta en el siguiente
            // refresh (login, compra, o al entrar a Ajustes).
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
