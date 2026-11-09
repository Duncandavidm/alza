import SwiftUI
import UIKit

/// "Canjea tus premios": catalogo de productos de comercios aliados. Cada
/// comercio canjea en una moneda: cashback (centavos, de facturas DGI) o
/// puntos (por buenos habitos). El usuario toca "Canjear", confirma, y la
/// RPC `redeem_reward` descuenta de la moneda correcta y genera el codigo
/// que muestra en caja.
struct RewardsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = RewardsViewModel()

    /// "Premios" (catalogo) o "Comercios" (donde canjear).
    enum Mode: String, CaseIterable, Identifiable {
        case rewards = "Premios"
        case merchants = "Comercios"
        var id: String { rawValue }
    }

    @State private var mode: Mode
    /// Si viene de "Ver premios" de un comercio, solo muestra los suyos.
    @State private var merchantFilter: UUID?

    init(initialMode: Mode = .rewards) {
        _mode = State(initialValue: initialMode)
    }

    @State private var pendingItem: RewardItem?
    @State private var isConfirming = false
    @State private var isRedeeming = false
    @State private var presentedRedemption: RewardRedemption?
    @State private var redeemErrorMessage: String?
    /// Producto cuyo canje pidio verificar el correo; se reintenta solo al
    /// cerrar EmailVerificationSheet si se verifico.
    @State private var itemAwaitingVerification: RewardItem?
    @State private var isVerifyingEmail = false
    @State private var didVerifyEmail = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                balanceHeader
                referralBanner
                Picker("Ver", selection: $mode) {
                    ForEach(Mode.allCases) { (option: Mode) in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                if mode == .rewards {
                    if let merchantFilter {
                        merchantFilterChip(merchantFilter)
                    } else if viewModel.categories.count > 1 {
                        categoryChips
                    }
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(mode == .rewards ? "Canjea tus premios" : "Dónde canjear")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .task { await refresh() }
        .overlay { redeemingOverlay }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirming,
            titleVisibility: .visible,
            presenting: pendingItem
        ) { (item: RewardItem) in
            Button("Canjear por \(item.formattedCost)") {
                Task { await redeem(item) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $presentedRedemption) { (redemption: RewardRedemption) in
            RedemptionCodeView(redemption: redemption)
        }
        .sheet(isPresented: $isVerifyingEmail, onDismiss: retryAfterEmailVerification) {
            EmailVerificationSheet {
                didVerifyEmail = true
            }
        }
        .alert("No se pudo canjear", isPresented: isShowingRedeemError) {
            Button("OK", role: .cancel) { redeemErrorMessage = nil }
        } message: {
            Text(redeemErrorMessage ?? "")
        }
    }

    // MARK: - Secciones

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                MyRedemptionsView()
            } label: {
                Label("Mis canjes", systemImage: "ticket.fill")
            }
        }
    }

    private var balanceHeader: some View {
        RewardBalancesHeader(balance: viewModel.balance)
    }

    /// Atajo a "Invita amigos" (mismo ReferralView que en Mi perfil).
    private var referralBanner: some View {
        NavigationLink {
            ReferralView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title3)
                    .foregroundStyle(MonAviBrand.primary)
                Text("Invita amigos y gana 200 puntos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "Todos", category: nil)
                ForEach(viewModel.categories, id: \.self) { (category: String) in
                    categoryChip(title: category, category: category)
                }
            }
        }
    }

    private func categoryChip(title: String, category: String?) -> some View {
        let isSelected = viewModel.selectedCategory == category
        return Button {
            withAnimation(.snappy) {
                viewModel.selectedCategory = category
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? MonAviBrand.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded && viewModel.items.isEmpty {
            ProgressView("Cargando comercios…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            errorState(errorMessage)
        } else if viewModel.items.isEmpty {
            emptyState
        } else if mode == .merchants {
            merchantsList
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            itemsList
        }
    }

    private var visibleItems: [RewardItem] {
        if let merchantFilter {
            return viewModel.items.filter { $0.merchantId == merchantFilter }
        }
        return viewModel.filteredItems
    }

    private var merchantsList: some View {
        ForEach(PartnerMerchantSummary.group(viewModel.items)) { (summary: PartnerMerchantSummary) in
            PartnerMerchantRow(
                summary: summary,
                balance: viewModel.spendableBalance(for: summary.items[0]),
                onDirections: { openDirections(for: summary.items[0]) },
                onShowRewards: {
                    withAnimation(.snappy) {
                        merchantFilter = summary.id
                        mode = .rewards
                    }
                }
            )
        }
    }

    private func merchantFilterChip(_ merchantId: UUID) -> some View {
        let name = viewModel.items.first { $0.merchantId == merchantId }?.merchantName ?? "Comercio"
        return Button {
            withAnimation(.snappy) { merchantFilter = nil }
        } label: {
            Label("\(name)  ✕", systemImage: "storefront")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MonAviBrand.primary, in: Capsule())
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Quitar filtro de \(name)")
    }

    private var itemsList: some View {
        ForEach(visibleItems) { (item: RewardItem) in
            RewardItemCard(
                item: item,
                balance: viewModel.spendableBalance(for: item),
                isRedeeming: isRedeeming,
                onDirections: { openDirections(for: item) },
                onRedeem: { askToRedeem(item) }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Pronto habrá comercios aliados",
                systemImage: "gift",
                description: Text("Pronto verás aquí los comercios aliados donde canjear tus puntos y tu cashback.")
            )
            .padding(.top, 24)
        } else {
            ContentUnavailableView(
                "Nada en esta categoría",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Prueba con otra categoría o toca \"Todos\".")
            )
            .padding(.top, 24)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Algo salió mal", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Reintentar") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private var redeemingOverlay: some View {
        if isRedeeming {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView("Canjeando…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Acciones

    private var confirmationTitle: String {
        guard let item = pendingItem else { return "¿Canjear este producto?" }
        return RewardsMath.confirmationTitle(
            itemName: item.name,
            merchantName: item.merchantName,
            cost: item.pointsCost,
            currency: item.currency
        )
    }

    private var isShowingRedeemError: Binding<Bool> {
        Binding(
            get: { redeemErrorMessage != nil },
            set: { newValue in
                if !newValue { redeemErrorMessage = nil }
            }
        )
    }

    private func askToRedeem(_ item: RewardItem) {
        pendingItem = item
        isConfirming = true
    }

    private func openDirections(for item: RewardItem) {
        let url = RewardsMath.directionsURL(for: item.merchant)
            ?? RewardsMath.directionsURL(name: item.merchantName, address: nil, mapsUrl: nil)
        if let url {
            openURL(url)
        }
    }

    private func redeem(_ item: RewardItem) async {
        guard !isRedeeming else { return }
        isRedeeming = true
        do {
            let redemption = try await RewardsRepository.shared.redeem(item: item)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isRedeeming = false
            pendingItem = nil
            presentedRedemption = redemption
        } catch let error where RewardsRepository.requiresEmailVerification(error) {
            // Primer canje con el correo sin verificar: pedir el codigo y,
            // al verificar, reintentar este mismo canje.
            isRedeeming = false
            itemAwaitingVerification = item
            didVerifyEmail = false
            isVerifyingEmail = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isRedeeming = false
            redeemErrorMessage = RewardsRepository.userMessage(for: error)
        }
        if let userId = appState.currentUserId {
            await viewModel.refreshBalance(userId: userId)
        }
    }

    /// Al cerrar EmailVerificationSheet: si se verifico, reintenta el canje
    /// pendiente (despues de cerrar la hoja, para poder presentar el
    /// codigo del canje sin chocar con la animacion de cierre).
    private func retryAfterEmailVerification() {
        let item = itemAwaitingVerification
        let verified = didVerifyEmail
        itemAwaitingVerification = nil
        didVerifyEmail = false
        guard verified, let item else { return }
        Task { await redeem(item) }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}
