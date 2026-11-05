import SwiftUI

/// "Ofertas cerca": comercios aliados y su oferta vigente. Solo lectura
/// — el catalogo se administra desde el panel admin / Table Editor.
struct PartnerOffersView: View {
    @ObservedObject var viewModel: PointsViewModel

    var body: some View {
        List {
            if viewModel.offers.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin ofertas por ahora",
                    systemImage: "tag",
                    description: Text("Cuando haya comercios aliados con una oferta activa, aparecerán aquí.")
                )
            } else {
                ForEach(viewModel.offers) { partnerOffer in
                    offerRow(partnerOffer)
                }
            }
        }
        .navigationTitle("Ofertas cerca")
    }

    @ViewBuilder
    private func offerRow(_ partnerOffer: PartnerOffer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(partnerOffer.merchant.name).font(.body)
            if let offer = partnerOffer.offer {
                Text(offer.summaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MonAviBrand.primary)
                if let minAmount = offer.minAmount {
                    Text("Compra minima: \(minAmount, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let endsAt = offer.endsAt {
                    Text("Vigente hasta \(endsAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sin oferta activa ahorita")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
