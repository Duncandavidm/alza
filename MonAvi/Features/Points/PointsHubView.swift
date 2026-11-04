import SwiftUI

/// Entrada unica a todo lo de puntos: el saldo real (ledger compartido
/// entre "Facturas que suman", tarjeta en comercios aliados, y mas
/// adelante ahorro/habitos) y accesos a cada fuente.
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
                    LinkedCardsView(viewModel: viewModel)
                } label: {
                    Label("Mis tarjetas", systemImage: "creditcard.fill")
                }

                NavigationLink {
                    PartnerOffersView(viewModel: viewModel)
                } label: {
                    Label("Ofertas cerca", systemImage: "tag.fill")
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
