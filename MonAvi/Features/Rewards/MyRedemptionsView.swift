import SwiftUI

/// "Mis canjes": historial de codigos generados. Tocar uno que sigue
/// listo para usar vuelve a abrir el codigo para mostrarlo en caja.
struct MyRedemptionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var redemptions: [RewardRedemption] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var presentedRedemption: RewardRedemption?

    var body: some View {
        List {
            content
        }
        .navigationTitle("Mis canjes")
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(item: $presentedRedemption) { (redemption: RewardRedemption) in
            RedemptionCodeView(redemption: redemption)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded && redemptions.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if let errorMessage, redemptions.isEmpty {
            Text(errorMessage)
                .foregroundStyle(MonAviBrand.alert)
        } else if redemptions.isEmpty {
            ContentUnavailableView(
                "Todavía no has canjeado nada",
                systemImage: "ticket",
                description: Text("Cuando canjees tus puntos en un comercio aliado, tus códigos aparecen aquí.")
            )
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(redemptions) { (redemption: RewardRedemption) in
                    row(redemption)
                }
            } footer: {
                Text("Los códigos vencen a los 7 días. Si no lo usas a tiempo, te devolvemos los puntos.")
            }
        }
    }

    @ViewBuilder
    private func row(_ redemption: RewardRedemption) -> some View {
        if redemption.isUsable() {
            Button {
                presentedRedemption = redemption
            } label: {
                rowContent(redemption)
            }
            .foregroundStyle(.primary)
        } else {
            rowContent(redemption)
        }
    }

    private func rowContent(_ redemption: RewardRedemption) -> some View {
        HStack(spacing: 12) {
            MerchantLogoView(
                urlString: redemption.displayMerchant?.logoUrl,
                name: redemption.merchantName,
                size: 40
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(redemption.item?.name ?? "Producto canjeado")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(redemption.merchantName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detailText(redemption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                RedemptionStatusBadge(status: redemption.effectiveStatus())
                Text("\(redemption.pointsCost) pts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func detailText(_ redemption: RewardRedemption) -> String {
        let created = redemption.createdAt.formatted(date: .abbreviated, time: .omitted)
        if redemption.isUsable() {
            return "Código \(redemption.code) · vence el \(redemption.expiresAt.formatted(date: .abbreviated, time: .omitted))"
        }
        if redemption.status == .entregado, let deliveredAt = redemption.deliveredAt {
            return "Entregado el \(deliveredAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Canjeado el \(created)"
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            redemptions = try await RewardsRepository.shared.fetchMyRedemptions(userId: userId)
            errorMessage = nil
        } catch {
            errorMessage = "No pudimos cargar tus canjes. Desliza hacia abajo para intentar de nuevo."
        }
    }
}
