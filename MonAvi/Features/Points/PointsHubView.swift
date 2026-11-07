import SwiftUI

/// "Puntos y cashback": entrada unica a las dos monedas de premio — el
/// cashback (facturas verificadas por la DGI) y los puntos (buenos
/// habitos, calculados en el servidor) — y al catalogo de canje.
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
                RewardBalancesHeader(balance: viewModel.balance)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    RewardsView()
                } label: {
                    rewardsCard
                }

                NavigationLink {
                    MyRedemptionsView()
                } label: {
                    Label("Mis canjes", systemImage: "ticket.fill")
                }
            } footer: {
                Text("Cada comercio aliado elige si canjea con puntos o con cashback.")
            }

            Section {
                NavigationLink {
                    DgiReceiptsListView()
                } label: {
                    Label("Facturas que suman", systemImage: "qrcode.viewfinder")
                }
            } header: {
                Text("Gana cashback")
            } footer: {
                Text("Ganas 1% de cashback de cada factura confirmada por la DGI.")
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
                Text("Gana puntos")
            } footer: {
                Text("Anotar tus movimientos, ahorrar con constancia y cumplir presupuestos te da puntos (hasta \(HabitEngine.Rules.monthlyXPCap) al mes) y te sube de nivel.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Puntos y cashback")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    /// Entrada destacada al catalogo de canje.
    private var rewardsCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MonAviBrand.headerGradient)
                Image(systemName: "gift.fill")
                    .font(.title3)
                    .foregroundStyle(MonAviBrand.accentOnDark)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("Canjea tus premios")
                    .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                Text("Usa tus puntos y tu cashback en comercios aliados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}
