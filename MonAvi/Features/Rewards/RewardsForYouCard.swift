import SwiftUI

/// Lo que muestra "Premios para ti" en Hoy: hasta 5 productos (primero
/// los que ya le alcanzan, luego los mas cercanos) y los saldos con los
/// que se calculo.
struct FeaturedRewards {
    var items: [RewardItem]
    var balance: PointsBalance

    static let empty = FeaturedRewards(items: [], balance: .zero)

    /// Liviano y tolerante a fallas: cualquier error devuelve `.empty` y
    /// la tarjeta simplemente no se muestra.
    @MainActor
    static func load(userId: UUID, limit: Int = 5) async -> FeaturedRewards {
        guard let items = try? await RewardsRepository.shared.fetchItems(), !items.isEmpty else {
            return .empty
        }
        let balance = await CardPointsRepository.shared.fetchBalance(userId: userId)
        let featured = RewardsMath.featured(
            items,
            cashbackCents: balance.confirmedPoints,
            habitPoints: balance.habitPoints,
            limit: limit
        )
        return FeaturedRewards(items: featured, balance: balance)
    }
}

/// "Premios para ti": carrusel compacto en Hoy que lleva al catalogo de
/// canje. Quien lo usa debe esconderlo cuando `items` esta vacio.
struct RewardsForYouCard: View {
    let items: [RewardItem]
    let balance: PointsBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Premios para ti")
                    .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                Spacer()
                NavigationLink {
                    RewardsView()
                } label: {
                    Text("Ver todos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MonAviBrand.primary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items) { (item: RewardItem) in
                        NavigationLink {
                            RewardsView()
                        } label: {
                            tile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tile(_ item: RewardItem) -> some View {
        let available = balance.spendable(in: item.currency)
        let missingText = RewardsMath.missingText(cost: item.pointsCost, balance: available, currency: item.currency)

        return VStack(alignment: .leading, spacing: 6) {
            RewardPhotoView(urlString: item.photoUrl, cornerRadius: 12)
                .frame(width: 140)
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(item.merchantName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            RewardPointsPill(points: item.pointsCost, currency: item.currency)
            Text(missingText ?? "¡Ya te alcanza!")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(missingText == nil ? MonAviBrand.primary : Color.secondary)
                .lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
