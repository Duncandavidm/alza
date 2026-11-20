import SwiftUI

/// Tarjeta de una campaña de marca: marca, descripcion, bono, tope por
/// factura, vigencia y como se gana.
struct BrandCampaignCard: View {
    let campaign: BrandCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let urlString = campaign.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(campaign.brand)
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                    if !campaign.name.isEmpty, campaign.name != campaign.brand {
                        Text(campaign.name)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let description = campaign.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let bonus = BrandCampaignText.bonusText(for: campaign) {
                Text(bonus)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MonAviBrand.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(MonAviBrand.primary.opacity(0.12)))
            }

            if let units = BrandCampaignText.unitsLimitText(campaign.maxUnitsPerReceipt) {
                Label(units, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ends = BrandCampaignText.endsText(campaign.endsAt) {
                Label(ends, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(BrandCampaignText.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Todas las ofertas de marcas (desde la fila compacta de Hoy).
struct BrandCampaignsView: View {
    @State var campaigns: [BrandCampaign]

    var body: some View {
        List {
            ForEach(campaigns) { campaign in
                BrandCampaignCard(campaign: campaign)
            }
        }
        .navigationTitle("Ofertas de marcas")
        .refreshable {
            let fresh = await BrandCampaignsRepository.shared.fetchActiveOrEmpty()
            if !fresh.isEmpty { campaigns = fresh }
        }
    }
}

/// Fila compacta en Hoy: solo se muestra si hay campañas activas (quien
/// la usa debe esconderla cuando `campaigns` esta vacio).
struct BrandCampaignsTodayRow: View {
    let campaigns: [BrandCampaign]

    var body: some View {
        NavigationLink {
            BrandCampaignsView(campaigns: campaigns)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(MonAviBrand.headerGradient)
                    Image(systemName: "tag.fill")
                        .foregroundStyle(MonAviBrand.accentOnDark)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ofertas de marcas")
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let first = campaigns.first else { return "" }
        let bonus = BrandCampaignText.bonusText(for: first).map { "\(first.brand): \($0)" } ?? first.brand
        let others = campaigns.count - 1
        return others > 0 ? "\(bonus) y \(others) más" : bonus
    }
}
