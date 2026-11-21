import SwiftUI

/// Tarjeta de un descuento de aliado "por ser de MonAvi" (0067): el
/// comercio arriba, la foto (o un % si no hay), el descuento, sus
/// condiciones y cuantas veces se puede usar. El boton cambia segun el
/// estado: desbloquear con la primera factura, usar, ver el codigo
/// vigente o cuando vuelve a estar disponible.
struct BenefitCard: View {
    let entry: BenefitEntry
    let state: BenefitState
    let isWorking: Bool
    let onDirections: () -> Void
    let onPrimary: () -> Void

    private var item: RewardItem { entry.item }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            merchantHeader
            RewardPhotoView(urlString: item.photoUrl, cornerRadius: 20, placeholderSymbol: item.kind.placeholderSymbol)
                .overlay(alignment: .topLeading) { remainingBadge }
            info
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
        }
    }

    @ViewBuilder
    private var remainingBadge: some View {
        if let text = RewardsMath.remainingText(item.remaining) {
            Label(text, systemImage: "flame.fill")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.orange, in: Capsule())
                .foregroundStyle(.white)
                .padding(10)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .heavy))
                .foregroundStyle(MonAviBrand.primaryDark)
                .fixedSize(horizontal: false, vertical: true)
            if let description = item.itemDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(
                "Por ser de MonAvi · \(BenefitsMath.limitText(limit: item.perUserLimit, period: item.perUserPeriod))",
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
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

                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
                .disabled(!isPrimaryEnabled || isWorking)
            }
            .controlSize(.large)

            if let footnote {
                Text(footnote)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var primaryTitle: String {
        switch state {
        case .locked: return "Desbloquear"
        case .active: return "Ver mi código"
        case .available: return "Usar"
        case .cooldown, .usedUp: return "Usado"
        }
    }

    private var primarySymbol: String {
        switch state {
        case .locked: return "qrcode.viewfinder"
        case .active: return "qrcode"
        case .available: return "percent"
        case .cooldown, .usedUp: return "checkmark"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch state {
        case .locked, .active, .available: return true
        case .cooldown, .usedUp: return false
        }
    }

    private var footnote: String? {
        switch state {
        case .locked: return "Escanea tu primera factura fiscal para usarlo"
        case .active: return "Tienes un código listo para usar"
        case .available: return nil
        case .cooldown(let date): return BenefitsMath.availableAgainText(date)
        case .usedUp: return "Ya usaste este descuento"
        }
    }
}

/// Aviso arriba de los descuentos mientras no los ha desbloqueado: lo
/// unico que falta es escanear una factura fiscal.
struct BenefitsUnlockCard: View {
    let bestDiscount: String?
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("🧾").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(bestDiscount.map { "Desbloquea descuentos de \($0)" } ?? "Desbloquea tus descuentos")
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Pide tu factura fiscal en cualquier compra y escanéala en MonAvi. Con la primera se activan todos los descuentos y además ganas cashback.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onScan) {
                Label("Escanear mi factura", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MonAviBrand.primary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MonAviBrand.primary.opacity(0.10))
        )
    }
}

/// Recordatorio fijo bajo los descuentos: la factura fiscal es la que da
/// el cashback.
struct AskForInvoiceTip: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(MonAviBrand.primary)
            Text("Pide siempre tu factura fiscal al pagar y escanéala: cada factura te da cashback para canjear premios.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}
