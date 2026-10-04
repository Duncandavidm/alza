import Foundation
import StoreKit
import UIKit

enum SubscriptionTier: String, CaseIterable, Identifiable {
    case individual
    case familia

    var id: String { rawValue }
}

enum SubscriptionBilling: String, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }
}

/// 2 tiers (individual / familia) x 2 ciclos (mensual / anual) = 4 planes,
/// todos en el mismo grupo de suscripcion "Avi Pro" en App Store
/// Connect. "Familia" NO es Apple Family Sharing (eso es gratis para la
/// familia del comprador) — es un producto propio, mas caro, que da
/// derecho a invitar hasta 5 personas con un codigo (ver
/// FamilyGroupService). Ver Config.swift para el porque de cada Product ID.
enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case individualMonthly
    case individualAnnual
    case familyMonthly
    case familyAnnual

    var id: String { rawValue }

    var tier: SubscriptionTier {
        switch self {
        case .individualMonthly, .individualAnnual: return .individual
        case .familyMonthly, .familyAnnual: return .familia
        }
    }

    var billing: SubscriptionBilling {
        switch self {
        case .individualMonthly, .familyMonthly: return .monthly
        case .individualAnnual, .familyAnnual: return .annual
        }
    }

    var productId: String {
        switch self {
        case .individualMonthly: return Config.subscriptionProductId
        case .individualAnnual: return Config.subscriptionProductIdAnnual
        case .familyMonthly: return Config.subscriptionProductIdFamily
        case .familyAnnual: return Config.subscriptionProductIdFamilyAnnual
        }
    }

    static func plan(tier: SubscriptionTier, billing: SubscriptionBilling) -> SubscriptionPlan {
        switch (tier, billing) {
        case (.individual, .monthly): return .individualMonthly
        case (.individual, .annual): return .individualAnnual
        case (.familia, .monthly): return .familyMonthly
        case (.familia, .annual): return .familyAnnual
        }
    }
}

/// Maneja la compra/restauracion de la suscripcion de Avi con StoreKit 2
/// directo (nada de bridge nativo<->JS: la app es 100% nativa). 4 planes
/// del mismo Pro (individual/familia x mensual/anual, mismo grupo de
/// suscripcion en App Store Connect) — el usuario elige cual comprar.
/// Individual y Familia dan acceso Pro igual de completo; la diferencia es
/// que Familia ademas habilita invitar hasta 5 personas (ver
/// FamilyGroupService) — eso lo decide el backend por product_id, ver
/// AppState.refreshSubscriptionStatus / la RPC get_entitlement_status.
/// appAccountToken = auth.uid() del usuario logueado en Supabase, para que
/// la Edge Function verify-apple-receipt pueda amarrar la transaccion al
/// usuario correcto sin depender de un login adicional.
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [SubscriptionPlan: Product] = [:]
    @Published var selectedPlan: SubscriptionPlan = .individualAnnual
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var purchaseError: String?

    var selectedProduct: Product? { products[selectedPlan] }

    func product(tier: SubscriptionTier, billing: SubscriptionBilling) -> Product? {
        products[.plan(tier: tier, billing: billing)]
    }

    /// Si la suscripcion activa se va a renovar sola o no (el usuario la
    /// cancelo desde Ajustes de iOS / el sheet de administrar suscripcion,
    /// algo que pasa FUERA de la app, no hay forma de que lo sepamos salvo
    /// preguntandole a StoreKit). nil = todavia no se ha podido consultar.
    @Published private(set) var willAutoRenew: Bool?
    /// Fecha en que termina el periodo pagado actual — si willAutoRenew es
    /// false, es la fecha en que el usuario pierde el acceso (no antes:
    /// Apple nunca corta el acceso a mitad del periodo ya pagado).
    @Published private(set) var currentPeriodEndDate: Date?

    /// "Prueba gratis 1 semana, luego $X / mes" para el plan seleccionado,
    /// solo cuando ese producto tiene una oferta introductoria de tipo
    /// prueba gratis Y el usuario todavia es elegible (nunca la ha usado).
    /// nil si no aplica — en ese caso el paywall muestra solo el precio.
    @Published private(set) var freeTrialOfferDescription: String?
    @Published private(set) var freeTrialDurationText: String?

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
            let ids = SubscriptionPlan.allCases.map(\.productId)
            let loaded = try await Product.products(for: ids)

            var byPlan: [SubscriptionPlan: Product] = [:]
            for plan in SubscriptionPlan.allCases {
                if let match = loaded.first(where: { $0.id == plan.productId }) {
                    byPlan[plan] = match
                }
            }
            products = byPlan

            if byPlan.isEmpty {
                purchaseError = "No se encontraron los productos de suscripcion. Revisa que existan en App Store Connect (o en el archivo .storekit local) con esos Product IDs exactos."
            } else if byPlan[selectedPlan] == nil {
                // Si el plan preferido (individual anual) no cargo, prueba
                // primero otro ciclo del mismo tier antes de saltar a
                // Familia, para no mostrar el tier equivocado por defecto.
                let sameTier = byPlan.keys.first { $0.tier == selectedPlan.tier }
                selectedPlan = sameTier ?? byPlan.keys.first ?? selectedPlan
            }

            await refreshRenewalInfo()
            await refreshFreeTrialEligibility()
        } catch {
            purchaseError = "No se pudo cargar el producto: \(error.localizedDescription)"
        }
    }

    func selectPlan(_ plan: SubscriptionPlan) {
        guard products[plan] != nil else { return }
        selectedPlan = plan
        Task { await refreshFreeTrialEligibility() }
    }

    /// Precio mensual equivalente del plan anual (total / 12), para mostrar
    /// "$X.XX / mes" en la tarjeta de "12 meses" igual que el precio
    /// mensual, en vez del total del año de una sola vez.
    func monthlyEquivalentPrice(for product: Product) -> String? {
        guard let subscriptionInfo = product.subscription, subscriptionInfo.subscriptionPeriod.unit == .year else {
            return product.displayPrice
        }
        let monthly = product.price / 12
        return monthly.formatted(product.priceFormatStyle)
    }

    /// Arma el texto de "prueba gratis" solo si el producto trae una oferta
    /// introductoria de tipo prueba gratis Y StoreKit confirma que el
    /// usuario todavia no la ha usado (isEligibleForIntroOffer) — alguien
    /// que ya tuvo una suscripcion antes no vuelve a ver la prueba gratis,
    /// asi StoreKit evita que la misma persona la reclame dos veces.
    private func refreshFreeTrialEligibility() async {
        guard
            let product = selectedProduct,
            let subscriptionInfo = product.subscription,
            let offer = subscriptionInfo.introductoryOffer,
            offer.paymentMode == .freeTrial
        else {
            freeTrialOfferDescription = nil
            freeTrialDurationText = nil
            return
        }

        guard await subscriptionInfo.isEligibleForIntroOffer else {
            freeTrialOfferDescription = nil
            freeTrialDurationText = nil
            return
        }

        let duration = Self.formattedPeriod(offer.period)
        let price = product.displayPrice
        freeTrialDurationText = duration
        freeTrialOfferDescription = "Prueba gratis \(duration), luego \(price)"
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
        // Cualquiera de los productos del grupo sirve para preguntar el
        // estado — StoreKit devuelve el estado real de lo que el usuario
        // tenga activo en el grupo, sea cual sea el plan que compro.
        guard let subscriptionInfo = (selectedProduct ?? products.values.first)?.subscription else { return }

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
        guard let product = selectedProduct else { return }
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
