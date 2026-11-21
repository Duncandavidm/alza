import SwiftUI

/// "Cashback y cupones": el cashback (facturas verificadas por la DGI),
/// los descuentos de aliados, el catalogo de premios y los cupones por
/// buenos habitos (1.0.3: ya no hay puntos).
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
/// ofertas) quedan sin usarse — ese flujo manual ya no hace falta. En su
/// lugar, "Conecta tus pagos con Wallet" (WalletAutomationGuideView)
/// explica como anotar cada pago con tarjeta solo, via Atajos.
///
/// "Ofertas de marcas" (brand_campaigns) solo aparece si hay campañas
/// activas; cualquier error la esconde en silencio. Al abrir el hub por
/// primera vez sin decision, se pide el consentimiento del estudio de
/// mercado anonimo (MarketStudyConsentView, una sola vez).
struct PointsHubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = PointsViewModel()
    @State private var brandCampaigns: [BrandCampaign] = []
    @State private var isShowingMarketStudyConsent = false

    var body: some View {
        List {
            Section {
                RewardBalancesHeader(balance: viewModel.balance)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    RewardsView(initialMode: .benefits)
                } label: {
                    rewardsCard
                }

                NavigationLink {
                    RewardsView(initialMode: .merchants)
                } label: {
                    Label("Dónde canjear: comercios aliados", systemImage: "storefront.fill")
                }

                NavigationLink {
                    MyRedemptionsView()
                } label: {
                    Label("Mis canjes", systemImage: "ticket.fill")
                }
            } footer: {
                Text("Descuentos gratis por ser de MonAvi y premios que canjeas con tu cashback.")
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
                Text("Ganas 1% de cashback de cada factura que escaneas.")
            }

            if !brandCampaigns.isEmpty {
                Section {
                    ForEach(brandCampaigns) { campaign in
                        BrandCampaignCard(campaign: campaign)
                    }
                } header: {
                    Text("Ofertas de marcas")
                }
            }

            Section {
                NavigationLink {
                    WalletAutomationGuideView()
                } label: {
                    Label("Conecta tus pagos con Wallet", systemImage: "wallet.pass.fill")
                }
            } header: {
                Text("Paga con tarjeta en comercios aliados")
            } footer: {
                Text("Cada pago con tarjeta se anota solo. Si pagas con tarjeta en un comercio aliado y escaneas la factura, ganas un bono extra.")
            }

            Section {
                NavigationLink {
                    HabitCouponsView()
                } label: {
                    Label("Cupones por buenos hábitos", systemImage: "ticket.fill")
                }

                NavigationLink {
                    SavingsGoalsView()
                } label: {
                    Label("Metas de ahorro", systemImage: "banknote.fill")
                }
            } header: {
                Text("Gana cupones")
            } footer: {
                Text("Ahorrar parte de tus ingresos, cumplir tus metas a tiempo y tus presupuestos te da cupones de descuento en comercios aliados.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Cashback y cupones")
        .refreshable { await refresh() }
        .task { await refresh() }
        .task { await promptMarketStudyConsentIfNeeded() }
        .sheet(isPresented: $isShowingMarketStudyConsent) {
            MarketStudyConsentView()
        }
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
                Text("Descuentos y premios")
                    .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                Text("Descuentos por ser de MonAvi y premios con tu cashback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        brandCampaigns = await BrandCampaignsRepository.shared.fetchActiveOrEmpty()
    }

    /// Una sola vez: si el usuario aun no decidio sobre el estudio de
    /// mercado anonimo, se le pregunta al abrir el hub.
    private func promptMarketStudyConsentIfNeeded() async {
        guard let userId = appState.currentUserId else { return }
        guard await MarketStudyConsentPrompt.shouldShow(userId: userId) else { return }
        MarketStudyConsentPrompt.markShown(userId: userId)
        isShowingMarketStudyConsent = true
    }
}
