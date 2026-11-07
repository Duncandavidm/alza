import SwiftUI

/// Foto del producto en 4:3 con esquinas redondeadas. Mientras carga (o
/// si falla / no hay foto) se ve un fondo con el tinte de marca.
struct RewardPhotoView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 20

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay { photo }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photo: some View {
        if let url = RewardsMath.webURL(from: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    placeholder(isLoading: true)
                case .failure:
                    placeholder(isLoading: false)
                @unknown default:
                    placeholder(isLoading: false)
                }
            }
        } else {
            placeholder(isLoading: false)
        }
    }

    private func placeholder(isLoading: Bool) -> some View {
        ZStack {
            MonAviBrand.primary.opacity(0.12)
            if isLoading {
                ProgressView()
                    .tint(MonAviBrand.primary)
            } else {
                Image(systemName: "gift.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(MonAviBrand.primary.opacity(0.55))
            }
        }
    }
}

/// Logo redondo del comercio; si no hay logo (o no carga), la inicial
/// del nombre sobre el tinte de marca.
struct MerchantLogoView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(MonAviBrand.primary.opacity(0.15))
            logo
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(MonAviBrand.border, lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var logo: some View {
        if let url = RewardsMath.webURL(from: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    initial
                }
            }
        } else {
            initial
        }
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: MonAviBrand.fontDesign))
            .foregroundStyle(MonAviBrand.primary)
    }
}

/// Pastilla con el costo: "$1.50" (cashback, `points` en centavos) o
/// "150 pts" (puntos por habitos).
struct RewardPointsPill: View {
    let points: Int
    var currency: RewardCurrency = .cashback

    var body: some View {
        Text(currency.format(points))
            .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(MonAviBrand.primary.opacity(0.15), in: Capsule())
            .foregroundStyle(MonAviBrand.primaryDark)
    }
}

/// Badge chico de un comercio: "Canje con puntos" / "Canje con cashback".
struct RewardCurrencyBadge: View {
    let currency: RewardCurrency

    var body: some View {
        Label(currency.badgeText, systemImage: currency.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    private var tint: Color {
        switch currency {
        case .cashback: return MonAviBrand.primaryDark
        case .puntos: return Color.orange
        }
    }
}

/// Uno de los dos saldos de arriba ("Cashback" / "Puntos") sobre el
/// degradado de marca.
struct RewardBalanceTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.9))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: MonAviBrand.fontDesign))
                .foregroundStyle(MonAviBrand.onDarkSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MonAviBrand.accentOnDark)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MonAviBrand.headerGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Los dos saldos lado a lado: cashback (con lo pendiente) y puntos.
struct RewardBalancesHeader: View {
    let balance: PointsBalance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RewardBalanceTile(
                title: "Cashback",
                value: Cashback.format(cents: max(0, balance.confirmedPoints)),
                subtitle: cashbackSubtitle,
                systemImage: RewardCurrency.cashback.systemImage
            )
            RewardBalanceTile(
                title: "Puntos",
                value: RewardCurrency.formatPoints(max(0, balance.habitPoints)),
                subtitle: "por buenos hábitos",
                systemImage: RewardCurrency.puntos.systemImage
            )
        }
    }

    private var cashbackSubtitle: String {
        if balance.pendingPoints > 0 {
            return "+\(Cashback.format(cents: balance.pendingPoints)) pendiente"
        }
        return "de tus facturas"
    }
}

/// Badge de estado de un canje en "Mis canjes".
struct RedemptionStatusBadge: View {
    let status: RewardRedemptionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .emitido: return MonAviBrand.primary
        case .entregado: return Color.blue
        case .cancelado: return MonAviBrand.alert
        case .vencido: return Color.secondary
        }
    }
}

/// Badge "🎁 Regalo de MonAvi" de los canjes que son regalos.
struct GiftBadge: View {
    var body: some View {
        Text("🎁 Regalo de MonAvi")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.orange)
            .lineLimit(1)
    }
}

/// Regalo activo en "Mis canjes", con forma de cupon: foto del producto,
/// comercio, nombre, mensaje y vencimiento.
struct GiftCouponCard: View {
    let redemption: RewardRedemption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RewardPhotoView(urlString: redemption.item?.photoUrl, cornerRadius: 12)
                    .frame(width: 104)

                VStack(alignment: .leading, spacing: 5) {
                    GiftBadge()
                    HStack(spacing: 6) {
                        MerchantLogoView(
                            urlString: redemption.displayMerchant?.logoUrl,
                            name: redemption.merchantName,
                            size: 20
                        )
                        Text(redemption.merchantName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(redemption.itemName)
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let message = redemption.displayGiftMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            // Linea punteada del cupon.
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(MonAviBrand.border)
                .frame(height: 1)
                .padding(.horizontal, 14)

            HStack {
                Label(
                    "Vence el \(redemption.expiresAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Text("Gratis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MonAviBrand.primaryDark)
                Label("Ver código", systemImage: "qrcode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el código para mostrarlo en caja")
    }

    /// Linea horizontal para el separador punteado.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// "🎁 Tienes N regalo(s)" en Hoy: lleva a "Mis canjes". Quien lo usa
/// debe esconderlo cuando no hay regalos activos.
struct GiftsTodayCard: View {
    let count: Int

    var body: some View {
        NavigationLink {
            MyRedemptionsView()
        } label: {
            HStack(spacing: 12) {
                Text("🎁")
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(RewardsMath.giftCountText(count))
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Muéstralo en caja y llévatelo gratis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RewardsMath.giftCountText(count))
    }
}
