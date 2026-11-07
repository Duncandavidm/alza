import SwiftUI

/// Tarjeta de un producto canjeable. El producto es lo principal: el
/// nombre del comercio arriba, la foto grande, y abajo el nombre del
/// producto, la descripcion, el costo y las acciones.
struct RewardItemCard: View {
    let item: RewardItem
    /// Saldo en la moneda del comercio (`item.currency`): centavos de
    /// cashback o puntos por habitos.
    let balance: Int
    let isRedeeming: Bool
    let onDirections: () -> Void
    let onRedeem: () -> Void

    private var missingPoints: Int {
        RewardsMath.pointsMissing(cost: item.pointsCost, balance: balance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            merchantHeader
            RewardPhotoView(urlString: item.photoUrl, cornerRadius: 20)
            productInfo
            actions
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var merchantHeader: some View {
        HStack(spacing: 10) {
            MerchantLogoView(urlString: item.merchant?.logoUrl, name: item.merchantName, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.merchantName)
                    .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .bold))
                    .lineLimit(1)
                if let category = item.merchant?.category, !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            RewardCurrencyBadge(currency: item.currency)
        }
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RewardPointsPill(points: item.pointsCost, currency: item.currency)
            }
            if let description = item.itemDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onDirections) {
                    Label("Cómo llegar", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MonAviBrand.primary)

                Button(action: onRedeem) {
                    Label("Canjear", systemImage: "gift.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
                .disabled(missingPoints > 0 || isRedeeming)
            }
            .controlSize(.large)

            if let missingText = RewardsMath.missingText(cost: item.pointsCost, balance: balance, currency: item.currency) {
                Text(missingText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
