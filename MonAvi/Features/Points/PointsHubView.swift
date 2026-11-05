import SwiftUI

/// Entrada unica a todo lo de puntos: el saldo real (ledger compartido
/// entre todas las fuentes) y accesos a cada una.
///
/// "Tarjeta en comercios aliados" (LinkedCardsView/PartnerOffersView) se
/// quito de aqui a proposito — depender de que cada comercio suba su
/// reporte de ventas resulto poco practico para lanzar. El codigo y el
/// backend (migracion 0024, reconcile-card-transactions) se quedan tal
/// cual, sin usarse, por si se retoma mas adelante con un comercio que
/// si quiera participar.
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
