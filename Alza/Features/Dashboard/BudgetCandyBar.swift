import SwiftUI

/// La barra "candy" de presupuesto del diseño de referencia: una pastilla
/// vertical rellena hasta donde vas de gasto, con un contorno punteado que
/// marca el limite completo (si te pasas, el relleno llega hasta arriba y
/// cambia de tono). Toda la fila se desliza horizontal con una por
/// categoria.
struct BudgetCandyBar: View {
    let progress: BudgetProgress
    let color: Color
    /// Alto total de la pastilla — el contorno punteado siempre llega
    /// hasta aqui, representando el 100% del limite.
    var height: CGFloat = 130

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 56, height: height)

                Capsule()
                    .fill(fillColor)
                    .frame(width: 52, height: max(10, height * min(progress.ratio, 1)))
            }
            .frame(height: height)

            Text(categoryEmoji)
                .font(.title3)

            VStack(spacing: 1) {
                Text(Self.compactAmount(progress.spent))
                    .font(.caption.weight(.semibold))
                Text("\(Int(progress.ratio * 100))%")
                    .font(.caption2)
                    .foregroundStyle(progress.status == .over ? AviBrand.alert : .secondary)
            }
        }
    }

    private var fillColor: Color {
        progress.status == .over ? AviBrand.alert : color
    }

    private var categoryEmoji: String {
        TransactionCategory(rawValue: progress.budget.category)?.emoji ?? "🛍️"
    }

    /// "$1.2k", "$834" — sin depender de un FormatStyle cuya version minima
    /// de iOS no se pudo confirmar con certeza desde este entorno.
    static func compactAmount(_ value: Decimal) -> String {
        let magnitude = NSDecimalNumber(decimal: value).doubleValue
        if magnitude >= 1_000_000 {
            return String(format: "$%.1fM", magnitude / 1_000_000)
        } else if magnitude >= 1_000 {
            return String(format: "$%.1fk", magnitude / 1_000)
        } else {
            return String(format: "$%.0f", magnitude)
        }
    }
}

/// La fila horizontal de barras — el banner "sobre presupuesto" del diseño
/// de referencia vive en DayJournalView.totalsCard, no aqui, para no
/// repetirlo cuando esta fila se use en otro lado.
struct BudgetCandyBarRow: View {
    let progresses: [BudgetProgress]
    let onSelect: (BudgetProgress) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(Array(progresses.enumerated()), id: \.element.id) { index, progress in
                        Button {
                            onSelect(progress)
                        } label: {
                            BudgetCandyBar(
                                progress: progress,
                                color: BudgetColorPalette.color(for: progress.budget, index: index)
                            )
                        }
                        .buttonStyle(.plain)
                        .pressable(scale: 0.94)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
}
