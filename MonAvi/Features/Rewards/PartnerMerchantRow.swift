import SwiftUI

/// Un comercio aliado con sus premios activos, para la lista "Dónde
/// canjear". Se arma a partir del catalogo (solo aparecen comercios que
/// tienen al menos un premio disponible).
struct PartnerMerchantSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let merchant: PartnerMerchant?
    /// Nunca vacio (cada resumen nace de al menos un premio).
    let items: [RewardItem]

    var currency: RewardCurrency { items[0].currency }
    var cheapestCost: Int { items.map(\.pointsCost).min() ?? 0 }

    /// Agrupa por comercio, en el orden en que aparece cada uno en el
    /// catalogo.
    static func group(_ items: [RewardItem]) -> [PartnerMerchantSummary] {
        var order: [UUID] = []
        var byMerchant: [UUID: [RewardItem]] = [:]
        for item in items {
            if byMerchant[item.merchantId] == nil {
                order.append(item.merchantId)
            }
            byMerchant[item.merchantId, default: []].append(item)
        }
        return order.compactMap { (merchantId: UUID) -> PartnerMerchantSummary? in
            guard let merchantItems = byMerchant[merchantId], let first = merchantItems.first else { return nil }
            return PartnerMerchantSummary(
                id: merchantId,
                name: first.merchantName,
                merchant: first.merchant,
                items: merchantItems
            )
        }
    }
}

struct PartnerMerchantRow: View {
    let summary: PartnerMerchantSummary
    /// Saldo en la moneda del comercio.
    let balance: Int
    let onDirections: () -> Void
    let onShowRewards: () -> Void

    private var affordableCount: Int {
        summary.items.filter { RewardsMath.canAfford(cost: $0.pointsCost, balance: balance) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MerchantLogoView(urlString: summary.merchant?.logoUrl, name: summary.name, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.name)
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .lineLimit(2)
                    if let category = summary.merchant?.category, !category.isEmpty {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let address = summary.merchant?.address, !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                RewardCurrencyBadge(currency: summary.currency)
            }

            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(affordableCount > 0 ? MonAviBrand.primary : Color.secondary)

            HStack(spacing: 10) {
                Button(action: onDirections) {
                    Label("Cómo llegar", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MonAviBrand.primary)

                Button(action: onShowRewards) {
                    Label("Ver premios", systemImage: "gift.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
    }

    private var summaryText: String {
        let count = summary.items.count
        let prizes = count == 1 ? "1 premio" : "\(count) premios"
        let from = "desde \(summary.currency.format(summary.cheapestCost))"
        if affordableCount > 0 {
            let ready = affordableCount == 1 ? "ya te alcanza para 1" : "ya te alcanza para \(affordableCount)"
            return "\(prizes) \(from) · \(ready) 🎉"
        }
        return "\(prizes) \(from)"
    }
}
