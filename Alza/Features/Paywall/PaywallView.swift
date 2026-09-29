import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var subscriptionStore: SubscriptionStore
    @State private var isSigningOut = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Alza Pro")
                    .font(.largeTitle.bold())
                Text("Dashboard financiero completo + insights de IA personalizados sobre tus cuentas y gastos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                if let product = subscriptionStore.product {
                    Text("\(product.displayPrice) / mes")
                        .font(.title2.bold())
                } else if subscriptionStore.isLoadingProduct {
                    ProgressView()
                } else {
                    Text("No se pudo cargar el precio")
                        .foregroundStyle(.red)
                }

                Button {
                    guard let userId = appState.currentUserId else { return }
                    Task { await subscriptionStore.purchase(appAccountToken: userId) }
                } label: {
                    Text("Suscribirme")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
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
                        .foregroundStyle(.red)
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
