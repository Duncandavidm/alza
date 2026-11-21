import SwiftUI

/// Un comercio aliado con sus premios (cashback) y sus descuentos gratis,
/// para la lista "Dónde canjear". Sale si tiene al menos uno de los dos.
struct PartnerMerchantSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let merchant: PartnerMerchant?
    /// Premios que se canjean con cashback (puede estar vacio si el
    /// comercio solo da descuentos).
    let items: [RewardItem]
    /// Descuentos gratis por ser de MonAvi (1.0.3).
    var benefits: [RewardItem] = []

    var currency: RewardCurrency { items.first?.currency ?? .cashback }
    var cheapestCost: Int { items.map(\.pointsCost).min() ?? 0 }
    var category: String? { merchant?.category }

    /// Agrupa por comercio, en el orden en que aparece cada uno: primero
    /// los del catalogo, luego los que solo tienen descuentos.
    static func group(_ items: [RewardItem], benefits: [RewardItem] = []) -> [PartnerMerchantSummary] {
        var order: [UUID] = []
        var byMerchant: [UUID: [RewardItem]] = [:]
        var benefitsByMerchant: [UUID: [RewardItem]] = [:]
        var info: [UUID: RewardItem] = [:]
        for item in items {
            if info[item.merchantId] == nil {
                order.append(item.merchantId)
                info[item.merchantId] = item
            }
            byMerchant[item.merchantId, default: []].append(item)
        }
        for benefit in benefits {
            if info[benefit.merchantId] == nil {
                order.append(benefit.merchantId)
                info[benefit.merchantId] = benefit
            }
            benefitsByMerchant[benefit.merchantId, default: []].append(benefit)
        }
        return order.compactMap { (merchantId: UUID) -> PartnerMerchantSummary? in
            guard let first = info[merchantId] else { return nil }
            return PartnerMerchantSummary(
                id: merchantId,
                name: first.merchantName,
                merchant: first.merchant,
                items: byMerchant[merchantId] ?? [],
                benefits: benefitsByMerchant[merchantId] ?? []
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
                if summary.currency == .puntos {
                    RewardCurrencyBadge(currency: summary.currency)
                }
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
                    Label(summary.items.isEmpty ? "Ver descuentos" : "Ver premios",
                          systemImage: summary.items.isEmpty ? "percent" : "gift.fill")
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
        var parts: [String] = []
        if let benefit = summary.benefits.first {
            parts.append(summary.benefits.count == 1 ? "\(benefit.name) gratis" : "\(summary.benefits.count) descuentos gratis")
        }
        let count = summary.items.count
        if count > 0 {
            let prizes = count == 1 ? "1 premio" : "\(count) premios"
            var text = "\(prizes) desde \(summary.currency.format(summary.cheapestCost))"
            if affordableCount > 0 {
                text += affordableCount == 1 ? " · ya te alcanza para 1 🎉" : " · ya te alcanza para \(affordableCount) 🎉"
            }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }
}
