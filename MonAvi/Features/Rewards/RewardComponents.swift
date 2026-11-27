import SwiftUI
import UIKit

/// Foto del producto en 4:3 con esquinas redondeadas. Mientras carga (o
/// si falla / no hay foto) se ve un fondo con el tinte de marca.
struct RewardPhotoView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 20
    /// Icono si no hay foto: regalo, % (descuento) o boleto (cupon).
    var placeholderSymbol: String = RewardKind.producto.placeholderSymbol

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
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(MonAviBrand.primary.opacity(0.55))
            }
        }
    }
}

/// Logo redondo del comercio. Los logos llegan de todas las formas
/// (redondos, cuadrados, alargados como "Bungla", con fondo o
/// transparentes), asi que antes de mostrarlo se mira la imagen:
/// - Cuadrado con fondo parejo o tipo foto: llena el circulo.
/// - Alargado, o con dibujo hasta las esquinas: se ve COMPLETO dentro del
///   circulo, sobre su mismo color de fondo (blanco si es transparente).
/// Si no hay logo (o no carga), la inicial del nombre sobre el tinte de marca.
struct MerchantLogoView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 36

    @State private var loaded: MerchantLogoCache.Logo?

    var body: some View {
        ZStack {
            Circle()
                .fill(loaded.map { Color(uiColor: $0.background) } ?? MonAviBrand.primary.opacity(0.15))
            if let loaded {
                logoImage(loaded)
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(MonAviBrand.border, lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: urlString) {
            guard let url = RewardsMath.webURL(from: urlString) else {
                loaded = nil
                return
            }
            loaded = await MerchantLogoCache.shared.logo(for: url)
        }
    }

    @ViewBuilder
    private func logoImage(_ logo: MerchantLogoCache.Logo) -> some View {
        let image = Image(uiImage: logo.image).resizable()
        if logo.fillsCircle {
            image.scaledToFill()
        } else {
            // El rectangulo mas grande que cabe dentro del circulo con la
            // proporcion del logo, con un pequeño margen.
            let ratio = max(logo.aspectRatio, 0.01)
            let diagonal = (1 + ratio * ratio).squareRoot()
            let inner = size * 0.9
            image
                .scaledToFit()
                .frame(width: inner * ratio / diagonal, height: inner / diagonal)
        }
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: MonAviBrand.fontDesign))
            .foregroundStyle(MonAviBrand.primary)
    }
}

/// Descarga y analiza cada logo una sola vez (se reusa en todas las listas).
actor MerchantLogoCache {
    static let shared = MerchantLogoCache()

    final class Logo: @unchecked Sendable {
        let image: UIImage
        let background: UIColor
        let fillsCircle: Bool
        let aspectRatio: CGFloat

        init(image: UIImage, background: UIColor, fillsCircle: Bool, aspectRatio: CGFloat) {
            self.image = image
            self.background = background
            self.fillsCircle = fillsCircle
            self.aspectRatio = aspectRatio
        }
    }

    private var cache: [URL: Logo] = [:]
    private var inFlight: [URL: Task<Logo?, Never>] = [:]

    func logo(for url: URL) async -> Logo? {
        if let cached = cache[url] { return cached }
        if let task = inFlight[url] { return await task.value }
        let task = Task<Logo?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = UIImage(data: data) else { return nil }
            return Self.analyze(image)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache[url] = result }
        return result
    }

    /// Mira las esquinas de la imagen (reducida a 32x32) para saber si es
    /// transparente, si tiene un fondo parejo y de que color.
    static func analyze(_ image: UIImage, trimMargins: Bool = true) -> Logo {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let ratio = width / height
        let isSquare = ratio > 0.85 && ratio < 1.18

        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drewPixels: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgImage = image.cgImage else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drewPixels else {
            return Logo(image: image, background: .white, fillsCircle: false, aspectRatio: ratio)
        }

        func pixel(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let i = (y * side + x) * 4
            let a = CGFloat(pixels[i + 3]) / 255
            guard a > 0 else { return (1, 1, 1, 0) }
            // Quita el premultiplicado para comparar colores reales.
            return (CGFloat(pixels[i]) / 255 / a, CGFloat(pixels[i + 1]) / 255 / a, CGFloat(pixels[i + 2]) / 255 / a, a)
        }

        let corners = [pixel(1, 1), pixel(side - 2, 1), pixel(1, side - 2), pixel(side - 2, side - 2)]
        let first = corners[0]
        func sameColor(_ p: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) -> Bool {
            p.a > 0.9 && abs(p.r - first.r) + abs(p.g - first.g) + abs(p.b - first.b) < 0.12
        }
        let cornersUniform = corners.allSatisfy(sameColor)
        let background: UIColor = cornersUniform
            ? UIColor(red: first.r, green: first.g, blue: first.b, alpha: 1)
            : .white

        // Muchos logos traen mucho espacio vacio alrededor y se ven chiquitos:
        // se recorta al dibujo (con un pequeño margen) y se analiza de nuevo.
        if trimMargins, let cgImage = image.cgImage, cornersUniform || corners.allSatisfy({ $0.a < 0.2 }) {
            let transparentCorners = !cornersUniform
            var minX = side, minY = side, maxX = -1, maxY = -1
            for y in 0..<side {
                for x in 0..<side {
                    let p = pixel(x, y)
                    let isContent = transparentCorners ? p.a >= 0.2 : !sameColor(p)
                    if isContent {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            if maxX >= minX, maxY >= minY {
                let margin = 1
                let x0 = max(minX - margin, 0), y0 = max(minY - margin, 0)
                let x1 = min(maxX + margin + 1, side), y1 = min(maxY + margin + 1, side)
                let keptArea = CGFloat((x1 - x0) * (y1 - y0)) / CGFloat(side * side)
                if keptArea < 0.8 {
                    let scaleX = CGFloat(cgImage.width) / CGFloat(side)
                    let scaleY = CGFloat(cgImage.height) / CGFloat(side)
                    let rect = CGRect(
                        x: CGFloat(x0) * scaleX, y: CGFloat(y0) * scaleY,
                        width: CGFloat(x1 - x0) * scaleX, height: CGFloat(y1 - y0) * scaleY
                    ).integral
                    if let cropped = cgImage.cropping(to: rect) {
                        let trimmed = analyze(UIImage(cgImage: cropped, scale: image.scale, orientation: .up), trimMargins: false)
                        return Logo(image: trimmed.image, background: background, fillsCircle: trimmed.fillsCircle, aspectRatio: trimmed.aspectRatio)
                    }
                }
            }
        }

        // Llenar el circulo solo si lo que queda FUERA del circulo (las
        // esquinas) es fondo parejo o transparente: asi no se corta nada.
        // Un logo redondo o un icono cuadrado con margen llena; un nombre
        // alargado o un dibujo hasta las esquinas se muestra completo.
        var fills = false
        if isSquare {
            let center = CGFloat(side - 1) / 2
            var outside: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)] = []
            for y in 0..<side {
                for x in 0..<side {
                    let dx = CGFloat(x) - center, dy = CGFloat(y) - center
                    if (dx * dx + dy * dy).squareRoot() > center + 0.5 { outside.append(pixel(x, y)) }
                }
            }
            fills = outside.allSatisfy { $0.a < 0.2 } || (cornersUniform && outside.allSatisfy(sameColor))
        }
        return Logo(image: image, background: background, fillsCircle: fills, aspectRatio: ratio)
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

/// El saldo de cashback (con lo pendiente).
struct RewardBalancesHeader: View {
    let balance: PointsBalance

    /// El cashback pendiente se libera cuando los ingresos registrados
    /// respaldan las compras (ver migracion 0045).
    static let pendingHint = "Se libera cuando tus ingresos registrados respalden tus compras."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tiles
            if balance.pendingPoints > 0 {
                Label(Self.pendingHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Desde 1.0.3 solo hay cashback (los buenos habitos dan cupones, no
    /// puntos).
    private var tiles: some View {
        RewardBalanceTile(
            title: "Tu cashback",
            value: Cashback.format(cents: max(0, balance.confirmedPoints)),
            subtitle: cashbackSubtitle,
            systemImage: RewardCurrency.cashback.systemImage
        )
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
    /// Texto propio ("Aplicado" en descuentos); nil = el del estado.
    var text: String? = nil

    var body: some View {
        Text(text ?? status.displayName)
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
                RewardPhotoView(
                    urlString: redemption.item?.photoUrl,
                    cornerRadius: 12,
                    placeholderSymbol: (redemption.item?.kind ?? .producto).placeholderSymbol
                )
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

/// "🎁 Tienes N cupón(es)" en Hoy: lleva a "Mis cupones y canjes". Quien lo usa
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
                    Text("Toca para ver su código y úsalo en caja.")
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


/// Barra de "cuánto te falta" para desbloquear un beneficio con cashback:
/// "$5.58 de $6.00 · Te faltan $0.42". Al llegar dice "Desbloqueado 🔓".
struct RewardProgressBar: View {
    let balance: Int
    let cost: Int
    var currency: RewardCurrency = .cashback
    /// Version chica (tarjetas de "Para ti" en Hoy): solo la barra y "Te faltan".
    var compact = false

    private var ratio: Double {
        guard cost > 0 else { return 1 }
        return min(1, max(0, Double(balance) / Double(cost)))
    }

    private var missingText: String? {
        RewardsMath.missingText(cost: cost, balance: balance, currency: currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MonAviBrand.primary.opacity(0.15))
                    Capsule()
                        .fill(MonAviBrand.primary)
                        .frame(width: max(6, proxy.size.width * ratio))
                }
            }
            .frame(height: compact ? 5 : 7)
            .accessibilityHidden(true)

            if let missingText {
                Text(compact ? missingText : "\(currency.format(max(0, balance))) de \(currency.format(cost)) · \(missingText)")
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Desbloqueado 🔓")
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
