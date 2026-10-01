import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var subscriptionStore: SubscriptionStore
    @State private var isSigningOut = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                EmbeddedLogo.alzaMark
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text("Alza Pro")
                    .font(.system(.largeTitle, design: AlzaBrand.fontDesign, weight: .bold))
                Text("Dashboard financiero completo + insights de IA personalizados sobre tus cuentas y gastos.")
                    .font(.system(.subheadline, design: AlzaBrand.fontDesign))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                if let product = subscriptionStore.product {
                    if let trialOffer = subscriptionStore.freeTrialOfferDescription {
                        VStack(spacing: 4) {
                            Text(trialOffer)
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                            Text("Te vamos a pedir tu metodo de pago ahora, pero no se te cobra nada hasta que termine la prueba.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        Text("\(product.displayPrice) / mes")
                            .font(.title2.bold())
                    }
                } else if subscriptionStore.isLoadingProduct {
                    ProgressView()
                } else {
                    Text("No se pudo cargar el precio")
                        .foregroundStyle(AlzaBrand.alert)
                }

                Button {
                    guard let userId = appState.currentUserId else { return }
                    Task { await subscriptionStore.purchase(appAccountToken: userId) }
                } label: {
                    Text(subscriptionStore.freeTrialOfferDescription != nil ? "Empezar prueba gratis" : "Suscribirme")
                        .font(.system(.headline, design: AlzaBrand.fontDesign))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .pressable()
                .disabled(subscriptionStore.product == nil)

                Button("Restaurar compras") {
                    Task {
                        await subscriptionStore.restore()
                        await appState.refreshSubscriptionStatus()
                    }
                }
                .font(.footnote)

                if let error = subscriptionStore.purchaseError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(AlzaBrand.alert)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        isSigningOut = true
                        await appState.signOut()
                        isSigningOut = false
                    }
                } label: {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Text("Cerrar sesion")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .disabled(isSigningOut)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .task {
            await subscriptionStore.loadProduct()
        }
    }
}
