import StoreKit
import SwiftUI

/// Durante la prueba gratis los descuentos, bonos y canjes se ven pero en
/// gris: se desbloquean cuando empieza el plan pagado (el servidor también
/// los bloquea, migración 0096). Este aviso va arriba de esas pantallas,
/// con «Pasar a Pro ya» para quien no quiera esperar.
struct TrialLockedBanner: View {
    @EnvironmentObject private var appState: AppState
    @State private var isShowingUnlock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MonAviBrand.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MonAviBrand.primary.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Se desbloquean con tu plan Pro")
                        .font(.subheadline.weight(.semibold))
                    Text(TrialUnlockText.bannerDetail(endDate: appState.trialEndDate))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                isShowingUnlock = true
            } label: {
                Text("Pasar a Pro ya")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MonAviBrand.primary.opacity(0.08)))
        .sheet(isPresented: $isShowingUnlock) {
            UpgradeNowSheet(store: appState.subscriptionStore)
                .presentationDetents([.medium, .large])
        }
    }
}

extension View {
    /// En gris y sin poder tocarse mientras dure la prueba gratis. Tocarlo
    /// abre «Pasar a Pro ya».
    func trialLocked(_ locked: Bool, onTap: @escaping () -> Void) -> some View {
        self
            .grayscale(locked ? 1 : 0)
            .opacity(locked ? 0.5 : 1)
            .allowsHitTesting(!locked)
            .overlay {
                if locked {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTap)
                }
            }
            .accessibilityHint(locked ? "Se desbloquea con tu plan Pro" : "")
    }
}

enum TrialUnlockText {
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_PA")))
    }

    static func bannerDetail(endDate: Date?) -> String {
        if let endDate {
            return "Durante la prueba gratis puedes verlos. El \(dayText(endDate)) empieza tu plan y se activan solos."
        }
        return "Durante la prueba gratis puedes verlos. Cuando empiece tu plan se activan solos."
    }
}

extension AppState {
    /// Último día de la prueba gratis (cuando empieza a cobrarse el plan).
    var trialEndDate: Date? {
        guard isInFreeTrial, case .active(let expiresAt) = subscriptionStatus else { return nil }
        return expiresAt
    }
}

/// «Pasar a Pro ya»: termina la prueba y activa el plan pagado hoy mismo.
/// Apple no deja adelantar el cobro del mismo plan; sí deja pasar al plan
/// de nivel más alto del grupo, que se activa al instante.
struct UpgradeNowSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    @ObservedObject var store: SubscriptionStore

    private var upgrade: Product? {
        store.upgradeProduct(fromProductId: appState.entitlementProductId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(MonAviBrand.primary)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(MonAviBrand.primary.opacity(0.12)))
                        .padding(.top, 8)

                    Text("Desbloquea tus descuentos hoy")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Los descuentos de comercios, bonos y canjes son para el plan pagado. Si no quieres esperar a que termine tu prueba gratis, activa tu plan ahora y quedan listos al instante.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let upgrade {
                        purchaseButton(upgrade)
                    } else {
                        unavailableNotice
                    }

                    if let error = store.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                if store.products.isEmpty { await store.loadProduct() }
            }
        }
    }

    private func purchaseButton(_ product: Product) -> some View {
        VStack(spacing: 8) {
            Button {
                Task { await buy(product) }
            } label: {
                HStack {
                    if isPurchasing { ProgressView().tint(.white) }
                    Text("Pagar ya · \(store.formattedPrice(product)) \(periodSuffix(product))")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
            .disabled(isPurchasing)

            Text("Se cobra hoy con tu cuenta de Apple, tu prueba gratis termina y pasas a \(product.displayName). Se renueva sola; cancélala cuando quieras en Ajustes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var unavailableNotice: some View {
        VStack(spacing: 10) {
            Text(appState.trialEndDate.map { "Tu plan empieza solo el \(TrialUnlockText.dayText($0)) y ese día se desbloquean." }
                 ?? "Tu plan empieza solo al terminar la prueba y ese día se desbloquean.")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Apple no permite adelantar el cobro del plan que ya tienes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Administrar suscripción") {
                Task { await store.openManageSubscriptions() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func periodSuffix(_ product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: return "al año"
        case .month: return "al mes"
        case .week: return "a la semana"
        default: return ""
        }
    }

    private func buy(_ product: Product) async {
        guard let userId = appState.currentUserId else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        if await store.purchase(product, appAccountToken: userId) {
            await appState.refreshSubscriptionStatus()
            dismiss()
        }
    }
}
