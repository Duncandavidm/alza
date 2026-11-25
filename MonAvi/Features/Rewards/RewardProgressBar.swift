import SwiftUI

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
