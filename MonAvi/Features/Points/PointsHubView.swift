import SwiftUI

/// Entrada unica a todo lo de puntos: el saldo canjeable (solo fuentes
/// verificadas por un tercero, hoy facturas DGI) y, aparte, los habitos
/// (nivel e insignias, que no se canjean).
///
/// "Ahorro verificado" con bancos se quito por completo del app (vistas,
/// modelos y llamadas): depender de reportes de bancos no era viable para
/// lanzar. Las tablas siguen en Supabase, intactas, por si algun banco
/// quiere participar mas adelante.
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

            Section {
                NavigationLink {
                    DgiReceiptsListView()
                } label: {
                    Label("Facturas que suman", systemImage: "qrcode.viewfinder")
                }
            } header: {
                Text("Gana puntos canjeables")
            } footer: {
                Text("Solo las facturas confirmadas por la DGI dan puntos canjeables.")
            }

            Section {
                NavigationLink {
                    LevelsView()
                } label: {
                    Label("Nivel e insignias", systemImage: "rosette")
                }

                NavigationLink {
                    SavingsGoalsView()
                } label: {
                    Label("Metas de ahorro", systemImage: "banknote.fill")
                }
            } header: {
                Text("Hábitos")
            } footer: {
                Text("Anotar tus movimientos, ahorrar con constancia y cumplir presupuestos te sube de nivel. Los niveles no se canjean.")
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
                Text("Canjeables").font(.caption).foregroundStyle(.secondary)
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
