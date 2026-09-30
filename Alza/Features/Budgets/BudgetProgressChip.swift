import SwiftUI

/// Chip compacto reusado en "Hoy" (vista rapida) y en la lista completa de
/// Presupuestos. Mismo semaforo de colores que el resto de la app.
struct BudgetProgressChip: View {
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(categoryEmoji)
                Text(progress.budget.category)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            ProgressView(value: min(progress.ratio, 1))
                .tint(statusColor)

            Text("\(progress.spent, format: .currency(code: "USD")) de \(progress.budget.limitAmount, format: .currency(code: "USD"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var categoryEmoji: String {
        TransactionCategory(rawValue: progress.budget.category)?.emoji ?? "🛍️"
    }

    var statusColor: Color {
        switch progress.status {
        case .onTrack: return .green
        case .warning: return .orange
        case .over: return .red
        }
    }
}
