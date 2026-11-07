import SwiftUI
import UIKit

/// "Canjea tu cashback": catalogo de productos de comercios aliados. El
/// usuario toca "Canjear", confirma, y la RPC `redeem_reward` descuenta
/// el cashback (puntos en centavos) y genera el codigo que muestra en caja.
struct RewardsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = RewardsViewModel()

    @State private var pendingItem: RewardItem?
    @State private var isConfirming = false
    @State private var isRedeeming = false
    @State private var presentedRedemption: RewardRedemption?
    @State private var redeemErrorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                balanceHeader
                if viewModel.categories.count > 1 {
                    categoryChips
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Canjea tu cashback")
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
            Button("Canjear por \(Cashback.format(cents: item.pointsCost))") {
                Task { await redeem(item) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $presentedRedemption) { (redemption: RewardRedemption) in
            RedemptionCodeView(redemption: redemption)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Tu cashback disponible")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.85))
            Text(Cashback.format(cents: viewModel.redeemablePoints))
                .font(.system(size: 40, weight: .bold, design: MonAviBrand.fontDesign))
                .foregroundStyle(MonAviBrand.onDarkSurface)
                .contentTransition(.numericText())
            if viewModel.balance.pendingPoints > 0 {
                Text("+\(Cashback.format(cents: viewModel.balance.pendingPoints)) por confirmar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MonAviBrand.accentOnDark)
            } else {
                Text("Úsalo en productos de comercios aliados.")
                    .font(.caption)
                    .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(MonAviBrand.headerGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
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
        } else if viewModel.filteredItems.isEmpty {
            emptyState
        } else {
            itemsList
        }
    }

    private var itemsList: some View {
        ForEach(viewModel.filteredItems) { (item: RewardItem) in
            RewardItemCard(
                item: item,
                balance: viewModel.redeemablePoints,
                isRedeeming: isRedeeming,
                onDirections: { openDirections(for: item) },
                onRedeem: { askToRedeem(item) }
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Pronto habrá comercios aliados aquí",
            systemImage: "gift",
            description: Text("Sigue sumando cashback con tus facturas: cuando lleguen los primeros comercios, lo vas a poder canjear aquí mismo.")
        )
        .padding(.top, 24)
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
        return RewardsMath.confirmationTitle(itemName: item.name, merchantName: item.merchantName, cost: item.pointsCost)
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
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isRedeeming = false
            redeemErrorMessage = RewardsRepository.userMessage(for: error)
        }
        if let userId = appState.currentUserId {
            await viewModel.refreshBalance(userId: userId)
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}
