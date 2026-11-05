import SwiftUI

/// Entrada unica a todo lo de puntos: el saldo real (ledger compartido
/// entre todas las fuentes) y accesos a cada una.
///
/// "Tarjeta en comercios aliados" ya no tiene entrada propia aqui ni
/// requiere vincular tarjeta: verify-dgi-receipt revisa la "Forma de
/// Pago" que reporta la propia factura DGI escaneada en "Facturas que
/// suman" y, si dice tarjeta y el RUC es un comercio aliado con oferta
/// activa, acredita el bono ahi mismo (entra al mismo saldo de abajo).
/// LinkedCardsView/PartnerOffersView (vincular tarjeta a mano, navegar
/// ofertas) quedan sin usarse — ese flujo manual ya no hace falta.
struct PointsHubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = PointsViewModel()

    var body: some View {
        List {
            Section {
                balanceSummary
            }

            Section("Gana puntos") {
                NavigationLink {
                    DgiReceiptsListView()
                } label: {
                    Label("Facturas que suman", systemImage: "qrcode.viewfinder")
                }

                NavigationLink {
                    HabitsView()
                } label: {
                    Label("Habitos", systemImage: "flame.fill")
                }

                NavigationLink {
                    MySavingsGoalsView()
                } label: {
                    Label("Mis metas", systemImage: "banknote.fill")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Puntos")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var balanceSummary: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Confirmados").font(.caption).foregroundStyle(.secondary)
                Text("\(viewModel.balance.confirmedPoints) pts").font(.title.weight(.bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pendientes").font(.caption).foregroundStyle(.secondary)
                Text("\(viewModel.balance.pendingPoints) pts").font(.title.weight(.bold))
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}
